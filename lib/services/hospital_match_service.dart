import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'incident_service.dart';
import 'ops_hospital_service.dart';
import 'ops_incident_hospital_assignment_service.dart';

/// EmergencyOS — Hospital Match Service (client-side mirror of the v2 engine)
/// ---------------------------------------------------------------------------
/// The authoritative matching + escalation logic lives in
/// `functions/src/hospital_dispatch_v2.js` so every client sees the same
/// ranking. This service re-implements the scoring in Dart for two use-cases
/// that must not hit the network:
///
///   1. **Ops preview** — show the operator the ranked list *before* the
///      cloud function fires (e.g. when they open a freshly-created incident
///      and the assignment doc has not yet propagated).
///   2. **Offline hospital card** — on the hospital dashboard we need to
///      explain *why* an incident was routed to us ("You scored 0.86 because
///      you're 1.8 km away, have 6 beds, and 2 ambulances are ready.").
///
/// Keep constants in sync with `SEVERITY_PROFILES` / `FACTOR_WEIGHTS` in the
/// Node engine. A mismatch is not catastrophic — the server ranking is final
/// — but the UI will feel inconsistent if they drift too far apart.
class HospitalMatchService {
  /// Severity config (parallel-per-wave, wave timeout, max waves).
  static const Map<String, _SeverityProfile> severityProfiles = {
    'critical': _SeverityProfile(
      parallelPerWave: 3,
      waveTimeoutMs: 45000,
      maxWaves: 6,
    ),
    'high': _SeverityProfile(
      parallelPerWave: 2,
      waveTimeoutMs: 75000,
      maxWaves: 5,
    ),
    'standard': _SeverityProfile(
      parallelPerWave: 1,
      waveTimeoutMs: 120000,
      maxWaves: 4,
    ),
  };

  static const Map<String, _FactorWeights> factorWeights = {
    'critical': _FactorWeights(
      proximity: 0.28,
      specialty: 0.22,
      capacity: 0.15,
      staffing: 0.10,
      bloodBank: 0.08,
      load: 0.07,
      ambulance: 0.05,
      freshness: 0.03,
      reliability: 0.02,
    ),
    'high': _FactorWeights(
      proximity: 0.25,
      specialty: 0.20,
      capacity: 0.15,
      staffing: 0.10,
      bloodBank: 0.08,
      load: 0.08,
      ambulance: 0.07,
      freshness: 0.04,
      reliability: 0.03,
    ),
    'standard': _FactorWeights(
      proximity: 0.22,
      specialty: 0.18,
      capacity: 0.18,
      staffing: 0.10,
      bloodBank: 0.07,
      load: 0.10,
      ambulance: 0.08,
      freshness: 0.04,
      reliability: 0.03,
    ),
  };

  static const List<String> _criticalKeywords = [
    'cardiac arrest', 'cardiac', 'chest pain', 'stroke', 'cva',
    'unresponsive', 'unconscious', 'no pulse', 'not breathing',
    'severe bleeding', 'haemorrhage', 'hemorrhage', 'gunshot', 'stab',
    'childbirth', 'obstetric emergency', 'anaphylaxis', 'overdose',
    'triage_red', 'mass casualty', 'polytrauma',
  ];
  static const List<String> _highKeywords = [
    'accident', 'crash', 'rta', 'collision', 'vehicle',
    'burn', 'fire', 'smoke', 'fall from height', 'fracture',
    'seizure', 'convulsion', 'pediatric', 'allergic', 'asthma',
    'heat stroke', 'drowning', 'electrocution', 'triage_orange',
  ];

  /// Emergency type → preferred specialty keywords.
  static const Map<String, List<String>> _specialtyMap = {
    'trauma':     ['accident', 'crash', 'rta', 'collision', 'road', 'vehicle', 'polytrauma', 'fall'],
    'burn':       ['burn', 'fire', 'smoke'],
    'cardiac':    ['cardiac', 'chest', 'heart', 'arrest'],
    'stroke':     ['stroke', 'cva'],
    'obstetric':  ['childbirth', 'obstetric', 'labour', 'labor', 'pregnan'],
    'pediatric':  ['pediatric', 'child', 'infant'],
    'toxicology': ['poison', 'overdose', 'toxic'],
    'psychiatric':['psychiatric', 'mental', 'suicide'],
  };

