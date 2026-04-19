import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'incident_service.dart';
import 'ops_hospital_service.dart';

/// Per-hospital score breakdown persisted alongside the dispatch assignment.
/// Lets the ops console and hospital dashboard display *why* a given hospital
/// ranked where it did (proximity, specialty match, beds, staffing, etc.).
class HospitalDispatchFactorBreakdown {
  final double proximity;
  final double specialty;
  final double capacity;
  final double staffing;
  final double bloodBank;
  final double load;
  final double ambulance;
  final double freshness;
  final double reliability;

  const HospitalDispatchFactorBreakdown({
    this.proximity = 0,
    this.specialty = 0,
    this.capacity = 0,
    this.staffing = 0,
    this.bloodBank = 0,
    this.load = 0,
    this.ambulance = 0,
    this.freshness = 0,
    this.reliability = 0,
  });

  factory HospitalDispatchFactorBreakdown.fromMap(Map<String, dynamic>? m) {
    double pick(String k) => (m == null ? 0 : (m[k] as num?)?.toDouble() ?? 0);
    return HospitalDispatchFactorBreakdown(
      proximity: pick('proximity'),
      specialty: pick('specialty'),
      capacity: pick('capacity'),
      staffing: pick('staffing'),
      bloodBank: pick('bloodBank'),
      load: pick('load'),
      ambulance: pick('ambulance'),
      freshness: pick('freshness'),
      reliability: pick('reliability'),
    );
  }

  Map<String, double> asMap() => {
        'proximity': proximity,
        'specialty': specialty,
        'capacity': capacity,
        'staffing': staffing,
        'bloodBank': bloodBank,
        'load': load,
        'ambulance': ambulance,
        'freshness': freshness,
        'reliability': reliability,
      };
}

/// One ranked hospital candidate produced by the v2 dispatch engine.
class RankedHospitalCandidate {
  final String id;
  final String name;
  final int rank;
  final double score;
  final double? distKm;
  final int? etaSec;
  final int ring;
  final int bedsAvailable;
  final int bedsTotal;
  final List<String> offeredServices;
  final bool hasBloodBank;
  final int bloodUnitsAvailable;
  final int doctorsOnDuty;
  final int specialistsOnCall;
  final int workload;
  final int ambulanceReady;
  final String? disqualified;
  final HospitalDispatchFactorBreakdown factors;
  final double? lat;
  final double? lng;

  const RankedHospitalCandidate({
    required this.id,
    required this.name,
    required this.rank,
    required this.score,
    required this.distKm,
    required this.etaSec,
    required this.ring,
    required this.bedsAvailable,
    required this.bedsTotal,
    required this.offeredServices,
    required this.hasBloodBank,
    required this.bloodUnitsAvailable,
    required this.doctorsOnDuty,
    required this.specialistsOnCall,
    required this.workload,
    required this.ambulanceReady,
    required this.disqualified,
    required this.factors,
    required this.lat,
    required this.lng,
  });

