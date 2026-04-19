import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/legacy_demo_ops_hospital_ids.dart';

/// Hospital bed / capacity row for the emergency services grid (demo: any signed-in client may write).
class OpsHospitalRow {
  final String id;
  final String name;
  final String region;
  final int bedsAvailable;
  final int bedsTotal;
  final String? traumaBedsNote;
  final DateTime updatedAt;
  final double? lat;
  final double? lng;
  final List<String> offeredServices;
  final bool hasBloodBank;
  final int doctorsOnDuty;
  final int specialistsOnCall;
  final int bloodUnitsAvailable;
  /// True when `ops_hospitals/{id}` contains `staffCredentials` from onboarding.
  final bool hasStaffCredentials;
  /// Hospital dashboard: when false, main map shows this facility as offline for routing visibility.
  final bool mapListingOnline;
  /// Legacy field; per-hospital hex dispatch filtering is no longer used in-app.
  final bool coverageHexUseCustom;
  final List<String> coverageHexKeys;

  const OpsHospitalRow({
    required this.id,
    required this.name,
    required this.region,
    required this.bedsAvailable,
    required this.bedsTotal,
    this.traumaBedsNote,
    required this.updatedAt,
    this.lat,
    this.lng,
    this.offeredServices = const [],
    this.hasBloodBank = false,
    this.doctorsOnDuty = 0,
    this.specialistsOnCall = 0,
    this.bloodUnitsAvailable = 0,
    this.hasStaffCredentials = false,
    this.mapListingOnline = true,
    this.coverageHexUseCustom = false,
    this.coverageHexKeys = const [],
  });

  factory OpsHospitalRow.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final servicesRaw = d['offeredServices'];
    final offeredServices = servicesRaw is List
        ? servicesRaw.map((e) => e.toString()).toList()
        : <String>[];
    final hexRaw = d['coverageHexKeys'];
    final coverageHexKeys = hexRaw is List
        ? hexRaw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : const <String>[];
    final hasStaffCredentials = d['staffCredentials'] is Map;
    return OpsHospitalRow(
      id: doc.id,
      name: (d['name'] as String?) ?? doc.id,
      region: (d['region'] as String?) ?? '—',
      bedsAvailable: (d['bedsAvailable'] as num?)?.toInt() ?? 0,
      bedsTotal: (d['bedsTotal'] as num?)?.toInt() ?? 0,
      traumaBedsNote: d['traumaBedsNote'] as String?,
      updatedAt: _ts(d['updatedAt']) ?? DateTime.now(),
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      offeredServices: offeredServices,
      hasBloodBank: d['hasBloodBank'] as bool? ?? false,
      doctorsOnDuty: (d['doctorsOnDuty'] as num?)?.toInt() ?? 0,
      specialistsOnCall: (d['specialistsOnCall'] as num?)?.toInt() ?? 0,
      bloodUnitsAvailable: (d['bloodUnitsAvailable'] as num?)?.toInt() ?? 0,
      hasStaffCredentials: hasStaffCredentials,
      mapListingOnline: d['mapListingOnline'] is bool ? d['mapListingOnline'] as bool : true,
      coverageHexUseCustom: d['coverageHexUseCustom'] == true,
      coverageHexKeys: coverageHexKeys,
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }
}

/// EmergencyOS: OpsHospitalService in lib/services/ops_hospital_service.dart.
class OpsHospitalService {
  static final _db = FirebaseFirestore.instance;
  static const _col = 'ops_hospitals';

