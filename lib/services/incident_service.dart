import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/sos_demo_incident_filter.dart';
import 'drill_session_persistence.dart';
import 'offline_cache_service.dart';
import 'leaderboard_service.dart';
import 'ops_incident_hospital_assignment_service.dart';

// ---------------------------------------------------------------------------
// Incident Service — Firestore persistence for SOS incidents
// ---------------------------------------------------------------------------

/// EmergencyOS: IncidentStatus in lib/services/incident_service.dart.
enum IncidentStatus { pending, dispatched, blocked, resolved }

/// EmergencyOS: SosIncident in lib/services/incident_service.dart.
class SosIncident {
  final String id;
  final String userId;
  final String userDisplayName;
  final LatLng location;
  final String type; // e.g. 'Cardiac Arrest'
  final DateTime timestamp;
  final DateTime goldenHourStart;
  final IncidentStatus status;
  
  // Privacy-preserving Medical Data (attached at time of SOS only)
  final String? bloodType;
  final String? allergies;
  final String? medicalConditions;
  
  // ETA / Responder Updates
  final String? ambulanceEta;
  final String? medicalStatus; // "medical eta" / status

  // Emergency contact updates (victim chosen contact)
  final String? emergencyContactPhone;
  final String? emergencyContactEmail;
  final bool useEmergencyContactForSms;
  /// Optional secret used for family tracker links (read-only status view).
  final String? familyTrackingToken;
  
  // List of IDs for volunteers who accepted this incident
  final List<String> acceptedVolunteerIds;

  /// Ambulance / EMS unit last reported position (ops consoles).
  final double? ambulanceLiveLat;
  final double? ambulanceLiveLng;
  final DateTime? ambulanceLiveUpdatedAt;
  /// Compass heading (0° north, clockwise) for flat vehicle marker rotation.
  final double? ambulanceLiveHeadingDeg;
  final String? adminDispatchNote;

  /// Inbound GeoSMS created this incident (SMS-only path).
  final bool smsOrigin;
  /// Victim phone for Twilio ETA bridge (SMS-origin or parallel relay).
  final String? senderPhone;
  /// Parallel GeoSMS linked to an existing in-app SOS (backend merge).
  final bool smsRelayReceived;
  final DateTime? smsRelayAt;
  /// Backend confirmed GeoSMS parse (new incident or relay merge).
  final bool geoSmsPatternRecognized;
  final DateTime? geoSmsRecognizedAt;

  /// EMS / official unit workflow: `inbound` → `on_scene` (~200 m) → `returning` (rescue complete) → `complete` (then archived).
  final String? emsWorkflowPhase;
  final DateTime? emsAcceptedAt;
  final String? emsAcceptedBy;
  final DateTime? emsOnSceneAt;
  final DateTime? emsRescueCompleteAt;
  final DateTime? emsReturningStartedAt;
  final DateTime? emsHospitalArrivalAt;
  final DateTime? emsResponseCompleteAt;
  final String? returnHospitalId;
  final double? returnHospitalLat;
  final double? returnHospitalLng;

  /// Crane / heavy recovery unit (mobile console + command).
  final String? craneUnitAcceptedBy;
  final DateTime? craneUnitAcceptedAt;
  final double? craneLiveLat;
  final double? craneLiveLng;
  final DateTime? craneLiveUpdatedAt;
  final double? craneLiveHeadingDeg;

  /// Last volunteer-reported position (active consignment map).
  final double? volunteerLat;
  final double? volunteerLng;
  final DateTime? volunteerUpdatedAt;

  /// Victim breadcrumb GPS (SOS active screen).
  final double? lastKnownLat;
  final double? lastKnownLng;
  final DateTime? lastLocationAt;

  final List<String> onSceneVolunteerIds;
  final Map<String, String> responderNames;

  /// Victim triage / interview snapshot (SOS active).
  final Map<String, dynamic>? triage;

  /// Volunteer structured scene report (on-scene tab).
  final Map<String, dynamic>? volunteerSceneReport;

  /// Shared Gemini situation brief stored on the incident document.
  ///
  /// Generated from on-scene volunteer assessment, scene photos, video
  /// assessment, and dispatch context. Read-only for clients — updated by
  /// Cloud Functions / backend pipelines.
  final Map<String, dynamic>? sharedSituationBrief;

  /// Green corridor dispatch status from Cloud Function (`sending`, `sent`, `failed`).
  final String? greenCorridorStatus;

  /// First time the incident moved off purely “open” (pending) — volunteer accept or ops dispatch.
  final DateTime? firstAcknowledgedAt;
  final String? firstAcknowledgedByUid;

  bool get smsRelayOrOrigin => smsOrigin || smsRelayReceived;

  /// Human-readable lifecycle bucket for ops consoles (open → assigned → closed).
  String get lifecyclePhaseLabel {
    switch (status) {
      case IncidentStatus.pending:
        return 'Open';
      case IncidentStatus.dispatched:
        return 'Assigned';
      case IncidentStatus.blocked:
        return 'Blocked';
      case IncidentStatus.resolved:
        return 'Closed';
    }
  }

  /// Prefer live GPS breadcrumbs over the original SOS pin when present.
  LatLng get liveVictimPin {
    final a = lastKnownLat;
    final b = lastKnownLng;
    if (a != null && b != null) return LatLng(a, b);
    return location;
  }

  LatLng? get volunteerLiveLocation {
    final a = volunteerLat;
    final b = volunteerLng;
    if (a == null || b == null) return null;
    return LatLng(a, b);
  }

  const SosIncident({
    required this.id,
    required this.userId,
    required this.userDisplayName,
    required this.location,
    required this.type,
    required this.timestamp,
    required this.goldenHourStart,
    this.status = IncidentStatus.pending,
    this.bloodType,
    this.allergies,
    this.medicalConditions,
    this.ambulanceEta,
    this.medicalStatus,
    this.emergencyContactPhone,
    this.emergencyContactEmail,
    this.useEmergencyContactForSms = false,
    this.familyTrackingToken,
    this.acceptedVolunteerIds = const [],
    this.ambulanceLiveLat,
    this.ambulanceLiveLng,
    this.ambulanceLiveUpdatedAt,
    this.ambulanceLiveHeadingDeg,
    this.adminDispatchNote,
    this.smsOrigin = false,
    this.senderPhone,
    this.smsRelayReceived = false,
    this.smsRelayAt,
    this.geoSmsPatternRecognized = false,
    this.geoSmsRecognizedAt,
    this.emsWorkflowPhase,
    this.emsAcceptedAt,
    this.emsAcceptedBy,
    this.emsOnSceneAt,
    this.emsRescueCompleteAt,
    this.emsReturningStartedAt,
    this.emsHospitalArrivalAt,
    this.emsResponseCompleteAt,
    this.returnHospitalId,
    this.returnHospitalLat,
    this.returnHospitalLng,
    this.craneUnitAcceptedBy,
    this.craneUnitAcceptedAt,
    this.craneLiveLat,
    this.craneLiveLng,
    this.craneLiveUpdatedAt,
    this.craneLiveHeadingDeg,
    this.volunteerLat,
    this.volunteerLng,
    this.volunteerUpdatedAt,
    this.lastKnownLat,
    this.lastKnownLng,
    this.lastLocationAt,
    this.onSceneVolunteerIds = const [],
    this.responderNames = const {},
    this.triage,
    this.volunteerSceneReport,
    this.sharedSituationBrief,
    this.greenCorridorStatus,
    this.firstAcknowledgedAt,
    this.firstAcknowledgedByUid,
  });

  LatLng? get ambulanceLiveLocation {
    final a = ambulanceLiveLat;
    final b = ambulanceLiveLng;
    if (a == null || b == null) return null;
    return LatLng(a, b);
  }