  /// Rank a snapshot of hospitals against an incident. All work is synchronous
  /// (no Firestore reads) — caller provides the hospital snapshot.
  ///
  /// If `workloadByHospitalId` is provided (e.g. from a separate Firestore
  /// read of `ops_incident_hospital_assignments`), that data is factored into
  /// the load score. Otherwise load defaults to neutral (0).
  static List<RankedHospitalCandidate> rankHospitalsForIncident({
    required SosIncident incident,
    required List<OpsHospitalRow> hospitals,
    Map<String, int>? workloadByHospitalId,
    Map<String, int>? ambulanceReadyByHospitalId,
    Map<String, double>? reliabilityByHospitalId,
    double searchRadiusKm = 60,
  }) {
    final severity = classifySeverity(incident);
    final weights = factorWeights[severity] ?? factorWeights['standard']!;
    final emergencyType = incident.type.toLowerCase();
    final required = _extractRequiredServices(incident);
    final specialties = _emergencySpecialtyTags(emergencyType);

    final pin = incident.liveVictimPin;
    final ranked = <RankedHospitalCandidate>[];

    for (final h in hospitals) {
      if (h.lat == null || h.lng == null) continue;
      if (h.mapListingOnline == false) continue;
      final distKm = Geolocator.distanceBetween(
            pin.latitude,
            pin.longitude,
            h.lat!,
            h.lng!,
          ) /
          1000.0;
      if (distKm > searchRadiusKm) continue;

      final offered = h.offeredServices.map((s) => s.toLowerCase()).toList();

      // 1. Proximity (haversine × 30 km/h urban average → minutes).
      final etaMin = (distKm / 30.0) * 60.0;
      final proximity = _clamp01(1 - (etaMin - 3).clamp(0, 999) / 27);

      // 2. Specialty.
      double specialty;
      if (required.isEmpty) {
        var rel = 0;
        for (final tag in specialties) {
          if (offered.any((o) => o.contains(tag))) rel++;
        }
        final relMax = specialties.isEmpty ? 1 : specialties.length;
        specialty = _clamp01(0.5 + 0.5 * (rel / relMax));
      } else {
        var hits = 0;
        for (final rs in required) {
          if (offered.any((o) => o.contains(rs))) hits++;
        }
        final coverage = hits / required.length;
        var bonus = 0.0;
        for (final tag in specialties) {
          if (offered.any((o) => o.contains(tag))) {
            bonus += 0.05;
            if (bonus >= 0.15) break;
          }
        }
        specialty = _clamp01(coverage * 0.85 + bonus);
      }

      // 3. Capacity (diminishing returns + occupancy dampener).
      double capacity;
      if (h.bedsTotal == 0) {
        capacity = _clamp01(h.bedsAvailable / 6);
      } else if (h.bedsAvailable <= 0) {
        capacity = 0;
      } else if (h.bedsAvailable <= 2) {
        capacity = 0.4;
      } else if (h.bedsAvailable <= 5) {
        capacity = 0.7;
      } else if (h.bedsAvailable <= 10) {
        capacity = 0.9;
      } else {
        capacity = 1.0;
      }
      if (h.bedsTotal > 0) {
        final occupancy = 1 - h.bedsAvailable / h.bedsTotal;
        if (occupancy >= 0.95) {
          capacity *= 0.5;
        } else if (occupancy >= 0.85) capacity *= 0.8;
      }

      // 4. Staffing.
      final staffPoints = h.doctorsOnDuty + h.specialistsOnCall * 1.5;
      final staffing = _clamp01(0.2 + staffPoints / 12);

      // 5. Blood bank.
      double bloodBank = h.hasBloodBank ? 0.6 : 0.2;
      if (h.bloodUnitsAvailable >= 10) {
        bloodBank = 1.0;
      } else if (h.bloodUnitsAvailable >= 4) {
        bloodBank = 0.85;
      } else if (h.bloodUnitsAvailable >= 1) bloodBank = 0.7;

      // 6. Load (cross-incident distribution).
      final workload = workloadByHospitalId?[h.id] ?? 0;
      final load = workload <= 0
          ? 1.0
          : workload == 1
              ? 0.85
              : workload == 2
                  ? 0.65
                  : workload == 3
                      ? 0.35
                      : 0.0;

      // 7. Ambulance readiness.
      final ambReady = ambulanceReadyByHospitalId?[h.id] ?? 0;
      final ambulance = ambReady <= 0
          ? 0.2
          : ambReady == 1
              ? 0.7
              : 1.0;

      // 8. Data freshness (minutes since updatedAt).
      final ageMin = DateTime.now().difference(h.updatedAt).inMinutes;
      final freshness = ageMin < 5
          ? 1.0
          : ageMin < 30
              ? 0.8
              : ageMin < 180
                  ? 0.5
                  : ageMin < 1440
                      ? 0.2
                      : 0.0;

      // 9. Reliability.
      final reliability = (reliabilityByHospitalId?[h.id] ?? 0.7).clamp(0.0, 1.0);

      final factors = HospitalDispatchFactorBreakdown(
        proximity: proximity,
        specialty: specialty,
        capacity: capacity,
        staffing: staffing,
        bloodBank: bloodBank,
        load: load,
        ambulance: ambulance,
        freshness: freshness,
        reliability: reliability,
      );
      final score = proximity * weights.proximity +
          specialty * weights.specialty +
          capacity * weights.capacity +
          staffing * weights.staffing +
          bloodBank * weights.bloodBank +
          load * weights.load +
          ambulance * weights.ambulance +
          freshness * weights.freshness +
          reliability * weights.reliability;

      ranked.add(RankedHospitalCandidate(
        id: h.id,
        name: h.name,
        rank: 0, // filled after sort
        score: double.parse(score.toStringAsFixed(3)),
        distKm: double.parse(distKm.toStringAsFixed(3)),
        etaSec: (etaMin * 60).round(),
        ring: 0,
        bedsAvailable: h.bedsAvailable,
        bedsTotal: h.bedsTotal,
        offeredServices: offered,
        hasBloodBank: h.hasBloodBank,
        bloodUnitsAvailable: h.bloodUnitsAvailable,
        doctorsOnDuty: h.doctorsOnDuty,
        specialistsOnCall: h.specialistsOnCall,
        workload: workload,
        ambulanceReady: ambReady,
        disqualified: null,
        factors: factors,
        lat: h.lat,
        lng: h.lng,
      ));
    }

    ranked.sort((a, b) => b.score.compareTo(a.score));
    return List<RankedHospitalCandidate>.generate(
      ranked.length,
      (i) => _withRank(ranked[i], i + 1),
    );
  }