  static Stream<List<OpsHospitalRow>> watchHospitals() {
    return _db
        .collection(_col)
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(OpsHospitalRow.fromFirestore).toList())
        .handleError((e) {
          debugPrint('[OpsHospitalService] watch: $e');
        });
  }

  /// Live updates for one facility (command strip, scoped medical console).
  static Stream<OpsHospitalRow?> watchHospital(String id) {
    final idTrim = id.trim();
    if (idTrim.isEmpty) return const Stream<OpsHospitalRow?>.empty();
    return _db.collection(_col).doc(idTrim).snapshots().map((s) {
      if (!s.exists) return null;
      return OpsHospitalRow.fromFirestore(s);
    });
  }

  /// One-shot fetch of all hospital rows (sorted by name) for decision engines.
  static Future<List<OpsHospitalRow>> fetchHospitalsOnce() async {
    try {
      final snap = await _db.collection(_col).orderBy('name').get();
      return snap.docs.map(OpsHospitalRow.fromFirestore).toList();
    } catch (e) {
      debugPrint('[OpsHospitalService] fetchHospitalsOnce: $e');
      return const <OpsHospitalRow>[];
    }
  }

  /// No-op: facilities are created via onboarding / admin only (no bundled demo catalog).
  static Future<void> ensureHospitalGateDocumentsMerged() async {}

  /// Kept for call-site compatibility; does not seed demo rows.
  static Future<void> ensureDemoRowsIfEmpty() async {}

  static const _fleetAccountsCol = 'ops_fleet_accounts';

  /// Deletes bundled-catalog `ops_hospitals` docs and matching `ops_fleet_accounts` gate rows
  /// (`EMS-H-LKO-n-A` / `-S`) that may still exist from older app versions.
  ///
  /// Returns false if any delete failed (e.g. security rules) so callers can retry later.
  static Future<bool> purgeLegacyBundledHospitalDocumentsFromFirestore() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (e) {
      debugPrint('[OpsHospitalService] purgeLegacy auth: $e');
    }
    var failed = false;
    for (final id in LegacyBundledOpsHospitalIds.docIds) {
      try {
        await _db.collection(_col).doc(id).delete();
      } catch (e) {
        failed = true;
        debugPrint('[OpsHospitalService] purge ops_hospitals/$id: $e');
      }
    }
    for (final cs in LegacyBundledOpsHospitalIds.legacyEmsFleetGateDocIds()) {
      try {
        await _db.collection(_fleetAccountsCol).doc(cs).delete();
      } catch (e) {
        failed = true;
        debugPrint('[OpsHospitalService] purge ops_fleet_accounts/$cs: $e');
      }
    }
    return !failed;
  }

  static Future<void> updateBeds({
    required String id,
    required int bedsAvailable,
    required int bedsTotal,
    String? traumaBedsNote,
  }) async {
    final data = <String, Object?>{
      'bedsAvailable': bedsAvailable,
      'bedsTotal': bedsTotal,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (traumaBedsNote != null) data['traumaBedsNote'] = traumaBedsNote;
    await _db.collection(_col).doc(id).set(data, SetOptions(merge: true));
  }

  static Future<void> updateServices({
    required String id,
    required List<String> offeredServices,
    required bool hasBloodBank,
  }) async {
    await _db.collection(_col).doc(id).set({
      'offeredServices': offeredServices,
      'hasBloodBank': hasBloodBank,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Merge-only update for allocator-facing specialties (Live Operations tab).
  /// Does not touch beds, blood bank flag, or map listing.
  static Future<void> updateOfferedServicesOnly({
    required String id,
    required List<String> offeredServices,
  }) async {
    await _db.collection(_col).doc(id.trim()).set(
      {
        'offeredServices': offeredServices,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// One merge write for beds + services (admin hospital editor). Avoids a snapshot
  /// between separate writes that can confuse in-memory form state.
  static Future<void> updateBedsAndServices({
    required String id,
    required int bedsAvailable,
    required int bedsTotal,
    String? traumaBedsNote,
    required List<String> offeredServices,
    required bool hasBloodBank,
  }) async {
    final data = <String, Object?>{
      'bedsAvailable': bedsAvailable,
      'bedsTotal': bedsTotal,
      'offeredServices': offeredServices,
      'hasBloodBank': hasBloodBank,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (traumaBedsNote != null) data['traumaBedsNote'] = traumaBedsNote;
    await _db.collection(_col).doc(id).set(data, SetOptions(merge: true));
  }

  /// Staffing / blood inventory snapshot for LiveOps dashboard.
  static Future<void> updateLiveOpsStaffing({
    required String id,
    required int doctorsOnDuty,
    required int specialistsOnCall,
    required int bloodUnitsAvailable,
  }) async {
    await _db.collection(_col).doc(id).set({
      'doctorsOnDuty': doctorsOnDuty.clamp(0, 999),
      'specialistsOnCall': specialistsOnCall.clamp(0, 999),
      'bloodUnitsAvailable': bloodUnitsAvailable.clamp(0, 99999),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Single merge write for the Hospital LiveOps card (beds, services, staffing).
  ///
  /// Using one [updatedAt] bump prevents Firestore snapshots from arriving between
  /// partial writes; those used to reset local service chips from stale data.
  static Future<void> updateMapListingOnline({
    required String id,
    required bool mapListingOnline,
  }) async {
    await _db.collection(_col).doc(id.trim()).set(
      {
        'mapListingOnline': mapListingOnline,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Master Management: update GPS pin only (merge; does not touch credentials).
  static Future<void> updateMapCoordinates({
    required String id,
    required double lat,
    required double lng,
  }) async {
    await _db.collection(_col).doc(id.trim()).set(
      {
        'lat': lat,
        'lng': lng,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> updateLiveOpsFull({
    required String id,
    required int bedsAvailable,
    required int bedsTotal,
    String? traumaBedsNote,
    required List<String> offeredServices,
    required bool hasBloodBank,
    required int doctorsOnDuty,
    required int specialistsOnCall,
    required int bloodUnitsAvailable,
  }) async {
    final data = <String, Object?>{
      'bedsAvailable': bedsAvailable,
      'bedsTotal': bedsTotal,
      'offeredServices': offeredServices,
      'hasBloodBank': hasBloodBank,
      'doctorsOnDuty': doctorsOnDuty.clamp(0, 999),
      'specialistsOnCall': specialistsOnCall.clamp(0, 999),
      'bloodUnitsAvailable': bloodUnitsAvailable.clamp(0, 99999),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (traumaBedsNote != null) data['traumaBedsNote'] = traumaBedsNote;
    await _db.collection(_col).doc(id).set(data, SetOptions(merge: true));
  }

  /// Legacy merge for hospital hex lists (UI removed; safe no-op for old clients).
  static Future<void> updateCoverageHexSelection({
    required String id,
    required bool coverageHexUseCustom,
    required List<String> coverageHexKeys,
  }) async {
    await _db.collection(_col).doc(id.trim()).set(
      {
        'coverageHexUseCustom': coverageHexUseCustom,
        'coverageHexKeys': coverageHexKeys,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> addHospital({
    required String name,
    required String region,
    int bedsAvailable = 0,
    int bedsTotal = 0,
    double? lat,
    double? lng,
    List<String> offeredServices = const [],
    bool hasBloodBank = false,
  }) async {
    final ref = _db.collection(_col).doc();
    final data = <String, Object?>{
      'name': name,
      'region': region,
      'bedsAvailable': bedsAvailable,
      'bedsTotal': bedsTotal,
      'offeredServices': offeredServices,
      'hasBloodBank': hasBloodBank,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (lat != null) data['lat'] = lat;
    if (lng != null) data['lng'] = lng;
    await ref.set(data);
  }
}