  LatLng? get craneLiveLocation {
    final a = craneLiveLat;
    final b = craneLiveLng;
    if (a == null || b == null) return null;
    return LatLng(a, b);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'userDisplayName': userDisplayName,
    'lat': location.latitude,
    'lng': location.longitude,
    'type': type,
    'timestamp': timestamp.toIso8601String(),
    'goldenHourStart': goldenHourStart.toIso8601String(),
    'status': status.name,
    if (bloodType != null) 'bloodType': bloodType,
    if (allergies != null) 'allergies': allergies,
    if (medicalConditions != null) 'medicalConditions': medicalConditions,
    if (ambulanceEta != null) 'ambulanceEta': ambulanceEta,
    if (medicalStatus != null) 'medicalStatus': medicalStatus,
    if (emergencyContactPhone != null) 'emergencyContactPhone': emergencyContactPhone,
    if (emergencyContactEmail != null && emergencyContactEmail!.trim().isNotEmpty)
      'emergencyContactEmail': emergencyContactEmail!.trim(),
    'useEmergencyContactForSms': useEmergencyContactForSms,
    if (familyTrackingToken != null) 'familyTrackingToken': familyTrackingToken,
    'acceptedVolunteerIds': acceptedVolunteerIds,
    if (ambulanceLiveLat != null) 'ambulanceLiveLat': ambulanceLiveLat,
    if (ambulanceLiveLng != null) 'ambulanceLiveLng': ambulanceLiveLng,
    if (ambulanceLiveUpdatedAt != null)
      'ambulanceLiveUpdatedAt': ambulanceLiveUpdatedAt!.toIso8601String(),
    if (ambulanceLiveHeadingDeg != null) 'ambulanceLiveHeadingDeg': ambulanceLiveHeadingDeg,
    if (adminDispatchNote != null) 'adminDispatchNote': adminDispatchNote,
    'smsOrigin': smsOrigin,
    if (senderPhone != null) 'senderPhone': senderPhone,
    'smsRelayReceived': smsRelayReceived,
    if (smsRelayAt != null) 'smsRelayAt': smsRelayAt!.toIso8601String(),
    'geoSmsPatternRecognized': geoSmsPatternRecognized,
    if (geoSmsRecognizedAt != null)
      'geoSmsRecognizedAt': geoSmsRecognizedAt!.toIso8601String(),
    if (emsWorkflowPhase != null) 'emsWorkflowPhase': emsWorkflowPhase,
    if (emsAcceptedAt != null) 'emsAcceptedAt': emsAcceptedAt!.toIso8601String(),
    if (emsAcceptedBy != null) 'emsAcceptedBy': emsAcceptedBy,
    if (emsOnSceneAt != null) 'emsOnSceneAt': emsOnSceneAt!.toIso8601String(),
    if (emsRescueCompleteAt != null) 'emsRescueCompleteAt': emsRescueCompleteAt!.toIso8601String(),
    if (emsReturningStartedAt != null) 'emsReturningStartedAt': emsReturningStartedAt!.toIso8601String(),
    if (emsHospitalArrivalAt != null) 'emsHospitalArrivalAt': emsHospitalArrivalAt!.toIso8601String(),
    if (emsResponseCompleteAt != null) 'emsResponseCompleteAt': emsResponseCompleteAt!.toIso8601String(),
    if (returnHospitalId != null) 'returnHospitalId': returnHospitalId,
    if (returnHospitalLat != null) 'returnHospitalLat': returnHospitalLat,
    if (returnHospitalLng != null) 'returnHospitalLng': returnHospitalLng,
    if (craneUnitAcceptedBy != null) 'craneUnitAcceptedBy': craneUnitAcceptedBy,
    if (craneUnitAcceptedAt != null) 'craneUnitAcceptedAt': craneUnitAcceptedAt!.toIso8601String(),
    if (craneLiveLat != null) 'craneLiveLat': craneLiveLat,
    if (craneLiveLng != null) 'craneLiveLng': craneLiveLng,
    if (craneLiveUpdatedAt != null) 'craneLiveUpdatedAt': craneLiveUpdatedAt!.toIso8601String(),
    if (craneLiveHeadingDeg != null) 'craneLiveHeadingDeg': craneLiveHeadingDeg,
    if (volunteerLat != null) 'volunteerLat': volunteerLat,
    if (volunteerLng != null) 'volunteerLng': volunteerLng,
    if (volunteerUpdatedAt != null)
      'volunteerUpdatedAt': volunteerUpdatedAt!.toIso8601String(),
    if (lastKnownLat != null) 'lastKnownLat': lastKnownLat,
    if (lastKnownLng != null) 'lastKnownLng': lastKnownLng,
    if (lastLocationAt != null) 'lastLocationAt': lastLocationAt!.toIso8601String(),
    if (onSceneVolunteerIds.isNotEmpty) 'onSceneVolunteerIds': onSceneVolunteerIds,
    if (responderNames.isNotEmpty) 'responderNames': responderNames,
    if (triage != null) 'triage': triage,
    if (volunteerSceneReport != null) 'volunteerSceneReport': volunteerSceneReport,
    if (sharedSituationBrief != null) 'sharedSituationBrief': sharedSituationBrief,
    if (firstAcknowledgedAt != null)
      'firstAcknowledgedAt': firstAcknowledgedAt!.toIso8601String(),
    if (firstAcknowledgedByUid != null) 'firstAcknowledgedByUid': firstAcknowledgedByUid,
    if (greenCorridorStatus != null) 'greenCorridorStatus': greenCorridorStatus,
  };

  static Map<String, String> _parseResponderNames(dynamic v) {
    if (v is! Map) return {};
    return v.map((k, val) => MapEntry(k.toString(), val?.toString() ?? ''));
  }

  /// Missing or invalid values must not default to [DateTime.now()] or they bypass the 1-hour SOS window.
  static DateTime _parseInstant(dynamic v) {
    if (v == null) return _invalidIncidentInstant;
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) {
      final p = DateTime.tryParse(v);
      if (p != null) return p;
    }
    return _invalidIncidentInstant;
  }

  static final DateTime _invalidIncidentInstant =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  factory SosIncident.fromJson(Map<String, dynamic> j) => SosIncident(
    id: j['id'] ?? '',
    userId: j['userId'] ?? '',
    userDisplayName: j['userDisplayName'] ?? 'Unknown',
    location: LatLng((j['lat'] ?? 0.0).toDouble(), (j['lng'] ?? 0.0).toDouble()),
    type: j['type'] ?? 'Unknown',
    timestamp: _parseInstant(j['timestamp']),
    goldenHourStart: _parseInstant(j['goldenHourStart']),
    status: IncidentStatus.values.firstWhere(
      (s) => s.name == j['status'], orElse: () => IncidentStatus.pending),
    bloodType: j['bloodType'] as String?,
    allergies: j['allergies'] as String?,
    medicalConditions: j['medicalConditions'] as String?,
    ambulanceEta: j['ambulanceEta'] as String?,
    medicalStatus: j['medicalStatus'] as String?,
    emergencyContactPhone: j['emergencyContactPhone'] as String?,
    emergencyContactEmail: () {
      final s = (j['emergencyContactEmail'] as String?)?.trim();
      if (s == null || s.isEmpty) return null;
      return s;
    }(),
    useEmergencyContactForSms: (j['useEmergencyContactForSms'] as bool?) ?? false,
    familyTrackingToken: j['familyTrackingToken'] as String?,
    acceptedVolunteerIds: List<String>.from(j['acceptedVolunteerIds'] ?? []),
    ambulanceLiveLat: (j['ambulanceLiveLat'] as num?)?.toDouble(),
    ambulanceLiveLng: (j['ambulanceLiveLng'] as num?)?.toDouble(),
    ambulanceLiveUpdatedAt: j['ambulanceLiveUpdatedAt'] != null
        ? _parseInstant(j['ambulanceLiveUpdatedAt'])
        : null,
    ambulanceLiveHeadingDeg: (j['ambulanceLiveHeadingDeg'] as num?)?.toDouble(),
    adminDispatchNote: j['adminDispatchNote'] as String?,
    smsOrigin: (j['smsOrigin'] as bool?) ?? false,
    senderPhone: j['senderPhone'] as String?,
    smsRelayReceived: (j['smsRelayReceived'] as bool?) ?? false,
    smsRelayAt: j['smsRelayAt'] != null ? _parseInstant(j['smsRelayAt']) : null,
    geoSmsPatternRecognized: (j['geoSmsPatternRecognized'] as bool?) ?? false,
    geoSmsRecognizedAt:
        j['geoSmsRecognizedAt'] != null ? _parseInstant(j['geoSmsRecognizedAt']) : null,
    emsWorkflowPhase: j['emsWorkflowPhase'] as String?,
    emsAcceptedAt:
        j['emsAcceptedAt'] != null ? _parseInstant(j['emsAcceptedAt']) : null,
    emsAcceptedBy: j['emsAcceptedBy'] as String?,
    emsOnSceneAt:
        j['emsOnSceneAt'] != null ? _parseInstant(j['emsOnSceneAt']) : null,
    emsRescueCompleteAt:
        j['emsRescueCompleteAt'] != null ? _parseInstant(j['emsRescueCompleteAt']) : null,
    emsReturningStartedAt:
        j['emsReturningStartedAt'] != null ? _parseInstant(j['emsReturningStartedAt']) : null,
    emsHospitalArrivalAt:
        j['emsHospitalArrivalAt'] != null ? _parseInstant(j['emsHospitalArrivalAt']) : null,
    emsResponseCompleteAt:
        j['emsResponseCompleteAt'] != null ? _parseInstant(j['emsResponseCompleteAt']) : null,
    returnHospitalId: j['returnHospitalId'] as String?,
    returnHospitalLat: (j['returnHospitalLat'] as num?)?.toDouble(),
    returnHospitalLng: (j['returnHospitalLng'] as num?)?.toDouble(),
    craneUnitAcceptedBy: j['craneUnitAcceptedBy'] as String?,
    craneUnitAcceptedAt: j['craneUnitAcceptedAt'] != null
        ? _parseInstant(j['craneUnitAcceptedAt'])
        : null,
    craneLiveLat: (j['craneLiveLat'] as num?)?.toDouble(),
    craneLiveLng: (j['craneLiveLng'] as num?)?.toDouble(),
    craneLiveUpdatedAt: j['craneLiveUpdatedAt'] != null
        ? _parseInstant(j['craneLiveUpdatedAt'])
        : null,
    craneLiveHeadingDeg: (j['craneLiveHeadingDeg'] as num?)?.toDouble(),
    volunteerLat: (j['volunteerLat'] as num?)?.toDouble(),
    volunteerLng: (j['volunteerLng'] as num?)?.toDouble(),
    volunteerUpdatedAt: j['volunteerUpdatedAt'] != null
        ? _parseInstant(j['volunteerUpdatedAt'])
        : null,
    lastKnownLat: (j['lastKnownLat'] as num?)?.toDouble(),
    lastKnownLng: (j['lastKnownLng'] as num?)?.toDouble(),
    lastLocationAt:
        j['lastLocationAt'] != null ? _parseInstant(j['lastLocationAt']) : null,
    onSceneVolunteerIds: List<String>.from(j['onSceneVolunteerIds'] ?? []),
    responderNames: _parseResponderNames(j['responderNames']),
    triage: j['triage'] is Map ? Map<String, dynamic>.from(j['triage'] as Map) : null,
    volunteerSceneReport: j['volunteerSceneReport'] is Map
        ? Map<String, dynamic>.from(j['volunteerSceneReport'] as Map)
        : null,
    sharedSituationBrief: j['sharedSituationBrief'] is Map
        ? Map<String, dynamic>.from(j['sharedSituationBrief'] as Map)
        : null,
    greenCorridorStatus: j['greenCorridorStatus'] as String?,
    firstAcknowledgedAt: j['firstAcknowledgedAt'] != null
        ? _parseInstant(j['firstAcknowledgedAt'])
        : null,
    firstAcknowledgedByUid: j['firstAcknowledgedByUid'] as String?,
  );

  factory SosIncident.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SosIncident.fromJson({...d, 'id': doc.id});
  }
}

/// EmergencyOS: IncidentService in lib/services/incident_service.dart.
class IncidentService {
  static final _db = FirebaseFirestore.instance;
  static const _col = 'sos_incidents';
  static final _uuid = Uuid();
  static const _archiveCol = 'sos_incidents_archive';
  static const String _kIncomingAlertShownPref = 'incoming_alert_shown_times_v1';