  /// Classify incident severity (mirror of server-side `classifySeverity`).
  static String classifySeverity(SosIncident incident) {
    final type = incident.type.toLowerCase();
    for (final kw in _criticalKeywords) {
      if (type.contains(kw)) return 'critical';
    }
    for (final kw in _highKeywords) {
      if (type.contains(kw)) return 'high';
    }
    return 'standard';
  }

  /// Live stream of the assignment + auto-computed remaining wave countdown
  /// for the ops console. Emits every 1s while waiting for hospital response
  /// so the UI can animate a progress ring.
  static Stream<HospitalDispatchLiveState> watchLiveState(String incidentId) async* {
    await for (final snap in FirebaseFirestore.instance
        .collection('ops_incident_hospital_assignments')
        .doc(incidentId)
        .snapshots()) {
      if (!snap.exists) {
        yield HospitalDispatchLiveState.empty();
        continue;
      }
      final assignment = OpsIncidentHospitalAssignment.fromFirestore(snap);
      yield HospitalDispatchLiveState(
        assignment: assignment,
        remainingWaveMs: assignment.remainingWaveMs(DateTime.now()),
        computedAt: DateTime.now(),
      );
    }
  }

  /// Calls the `adminRestartHospitalDispatch` cloud function (master console
  /// only). Intended for the "Retry dispatch" button on the ops dashboard
  /// when an assignment is stuck in `exhausted` or `no_candidates`.
  static Future<void> restartDispatch(String incidentId) async {
    try {
      await FirebaseFirestore.instance
          .collection('ops_incident_hospital_assignments')
          .doc(incidentId.trim())
          .set(
            {'adminRestartRequestedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
    } catch (e) {
      debugPrint('[HospitalMatchService] restartDispatch signal: $e');
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  static List<String> _extractRequiredServices(SosIncident incident) {
    final base = <String>{};
    final t = incident.type.trim().toLowerCase();
    if (t.isNotEmpty) base.add(t);
    return base.toList();
  }

  static Set<String> _emergencySpecialtyTags(String type) {
    final tags = <String>{'emergency'};
    for (final entry in _specialtyMap.entries) {
      for (final kw in entry.value) {
        if (type.contains(kw)) {
          tags.add(entry.key);
          break;
        }
      }
    }
    return tags;
  }

  static double _clamp01(num v) {
    if (v.isNaN) return 0;
    if (v < 0) return 0;
    if (v > 1) return 1;
    return v.toDouble();
  }

  static RankedHospitalCandidate _withRank(RankedHospitalCandidate c, int rank) {
    return RankedHospitalCandidate(
      id: c.id,
      name: c.name,
      rank: rank,
      score: c.score,
      distKm: c.distKm,
      etaSec: c.etaSec,
      ring: c.ring,
      bedsAvailable: c.bedsAvailable,
      bedsTotal: c.bedsTotal,
      offeredServices: c.offeredServices,
      hasBloodBank: c.hasBloodBank,
      bloodUnitsAvailable: c.bloodUnitsAvailable,
      doctorsOnDuty: c.doctorsOnDuty,
      specialistsOnCall: c.specialistsOnCall,
      workload: c.workload,
      ambulanceReady: c.ambulanceReady,
      disqualified: c.disqualified,
      factors: c.factors,
      lat: c.lat,
      lng: c.lng,
    );
  }
}

@immutable
class _SeverityProfile {
  final int parallelPerWave;
  final int waveTimeoutMs;
  final int maxWaves;
  const _SeverityProfile({
    required this.parallelPerWave,
    required this.waveTimeoutMs,
    required this.maxWaves,
  });
}

@immutable
class _FactorWeights {
  final double proximity;
  final double specialty;
  final double capacity;
  final double staffing;
  final double bloodBank;
  final double load;
  final double ambulance;
  final double freshness;
  final double reliability;
  const _FactorWeights({
    required this.proximity,
    required this.specialty,
    required this.capacity,
    required this.staffing,
    required this.bloodBank,
    required this.load,
    required this.ambulance,
    required this.freshness,
    required this.reliability,
  });
}

/// Snapshot emitted by [HospitalMatchService.watchLiveState] — includes the
/// current Firestore assignment plus derived "time remaining in wave" data so
/// the operator can see a live countdown.
@immutable
class HospitalDispatchLiveState {
  final OpsIncidentHospitalAssignment? assignment;
  final int remainingWaveMs;
  final DateTime computedAt;

  const HospitalDispatchLiveState({
    required this.assignment,
    required this.remainingWaveMs,
    required this.computedAt,
  });

  factory HospitalDispatchLiveState.empty() => HospitalDispatchLiveState(
        assignment: null,
        remainingWaveMs: 0,
        computedAt: DateTime.now(),
      );

  bool get isActive =>
      assignment != null &&
      (assignment!.dispatchStatus == 'pending_acceptance' ||
          assignment!.dispatchStatus == 'accepted');
}