  factory RankedHospitalCandidate.fromMap(Map<String, dynamic> m) {
    final services = (m['offeredServices'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    return RankedHospitalCandidate(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      rank: (m['rank'] as num?)?.toInt() ?? 0,
      score: (m['score'] as num?)?.toDouble() ?? 0,
      distKm: (m['distKm'] as num?)?.toDouble(),
      etaSec: (m['etaSec'] as num?)?.toInt(),
      ring: (m['ring'] as num?)?.toInt() ?? 0,
      bedsAvailable: (m['bedsAvailable'] as num?)?.toInt() ?? 0,
      bedsTotal: (m['bedsTotal'] as num?)?.toInt() ?? 0,
      offeredServices: services,
      hasBloodBank: m['hasBloodBank'] == true,
      bloodUnitsAvailable: (m['bloodUnitsAvailable'] as num?)?.toInt() ?? 0,
      doctorsOnDuty: (m['doctorsOnDuty'] as num?)?.toInt() ?? 0,
      specialistsOnCall: (m['specialistsOnCall'] as num?)?.toInt() ?? 0,
      workload: (m['workload'] as num?)?.toInt() ?? 0,
      ambulanceReady: (m['ambulanceReady'] as num?)?.toInt() ?? 0,
      disqualified: (m['disqualified'] as String?)?.trim(),
      factors: HospitalDispatchFactorBreakdown.fromMap(
          m['factors'] is Map<String, dynamic>
              ? m['factors'] as Map<String, dynamic>
              : (m['factors'] as Map?)?.cast<String, dynamic>()),
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
    );
  }
}

/// One escalation wave recorded by the v2 engine (notified hospital IDs +
/// outcome). Lets the ops console animate the escalation timeline.
class DispatchWave {
  final int waveIndex;
  final List<String> hospitalIds;
  final DateTime? startedAt;
  final DateTime? timeoutAt;
  final DateTime? closedAt;
  final String? outcome; // pending | accepted | declined | timeout | superseded | exhausted
  final String? reason;
  final List<String> declinedBy;
  final String? acceptedHospitalId;

  const DispatchWave({
    required this.waveIndex,
    required this.hospitalIds,
    required this.startedAt,
    required this.timeoutAt,
    required this.closedAt,
    required this.outcome,
    required this.reason,
    required this.declinedBy,
    required this.acceptedHospitalId,
  });

  factory DispatchWave.fromMap(Map<String, dynamic> m) {
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
    return DispatchWave(
      waveIndex: (m['waveIndex'] as num?)?.toInt() ?? 0,
      hospitalIds: (m['hospitalIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      startedAt: ts(m['startedAt']),
      timeoutAt: ts(m['timeoutAt']),
      closedAt: ts(m['closedAt']),
      outcome: (m['outcome'] as String?)?.trim(),
      reason: (m['reason'] as String?)?.trim(),
      declinedBy: (m['declinedBy'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      acceptedHospitalId: (m['acceptedHospitalId'] as String?)?.trim(),
    );
  }
}

/// EmergencyOS: OpsIncidentHospitalAssignment in lib/services/ops_incident_hospital_assignment_service.dart.
class OpsIncidentHospitalAssignment {
  final String incidentId;
  final String? zoneId;
  final int? hexQ;
  final int? hexR;
  final List<String> requiredServices;
  final List<String> candidateHospitalIds;
  final List<String> orderedHospitalIds;
  final List<String> notifiedHospitalIds;
  final String? dispatchStatus;
  final String? notifiedHospitalId;
  final String? notifiedHospitalName;
  final double? notifiedHospitalLat;
  final double? notifiedHospitalLng;
  final DateTime? notifiedAt;
  final int? notifyIndex;
  final int? escalateAfterMs;
  final int? tier1EndIndex;
  final int? tier2EndIndex;
  final String? primaryHospitalId;
  final String? primaryHospitalName;
  final num? primaryDistanceKm;
  final String? acceptedHospitalId;
  final String? acceptedHospitalName;
  final double? acceptedHospitalLat;
  final double? acceptedHospitalLng;
  final DateTime? acceptedAt;
  final String? reason;
  final DateTime? assignedAt;
  final String? ambulanceDispatchStatus;
  /// Set when [dispatchStatus] becomes `failed_to_assist` (1h TTL after accept).
  final DateTime? consignmentClosedAt;
  final String? consignmentCloseReason;
  final String? assignedFleetCallSign;
  final String? assignedFleetOperatorUid;
  final DateTime? ambulanceDispatchedAt;
  final DateTime? ambulanceAcceptedAt;
  final String? dispatchingHospitalName;

  // ── v2 engine fields (all nullable so older assignments keep parsing). ─────
  /// `critical` | `high` | `standard` (drives parallelism + wave timeout).
  final String? severityTier;
  /// How many hospitals are notified simultaneously in each wave.
  final int? parallelPerWave;
  /// Per-wave escalation timeout (ms). `escalateAfterMs` is the legacy alias.
  final int? waveTimeoutMs;
  /// Maximum number of waves before the engine gives up and flags `exhausted`.
  final int? maxWaves;
  /// 0-based index of the wave currently awaiting acceptance.
  final int? currentWaveIndex;
  /// Hospital IDs being notified right now (parallel fan-out members).
  final List<String> currentWaveHospitalIds;
  /// Fully-ranked top candidates with per-factor scores (for the ops console).
  final List<RankedHospitalCandidate> rankedCandidates;
  /// Complete wave history (including pending, timeout, accepted outcomes).
  final List<DispatchWave> waves;
  final bool smsFallbackSent;
  final int? engineVersion;

  const OpsIncidentHospitalAssignment({
    required this.incidentId,
    required this.zoneId,
    required this.hexQ,
    required this.hexR,
    required this.requiredServices,
    required this.candidateHospitalIds,
    required this.orderedHospitalIds,
    required this.notifiedHospitalIds,
    required this.dispatchStatus,
    required this.notifiedHospitalId,
    required this.notifiedHospitalName,
    this.notifiedHospitalLat,
    this.notifiedHospitalLng,
    required this.notifiedAt,
    required this.notifyIndex,
    required this.escalateAfterMs,
    this.tier1EndIndex,
    this.tier2EndIndex,
    required this.primaryHospitalId,
    required this.primaryHospitalName,
    required this.primaryDistanceKm,
    required this.acceptedHospitalId,
    required this.acceptedHospitalName,
    this.acceptedHospitalLat,
    this.acceptedHospitalLng,
    required this.acceptedAt,
    required this.reason,
    required this.assignedAt,
    required this.ambulanceDispatchStatus,
    this.consignmentClosedAt,
    this.consignmentCloseReason,
    required this.assignedFleetCallSign,
    required this.assignedFleetOperatorUid,
    required this.ambulanceDispatchedAt,
    required this.ambulanceAcceptedAt,
    required this.dispatchingHospitalName,
    this.severityTier,
    this.parallelPerWave,
    this.waveTimeoutMs,
    this.maxWaves,
    this.currentWaveIndex,
    this.currentWaveHospitalIds = const <String>[],
    this.rankedCandidates = const <RankedHospitalCandidate>[],
    this.waves = const <DispatchWave>[],
    this.smsFallbackSent = false,
    this.engineVersion,
  });

  /// True when the engine is actively fanning out to multiple hospitals in
  /// parallel (critical = 3, high = 2). Used by the ops console to show the
  /// "parallel dispatch" pill on the incident tile.
  bool get isParallelFanOut =>
      (parallelPerWave ?? 1) > 1 && currentWaveHospitalIds.length > 1;

  /// Wave timeout in seconds (client-friendly, with graceful fallback).
  int get waveTimeoutSeconds =>
      ((waveTimeoutMs ?? escalateAfterMs ?? 120000) / 1000).round();

  /// Returns the ms remaining before the current wave escalates.
  /// Negative values mean the wave is overdue and the scheduler will pick it up.
  int remainingWaveMs(DateTime now) {
    final start = notifiedAt;
    if (start == null) return waveTimeoutMs ?? escalateAfterMs ?? 120000;
    final total = waveTimeoutMs ?? escalateAfterMs ?? 120000;
    return total - now.difference(start).inMilliseconds;
  }

  /// Current dispatch tier (1-indexed) based on notifyIndex and tier boundaries.
  int get currentTier {
    final idx = notifyIndex ?? 0;
    if (tier1EndIndex != null && idx < tier1EndIndex!) return 1;
    if (tier2EndIndex != null && idx < tier2EndIndex!) return 2;
    return 3;
  }

  String get currentTierLabel {
    switch (currentTier) {
      case 1:
        return 'Tier 1 · Same hex';
      case 2:
        return 'Tier 2 · Nearby hospitals';
      default:
        return 'Tier 3 · All specialists';
    }
  }

  factory OpsIncidentHospitalAssignment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final hex = d['incidentHex'] as Map<String, dynamic>?;
    final req = (d['requiredServices'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final chain = (d['candidateHospitalIds'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final ordered = (d['orderedHospitalIds'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final notifiedList = (d['notifiedHospitalIds'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final at = d['assignedAt'];
    final nt = d['notifiedAt'];
    final ac = d['acceptedAt'];
    final ad = d['ambulanceDispatchedAt'];
    final aa = d['ambulanceAcceptedAt'];
    final cc = d['consignmentClosedAt'];
    final currentWave = (d['currentWaveHospitalIds'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final rankedRaw = d['rankedCandidates'];
    final ranked = rankedRaw is List
        ? rankedRaw
            .whereType<Map>()
            .map((m) => RankedHospitalCandidate.fromMap(m.cast<String, dynamic>()))
            .toList()
        : const <RankedHospitalCandidate>[];
    final wavesRaw = d['waves'];
    final waves = wavesRaw is List
        ? wavesRaw
            .whereType<Map>()
            .map((m) => DispatchWave.fromMap(m.cast<String, dynamic>()))
            .toList()
        : const <DispatchWave>[];
    return OpsIncidentHospitalAssignment(
      incidentId: (d['incidentId'] as String?)?.trim().isNotEmpty == true ? (d['incidentId'] as String) : doc.id,
      zoneId: (d['zoneId'] as String?)?.trim(),
      hexQ: (hex?['q'] as num?)?.toInt(),
      hexR: (hex?['r'] as num?)?.toInt(),
      requiredServices: req,
      candidateHospitalIds: chain,
      orderedHospitalIds: ordered,
      notifiedHospitalIds: notifiedList,
      dispatchStatus: (d['dispatchStatus'] as String?)?.trim(),
      notifiedHospitalId: (d['notifiedHospitalId'] as String?)?.trim(),
      notifiedHospitalName: (d['notifiedHospitalName'] as String?)?.trim(),
      notifiedHospitalLat: (d['notifiedHospitalLat'] as num?)?.toDouble(),
      notifiedHospitalLng: (d['notifiedHospitalLng'] as num?)?.toDouble(),
      notifiedAt: nt is Timestamp ? nt.toDate() : null,
      notifyIndex: (d['notifyIndex'] as num?)?.toInt(),
      escalateAfterMs: (d['escalateAfterMs'] as num?)?.toInt(),
      tier1EndIndex: (d['tier1EndIndex'] as num?)?.toInt(),
      tier2EndIndex: (d['tier2EndIndex'] as num?)?.toInt(),
      primaryHospitalId: (d['primaryHospitalId'] as String?)?.trim(),
      primaryHospitalName: (d['primaryHospitalName'] as String?)?.trim(),
      primaryDistanceKm: d['primaryDistanceKm'] as num?,
      acceptedHospitalId: (d['acceptedHospitalId'] as String?)?.trim(),
      acceptedHospitalName: (d['acceptedHospitalName'] as String?)?.trim(),
      acceptedHospitalLat: (d['acceptedHospitalLat'] as num?)?.toDouble(),
      acceptedHospitalLng: (d['acceptedHospitalLng'] as num?)?.toDouble(),
      acceptedAt: ac is Timestamp ? ac.toDate() : null,
      reason: (d['reason'] as String?)?.trim(),
      assignedAt: at is Timestamp ? at.toDate() : null,
      ambulanceDispatchStatus: (d['ambulanceDispatchStatus'] as String?)?.trim(),
      consignmentClosedAt: cc is Timestamp ? cc.toDate() : null,
      consignmentCloseReason: (d['consignmentCloseReason'] as String?)?.trim(),
      assignedFleetCallSign: (d['assignedFleetCallSign'] as String?)?.trim(),
      assignedFleetOperatorUid: (d['assignedFleetOperatorUid'] as String?)?.trim(),
      ambulanceDispatchedAt: ad is Timestamp ? ad.toDate() : null,
      ambulanceAcceptedAt: aa is Timestamp ? aa.toDate() : null,
      dispatchingHospitalName: (d['dispatchingHospitalName'] as String?)?.trim(),
      severityTier: (d['severityTier'] as String?)?.trim(),
      parallelPerWave: (d['parallelPerWave'] as num?)?.toInt(),
      waveTimeoutMs: (d['waveTimeoutMs'] as num?)?.toInt(),
      maxWaves: (d['maxWaves'] as num?)?.toInt(),
      currentWaveIndex: (d['currentWaveIndex'] as num?)?.toInt(),
      currentWaveHospitalIds: currentWave,
      rankedCandidates: ranked,
      waves: waves,
      smsFallbackSent: d['smsFallbackSent'] == true,
      engineVersion: (d['engineVersion'] as num?)?.toInt(),
    );
  }
}

/// EmergencyOS: OpsIncidentHospitalAssignmentService in lib/services/ops_incident_hospital_assignment_service.dart.
class OpsIncidentHospitalAssignmentService {
  static final _db = FirebaseFirestore.instance;
  static const _col = 'ops_incident_hospital_assignments';

  static Stream<OpsIncidentHospitalAssignment?> watchForIncident(String incidentId) {
    final id = incidentId.trim();
    if (id.isEmpty) return Stream.value(null);
    return _db.collection(_col).doc(id).snapshots().map((s) {
      if (!s.exists) return null;
      return OpsIncidentHospitalAssignment.fromFirestore(s);
    }).handleError((e) {
      debugPrint('[OpsIncidentHospitalAssignmentService] watch: $e');
    });
  }

  /// Sorts hospitals by straight-line distance from the incident (nearest first)
  /// and persists the chain to `ops_incident_hospital_assignments/{incidentId}`.
  static Future<OpsIncidentHospitalAssignment?> upsertAssignmentForIncident(
    SosIncident incident, {
    List<OpsHospitalRow>? hospitalsSnapshot,
  }) async {
    final id = incident.id.trim();
    if (id.isEmpty) return null;

    final hospitals = hospitalsSnapshot ?? await OpsHospitalService.fetchHospitalsOnce();
    if (hospitals.isEmpty) return null;

    final pin = incident.liveVictimPin;
    final withCoords = hospitals.where((h) => h.lat != null && h.lng != null).toList();
    if (withCoords.isEmpty) return null;

    final scored = <({OpsHospitalRow h, double distKm})>[];
    for (final h in withCoords) {
      final m = Geolocator.distanceBetween(
        pin.latitude,
        pin.longitude,
        h.lat!,
        h.lng!,
      );
      scored.add((h: h, distKm: m / 1000.0));
    }
    scored.sort((a, b) => a.distKm.compareTo(b.distKm));

    if (scored.isEmpty) {
      debugPrint('[OpsIncidentHospitalAssignmentService] no hospitals with coordinates');
      return null;
    }

    final orderedIds = scored.map((e) => e.h.id).toList();
    final primary = scored.first;

    try {
      await _db.collection(_col).doc(id).set(
        {
          'incidentId': id,
          'requiredServices': incident.type.isNotEmpty ? [incident.type.toLowerCase()] : <String>[],
          'candidateHospitalIds': hospitals.map((h) => h.id).toList(),
          'orderedHospitalIds': orderedIds,
          'notifiedHospitalIds': const <String>[],
          'dispatchStatus': 'pending_notify',
          'primaryHospitalId': primary.h.id,
          'primaryHospitalName': primary.h.name,
          'primaryDistanceKm': primary.distKm,
          'assignedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[OpsIncidentHospitalAssignmentService] upsertAssignmentForIncident: $e');
    }

    return OpsIncidentHospitalAssignment(
      incidentId: id,
      zoneId: null,
      hexQ: null,
      hexR: null,
      requiredServices: incident.type.isNotEmpty ? [incident.type.toLowerCase()] : const <String>[],
      candidateHospitalIds: hospitals.map((h) => h.id).toList(),
      orderedHospitalIds: orderedIds,
      notifiedHospitalIds: const <String>[],
      dispatchStatus: 'pending_notify',
      notifiedHospitalId: null,
      notifiedHospitalName: null,
      notifiedAt: null,
      notifyIndex: null,
      escalateAfterMs: null,
      primaryHospitalId: primary.h.id,
      primaryHospitalName: primary.h.name,
      primaryDistanceKm: primary.distKm,
      acceptedHospitalId: null,
      acceptedHospitalName: null,
      acceptedAt: null,
      reason: null,
      assignedAt: DateTime.now(),
      ambulanceDispatchStatus: null,
      consignmentClosedAt: null,
      consignmentCloseReason: null,
      assignedFleetCallSign: null,
      assignedFleetOperatorUid: null,
      ambulanceDispatchedAt: null,
      ambulanceAcceptedAt: null,
      dispatchingHospitalName: null,
    );
  }
}