  /// Open SOS incidents and volunteer response bindings expire after this window.
  static const Duration activeSosMaxDuration = Duration(hours: 1);

  static final DateTime _invalidIncidentTimestamp =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static DateTime _parseIncidentTimestampField(dynamic v) {
    if (v == null) return _invalidIncidentTimestamp;
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) {
      final p = DateTime.tryParse(v);
      if (p != null) return p;
    }
    return _invalidIncidentTimestamp;
  }

  /// True when [incidentStart] is at or past the active SOS lifetime (1 hour).
  static bool isIncidentActiveWindowExpired(DateTime incidentStart) {
    return DateTime.now().difference(incidentStart) >= activeSosMaxDuration;
  }

  static bool _incidentMapOpenAndUnexpired(Map<String, dynamic> d) {
    final st = (d['status'] as String?) ?? '';
    if (!['pending', 'dispatched', 'blocked'].contains(st)) return false;
    final ts = _parseIncidentTimestampField(d['timestamp']);
    return !isIncidentActiveWindowExpired(ts);
  }

  static Future<bool> _validateVolunteerAssignmentActive({
    required String incidentId,
    required String volunteerUid,
  }) async {
    if (incidentId.isEmpty || volunteerUid.isEmpty) return false;
    if (incidentId == AppConstants.drillIncidentId) return true;
    try {
      final doc = await _db.collection(_col).doc(incidentId).get();
      if (!doc.exists || doc.data() == null) return false;
      final d = doc.data()!;
      if (!_incidentMapOpenAndUnexpired(d)) return false;
      final accepted = List<String>.from(d['acceptedVolunteerIds'] ?? []);
      return accepted.contains(volunteerUid);
    } catch (_) {
      return false;
    }
  }

  static Future<void> _clearResponderAssignmentsForIncident(
    String incidentId,
    Set<String> responderUids,
  ) async {
    if (incidentId.isEmpty) return;
    for (final vid in responderUids) {
      if (vid.isEmpty || vid == 'system_auto_expire' || vid == 'system_auto_archive') continue;
      try {
        final uref = _db.collection('users').doc(vid);
        final u = await uref.get();
        final assign = u.data()?['activeAssignment'] as Map<String, dynamic>?;
        final aid = (assign?['incidentId'] as String?)?.trim();
        if (aid == incidentId) {
          await uref.set(
            {'activeAssignment': FieldValue.delete()},
            SetOptions(merge: true),
          );
        }
      } catch (e) {
        debugPrint('[IncidentService] clear responder assignment $vid: $e');
      }
    }
  }

  /// Incidents the volunteer explicitly left from the response UI this app run — do not re-queue alerts.
  static final Set<String> volunteerWithdrewIncidentIds = <String>{};

  /// IDs for which we already surfaced the full-screen incoming SOS UI (persisted so
  /// leaving [MainNavigationShell] / web navigator quirks cannot replay the same alert).
  static Future<Set<String>> loadRecentlyShownIncomingAlertIds() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kIncomingAlertShownPref);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final cutoff =
          DateTime.now().subtract(const Duration(hours: 6)).millisecondsSinceEpoch;
      final out = <String>{};
      for (final e in decoded.entries) {
        final id = e.key;
        final v = e.value;
        final ms = v is int ? v : int.tryParse('$v') ?? 0;
        if (ms >= cutoff && id.isNotEmpty) out.add(id);
      }
      return out;
    } catch (e) {
      debugPrint('[IncidentService] loadRecentlyShownIncomingAlertIds: $e');
      return {};
    }
  }

  static Future<void> rememberIncomingAlertShown(String incidentId) async {
    if (incidentId.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      var map = <String, int>{};
      final raw = p.getString(_kIncomingAlertShownPref);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in decoded.entries) {
          final v = e.value;
          map[e.key] = v is int ? v : int.tryParse('$v') ?? 0;
        }
      }
      map[incidentId] = DateTime.now().millisecondsSinceEpoch;
      final cutoff =
          DateTime.now().subtract(const Duration(hours: 6)).millisecondsSinceEpoch;
      map.removeWhere((_, t) => t < cutoff);
      if (map.length > 150) {
        final sorted = map.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
        map = Map.fromEntries(sorted.sublist(sorted.length - 150));
      }
      await p.setString(_kIncomingAlertShownPref, jsonEncode(map));
    } catch (e) {
      debugPrint('[IncidentService] rememberIncomingAlertShown: $e');
    }
  }

  /// Public timeline line (victim + volunteer + dispatch UIs). Any authenticated client may create per rules.
  /// Append-only audit row under [incidentId] (`sos_incidents/{id}/audit_log`).
  static Future<void> appendIncidentAuditLog(
    String incidentId, {
    required String action,
    String? fromStatus,
    String? toStatus,
    String? note,
  }) async {
    final id = incidentId.trim();
    if (id.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      await _db.collection(_col).doc(id).collection('audit_log').add({
        'at': FieldValue.serverTimestamp(),
        'actorUid': uid,
        'action': action,
        if (fromStatus != null && fromStatus.isNotEmpty) 'fromStatus': fromStatus,
        if (toStatus != null && toStatus.isNotEmpty) 'toStatus': toStatus,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });
    } catch (e) {
      debugPrint('[IncidentService] appendIncidentAuditLog: $e');
    }
  }

  static Future<void> appendIncidentFeedLine({
    required String incidentId,
    required String text,
    String source = 'responder',
  }) async {
    final id = incidentId.trim();
    if (id.isEmpty || text.trim().isEmpty) return;
    try {
      await _db.collection(_col).doc(id).collection('victim_activity').add({
        'text': text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'source': source,
      });
    } catch (e) {
      debugPrint('[IncidentService] appendIncidentFeedLine: $e');
    }
  }

  /// Incident IDs created on THIS device during this app session.
  /// Used to filter out self-created incidents from the alert system
  /// without incorrectly blocking the same user on a different device.
  static final Set<String> _deviceCreatedIncidentIds = {};

  static bool wasCreatedOnThisDevice(String id) =>
      _deviceCreatedIncidentIds.contains(id);

  /// Reverse-geocode [location] to a 3-letter uppercase area code (e.g. "LKO"
  /// for Lucknow). Returns `'UNK'` when geocoding is unavailable (e.g. web) or
  /// when no locality can be determined. Kept short so incident IDs stay
  /// compact enough to dictate over radio.
  static Future<String> _resolveAreaCode(LatLng location) async {
    try {
      final marks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      ).timeout(const Duration(seconds: 3));
      for (final m in marks) {
        for (final candidate in [
          m.locality,
          m.subAdministrativeArea,
          m.administrativeArea,
          m.country,
        ]) {
          final s = (candidate ?? '').trim();
          if (s.isEmpty) continue;
          final letters = s
              .toUpperCase()
              .replaceAll(RegExp(r'[^A-Z]'), '');
          if (letters.length >= 3) return letters.substring(0, 3);
          if (letters.length == 2) return '${letters}X';
        }
      }
    } catch (e) {
      debugPrint('[IncidentService] reverse geocode failed: $e');
    }
    return 'UNK';
  }

  /// Next sequence number for `counters/incident_seq_{area}`. Atomic via
  /// transaction; falls back to a timestamp-derived number if Firestore is
  /// unreachable so the ID is still unique.
  static Future<int> _nextIncidentSeq(String areaCode) async {
    final ref = _db
        .collection('counters')
        .doc('incident_seq_$areaCode');
    try {
      return await _db.runTransaction<int>((tx) async {
        final snap = await tx.get(ref);
        final current = (snap.data()?['value'] as int?) ?? 0;
        final next = current + 1;
        tx.set(
          ref,
          {
            'value': next,
            'areaCode': areaCode,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        return next;
      }).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[IncidentService] counter transaction failed: $e');
      return DateTime.now().millisecondsSinceEpoch % 100000;
    }
  }

  /// Build a human-readable incident ID in the form `H-LKO-18`. Uses reverse
  /// geocoding for the middle segment and a Firestore counter for the tail.
  /// Collisions are guarded by an `exists()` check with a short random
  /// fallback suffix so concurrent clients never overwrite each other.
  static Future<String> generateReadableIncidentId(LatLng location) async {
    final area = await _resolveAreaCode(location);
    final seq = await _nextIncidentSeq(area);
    var id = 'H-$area-$seq';
    try {
      final exists = await _db
          .collection(_col)
          .doc(id)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 3));
      if (exists.exists) {
        final rand = DateTime.now().microsecondsSinceEpoch % 1000;
        id = 'H-$area-$seq-$rand';
      }
    } catch (_) {
      // Collision check is best-effort; counter + transaction is primary guard.
    }
    return id;
  }

  /// Creates a new SOS incident and saves to Firestore + local cache
  static Future<SosIncident> createIncident({
    required String userId,
    required String userDisplayName,
    required LatLng location,
    required String type,
  }) async {
    final now = DateTime.now();

    // Client-side anti-abuse guard: per-user cooldown between SOS creates.
    // (Server also enforces limits for online users; this helps offline + UX.)
    if (userId.isNotEmpty && userId != 'anonymous') {
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = 'sos_last_created_ms_$userId';
        final nowMs = now.millisecondsSinceEpoch;
        final lastMs = prefs.getInt(key) ?? 0;
        if (nowMs - lastMs < 60 * 1000) {
          throw StateError('SOS cooldown');
        }
        await prefs.setInt(key, nowMs);
      } catch (e) {
        if (e is StateError) rethrow;
        // If prefs fails, fail open for real emergencies.
      }
    }
    
    // Privacy Logic: Fetch critical medical data from the locked `users` profile
    String? bType;
    String? algs;
    String? conds;
    String? emergencyPhone;
    String? emergencyEmail;
    bool useEmergencySms = false;
    
    if (userId.isNotEmpty && userId != 'anonymous') {
      try {
        final doc = await _db.collection('users').doc(userId).get().timeout(const Duration(seconds: 3));
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          if ((data['bloodType'] as String?)?.isNotEmpty ?? false) bType = data['bloodType'];
          if ((data['allergies'] as String?)?.isNotEmpty ?? false) algs = data['allergies'];
          if ((data['conditions'] as String?)?.isNotEmpty ?? false) conds = data['conditions'];
          if ((data['contactPhone'] as String?)?.trim().isNotEmpty ?? false) {
            emergencyPhone = (data['contactPhone'] as String).trim();
          }
          if ((data['contactEmail'] as String?)?.trim().isNotEmpty ?? false) {
            emergencyEmail = (data['contactEmail'] as String).trim();
          }
          useEmergencySms = (data['useEmergencyContactForSms'] as bool?) ?? false;
        }
      } catch (e) {
        debugPrint('[IncidentService] Could not fetch medical profile: $e');
      }
    }

    String incidentId;
    try {
      incidentId = await generateReadableIncidentId(location);
    } catch (e) {
      debugPrint('[IncidentService] readable id generation failed: $e');
      incidentId = _uuid.v4();
    }

    final incident = SosIncident(
      id: incidentId,
      userId: userId,
      userDisplayName: userDisplayName,
      location: location,
      type: type,
      timestamp: now,
      goldenHourStart: now,
      bloodType: bType,
      allergies: algs,
      medicalConditions: conds,
      emergencyContactPhone: emergencyPhone,
      emergencyContactEmail: emergencyEmail,
      useEmergencyContactForSms: useEmergencySms,
    );

    // Before Firestore write: listener snapshots can arrive as soon as set()
    // completes; if we only registered after await, the victim could briefly see
    // their own incident as an "incoming" volunteer alert.
    _deviceCreatedIncidentIds.add(incident.id);

    try {
      await _db.collection(_col).doc(incident.id).set(incident.toJson());
      if (userId.isNotEmpty && userId != 'anonymous') {
        await _db.collection('users').doc(userId).set(
          {
            'lastActiveIncidentId': incident.id,
            'lastActiveIncidentAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      debugPrint('[IncidentService] Firestore write failed: $e');
      final msg = e.toString().toLowerCase();
      final isOffline = msg.contains('unavailable') ||
          msg.contains('offline') ||
          msg.contains('network') ||
          msg.contains('failed to get document because the client is offline');
      if (!isOffline) rethrow;
    }

    // Always update local cache
    final all = OfflineCacheService.loadIncidents();
    all.add(incident.toJson());
    await OfflineCacheService.saveIncidents(all);

    return incident;
  }

  /// Stream of active incidents (real-time Firestore listener).
  /// Watches pending, dispatched, AND blocked incidents so the alert
  /// system never silently misses an SOS due to server-side rate limiting.
  static Stream<List<SosIncident>> watchActiveIncidents() {
    return _db
        .collection(_col)
        .where('status', whereIn: ['pending', 'dispatched', 'blocked'])
        .limit(30)
        .snapshots()
        .map((snap) {
          final cutoff = DateTime.now().subtract(activeSosMaxDuration);
          final incidents = snap.docs
              .map(SosIncident.fromFirestore)
              .where((i) => i.timestamp.isAfter(cutoff))
              .toList();
          incidents.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return incidents;
        })
        .handleError((e) {
          debugPrint('[IncidentService] watchActiveIncidents error: $e');
        });
  }

  /// Convenience helper for command center: ensure a hospital assignment exists
  /// for [incidentId] by ordering hospitals nearest-first and writing the
  /// chain to `ops_incident_hospital_assignments/{incidentId}`.
  static Future<void> ensureHospitalAssignmentForIncident(String incidentId) async {
    final id = incidentId.trim();
    if (id.isEmpty) return;
    try {
      final snap = await _db.collection(_col).doc(id).get();
      if (!snap.exists || snap.data() == null) return;
      final incident = SosIncident.fromJson({...snap.data()!, 'id': id});
      await OpsIncidentHospitalAssignmentService.upsertAssignmentForIncident(incident);
    } catch (e) {
      debugPrint('[IncidentService] ensureHospitalAssignmentForIncident: $e');
    }
  }

  /// One-shot poll for recent incidents — safety net when the real-time
  /// listener may have disconnected without the client noticing.
  static Future<List<SosIncident>> pollRecentIncidents() async {
    try {
      final snap = await _db
          .collection(_col)
          .where('status', whereIn: ['pending', 'dispatched', 'blocked'])
          .limit(30)
          .get();
      final cutoff = DateTime.now().subtract(activeSosMaxDuration);
      return snap.docs
          .map(SosIncident.fromFirestore)
          .where((i) => i.timestamp.isAfter(cutoff))
          .toList();
    } catch (e) {
      debugPrint('[IncidentService] pollRecentIncidents error: $e');
      return [];
    }
  }

  /// Wider window for admin / ops consoles (still excludes resolved/cancelled in query).
  static Stream<List<SosIncident>> watchActiveIncidentsForOps({int limit = 100}) {
    final cutoff = DateTime.now().subtract(const Duration(hours: 48));
    return _db
        .collection(_col)
        .where('timestamp', isGreaterThan: cutoff)
        .limit(limit)
        .snapshots()
        .map((snap) {
          final incidents = snap.docs
              .map(SosIncident.fromFirestore)
              .toList();
          incidents.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return incidents;
        })
        .handleError((e) {
          debugPrint('[IncidentService] watchActiveIncidentsForOps error: $e');
        });
  }

  /// Live single-incident stream for ops detail panes (ETAs, SMS flags, ambulance ping).
  static Stream<SosIncident?> watchIncidentById(
    String incidentId, {
    bool archived = false,
  }) {
    if (incidentId.isEmpty) {
      return Stream<SosIncident?>.value(null);
    }
    final col = archived ? _archiveCol : _col;
    return _db.collection(col).doc(incidentId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return SosIncident.fromFirestore(snap);
    }).handleError((e) {
      debugPrint('[IncidentService] watchIncidentById error: $e');
    });
  }

  /// Recent archived incidents for admin review.
  static Stream<List<SosIncident>> watchRecentArchivedForOps({int limit = 80}) {
    return _db
        .collection(_archiveCol)
        .limit(limit)
        .snapshots()
        .map((snap) {
          final docs = snap.docs.map(SosIncident.fromFirestore).toList();
          docs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return docs;
        })
        .handleError((e) {
          debugPrint('[IncidentService] watchRecentArchivedForOps error: $e');
        });
  }

  /// Ops/admin metadata only (Firestore rules must allow these keys).
  static Future<void> patchIncidentOpsFields(
    String incidentId,
    Map<String, Object?> patch,
  ) async {
    if (incidentId.isEmpty) return;
    try {
      await _db.collection(_col).doc(incidentId).update({
        ...patch,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[IncidentService] patchIncidentOpsFields failed: $e');
      rethrow;
    }
  }

  /// EMS unit location pushed on a 5s poll from the emergency services console.
  static Future<void> pushAmbulanceLiveLocation(
    String incidentId,
    double lat,
    double lng, {
    double? headingDeg,
  }) async {
    if (incidentId.isEmpty) return;
    try {
      final patch = <String, dynamic>{
        'ambulanceLiveLat': lat,
        'ambulanceLiveLng': lng,
        'ambulanceLiveUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (headingDeg != null) patch['ambulanceLiveHeadingDeg'] = headingDeg;
      await _db.collection(_col).doc(incidentId).update(patch);
    } catch (e) {
      debugPrint('[IncidentService] pushAmbulanceLiveLocation failed: $e');
      rethrow;
    }
  }

  static Future<void> assignCraneUnitDriver({
    required String incidentId,
    required String driverUid,
  }) async {
    final id = incidentId.trim();
    final u = driverUid.trim();
    if (id.isEmpty || u.isEmpty) return;
    await patchIncidentOpsFields(id, {
      'craneUnitAcceptedBy': u,
      'craneUnitAcceptedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> pushCraneLiveLocation(
    String incidentId,
    double lat,
    double lng, {
    double? headingDeg,
  }) async {
    if (incidentId.isEmpty) return;
    try {
      final patch = <String, dynamic>{
        'craneLiveLat': lat,
        'craneLiveLng': lng,
        'craneLiveUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (headingDeg != null) patch['craneLiveHeadingDeg'] = headingDeg;
      await _db.collection(_col).doc(incidentId).update(patch);
    } catch (e) {
      debugPrint('[IncidentService] pushCraneLiveLocation failed: $e');
      rethrow;
    }
  }

  /// Command center: assign ambulance driver without using current user as acceptor.
  /// Also triggers nearest-hospital assignment chain upsert.
  static Future<void> adminAssignAmbulanceDriver({
    required String incidentId,
    required String driverUid,
    String? etaText,
  }) async {
    final id = incidentId.trim();
    final u = driverUid.trim();
    if (id.isEmpty || u.isEmpty) return;
    final patch = <String, Object?>{
      'emsWorkflowPhase': 'inbound',
      'emsAcceptedAt': FieldValue.serverTimestamp(),
      'emsAcceptedBy': u,
      'status': IncidentStatus.dispatched.name,
      'etaUpdatedAt': FieldValue.serverTimestamp(),
    };
    final eta = etaText?.trim();
    if (eta != null && eta.isNotEmpty) patch['ambulanceEta'] = eta;
    await patchIncidentOpsFields(id, patch);
    // Fire-and-forget: nearest-hospital assignment chain.
    ensureHospitalAssignmentForIncident(id).ignore();
  }

  /// EMS console: unit accepted alert — marks workflow **inbound** (ops fields only).
  /// Also triggers nearest-hospital assignment chain upsert.
  static Future<void> emsAcceptIncident(String incidentId) async {
    final id = incidentId.trim();
    if (id.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      await _db.collection(_col).doc(id).update({
        'emsWorkflowPhase': 'inbound',
        'emsAcceptedAt': FieldValue.serverTimestamp(),
        if (uid.isNotEmpty) 'emsAcceptedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // Fire-and-forget: nearest-hospital assignment chain.
      ensureHospitalAssignmentForIncident(id).ignore();
    } catch (e) {
      debugPrint('[IncidentService] emsAcceptIncident failed: $e');
      rethrow;
    }
  }

  /// EMS: claim alert, mark incident dispatched, optional public **ambulanceEta** (victim / volunteer UIs).
  /// Also triggers nearest-hospital assignment chain upsert.
  static Future<void> emsDispatchAmbulance({
    required String incidentId,
    String? etaText,
  }) async {
    final id = incidentId.trim();
    if (id.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final patch = <String, Object?>{
      'emsWorkflowPhase': 'inbound',
      'emsAcceptedAt': FieldValue.serverTimestamp(),
      if (uid.isNotEmpty) 'emsAcceptedBy': uid,
      'status': IncidentStatus.dispatched.name,
      'etaUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final eta = etaText?.trim();
    if (eta != null && eta.isNotEmpty) {
      patch['ambulanceEta'] = eta;
    }
    try {
      await _db.collection(_col).doc(id).update(patch);
      // Fire-and-forget: nearest-hospital assignment chain.
      ensureHospitalAssignmentForIncident(id).ignore();
    } catch (e) {
      debugPrint('[IncidentService] emsDispatchAmbulance failed: $e');
      rethrow;
    }
  }

  /// Push unit GPS. **On-scene** is confirmed by the driver (slide) — proximity only updates [medicalStatus] while [emsWorkflowPhase] is `inbound`.
  /// Default [withinKm] is **0.2** (~200 m) for “near scene” hints.
  static Future<void> emsPushUnitLocationWithProximity({
    required String incidentId,
    required double unitLat,
    required double unitLng,
    required double victimLat,
    required double victimLng,
    double withinKm = 0.2,
    double? headingDeg,
  }) async {
    final id = incidentId.trim();
    if (id.isEmpty) return;
    final km = Geolocator.distanceBetween(unitLat, unitLng, victimLat, victimLng) / 1000.0;
    try {
      final ref = _db.collection(_col).doc(id);
      final snap = await ref.get();
      final phase = (snap.data()?['emsWorkflowPhase'] as String?) ?? '';
      final patch = <String, dynamic>{
        'ambulanceLiveLat': unitLat,
        'ambulanceLiveLng': unitLng,
        'ambulanceLiveUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (headingDeg != null) patch['ambulanceLiveHeadingDeg'] = headingDeg;
      if (phase == 'inbound') {
        final m = (km * 1000).round();
        if (km <= withinKm) {
          patch['medicalStatus'] = m < 1000
              ? 'Within ~$m m of scene — confirm on scene in fleet app'
              : 'Approaching scene (~${km.toStringAsFixed(1)} km)';
        } else {
          patch['medicalStatus'] =
              m < 1000 ? 'En route to scene (~$m m)' : 'En route to scene (~${km.toStringAsFixed(1)} km)';
        }
      }
      await ref.update(patch);
    } catch (e) {
      debugPrint('[IncidentService] emsPushUnitLocationWithProximity failed: $e');
      rethrow;
    }
  }

  /// Fleet: same live GPS write as [emsPushUnitLocationWithProximity], plus when
  /// `emsWorkflowPhase == returning` updates [medicalStatus] with distance to cached
  /// `returnHospitalLat` / `returnHospitalLng` on the incident doc.
  static Future<void> emsPushUnitLocationWithReturnProximity({
    required String incidentId,
    required double unitLat,
    required double unitLng,
    required double victimLat,
    required double victimLng,
    double withinKm = 0.2,
    double? headingDeg,
  }) async {
    final id = incidentId.trim();
    if (id.isEmpty) return;
    final kmVictim = Geolocator.distanceBetween(unitLat, unitLng, victimLat, victimLng) / 1000.0;
    try {
      final ref = _db.collection(_col).doc(id);
      final snap = await ref.get();
      final data = snap.data() ?? {};
      final phase = (data['emsWorkflowPhase'] as String?) ?? '';
      final patch = <String, dynamic>{
        'ambulanceLiveLat': unitLat,
        'ambulanceLiveLng': unitLng,
        'ambulanceLiveUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (headingDeg != null) patch['ambulanceLiveHeadingDeg'] = headingDeg;

      if (phase == 'inbound') {
        final m = (kmVictim * 1000).round();
        if (kmVictim <= withinKm) {
          patch['medicalStatus'] = m < 1000
              ? 'Within ~$m m of scene — confirm on scene in fleet app'
              : 'Approaching scene (~${kmVictim.toStringAsFixed(1)} km)';
        } else {
          patch['medicalStatus'] = m < 1000
              ? 'En route to scene (~$m m)'
              : 'En route to scene (~${kmVictim.toStringAsFixed(1)} km)';
        }
      } else if (phase == 'returning') {
        final hLat = (data['returnHospitalLat'] as num?)?.toDouble();
        final hLng = (data['returnHospitalLng'] as num?)?.toDouble();
        if (hLat != null && hLng != null) {
          final kmH = Geolocator.distanceBetween(unitLat, unitLng, hLat, hLng) / 1000.0;
          final mH = (kmH * 1000).round();
          patch['medicalStatus'] = mH < 1000
              ? 'EMS returning to hospital (~$mH m)'
              : 'EMS returning to hospital (~${kmH.toStringAsFixed(1)} km)';
        }
      }
      await ref.update(patch);
    } catch (e) {
      debugPrint('[IncidentService] emsPushUnitLocationWithReturnProximity failed: $e');
      rethrow;
    }
  }

  /// Fleet operator: driver confirms **on scene** after entering ~200 m (slide in fleet app).
  static Future<void> markEmsOnScene({required String incidentId}) async {
    final id = incidentId.trim();
    if (id.isEmpty) return;
    try {
      final ref = _db.collection(_col).doc(id);
      final snap = await ref.get();
      final phase = (snap.data()?['emsWorkflowPhase'] as String?) ?? '';
      if (phase != 'inbound') {
        debugPrint('[IncidentService] markEmsOnScene: unexpected phase $phase');
        return;
      }
      await ref.update({
        'emsWorkflowPhase': 'on_scene',
        'emsOnSceneAt': FieldValue.serverTimestamp(),
        'medicalStatus': 'EMS on scene',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await appendIncidentAuditLog(id, action: 'ems_on_scene');
    } catch (e) {
      debugPrint('[IncidentService] markEmsOnScene failed: $e');
      rethrow;
    }
  }

  /// Fleet operator: after on-scene rescue, start return leg to the accepting hospital.
  static Future<void> markEmsRescueComplete({
    required String incidentId,
    required String returnHospitalId,
    required double returnHospitalLat,
    required double returnHospitalLng,
  }) async {
    final id = incidentId.trim();
    final hid = returnHospitalId.trim();
    if (id.isEmpty || hid.isEmpty) return;
    try {
      final ref = _db.collection(_col).doc(id);
      final snap = await ref.get();
      final phase = (snap.data()?['emsWorkflowPhase'] as String?) ?? '';
      if (phase != 'on_scene') {
        debugPrint('[IncidentService] markEmsRescueComplete: unexpected phase $phase');
        return;
      }
      await ref.update({
        'emsWorkflowPhase': 'returning',
        'emsRescueCompleteAt': FieldValue.serverTimestamp(),
        'emsReturningStartedAt': FieldValue.serverTimestamp(),
        'returnHospitalId': hid,
        'returnHospitalLat': returnHospitalLat,
        'returnHospitalLng': returnHospitalLng,
        'medicalStatus': 'EMS returning to hospital',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await appendIncidentAuditLog(id, action: 'ems_rescue_complete');
    } catch (e) {
      debugPrint('[IncidentService] markEmsRescueComplete failed: $e');
      rethrow;
    }
  }

  /// Fleet operator: confirm arrival at hospital and close the response cycle (archives incident as resolved).
  static Future<void> markEmsResponseComplete({required String incidentId}) async {
    final id = incidentId.trim();
    if (id.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      debugPrint('[IncidentService] markEmsResponseComplete: no uid');
      return;
    }
    try {
      final ref = _db.collection(_col).doc(id);
      final snap = await ref.get();
      final phase = (snap.data()?['emsWorkflowPhase'] as String?) ?? '';
      if (phase != 'returning') {
        debugPrint('[IncidentService] markEmsResponseComplete: unexpected phase $phase');
        return;
      }
      await ref.update({
        'emsWorkflowPhase': 'complete',
        'emsHospitalArrivalAt': FieldValue.serverTimestamp(),
        'emsResponseCompleteAt': FieldValue.serverTimestamp(),
        'medicalStatus': 'EMS response complete — at hospital',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await appendIncidentAuditLog(id, action: 'ems_response_complete');
      await archiveAndCloseIncident(
        incidentId: id,
        status: 'resolved',
        closedByUid: uid,
      );
    } catch (e) {
      debugPrint('[IncidentService] markEmsResponseComplete failed: $e');
      rethrow;
    }
  }

  /// Admin / EMS: ops note on incident.
  static Future<void> setAdminDispatchNote(String incidentId, String note) async {
    final id = incidentId.trim();
    if (id.isEmpty) return;
    await _db.collection(_col).doc(id).update({
      'adminDispatchNote': note,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Command center: add a responder without volunteer XP side effects.
  static Future<void> opsAttachResponder({
    required String incidentId,
    required String volunteerId,
    String? displayName,
  }) async {
    final id = incidentId.trim();
    final vid = volunteerId.trim();
    if (id.isEmpty || vid.isEmpty) return;
    final patch = <Object, Object?>{
      'acceptedVolunteerIds': FieldValue.arrayUnion([vid]),
      'status': IncidentStatus.dispatched.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final dn = displayName?.trim();
    if (dn != null && dn.isNotEmpty) {
      patch[FieldPath(['responderNames', vid])] = dn;
    }
    await _db.collection(_col).doc(id).update(patch);
  }

  /// Command center: remove responder from acceptance + on-scene + name map.
  static Future<void> opsDetachResponder({
    required String incidentId,
    required String volunteerId,
  }) async {
    final id = incidentId.trim();
    final vid = volunteerId.trim();
    if (id.isEmpty || vid.isEmpty) return;
    await _db.collection(_col).doc(id).update({
      'acceptedVolunteerIds': FieldValue.arrayRemove([vid]),
      'onSceneVolunteerIds': FieldValue.arrayRemove([vid]),
      FieldPath(['responderNames', vid]): FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update status of an incident
  static Future<void> updateStatus(String id, IncidentStatus status) async {
    try {
      final ref = _db.collection(_col).doc(id);
      final snap = await ref.get();
      final prev = snap.data()?['status']?.toString() ?? '';
      final hadAck = snap.data()?['firstAcknowledgedAt'] != null;
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final patch = <String, dynamic>{'status': status.name};
      if (!hadAck &&
          prev == IncidentStatus.pending.name &&
          (status == IncidentStatus.dispatched || status == IncidentStatus.blocked) &&
          uid.isNotEmpty) {
        patch['firstAcknowledgedAt'] = FieldValue.serverTimestamp();
        patch['firstAcknowledgedByUid'] = uid;
      }
      await ref.update(patch);
      await appendIncidentAuditLog(
        id,
        action: 'status_change',
        fromStatus: prev.isEmpty ? null : prev,
        toStatus: status.name,
      );
    } catch (e) {
      debugPrint('[IncidentService] updateStatus failed: $e');
      rethrow;
    }
  }

  /// Volunteer leaves the response UI: clear local resume prefs and drop self from the incident.
  static Future<void> volunteerWithdrawFromIncident(String incidentId) async {
    await clearVolunteerAssignment();
    final trimmed = incidentId.trim();
    if (trimmed.isNotEmpty) {
      volunteerWithdrewIncidentIds.add(trimmed);
      await rememberIncomingAlertShown(trimmed);
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (trimmed.isEmpty || uid == null || uid.isEmpty) return;
    try {
      await _db.collection(_col).doc(trimmed).update({
        'acceptedVolunteerIds': FieldValue.arrayRemove([uid]),
      });
    } catch (e) {
      debugPrint('[IncidentService] volunteerWithdrawFromIncident: $e');
    }
  }

  /// XP when a volunteer accepts an SOS (once per incident per user).
  static const int xpAcceptIncident = 100;
  /// XP when on-scene checklist is completed (airway, bleeding, backup) — once per incident.
  static const int xpOnSceneChecklist = 200;
  /// XP for each accepted responder when victim marks incident resolved.
  static const int xpVictimMarkedResolved = 500;
  /// XP when victim cancels / false alarm (responders still showed up).
  static const int xpFalseAlarmClosure = 180;

  /// Mark an incident as accepted by a specific volunteer
  static Future<void> acceptIncident(String id, String volunteerId) async {
    try {
      final self = FirebaseAuth.instance.currentUser;
      final incRef = _db.collection(_col).doc(id);
      await _db.runTransaction((tx) async {
        final snap = await tx.get(incRef);
        if (!snap.exists || snap.data() == null) return;
        final data = snap.data()!;
        final accepted = List<String>.from(data['acceptedVolunteerIds'] ?? []);
        if (accepted.contains(volunteerId)) return;
        final prevStatus = (data['status'] as String?) ?? IncidentStatus.pending.name;
        final hadAck = data['firstAcknowledgedAt'] != null;
        final patch = <String, dynamic>{
          'acceptedVolunteerIds': FieldValue.arrayUnion([volunteerId]),
          'status': IncidentStatus.dispatched.name,
        };
        if (!hadAck && prevStatus == IncidentStatus.pending.name) {
          patch['firstAcknowledgedAt'] = FieldValue.serverTimestamp();
          patch['firstAcknowledgedByUid'] = volunteerId;
        }
        if (self != null && self.uid == volunteerId) {
          final label = LeaderboardService.volunteerLabelFromAuth(self);
          patch['responderNames.$volunteerId'] = label;
        }
        tx.update(incRef, patch);
        final auditRef = incRef.collection('audit_log').doc();
        tx.set(auditRef, {
          'at': FieldValue.serverTimestamp(),
          'actorUid': volunteerId,
          'action': 'volunteer_accept',
          'fromStatus': prevStatus,
          'toStatus': IncidentStatus.dispatched.name,
        });
      });
      // Volunteer progression — elite LiveKit bridge unlock (see Cloud Function getLivekitToken).
      if (volunteerId.isNotEmpty) {
        if (self != null && self.uid == volunteerId) {
          await LeaderboardService.syncVolunteerPublicProfile(self);
        }
        final profilePatch = <String, Object>{
          'volunteerLivesSaved': FieldValue.increment(1),
          'volunteerXp': FieldValue.increment(xpAcceptIncident),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (self != null && self.uid == volunteerId) {
          final dn = self.displayName?.trim();
          if (dn != null && dn.isNotEmpty) profilePatch['displayName'] = dn;
          final em = self.email?.trim();
          if (em != null && em.isNotEmpty) profilePatch['email'] = em;
          final ph = self.phoneNumber?.trim();
          if (ph != null && ph.isNotEmpty) profilePatch['phoneNumber'] = ph;
        }
        await _db.collection('users').doc(volunteerId).set(profilePatch, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('[IncidentService] Failed to accept incident: $e');
      rethrow;
    }
  }

  /// Awards [xpOnSceneChecklist] once per volunteer per incident when the on-scene
  /// checklist is completed (guarded by `sceneChecklistXpGrantedIds` on the incident).
  static Future<void> tryGrantOnSceneChecklistXp(String incidentId) async {
    final trimmed = incidentId.trim();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (trimmed.isEmpty || uid == null || uid.isEmpty) return;

    final incRef = _db.collection(_col).doc(trimmed);
    final userRef = _db.collection('users').doc(uid);

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(incRef);
        if (!snap.exists || snap.data() == null) return;

        final data = snap.data()!;
        final accepted = List<String>.from(data['acceptedVolunteerIds'] ?? []);
        if (!accepted.contains(uid)) return;

        final granted = List<String>.from(data['sceneChecklistXpGrantedIds'] ?? []);
        if (granted.contains(uid)) return;

        tx.update(incRef, {
          'sceneChecklistXpGrantedIds': FieldValue.arrayUnion([uid]),
        });
        tx.set(
          userRef,
          {
            'volunteerXp': FieldValue.increment(xpOnSceneChecklist),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } catch (e) {
      debugPrint('[IncidentService] tryGrantOnSceneChecklistXp: $e');
    }
  }

  static Future<void> _awardVolunteerClosureXp(Iterable<String> responderUids, int delta) async {
    if (delta <= 0) return;
    final unique = responderUids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (unique.isEmpty) return;
    const chunk = 400;
    var batch = _db.batch();
    var n = 0;
    for (final uid in unique) {
      batch.set(
        _db.collection('users').doc(uid),
        {
          'volunteerXp': FieldValue.increment(delta),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      n++;
      if (n >= chunk) {
        await batch.commit();
        batch = _db.batch();
        n = 0;
      }
    }
    if (n > 0) await batch.commit();
  }

  /// Archive an incident and remove it from the active collection.
  ///
  /// This is used by the victim SOS lock screen when a user cancels (false alarm)
  /// or marks an incident resolved. We copy the full incident doc (if present)
  /// into `sos_incidents_archive/{incidentId}` with closure metadata, then delete
  /// the active doc so responders no longer see it.
  ///
  /// Accepted responders earn [xpVictimMarkedResolved] XP when [status] is `resolved`,
  /// and [xpFalseAlarmClosure] XP when [status] is `cancelled` (false alarm — showed up).
  /// `expired` archives after the 1-hour active window with no responder XP.
  static Future<void> archiveAndCloseIncident({
    required String incidentId,
    required String status, // 'cancelled' | 'resolved' | 'expired'
    required String closedByUid,
  }) async {
    if (incidentId.isEmpty) return;
    final activeRef = _db.collection(_col).doc(incidentId);
    final archiveRef = _db.collection(_archiveCol).doc(incidentId);

    Map<String, dynamic> payload = {
      'id': incidentId,
      'status': status,
      'closedByUid': closedByUid,
      'closedAt': FieldValue.serverTimestamp(),
    };

    List<Map<String, dynamic>> auditExport = [];
    try {
      final snap = await activeRef.get();
      if (snap.exists && snap.data() != null) {
        payload = {
          ...snap.data() as Map<String, dynamic>,
          ...payload,
        };
      }
      try {
        final auditSnap =
            await activeRef.collection('audit_log').orderBy('at').limit(500).get();
        auditExport = auditSnap.docs.map((d) => {...d.data(), 'auditEntryId': d.id}).toList();
      } catch (e) {
        debugPrint('[IncidentService] audit export: $e');
      }
      auditExport = [
        ...auditExport,
        {
          'action': 'incident_closed',
          'closedByUid': closedByUid,
          'closureStatus': status,
        },
      ];
      payload['auditTrailExport'] = auditExport;
    } catch (e) {
      debugPrint('[IncidentService] archiveAndCloseIncident read failed: $e');
    }

    final closureResponderIds = <String>{
      for (final raw in List<dynamic>.from(payload['acceptedVolunteerIds'] ?? []))
        if (raw.toString().trim().isNotEmpty) raw.toString().trim(),
    };

    final closureXpDelta = status == 'resolved'
        ? xpVictimMarkedResolved
        : (status == 'cancelled' ? xpFalseAlarmClosure : 0);

    try {
      await archiveRef.set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[IncidentService] archiveAndCloseIncident archive write failed: $e');
      // If we can’t archive, don’t delete the active incident.
      return;
    }

    try {
      await activeRef.delete();
    } catch (e) {
      debugPrint('[IncidentService] archiveAndCloseIncident delete failed: $e');
    }

    unawaited(_clearResponderAssignmentsForIncident(incidentId, closureResponderIds));

    final victimUid = (payload['userId'] as String?)?.trim();
    if (victimUid != null && victimUid.isNotEmpty) {
      try {
        final uref = _db.collection('users').doc(victimUid);
        final u = await uref.get();
        final active = (u.data()?[_userActiveSosField] as String?)?.trim();
        if (active == incidentId) {
          await uref.set({
            _userActiveSosField: FieldValue.delete(),
            _userActiveSosAtField: FieldValue.delete(),
          }, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint('[IncidentService] clear victim activeSos on archive: $e');
      }
    }

    if (closureXpDelta > 0 && closureResponderIds.isNotEmpty) {
      try {
        await _awardVolunteerClosureXp(closureResponderIds, closureXpDelta);
      } catch (e) {
        debugPrint('[IncidentService] closure XP award failed: $e');
      }
    }
  }

  /// Archives open incidents whose SOS start time is past [activeSosMaxDuration].
  ///
  /// Uses a single-field `timestamp` query (no composite index) and filters
  /// status on the client.
  static Future<void> autoArchiveExpiredIncidents() async {
    try {
      final cutoff = Timestamp.fromDate(
        DateTime.now().subtract(activeSosMaxDuration),
      );

      final snap = await _db
          .collection(_col)
          .where('timestamp', isLessThan: cutoff)
          .limit(100)
          .get();

      for (final doc in snap.docs) {
        final st = doc.data()['status'] as String? ?? '';
        if (!['pending', 'dispatched', 'blocked'].contains(st)) continue;
        await archiveAndCloseIncident(
          incidentId: doc.id,
          status: 'expired',
          closedByUid: 'system_auto_expire',
        );
      }
    } catch (e) {
      debugPrint('[IncidentService] autoArchiveExpiredIncidents error: $e');
    }
  }

  static const prefVolunteerIncidentId = 'persist_volunteer_incident_id';
  static const prefVolunteerIncidentType = 'persist_volunteer_incident_type';

  /// Remembers an accepted SOS assignment until the volunteer goes off duty or the incident ends.
  static Future<void> persistVolunteerAssignment({
    required String incidentId,
    required String incidentType,
  }) async {
    if (incidentId.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(prefVolunteerIncidentId, incidentId);
      await p.setString(prefVolunteerIncidentType, incidentType);

      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        await _db.collection('users').doc(uid).set({
          'activeAssignment': {
            'incidentId': incidentId,
            'incidentType': incidentType,
            'assignedAt': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('[IncidentService] persistVolunteerAssignment: $e');
    }
  }

  static Future<void> clearVolunteerAssignment() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(prefVolunteerIncidentId);
      await p.remove(prefVolunteerIncidentType);
      
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        await _db.collection('users').doc(uid).update({
          'activeAssignment': FieldValue.delete(),
        });
      }
    } catch (e) {
      debugPrint('[IncidentService] clearVolunteerAssignment: $e');
    }
  }

  static Future<({String? incidentId, String? incidentType})> loadVolunteerAssignment() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      final p = await SharedPreferences.getInstance();

      Future<({String? incidentId, String? incidentType})?> validate(String id, String type) async {
        final tid = id.trim();
        if (tid.isEmpty) return null;
        if (tid == AppConstants.drillIncidentId) {
          final tt = type.trim().isEmpty ? 'Emergency' : type.trim();
          return (incidentId: tid, incidentType: tt);
        }
        final ok = await _validateVolunteerAssignmentActive(incidentId: tid, volunteerUid: uid);
        if (!ok) {
          await clearVolunteerAssignment();
          return null;
        }
        final tt = type.trim().isEmpty ? 'Emergency' : type.trim();
        return (incidentId: tid, incidentType: tt);
      }

      final localId = p.getString(prefVolunteerIncidentId)?.trim();
      final localType = p.getString(prefVolunteerIncidentType) ?? 'Emergency';
      if (localId != null && localId.isNotEmpty) {
        final r = await validate(localId, localType);
        if (r != null) return r;
      }

      if (uid.isNotEmpty) {
        final snap = await _db.collection('users').doc(uid).get();
        if (snap.exists && snap.data() != null) {
          final assignment = snap.data()!['activeAssignment'] as Map<String, dynamic>?;
          if (assignment != null) {
            final fId = (assignment['incidentId'] as String? ?? '').trim();
            final fType = (assignment['incidentType'] as String? ?? 'Emergency').trim();
            if (fId.isNotEmpty) {
              final r = await validate(fId, fType);
              if (r != null) {
                await p.setString(prefVolunteerIncidentId, r.incidentId!);
                await p.setString(prefVolunteerIncidentType, r.incidentType ?? 'Emergency');
                return r;
              }
            }
          }
        }
      }
    } catch (_) {}
    return (incidentId: null, incidentType: null);
  }

  /// Fetch all past (archived) incidents within [radiusMeters] of [center].
  /// Returns incidents from `sos_incidents_archive` sorted newest-first.
  static Future<List<SosIncident>> fetchPastIncidents({
    LatLng? center,
    double radiusMeters = 50000,
    int limit = 200,
  }) async {
    List<SosIncident> filterByRadius(List<SosIncident> all) {
      if (center == null) return all;
      return all.where((inc) {
        final dist = _haversineMeters(
          center.latitude, center.longitude,
          inc.location.latitude, inc.location.longitude,
        );
        return dist <= radiusMeters;
      }).toList();
    }

    try {
      final snap = await _db
          .collection(_archiveCol)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();
      final all = <SosIncident>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        if (isDemoSosFirestoreDoc(doc.id, d)) continue;
        all.add(SosIncident.fromJson({...d, 'id': doc.id}));
      }

      if (all.isNotEmpty) {
        await OfflineCacheService.savePastIncidentsArchive(all.map((e) => e.toJson()).toList());
      }
      return filterByRadius(all);
    } catch (e) {
      debugPrint('[IncidentService] fetchPastIncidents failed: $e');
      final cached = OfflineCacheService.loadPastIncidentsArchive();
      if (cached.isEmpty) return [];
      try {
        final parsed = cached
            .map((m) => SosIncident.fromJson(Map<String, dynamic>.from(m)))
            .where((inc) => !isDemoSosFirestoreDoc(inc.id, {'userId': inc.userId}))
            .toList();
        return filterByRadius(parsed);
      } catch (_) {
        return [];
      }
    }
  }

  static double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * math.pi / 180;

  /// Compute area intelligence statistics from a list of past incidents.
  static AreaIntelligence computeAreaIntel(List<SosIncident> pastIncidents, LatLng? center) {
    if (pastIncidents.isEmpty) {
      return AreaIntelligence.empty();
    }

    final typeCount = <String, int>{};
    final severityCounts = <String, int>{'critical': 0, 'high': 0, 'medium': 0, 'low': 0};
    final hourBuckets = List<int>.filled(24, 0);
    final dayBuckets = List<int>.filled(7, 0);
    final hotspots = <LatLng, int>{};
    int resolvedCount = 0;
    int totalResponseMinutes = 0;
    int responseCountForAvg = 0;
    int ambResponseSum = 0;
    int ambResponseCount = 0;
    int volResponseSum = 0;
    int volResponseCount = 0;

    for (final inc in pastIncidents) {
      final t = inc.type.toLowerCase();
      typeCount[inc.type] = (typeCount[inc.type] ?? 0) + 1;

      if (t.contains('cardiac') || t.contains('stroke') || t.contains('hemorrhage') || t.contains('critical')) {
        severityCounts['critical'] = severityCounts['critical']! + 1;
      } else if (t.contains('collision') || t.contains('accident') || t.contains('fire') || t.contains('drown')) {
        severityCounts['high'] = severityCounts['high']! + 1;
      } else if (t.contains('bleeding') || t.contains('choking') || t.contains('fracture')) {
        severityCounts['medium'] = severityCounts['medium']! + 1;
      } else {
        severityCounts['low'] = severityCounts['low']! + 1;
      }

      hourBuckets[inc.timestamp.hour]++;
      dayBuckets[inc.timestamp.weekday % 7]++;

      final gridKey = LatLng(
        (inc.location.latitude * 200).roundToDouble() / 200,
        (inc.location.longitude * 200).roundToDouble() / 200,
      );
      hotspots[gridKey] = (hotspots[gridKey] ?? 0) + 1;

      final status = inc.status.name.toLowerCase();
      if (status == 'resolved' || status == 'cancelled') {
        resolvedCount++;
        final respTime = inc.timestamp.difference(inc.goldenHourStart).inMinutes.abs();
        if (respTime > 0 && respTime < 120) {
          totalResponseMinutes += respTime;
          responseCountForAvg++;
        }
      }

      final emsOn = inc.emsOnSceneAt;
      if (emsOn != null) {
        final ambM = emsOn.difference(inc.timestamp).inMinutes.abs();
        if (ambM > 0 && ambM < 180) {
          ambResponseSum += ambM;
          ambResponseCount++;
        }
      }
      final firstAck = inc.firstAcknowledgedAt;
      if (firstAck != null) {
        final volM = firstAck.difference(inc.timestamp).inMinutes.abs();
        if (volM > 0 && volM < 120) {
          volResponseSum += volM;
          volResponseCount++;
        }
      }
    }

    final sortedTypes = typeCount.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final peakHour = hourBuckets.indexOf(hourBuckets.reduce((a, b) => a > b ? a : b));
    final peakDay = dayBuckets.indexOf(dayBuckets.reduce((a, b) => a > b ? a : b));
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    final hotspotList = hotspots.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final dangerZones = hotspotList.take(5).map((e) => DangerZone(
      center: e.key,
      incidentCount: e.value,
      radiusMeters: 300.0 + (e.value * 50.0).clamp(0, 700),
    )).toList();

    final totalInc = pastIncidents.length;
    final riskScore = ((severityCounts['critical']! * 4 +
        severityCounts['high']! * 3 +
        severityCounts['medium']! * 2 +
        severityCounts['low']! * 1) / totalInc * 25)
        .clamp(0, 100)
        .round();

    return AreaIntelligence(
      totalPastIncidents: totalInc,
      topIncidentType: sortedTypes.isNotEmpty ? sortedTypes.first.key : 'Unknown',
      topIncidentCount: sortedTypes.isNotEmpty ? sortedTypes.first.value : 0,
      severityCounts: severityCounts,
      peakHour: peakHour,
      peakDay: days[peakDay],
      avgResponseMinutes: responseCountForAvg > 0 ? totalResponseMinutes ~/ responseCountForAvg : 0,
      avgAmbulanceResponseMinutes: ambResponseCount > 0 ? ambResponseSum ~/ ambResponseCount : 0,
      avgVolunteerResponseMinutes: volResponseCount > 0 ? volResponseSum ~/ volResponseCount : 0,
      resolvedPercent: totalInc > 0 ? (resolvedCount / totalInc * 100).round() : 0,
      riskScore: riskScore,
      dangerZones: dangerZones,
      incidentTypeBreakdown: Map.fromEntries(sortedTypes),
    );
  }

  static const String _userActiveSosField = 'activeSosIncidentId';
  static const String _userActiveSosAtField = 'activeSosUpdatedAt';

  /// Persist the active SOS incident ID locally and on the signed-in user's
  /// Firestore profile so any device with the same account recovers the session.
  static Future<void> persistActiveSos(String incidentId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_sos_incident_id', incidentId);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      try {
        await _db.collection('users').doc(uid).set({
          _userActiveSosField: incidentId,
          _userActiveSosAtField: FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[IncidentService] persistActiveSos user mirror failed: $e');
      }
    }
  }

  /// Clear the persisted active SOS (called on resolve/cancel).
  static Future<void> clearActiveSos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_sos_incident_id');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      try {
        await _db.collection('users').doc(uid).set({
          _userActiveSosField: FieldValue.delete(),
          _userActiveSosAtField: FieldValue.delete(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('[IncidentService] clearActiveSos user mirror failed: $e');
      }
    }
  }

  static Future<String?> _recoverVictimIfIncidentValid(
    String incidentId,
    User? user,
    SharedPreferences prefs,
  ) async {
    final id = incidentId.trim();
    if (id.isEmpty) return null;
    if (id == AppConstants.drillIncidentId) {
      await prefs.setString('active_sos_incident_id', id);
      return id;
    }
    try {
      final doc = await _db.collection(_col).doc(id).get().timeout(const Duration(seconds: 5));
      if (!doc.exists || doc.data() == null) return null;
      final d = doc.data()!;
      final victimUid = (d['userId'] as String?)?.trim() ?? '';
      if (user != null && user.uid.isNotEmpty && victimUid.isNotEmpty && victimUid != user.uid) {
        return null;
      }
      final status = d['status'] as String? ?? '';
      if (status == 'resolved' ||
          status == 'cancelled' ||
          status == 'blocked' ||
          status == 'expired' ||
          status == 'archived_stale') {
        return null;
      }
      final ts = _parseIncidentTimestampField(d['timestamp']);
      if (isIncidentActiveWindowExpired(ts)) {
        await archiveAndCloseIncident(
          incidentId: id,
          status: 'expired',
          closedByUid: 'system_auto_expire',
        );
        await clearActiveSos();
        return null;
      }
      await prefs.setString('active_sos_incident_id', id);
      return id;
    } catch (e) {
      debugPrint('[IncidentService] _recoverVictimIfIncidentValid failed: $e');
      return null;
    }
  }

  /// Active SOS for the signed-in victim (prefs + `users/{uid}.activeSosIncidentId` + newest open incident).
  static Future<String?> checkActiveSosOnStartup() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();

    Future<void> clearRemoteVictimPointer() async {
      if (user == null || user.uid.isEmpty) return;
      try {
        await _db.collection('users').doc(user.uid).set({
          _userActiveSosField: FieldValue.delete(),
          _userActiveSosAtField: FieldValue.delete(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }

    if (user != null && user.uid.isNotEmpty) {
      try {
        final udoc = await _db.collection('users').doc(user.uid).get().timeout(
              const Duration(seconds: 6),
            );
        final remoteId = (udoc.data()?[_userActiveSosField] as String?)?.trim();
        if (remoteId != null && remoteId.isNotEmpty) {
          final ok = await _recoverVictimIfIncidentValid(remoteId, user, prefs);
          if (ok != null) return ok;
          await clearRemoteVictimPointer();
        }
      } catch (e) {
        debugPrint('[IncidentService] remote active SOS user field: $e');
      }
    }

    final localId = prefs.getString('active_sos_incident_id')?.trim();
    if (localId != null && localId.isNotEmpty) {
      try {
        final ok = await _recoverVictimIfIncidentValid(localId, user, prefs);
        if (ok != null) return ok;
        await prefs.remove('active_sos_incident_id');
        await clearRemoteVictimPointer();
      } catch (e) {
        debugPrint('[IncidentService] checkActiveSosOnStartup local recovery: $e');
        return null;
      }
    }

    if (user == null) return null;

    try {
      final query = await _db
          .collection(_col)
          .where('userId', isEqualTo: user.uid)
          .where('status', whereIn: ['pending', 'dispatched'])
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 8));

      if (query.docs.isNotEmpty) {
        final foundId = query.docs.first.id;
        final ok = await _recoverVictimIfIncidentValid(foundId, user, prefs);
        if (ok != null) return ok;
      }
    } catch (e) {
      debugPrint('Error checking remote active SOS: $e');
    }

    return null;
  }

  /// After sign-in (same Firebase account on any device), returns the GoRouter path
  /// for an in-progress victim SOS or volunteer response, or null for normal home.
  static Future<String?> recoverEmergencyRoutePath({bool runAutoExpireSweep = true}) async {
    if (runAutoExpireSweep) {
      try {
        await autoArchiveExpiredIncidents().timeout(const Duration(seconds: 12));
      } catch (_) {}
    }
    try {
      if (await DrillSessionPersistence.isActive()) return null;
    } catch (_) {}

    final sos = await checkActiveSosOnStartup();
    if (sos != null && sos.isNotEmpty) {
      if (sos == AppConstants.drillIncidentId) {
        return '/sos-active/${Uri.encodeComponent(sos)}?drill=1';
      }
      return '/sos-active/${Uri.encodeComponent(sos)}';
    }

    final a = await loadVolunteerAssignment();
    final volId = a.incidentId;
    if (volId != null && volId.isNotEmpty) {
      final t = (a.incidentType ?? 'Emergency').trim();
      final tt = t.isEmpty ? 'Emergency' : t;
      final q = volId == AppConstants.drillIncidentId ? '&drill=1' : '';
      return '/active-consignment/${Uri.encodeComponent(volId)}?type=${Uri.encodeComponent(tt)}$q';
    }
    return null;
  }

  /// Voluntary sign-out should be blocked while a non-drill emergency session is in effect.
  static Future<bool> mustStaySignedInForEmergencyFlow() async {
    try {
      if (await DrillSessionPersistence.isActive()) return false;
    } catch (_) {}
    final path = await recoverEmergencyRoutePath(runAutoExpireSweep: false);
    return path != null && path.isNotEmpty;
  }

  /// True when Firestore incident map is past the 1-hour active window.
  static bool incidentMapActiveWindowExpired(Map<String, dynamic> d) {
    return isIncidentActiveWindowExpired(_parseIncidentTimestampField(d['timestamp']));
  }
}

/// EmergencyOS: DangerZone in lib/services/incident_service.dart.
class DangerZone {
  final LatLng center;
  final int incidentCount;
  final double radiusMeters;
  const DangerZone({required this.center, required this.incidentCount, required this.radiusMeters});
}

/// EmergencyOS: AreaIntelligence in lib/services/incident_service.dart.
class AreaIntelligence {
  final int totalPastIncidents;
  final String topIncidentType;
  final int topIncidentCount;
  final Map<String, int> severityCounts;
  final int peakHour;
  final String peakDay;
  final int avgResponseMinutes;
  /// Mean minutes from SOS [timestamp] to EMS on-scene when [SosIncident.emsOnSceneAt] is present.
  final int avgAmbulanceResponseMinutes;
  /// Mean minutes from SOS [timestamp] to first acknowledgment when [SosIncident.firstAcknowledgedAt] is present.
  final int avgVolunteerResponseMinutes;
  final int resolvedPercent;
  final int riskScore;
  final List<DangerZone> dangerZones;
  final Map<String, int> incidentTypeBreakdown;

  const AreaIntelligence({
    required this.totalPastIncidents,
    required this.topIncidentType,
    required this.topIncidentCount,
    required this.severityCounts,
    required this.peakHour,
    required this.peakDay,
    required this.avgResponseMinutes,
    required this.avgAmbulanceResponseMinutes,
    required this.avgVolunteerResponseMinutes,
    required this.resolvedPercent,
    required this.riskScore,
    required this.dangerZones,
    required this.incidentTypeBreakdown,
  });

  factory AreaIntelligence.empty() => const AreaIntelligence(
    totalPastIncidents: 0,
    topIncidentType: 'None',
    topIncidentCount: 0,
    severityCounts: {'critical': 0, 'high': 0, 'medium': 0, 'low': 0},
    peakHour: 0,
    peakDay: 'N/A',
    avgResponseMinutes: 0,
    avgAmbulanceResponseMinutes: 0,
    avgVolunteerResponseMinutes: 0,
    resolvedPercent: 0,
    riskScore: 0,
    dangerZones: [],
    incidentTypeBreakdown: {},
  );

  String get riskLabel {
    if (riskScore >= 75) return 'EXTREME';
    if (riskScore >= 50) return 'HIGH';
    if (riskScore >= 25) return 'MODERATE';
    return 'LOW';
  }
}

// ─── Riverpod Provider ─────────────────────────────────────────────────────

final activeIncidentsProvider = StreamProvider<List<SosIncident>>(
  (_) => IncidentService.watchActiveIncidents(),
);

final pastIncidentsProvider = FutureProvider.family<List<SosIncident>, LatLng?>(
  (ref, center) => IncidentService.fetchPastIncidents(center: center),
);

// ─── Current SOS incident state ────────────────────────────────────────────

/// EmergencyOS: ActiveSosNotifier in lib/services/incident_service.dart.
class ActiveSosNotifier extends Notifier<SosIncident?> {
  @override
  SosIncident? build() => null;

  void setIncident(SosIncident incident) => state = incident;
  void clear() => state = null;
}

final activeSosProvider = NotifierProvider<ActiveSosNotifier, SosIncident?>(
  ActiveSosNotifier.new,
);
