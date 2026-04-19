import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/maps/eos_hybrid_map.dart';
import '../../../core/maps/ops_map_controller.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/demo_credentials.dart';
import '../../../core/constants/google_maps_illustrative_light_style.dart';
import '../../../core/constants/india_ops_zones.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/language_switcher_button.dart';
import '../../../core/widgets/shared_situation_brief_card.dart';
import '../../../core/widgets/slide_to_confirm_action.dart';
import '../../../core/constants/station_unit_role.dart';
import '../../../core/utils/fleet_map_icons.dart';
import '../../../core/utils/ops_map_markers.dart';
import '../../../core/utils/osrm_route_util.dart';
import 'widgets/fleet_operator_handoff_editor.dart';
import '../../../services/fleet_assignment_service.dart';
import '../../../services/fleet_operator_auth_service.dart';
import '../../../services/fleet_operator_session_service.dart';
import '../../../services/fleet_unit_service.dart';
import '../../../services/incident_service.dart';
import '../../../services/ops_incident_hospital_assignment_service.dart';
import '../../../services/station_unit_role_prefs.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

/// Mobile-first **unit driver** view: ambulance / EMS.
/// Full dispatch stays in the admin command center — drivers only see incidents **allotted to them**.
class EmergencyServicesPanelScreen extends StatefulWidget {
  const EmergencyServicesPanelScreen({super.key, this.focusIncidentId});

  final String? focusIncidentId;

  @override
  State<EmergencyServicesPanelScreen> createState() => _EmergencyServicesPanelScreenState();
}

enum _OperatorPhase { gate, dutyPrep, roster }

class _EmergencyServicesPanelScreenState extends State<EmergencyServicesPanelScreen> {
  static final _functionsUsEast1 = FirebaseFunctions.instanceFor(region: 'us-east1');

  _OperatorPhase _phase = _OperatorPhase.gate;
  bool _sessionReady = false;
  bool _gateBusy = false;
  StationUnitRole? _role;
  StationUnitRole? _pendingRole;
  final _fleetIdCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String? _selectedIncidentId;
  OpsMapController? _mapCtl;
  OpsMapController? _standbyMapCtl;
  Timer? _locTimer;
  Timer? _dutyHeartbeatTimer;
  Timer? _routeDebounce;
  List<LatLng> _routeToVictim = [];
  List<LatLng> _routeToHospital = [];
  List<LatLng> _volunteerRouteToScene = [];
  String _volunteerRouteOverlaySig = '';
  Position? _lastSharePos;
  Position? _lastDutyPos;
  double _driverMapZoom = 14.0;

  // ── Incoming assignment notification state ─────────────────────────────────
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _assignmentSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pendingAssignmentDocs = [];
  Timer? _assignmentTickTimer;
  final Set<String> _noResponseWriteIssued = {};
  /// Cached `custom_*` Fleet Management row for this call sign (coords + hospital id).
  FleetPlaceholderRow? _cachedFleetPlaceholderRow;

  StreamSubscription<OpsIncidentHospitalAssignment?>? _hospitalAssignmentSub;
  OpsIncidentHospitalAssignment? _hospitalAssignment;
  String? _hospitalAssignmentListenId;
  bool _withinVictimRadius = false;
  bool _withinHospitalRadius = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill demo credentials for judge demo access.
    const demoFleet = DemoCredentials.fleetId;
    const demoGatePw = DemoCredentials.adminPassword;
    if (demoFleet.isNotEmpty) _fleetIdCtrl.text = demoFleet;
    if (demoGatePw.isNotEmpty) _passwordCtrl.text = demoGatePw;
    final f = widget.focusIncidentId?.trim();
    if (f != null && f.isNotEmpty) _selectedIncidentId = f;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await FleetOperatorSession.load();
      await OpsMapMarkers.preload();
      await FleetMapIcons.preload();
      if (!context.mounted) return;
      if (FleetOperatorSession.isVerified && FleetOperatorSession.isOnDuty) {
        final r = await StationUnitRolePrefs.load();
        if (r != null) {
          setState(() {
            _sessionReady = true;
            _role = r;
            _phase = _OperatorPhase.roster;
          });
          _startDutyHeartbeat();
          _startAssignmentListener();
          WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_dutyHeartbeatTick()));
        } else {
          setState(() {
            _sessionReady = true;
            _phase = _OperatorPhase.dutyPrep;
          });
        }
      } else if (FleetOperatorSession.isVerified) {
        setState(() {
          _sessionReady = true;
          _phase = _OperatorPhase.dutyPrep;
        });
      } else {
        setState(() => _sessionReady = true);
      }
    });
  }

  @override
  void dispose() {
    _locTimer?.cancel();
    _dutyHeartbeatTimer?.cancel();
    _routeDebounce?.cancel();
    _assignmentTickTimer?.cancel();
    _assignmentSub?.cancel();
    _hospitalAssignmentSub?.cancel();
    _standbyMapCtl?.dispose();
    _fleetIdCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Parses `EMS-<hospitalDocId>-A` / `-S` call signs → `ops_hospitals` doc id.
  String? _stationedHospitalIdFromFleetCallSign(String? callSign) {
    final s = (callSign ?? '').trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'^EMS-(.+)-[AS]$', caseSensitive: false).firstMatch(s);
    return m?.group(1)?.trim().toUpperCase();
  }

  /// `ops_hospitals` doc id for hospital-scoped fleet UIs: EMS call sign, else placeholder row.
  Future<String?> _hospitalIdForFleetSync() async {
    final fid = FleetOperatorSession.fleetId?.trim();
    if (fid == null || fid.isEmpty) return null;
    final ems = _stationedHospitalIdFromFleetCallSign(fid);
    if (ems != null && ems.isNotEmpty) return ems;
    _cachedFleetPlaceholderRow ??= await FleetUnitService.fleetPlaceholderRowForCallSign(fid);
    return _cachedFleetPlaceholderRow?.assignedHospitalId;
  }

  void _ensureHospitalAssignmentListener(String? incidentId) {
    if (incidentId == null || incidentId.isEmpty) {
      _hospitalAssignmentSub?.cancel();
      _hospitalAssignmentSub = null;
      _hospitalAssignmentListenId = null;
      _hospitalAssignment = null;
      return;
    }
    if (_hospitalAssignmentListenId == incidentId && _hospitalAssignmentSub != null) return;
    _hospitalAssignmentSub?.cancel();
    _hospitalAssignmentListenId = incidentId;
    _hospitalAssignmentSub = OpsIncidentHospitalAssignmentService.watchForIncident(incidentId).listen((a) {
      if (mounted) setState(() => _hospitalAssignment = a);
    });
  }

  bool _isAllotted(SosIncident e, String? uid, StationUnitRole role) {
    if (uid == null || uid.isEmpty) return false;
    if (e.status == IncidentStatus.resolved || e.status == IncidentStatus.blocked) return false;
    return switch (role) {
      StationUnitRole.medical => e.emsAcceptedBy == uid,
      StationUnitRole.crane => e.craneUnitAcceptedBy == uid,
    };
  }

  /// Map overlay for this unit before/without Firestore `ambulanceLiveLocation`.
  LatLng? _unitMapOverlayLatLng(SosIncident inc) {
    final uid = _uid;
    final r = _role;
    if (uid == null || uid.isEmpty || r == null) return null;
    if (!_isAllotted(inc, uid, r)) return null;
    if (_lastSharePos != null && _selectedIncidentId == inc.id && (_locTimer?.isActive ?? false)) {
      return LatLng(_lastSharePos!.latitude, _lastSharePos!.longitude);
    }
    if (_lastDutyPos != null) {
      return LatLng(_lastDutyPos!.latitude, _lastDutyPos!.longitude);
    }
    return null;
  }

  double? _bearingDegFromPositions(Position from, Position to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final br = math.atan2(y, x) * (180 / math.pi);
    return (br + 360) % 360;
  }

  /// Maps Firestore `ops_fleet_accounts.vehicleType` to station role.
  static StationUnitRole? _stationRoleFromFleetVehicleType(String vt) {
    switch (vt.toLowerCase()) {
      case 'medical':
      case 'ambulance':
        return StationUnitRole.medical;
      case 'crane':
      case 'recovery':
        return StationUnitRole.crane;
      default:
        return null;
    }
  }

  Future<void> _verifyGate() async {
    // Normalize to upper-case to match Firestore document IDs (e.g. "POL-LKO-1").
    final id = _fleetIdCtrl.text.trim().toUpperCase();
    final pw = _passwordCtrl.text.trim();
    if (id.isEmpty || pw.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.opsTr('Enter fleet ID and password.'))),
        );
      }
      return;
    }
    setState(() => _gateBusy = true);
    try {
      final vehicleType = await FleetOperatorAuthService.verifyCredentials(fleetId: id, password: pw);
      if (!context.mounted) return;
      if (vehicleType == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unknown fleet ID or wrong password. Use the call sign and password issued for your unit (ops_fleet_accounts).',
            ),
          ),
        );
        return;
      }
      // Store the normalised ID so the session and call-sign match Firestore exactly.
      await FleetOperatorSession.setVerifiedFleet(id, vehicleType: vehicleType);
      await StationUnitRolePrefs.clear();
      _passwordCtrl.clear();
      final autoRole = _stationRoleFromFleetVehicleType(vehicleType);
      setState(() {
        _phase = _OperatorPhase.dutyPrep;
        _pendingRole = autoRole;
        _role = null;
      });
    } finally {
      if (context.mounted) setState(() => _gateBusy = false);
    }
  }

  Future<void> _goOnDuty() async {
    final r = _pendingRole;
    if (r == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.opsTr('Confirm medical or crane duty to continue.'))),
        );
      }
      return;
    }
    await StationUnitRolePrefs.save(r);
    await FleetOperatorSession.setOnDuty(true);
    if (!context.mounted) return;
    setState(() {
      _role = r;
      _phase = _OperatorPhase.roster;
      _selectedIncidentId = null;
    });
    _startDutyHeartbeat();
    _startAssignmentListener();
    await _dutyHeartbeatTick();
  }

  // ── Assignment notification listener ────────────────────────────────────────

  void _startAssignmentListener() {
    final fleetId = FleetOperatorSession.fleetId;
    if (fleetId == null || fleetId.isEmpty) return;
    _assignmentSub?.cancel();
    _assignmentSub = FleetAssignmentService.watchPendingAssignments(fleetId).listen((snap) {
      if (!context.mounted) return;
      final now = DateTime.now();
      final active = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final d in snap.docs) {
        final data = d.data();
        if (!FleetAssignmentService.isOperatorUiSource(data)) continue;
        if (!FleetAssignmentService.isAwaitingWithinWindow(data, now)) {
          unawaited(_maybeMarkDriverNoResponse(fleetId, d.id));
          continue;
        }
        active.add(d);
      }
      setState(() {
        _pendingAssignmentDocs = active;
      });
      _startAssignmentTickTimerIfNeeded();
    });
  }

  void _stopAssignmentTickTimer() {
    _assignmentTickTimer?.cancel();
    _assignmentTickTimer = null;
  }

  void _startAssignmentTickTimerIfNeeded() {
    if (_pendingAssignmentDocs.isEmpty) {
      _stopAssignmentTickTimer();
      return;
    }
    if (_assignmentTickTimer != null) return;
    _assignmentTickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onAssignmentTick());
  }

  void _onAssignmentTick() {
    if (!context.mounted) return;
    final fleetId = FleetOperatorSession.fleetId;
    if (fleetId == null || fleetId.isEmpty) return;
    final now = DateTime.now();
    final still = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in _pendingAssignmentDocs) {
      final data = d.data();
      if (!FleetAssignmentService.isOperatorUiSource(data)) continue;
      if (!FleetAssignmentService.isAwaitingWithinWindow(data, now)) {
        unawaited(_maybeMarkDriverNoResponse(fleetId, d.id));
        continue;
      }
      still.add(d);
    }
    setState(() {
      _pendingAssignmentDocs = still;
    });
    if (still.isEmpty) _stopAssignmentTickTimer();
  }

  Future<void> _maybeMarkDriverNoResponse(String fleetId, String assignmentDocId) async {
    if (_noResponseWriteIssued.contains(assignmentDocId)) return;
    _noResponseWriteIssued.add(assignmentDocId);
    try {
      await FleetAssignmentService.markDriverNoResponse(
        fleetId: fleetId,
        assignmentDocId: assignmentDocId,
      );
    } catch (e, st) {
      _noResponseWriteIssued.remove(assignmentDocId);
      debugPrint('[DriverPanel] markDriverNoResponse: $e\n$st');
    }
  }

  void _stopAssignmentListener() {
    _assignmentSub?.cancel();
    _assignmentSub = null;
    _stopAssignmentTickTimer();
    _noResponseWriteIssued.clear();
    if (context.mounted) setState(() => _pendingAssignmentDocs = []);
  }

  Future<void> _acceptAssignment(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final fleetId = FleetOperatorSession.fleetId ?? doc.id;
    final incidentId = (data['incidentId'] as String?)?.trim() ?? '';
    final now = DateTime.now();
    if (!FleetAssignmentService.isAwaitingWithinWindow(data, now)) {
      try {
        await FleetAssignmentService.markDriverNoResponse(
          fleetId: fleetId,
          assignmentDocId: doc.id,
        );
      } catch (_) {}
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.opsTr('This assignment has expired (3 min). Marked as driver did not respond.')),
            backgroundColor: Colors.orange.shade900,
          ),
        );
        setState(() {
          _pendingAssignmentDocs = _pendingAssignmentDocs.where((e) => e.id != doc.id).toList();
        });
      }
      return;
    }
    try {
      await FleetAssignmentService.acceptAssignment(
        fleetId: fleetId,
        assignmentDocId: doc.id,
      );
      // Update the incident with this fleet unit's UID / call sign.
      final uid = _uid ?? fleetId;
      if (incidentId.isNotEmpty) {
        final role = _role;
        if (role != null) {
          switch (role) {
            case StationUnitRole.medical:
              await IncidentService.adminAssignAmbulanceDriver(incidentId: incidentId, driverUid: uid);
              final src = (data['source'] as String?)?.trim() ?? '';
              if (src == 'hospital_accept_dispatch' || src == 'ambulance_dispatch_escalation') {
                try {
                  final callable = _functionsUsEast1.httpsCallable('acceptAmbulanceDispatch');
                  await callable.call(<String, dynamic>{
                    'incidentId': incidentId,
                    'fleetId': fleetId.trim().toUpperCase(),
                    'assignmentDocId': doc.id,
                    'etaMinutes': 12,
                  });
                } catch (e) {
                  debugPrint('[DriverPanel] acceptAmbulanceDispatch: $e');
                }
              }
            case StationUnitRole.crane:
              await IncidentService.assignCraneUnitDriver(incidentId: incidentId, driverUid: uid);
          }
        }
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Assignment accepted · Incident: ${incidentId.length > 12 ? incidentId.substring(0, 10) : incidentId}'),
            backgroundColor: Colors.green.shade800,
          ),
        );
        setState(() {
          _selectedIncidentId = incidentId.isNotEmpty ? incidentId : null;
          _pendingAssignmentDocs = [];
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Accept failed: $e'), backgroundColor: Colors.red.shade800),
        );
      }
    }
  }

  Future<void> _rejectAssignment(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final fleetId = FleetOperatorSession.fleetId ?? '';
    try {
      await FleetAssignmentService.rejectAssignment(
        fleetId: fleetId,
        assignmentDocId: doc.id,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.opsTr('Assignment rejected — status: driver unavailable')),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _pendingAssignmentDocs = []);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reject failed: $e'), backgroundColor: Colors.red.shade800),
        );
      }
    }
  }

  Future<void> _endDutySession() async {
    _stopAssignmentListener();
    _ensureHospitalAssignmentListener(null);
    _stopDutyHeartbeat();
    _locTimer?.cancel();
    _locTimer = null;
    _cachedFleetPlaceholderRow = null;
    await FleetUnitService.clearMyUnit();
    await FleetOperatorSession.setOnDuty(false);
    await StationUnitRolePrefs.clear();
    if (!context.mounted) return;
    setState(() {
      _role = null;
      _pendingRole = null;
      _selectedIncidentId = null;
      _routeToVictim = [];
      _routeToHospital = [];
      _withinVictimRadius = false;
      _withinHospitalRadius = false;
      _phase = _OperatorPhase.dutyPrep;
    });
  }

  Future<void> _signOutFleetGate() async {
    _stopAssignmentListener();
    _ensureHospitalAssignmentListener(null);
    _stopDutyHeartbeat();
    _locTimer?.cancel();
    _locTimer = null;
    _cachedFleetPlaceholderRow = null;
    await FleetUnitService.clearMyUnit();
    await FleetOperatorSession.clearVerified();
    await StationUnitRolePrefs.clear();
    if (!context.mounted) return;
    context.go('/login');
  }

  void _startDutyHeartbeat() {
    _dutyHeartbeatTimer?.cancel();
    if (!FleetOperatorSession.isOnDuty) return;
    _dutyHeartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) => _dutyHeartbeatTick());
  }

  void _stopDutyHeartbeat() {
    _dutyHeartbeatTimer?.cancel();
    _dutyHeartbeatTimer = null;
  }

  Future<void> _applyEmsProximityForSelectedIncident(Position pos, {double? headingDeg}) async {
    final selId = _selectedIncidentId?.trim();
    if (selId == null || selId.isEmpty) return;
    final uid = _uid;
    final role = _role;
    if (uid == null || role == null || role != StationUnitRole.medical) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('sos_incidents').doc(selId).get();
      if (!doc.exists || !mounted) return;
      final inc = SosIncident.fromFirestore(doc);
      if (!_isAllotted(inc, uid, role)) return;
      final victim = inc.liveVictimPin;
      final phase = (inc.emsWorkflowPhase ?? '').trim();
      if (phase == 'returning') {
        await IncidentService.emsPushUnitLocationWithReturnProximity(
          incidentId: selId,
          unitLat: pos.latitude,
          unitLng: pos.longitude,
          victimLat: victim.latitude,
          victimLng: victim.longitude,
          headingDeg: headingDeg,
        );
      } else {
        await IncidentService.emsPushUnitLocationWithProximity(
          incidentId: selId,
          unitLat: pos.latitude,
          unitLng: pos.longitude,
          victimLat: victim.latitude,
          victimLng: victim.longitude,
          headingDeg: headingDeg,
        );
      }
      final distVictimM = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        victim.latitude,
        victim.longitude,
      );
      var withinV = distVictimM <= 200;
      var withinH = false;
      if (phase == 'returning') {
        final hLat = inc.returnHospitalLat ?? _hospitalAssignment?.acceptedHospitalLat;
        final hLng = inc.returnHospitalLng ?? _hospitalAssignment?.acceptedHospitalLng;
        if (hLat != null && hLng != null) {
          withinH = Geolocator.distanceBetween(pos.latitude, pos.longitude, hLat, hLng) <= 200;
        }
      }
      if (mounted) {
        setState(() {
          _withinVictimRadius = withinV;
          _withinHospitalRadius = withinH;
        });
      }
      _scheduleRoute(inc, pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint('[DriverPanel] duty EMS proximity: $e');
    }
  }

  Future<void> _dutyHeartbeatTick() async {
    if (!context.mounted || !FleetOperatorSession.isOnDuty) return;
    final role = _role;
    if (role == null) return;
    if (_locTimer != null && _locTimer!.isActive) return;
    final fleetId = FleetOperatorSession.fleetId?.trim();
    if (fleetId == null || fleetId.isEmpty) return;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      Position? pos;
      if (perm != LocationPermission.denied && perm != LocationPermission.deniedForever) {
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
          );
        } catch (_) {
          pos = await Geolocator.getLastKnownPosition();
        }
      }
      pos ??= await Geolocator.getLastKnownPosition();

      if (pos == null) {
        _cachedFleetPlaceholderRow ??= await FleetUnitService.fleetPlaceholderRowForCallSign(fleetId);
      }

      double lat;
      double lng;
      double? headingDeg;
      if (pos != null) {
        headingDeg = _lastDutyPos == null ? null : _bearingDegFromPositions(_lastDutyPos!, pos);
        _lastDutyPos = pos;
        lat = pos.latitude;
        lng = pos.longitude;
      } else if (_cachedFleetPlaceholderRow != null) {
        lat = _cachedFleetPlaceholderRow!.lat;
        lng = _cachedFleetPlaceholderRow!.lng;
      } else {
        const defaultLat = 26.8467;
        const defaultLng = 80.9462;
        lat = defaultLat;
        lng = defaultLng;
      }

      final hid = await _hospitalIdForFleetSync();

      await FleetUnitService.syncMyUnit(
        vehicleType: role.fleetVehicleType,
        lat: lat,
        lng: lng,
        available: true,
        fleetCallSign: fleetId,
        headingDeg: headingDeg,
        stationedHospitalId: hid,
        assignedHospitalId: hid,
      );
      if (pos != null && role == StationUnitRole.medical) {
        await _applyEmsProximityForSelectedIncident(pos, headingDeg: headingDeg);
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[DriverPanel] duty heartbeat: $e');
    }
  }

  Future<void> _openDirections(LatLng dest) async {
    final u = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${dest.latitude},${dest.longitude}&travelmode=driving',
    );
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _refreshVolunteerRouteOverlay(SosIncident inc) async {
    final v = inc.volunteerLiveLocation;
    if (v == null) {
      if (_volunteerRouteToScene.isNotEmpty && context.mounted) {
        setState(() => _volunteerRouteToScene = []);
      }
      return;
    }
    final pin = inc.liveVictimPin;
    final sig =
        '${inc.id}:${v.latitude.toStringAsFixed(5)}:${v.longitude.toStringAsFixed(5)}:${pin.latitude.toStringAsFixed(5)}:${pin.longitude.toStringAsFixed(5)}';
    if (sig == _volunteerRouteOverlaySig && _volunteerRouteToScene.length >= 2) return;
    _volunteerRouteOverlaySig = sig;
    final pts = await OsrmRouteUtil.drivingRoute(v, pin);
    final path = pts.length >= 2 ? pts : OsrmRouteUtil.fallbackPolyline(v, pin);
    if (!context.mounted) return;
    setState(() => _volunteerRouteToScene = path);
  }

  void _scheduleRoute(SosIncident inc, double fromLat, double fromLng) {
    _routeDebounce?.cancel();
    final phase = (inc.emsWorkflowPhase ?? '').trim();
    late LatLng dest;
    if (phase == 'returning') {
      final lat = inc.returnHospitalLat ?? _hospitalAssignment?.acceptedHospitalLat;
      final lng = inc.returnHospitalLng ?? _hospitalAssignment?.acceptedHospitalLng;
      if (lat == null || lng == null) {
        if (context.mounted) {
          setState(() {
            _routeToVictim = [];
            _routeToHospital = [];
          });
        }
        return;
      }
      dest = LatLng(lat, lng);
    } else {
      dest = inc.liveVictimPin;
    }
    _routeDebounce = Timer(const Duration(milliseconds: 600), () async {
      final pts = await OsrmRouteUtil.drivingRoute(LatLng(fromLat, fromLng), dest);
      if (!context.mounted) return;
      if (phase == 'returning') {
        setState(() {
          _routeToHospital = pts;
          _routeToVictim = [];
        });
      } else {
        setState(() {
          _routeToVictim = pts;
          _routeToHospital = [];
        });
      }
    });
  }

  Future<void> _onSlideOnSceneConfirm(SosIncident inc) async {
    await IncidentService.markEmsOnScene(incidentId: inc.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.opsTr('On scene confirmed'))),
    );
    if (mounted) setState(() {});
  }

  Future<void> _onSlideRescueComplete(SosIncident inc) async {
    final hid = _hospitalAssignment?.acceptedHospitalId?.trim();
    final lat = _hospitalAssignment?.acceptedHospitalLat;
    final lng = _hospitalAssignment?.acceptedHospitalLng;
    if (hid == null || hid.isEmpty || lat == null || lng == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.opsTr('Accepting hospital coordinates not available yet.'))),
        );
      }
      return;
    }
    await IncidentService.markEmsRescueComplete(
      incidentId: inc.id,
      returnHospitalId: hid,
      returnHospitalLat: lat,
      returnHospitalLng: lng,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.opsTr('Rescue complete — route to accepting hospital'))),
    );
    final pos = _lastSharePos;
    if (pos != null) {
      final doc = await FirebaseFirestore.instance.collection('sos_incidents').doc(inc.id).get();
      if (doc.exists && context.mounted) {
        final fresh = SosIncident.fromFirestore(doc);
        _scheduleRoute(fresh, pos.latitude, pos.longitude);
        final hLat = fresh.returnHospitalLat ?? lat;
        final hLng = fresh.returnHospitalLng ?? lng;
        _mapCtl?.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(
                math.min(pos.latitude, hLat) - 0.01,
                math.min(pos.longitude, hLng) - 0.01,
              ),
              northeast: LatLng(
                math.max(pos.latitude, hLat) + 0.01,
                math.max(pos.longitude, hLng) + 0.01,
              ),
            ),
            40,
          ),
        );
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _onSlideResponseComplete(SosIncident inc) async {
    await IncidentService.markEmsResponseComplete(incidentId: inc.id);
    if (!context.mounted) return;
    final cycle = DateTime.now().difference(inc.timestamp);
    final m = cycle.inMinutes;
    final s = cycle.inSeconds % 60;
    _stopLiveShare();
    _ensureHospitalAssignmentListener(null);
    setState(() {
      _selectedIncidentId = null;
      _routeToVictim = [];
      _routeToHospital = [];
      _withinVictimRadius = false;
      _withinHospitalRadius = false;
    });
    if (FleetOperatorSession.isOnDuty) _startDutyHeartbeat();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Response cycle complete · ${m}m ${s}s total')),
      );
    }
  }

  Future<void> _startLiveShare(SosIncident inc, StationUnitRole role) async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.deniedForever || p == LocationPermission.denied) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.opsTr('Turn on location to share your unit position.'))),
        );
      }
      return;
    }

    final fleetHospitalId = await _hospitalIdForFleetSync();

    _lastSharePos = null;
    _withinVictimRadius = false;
    _withinHospitalRadius = false;
    _locTimer?.cancel();
    _locTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!context.mounted || _selectedIncidentId != inc.id) return;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
        );
        final doc = await FirebaseFirestore.instance.collection('sos_incidents').doc(inc.id).get();
        if (!doc.exists || !context.mounted) return;
        final fresh = SosIncident.fromFirestore(doc);
        final victim = fresh.liveVictimPin;
        final phase = (fresh.emsWorkflowPhase ?? '').trim();
        final heading = _lastSharePos == null ? null : _bearingDegFromPositions(_lastSharePos!, pos);
        _lastSharePos = pos;

        final distVictimM = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          victim.latitude,
          victim.longitude,
        );
        var withinV = distVictimM <= 200;
        var withinH = false;
        if (phase == 'returning') {
          final hLat = fresh.returnHospitalLat ?? _hospitalAssignment?.acceptedHospitalLat;
          final hLng = fresh.returnHospitalLng ?? _hospitalAssignment?.acceptedHospitalLng;
          if (hLat != null && hLng != null) {
            final distH = Geolocator.distanceBetween(pos.latitude, pos.longitude, hLat, hLng);
            withinH = distH <= 200;
          }
        }

        await FleetUnitService.syncMyUnit(
          vehicleType: role.fleetVehicleType,
          lat: pos.latitude,
          lng: pos.longitude,
          available: false,
          assignedIncidentId: inc.id,
          headingDeg: heading,
          fleetCallSign: FleetOperatorSession.fleetId,
          stationedHospitalId: fleetHospitalId,
          assignedHospitalId: fleetHospitalId,
        );
        switch (role) {
          case StationUnitRole.medical:
            if (phase == 'returning') {
              await IncidentService.emsPushUnitLocationWithReturnProximity(
                incidentId: inc.id,
                unitLat: pos.latitude,
                unitLng: pos.longitude,
                victimLat: victim.latitude,
                victimLng: victim.longitude,
                headingDeg: heading,
              );
            } else {
              await IncidentService.emsPushUnitLocationWithProximity(
                incidentId: inc.id,
                unitLat: pos.latitude,
                unitLng: pos.longitude,
                victimLat: victim.latitude,
                victimLng: victim.longitude,
                headingDeg: heading,
              );
            }
          case StationUnitRole.crane:
            await IncidentService.pushCraneLiveLocation(
              inc.id,
              pos.latitude,
              pos.longitude,
              headingDeg: heading,
            );
        }
        if (context.mounted) {
          setState(() {
            _withinVictimRadius = withinV;
            _withinHospitalRadius = withinH;
          });
        }
        _scheduleRoute(fresh, pos.latitude, pos.longitude);

        if (phase == 'returning') {
          final hLat = fresh.returnHospitalLat ?? _hospitalAssignment?.acceptedHospitalLat;
          final hLng = fresh.returnHospitalLng ?? _hospitalAssignment?.acceptedHospitalLng;
          if (hLat != null && hLng != null) {
            _mapCtl?.animateCamera(
              CameraUpdate.newLatLngBounds(
                LatLngBounds(
                  southwest: LatLng(
                    math.min(pos.latitude, hLat) - 0.01,
                    math.min(pos.longitude, hLng) - 0.01,
                  ),
                  northeast: LatLng(
                    math.max(pos.latitude, hLat) + 0.01,
                    math.max(pos.longitude, hLng) + 0.01,
                  ),
                ),
                40,
              ),
            );
          }
        } else {
          _mapCtl?.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(
                  math.min(victim.latitude, pos.latitude) - 0.01,
                  math.min(victim.longitude, pos.longitude) - 0.01,
                ),
                northeast: LatLng(
                  math.max(victim.latitude, pos.latitude) + 0.01,
                  math.max(victim.longitude, pos.longitude) + 0.01,
                ),
              ),
              40,
            ),
          );
        }
      } catch (e) {
        debugPrint('[DriverPanel] location tick: $e');
      }
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.opsTr('Live location sharing on (every 5s) · fleet map'))),
      );
    }
  }

  void _stopLiveShare() {
    _locTimer?.cancel();
    _locTimer = null;
    _lastSharePos = null;
    _withinVictimRadius = false;
    _withinHospitalRadius = false;
    unawaited(FleetUnitService.clearMyUnit());
    setState(() {
      _routeToVictim = [];
      _routeToHospital = [];
    });
    if (FleetOperatorSession.isOnDuty && _selectedIncidentId == null) {
      _startDutyHeartbeat();
    }
  }

  void _openFleetEmergencyBridge(SosIncident inc) {
    context.push('/fleet-live/emergency/${Uri.encodeComponent(inc.id)}');
  }

  void _openFleetOperatorComms(SosIncident inc) {
    final h = _stationedHospitalIdFromFleetCallSign(FleetOperatorSession.fleetId);
    final q = (h != null && h.isNotEmpty) ? '?h=${Uri.encodeComponent(h)}' : '';
    context.push('/fleet-live/operation/${Uri.encodeComponent(inc.id)}$q');
  }

  @override
  Widget build(BuildContext context) {
    if (!_sessionReady) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D1117),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF58A6FF))),
      );
    }

    if (_phase == _OperatorPhase.gate) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        appBar: AppBar(
          backgroundColor: const Color(0xFF161B22),
          title: Text(context.opsTr('Fleet operator gate')),
          actions: const [LanguageSwitcherButton()],
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => unawaited(_signOutFleetGate()),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Sign in with your unit call sign and the password stored in Firestore (ops_fleet_accounts). '
                'Operations can view or reset credentials from the admin Fleet Management console.',
                style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.45),
              ),
              // Demo hint banner for judges
              if (DemoCredentials.fleetId.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F6FEB).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF58A6FF), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFF58A6FF), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '🎯 Demo: Fleet ID and password are pre-filled. Tap "Verify & continue".',
                          style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 12, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: _fleetIdCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _opFieldDeco('Fleet ID / call sign'),
                textInputAction: TextInputAction.next,
                autocorrect: false,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _opFieldDeco('Password'),
                obscureText: true,
                onSubmitted: (_) => unawaited(_verifyGate()),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _gateBusy ? null : () => unawaited(_verifyGate()),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF238636), padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _gateBusy
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(context.opsTr('Verify & continue')),
              ),
            ],
          ),
        ),
      );
    }

    if (_phase == _OperatorPhase.dutyPrep) {
      if (_pendingRole == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _pendingRole = StationUnitRole.medical);
        });
      }
      return Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        appBar: AppBar(
          backgroundColor: const Color(0xFF161B22),
          title: Text('Fleet · ${FleetOperatorSession.fleetId ?? ""}'),
          actions: const [LanguageSwitcherButton()],
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => unawaited(_signOutFleetGate()),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.medical_services_rounded, size: 56, color: Color(0xFF58A6FF)),
                const SizedBox(height: 20),
                const Text(
                  'Ready for duty',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Command will see your unit on the fleet map once GPS is available. You will receive assignment notifications for active incidents.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 40),
                FilledButton(
                  onPressed: () => unawaited(_goOnDuty()),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF238636),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(context.opsTr('Go on duty'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () => unawaited(_signOutFleetGate()),
                  child: Text(context.opsTr('Sign out fleet ID'), style: TextStyle(color: Colors.white38)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final role = _role;
    if (role == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        body: Center(child: Text(context.opsTr('Session error — reopen operator console.'), style: TextStyle(color: Colors.white54))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(role.shortLabel, style: const TextStyle(fontSize: 16)),
            Text(
              FleetOperatorSession.fleetId ?? '',
              style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          const LanguageSwitcherButton(),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('sos_incidents').limit(200).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              final uid = _uid;
              final all = snap.data!.docs.map(SosIncident.fromFirestore).toList();
              final mine = all.where((e) => _isAllotted(e, uid, role)).length;
              if (mine < 2) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 6, top: 10, bottom: 10),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF238636).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF79C0FF).withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Queue: $mine',
                    style: const TextStyle(color: Color(0xFF79C0FF), fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
              );
            },
          ),
          TextButton(
            onPressed: () => unawaited(_endDutySession()),
            child: Text(context.opsTr('End duty'), style: TextStyle(color: Colors.orangeAccent, fontSize: 13)),
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_selectedIncidentId != null) {
              _ensureHospitalAssignmentListener(null);
              setState(() {
                _selectedIncidentId = null;
                _volunteerRouteToScene = [];
                _volunteerRouteOverlaySig = '';
                _routeToVictim = [];
                _routeToHospital = [];
                _withinVictimRadius = false;
                _withinHospitalRadius = false;
              });
              if (FleetOperatorSession.isOnDuty) _startDutyHeartbeat();
            } else {
              unawaited(_signOutFleetGate());
            }
          },
        ),
      ),
      body: Column(
        children: [
          // \u2500\u2500 Incoming assignment banner \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          if (_pendingAssignmentDocs.isNotEmpty)
            _AssignmentNotificationBanner(
              doc: _pendingAssignmentDocs.first,
              queueCount: _pendingAssignmentDocs.length,
              onAccept: () => _acceptAssignment(_pendingAssignmentDocs.first),
              onReject: () => _rejectAssignment(_pendingAssignmentDocs.first),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('sos_incidents').limit(200).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('${snap.error}', style: const TextStyle(color: Colors.white70)));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF58A6FF)));
                }
                final all = snap.data!.docs.map(SosIncident.fromFirestore).toList();
                final uid = _uid;
                final mine = all.where((e) => _isAllotted(e, uid, role)).toList()
                  ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

                final sid = _selectedIncidentId;
                SosIncident? selected;
                if (sid != null) {
                  for (final e in mine) {
                    if (e.id == sid) {
                      selected = e;
                      break;
                    }
                  }
                }

                if (sid != null && selected == null && mine.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _selectedIncidentId = mine.first.id);
                  });
                }

                if (mine.length == 1 && _selectedIncidentId == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _selectedIncidentId = mine.first.id);
                  });
                }

                if (selected != null) {
                  final incidentForCb = selected;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    _ensureHospitalAssignmentListener(incidentForCb.id);
                    unawaited(_refreshVolunteerRouteOverlay(incidentForCb));
                  });
                  return _DriverDetailView(
                    incident: incidentForCb,
                    queue: mine,
                    role: role,
                    fleetCallSign: FleetOperatorSession.fleetId,
                    operatorUid: uid ?? '',
                    fleetMapZoom: _driverMapZoom,
                    onFleetCameraMove: (z) {
                      if (FleetMapIcons.zoomTierChanged(_driverMapZoom, z)) {
                        setState(() => _driverMapZoom = z);
                      }
                    },
                    onMapCreated: (c) => _mapCtl = c,
                    routeToVictim: _routeToVictim,
                    routeToHospital: _routeToHospital,
                    volunteerRouteToScene: _volunteerRouteToScene,
                    unitMapOverride: _unitMapOverlayLatLng(incidentForCb),
                    withinVictimRadius: _withinVictimRadius,
                    withinHospitalRadius: _withinHospitalRadius,
                    hospitalAssignment: _hospitalAssignment,
                    onDirections: () => _openDirections(incidentForCb.liveVictimPin),
                    onEmergencyLiveKit: () => _openFleetEmergencyBridge(incidentForCb),
                    onOperatorLiveKit: () => _openFleetOperatorComms(incidentForCb),
                    onStartLive: () => _startLiveShare(incidentForCb, role),
                    onStopLive: _stopLiveShare,
                    isLive: _locTimer != null && _locTimer!.isActive,
                    onSlideOnSceneConfirm: () => _onSlideOnSceneConfirm(incidentForCb),
                    onSlideRescueComplete: () => _onSlideRescueComplete(incidentForCb),
                    onSlideResponseComplete: () => _onSlideResponseComplete(incidentForCb),
                    onSelectQueuedIncident: (id) {
                      _ensureHospitalAssignmentListener(id);
                      setState(() => _selectedIncidentId = id);
                    },
                  );
                }

                if (mine.isEmpty) {
                  final center = _lastDutyPos != null
                      ? LatLng(_lastDutyPos!.latitude, _lastDutyPos!.longitude)
                      : IndiaOpsZones.lucknow.center;
                  final fb = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
                  return Column(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: EosHybridMap(
                              initialCameraPosition:
                                  IndiaOpsZones.lucknowSafeCamera(center, preferZoom: _lastDutyPos != null ? 14 : 10.5),
                              cameraTargetBounds: IndiaOpsZones.lucknowCameraTargetBounds,
                              markers: {
                                if (_lastDutyPos != null)
                                  Marker(
                                    markerId: const MarkerId('operator_standby'),
                                    position: LatLng(_lastDutyPos!.latitude, _lastDutyPos!.longitude),
                                    icon: OpsMapMarkers.ambulanceOr(fb),
                                    infoWindow: InfoWindow(
                                      title: FleetOperatorSession.fleetId ?? 'Your unit',
                                      snippet: 'Standby — visible to command when GPS updates',
                                    ),
                                  ),
                              },
                              mapId: AppConstants.googleMapsDarkMapId.isNotEmpty
                                  ? AppConstants.googleMapsDarkMapId
                                  : null,
                              style: effectiveGoogleMapsEmbeddedStyleJson(),
                              onMapCreated: (c) => _standbyMapCtl = c,
                              zoomControlsEnabled: false,
                              mapToolbarEnabled: false,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: _StandbyDispatchPanel(
                          role: role,
                          fleetId: FleetOperatorSession.fleetId,
                          hasGpsFix: _lastDutyPos != null,
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: _AssignmentMiniMap(incidents: mine),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _AssignmentList(
                        incidents: mine,
                        role: role,
                        uid: uid,
                        onTap: (id) => setState(() => _selectedIncidentId = id),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (_pendingAssignmentDocs.isNotEmpty)
            _FleetAssignmentResponseBottomBar(
              key: ValueKey(_pendingAssignmentDocs.first.id),
              deadline: FleetAssignmentService.responseDeadlineForData(_pendingAssignmentDocs.first.data()) ??
                  DateTime.now(),
            ),
        ],
      ),
    );
  }
}

/// Bottom strip: time left in the 3-minute accept/reject window (rebuilds with parent tick).
class _FleetAssignmentResponseBottomBar extends StatelessWidget {
  const _FleetAssignmentResponseBottomBar({super.key, required this.deadline});

  final DateTime deadline;

  @override
  Widget build(BuildContext context) {
    final total = FleetAssignmentService.responseWindowSeconds;
    final secsLeft = deadline.difference(DateTime.now()).inSeconds.clamp(0, total);
    final progress = total <= 0 ? 0.0 : secsLeft / total;
    final m = secsLeft ~/ 60;
    final s = secsLeft % 60;
    final timeStr = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    final label =
        'Respond within $timeStr. After 3:00 the assignment is marked driver did not respond.';

    return Semantics(
      label: label,
      child: Material(
        color: const Color(0xFF0D1117),
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Response window',
                  style: TextStyle(color: Colors.orange.shade200, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: Colors.white12,
                    color: secsLeft <= 30 ? Colors.redAccent : Colors.orangeAccent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.25),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small overview map for all incidents allotted to this operator.
class _AssignmentMiniMap extends StatefulWidget {
  const _AssignmentMiniMap({required this.incidents});

  final List<SosIncident> incidents;

  @override
  State<_AssignmentMiniMap> createState() => _AssignmentMiniMapState();
}

class _AssignmentMiniMapState extends State<_AssignmentMiniMap> {
  OpsMapController? _ctl;

  void _fitBounds() {
    if (_ctl == null || widget.incidents.isEmpty) return;
    final pts = widget.incidents.map((e) => e.liveVictimPin).toList();
    var minLat = pts.first.latitude;
    var maxLat = minLat;
    var minLng = pts.first.longitude;
    var maxLng = minLng;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    const pad = 0.025;
    _ctl!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - pad, minLng - pad),
          northeast: LatLng(maxLat + pad, maxLng + pad),
        ),
        40,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _AssignmentMiniMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.incidents.length != widget.incidents.length ||
        oldWidget.incidents.map((e) => e.id).join() != widget.incidents.map((e) => e.id).join()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.incidents.isEmpty) return const SizedBox.shrink();
    final fb = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    return SizedBox(
      height: 180,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: EosHybridMap(
          initialCameraPosition: CameraPosition(target: widget.incidents.first.liveVictimPin, zoom: 12),
          cameraTargetBounds: IndiaOpsZones.lucknowCameraTargetBounds,
          mapId: AppConstants.googleMapsDarkMapId.isNotEmpty ? AppConstants.googleMapsDarkMapId : null,
          style: effectiveGoogleMapsEmbeddedStyleJson(),
          markers: {
            for (final e in widget.incidents)
              Marker(
                markerId: MarkerId('asg_${e.id}'),
                position: e.liveVictimPin,
                icon: OpsMapMarkers.incidentOr(fb),
                infoWindow: InfoWindow(title: e.type, snippet: 'Tap a run below'),
              ),
          },
          onMapCreated: (c) {
            _ctl = c;
            WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
          },
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
        ),
      ),
    );
  }
}

class _StandbyDispatchPanel extends StatefulWidget {
  const _StandbyDispatchPanel({
    required this.role,
    required this.fleetId,
    required this.hasGpsFix,
  });

  final StationUnitRole role;
  final String? fleetId;
  final bool hasGpsFix;

  @override
  State<_StandbyDispatchPanel> createState() => _StandbyDispatchPanelState();
}

class _StandbyDispatchPanelState extends State<_StandbyDispatchPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    FadeTransition(
                      opacity: Tween<double>(begin: 0.35, end: 1).animate(
                        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                      ),
                      child: const Icon(Icons.radar, color: Color(0xFF58A6FF), size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.opsTr('Awaiting dispatch…'), style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.hasGpsFix
                                ? 'You are on standby. Command sees your last GPS ping on the map above.'
                                : 'Enable location so your unit appears on the Lucknow fleet map.',
                            style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      avatar: Icon(
                        widget.role == StationUnitRole.medical ? Icons.medical_services : Icons.construction,
                        size: 18,
                        color: Colors.white70,
                      ),
                      label: Text(widget.role.shortLabel),
                      backgroundColor: const Color(0xFF21262D),
                      labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    if ((widget.fleetId ?? '').isNotEmpty)
                      Chip(
                        label: Text(widget.fleetId!),
                        backgroundColor: const Color(0xFF238636).withValues(alpha: 0.25),
                        labelStyle: const TextStyle(color: Color(0xFF7EE787), fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const LinearProgressIndicator(
                  backgroundColor: Color(0xFF21262D),
                  color: Color(0xFF58A6FF),
                  minHeight: 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _opFieldDeco(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: const Color(0xFF161B22),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
    );

// ── Incoming assignment notification banner ───────────────────────────────────

class _AssignmentNotificationBanner extends StatelessWidget {
  const _AssignmentNotificationBanner({
    required this.doc,
    this.queueCount = 1,
    required this.onAccept,
    required this.onReject,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final int queueCount;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final incidentId = (data['incidentId'] as String?)?.trim() ?? 'Unknown';
    final callSign = (data['callSign'] as String?)?.trim() ?? '';
    final vehicleType = (data['vehicleType'] as String?)?.trim() ?? '';
    final dispatchHosp = (data['dispatchingHospitalName'] as String?)?.trim() ?? '';
    final dispatchHospId = (data['dispatchingHospitalId'] as String?)?.trim() ?? '';
    final incType = (data['incidentType'] as String?)?.trim() ?? '';

    final shortId = incidentId.length > 14 ? '${incidentId.substring(0, 12)}…' : incidentId;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orangeAccent, width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.orange.withValues(alpha: 0.2), blurRadius: 14, spreadRadius: 2),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_turned_in, color: Colors.orangeAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  queueCount > 1 ? 'Incoming assignments ($queueCount in queue)' : 'Incoming Assignment',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              if (queueCount > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$queueCount',
                    style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _BannerRow('Incident', shortId),
          if (dispatchHosp.isNotEmpty)
            _BannerRow('Dispatch from', dispatchHosp)
          else if (dispatchHospId.isNotEmpty)
            _BannerRow('Hospital', dispatchHospId),
          if (incType.isNotEmpty) _BannerRow('Emergency type', incType),
          if (vehicleType.isNotEmpty) _BannerRow('Vehicle type', vehicleType),
          if (callSign.isNotEmpty) _BannerRow('Call sign', callSign),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: onAccept,
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(context.opsTr('Accept'), style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: onReject,
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(context.opsTr('Reject'), style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BannerRow extends StatelessWidget {
  const _BannerRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _AssignmentList extends StatelessWidget {
  const _AssignmentList({
    required this.incidents,
    required this.role,
    required this.uid,
    required this.onTap,
  });

  final List<SosIncident> incidents;
  final StationUnitRole role;
  final String? uid;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d · HH:mm');
    if (uid == null || uid!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(context.opsTr('Sign in to see your allotments.'), style: TextStyle(color: Colors.white54)),
        ),
      );
    }
    if (incidents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                role == StationUnitRole.medical
                    ? Icons.medical_services_outlined
                    : Icons.construction_outlined,
                size: 56,
                color: Colors.white24,
              ),
              const SizedBox(height: 16),
              Text(
                'No active allotments for ${role.label}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 10),
              const Text(
                'Command assigns your unit in the admin panel. When you are allotted, the run appears here with victim details and map.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: incidents.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = incidents[i];
        return Material(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onTap(e.id),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.type,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF238636).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(context.opsTr('Allotted to you'), style: TextStyle(color: Color(0xFF79C0FF), fontSize: 10, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(e.userDisplayName, style: const TextStyle(color: Colors.white60, fontSize: 13)),
                  Text(fmt.format(e.timestamp.toLocal()), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  if (role == StationUnitRole.medical && (e.emsWorkflowPhase ?? '').isNotEmpty)
                    Text('EMS: ${e.emsWorkflowPhase}', style: const TextStyle(color: Colors.cyanAccent, fontSize: 11)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Horizontal swipe pager when the operator has multiple simultaneous allotments.
class _QueuedIncidentPager extends StatefulWidget {
  const _QueuedIncidentPager({
    required this.queue,
    required this.currentId,
    required this.onSelect,
  });

  final List<SosIncident> queue;
  final String currentId;
  final ValueChanged<String> onSelect;

  @override
  State<_QueuedIncidentPager> createState() => _QueuedIncidentPagerState();
}

class _QueuedIncidentPagerState extends State<_QueuedIncidentPager> {
  late PageController _ctl;

  int _indexFor(String id) {
    final i = widget.queue.indexWhere((e) => e.id == id);
    return i >= 0 ? i : 0;
  }

  @override
  void initState() {
    super.initState();
    _ctl = PageController(initialPage: _indexFor(widget.currentId));
  }

  @override
  void didUpdateWidget(covariant _QueuedIncidentPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.queue.length != oldWidget.queue.length) {
      _ctl.dispose();
      _ctl = PageController(initialPage: _indexFor(widget.currentId));
      return;
    }
    if (widget.currentId != oldWidget.currentId) {
      final ix = _indexFor(widget.currentId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_ctl.hasClients) return;
        final cur = _ctl.page?.round() ?? 0;
        if (cur != ix) _ctl.jumpToPage(ix);
      });
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d · HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.swap_horiz, color: Color(0xFF79C0FF), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Swipe between ${widget.queue.length} active runs',
                style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 92,
          child: PageView.builder(
            controller: _ctl,
            itemCount: widget.queue.length,
            onPageChanged: (i) {
              final id = widget.queue[i].id;
              if (id != widget.currentId) widget.onSelect(id);
            },
            itemBuilder: (_, i) {
              final e = widget.queue[i];
              final sel = e.id == widget.currentId;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Material(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.type,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (sel)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF238636).withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(context.opsTr('VIEWING'), style: TextStyle(color: Color(0xFF69F0AE), fontSize: 9, fontWeight: FontWeight.w800),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.userDisplayName,
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          fmt.format(e.timestamp.toLocal()),
                          style: const TextStyle(color: Colors.white38, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Fleet driver run detail (three-tab mobile layout) ───────────────────────

String _shortIncidentIdForDisplay(String id) {
  final t = id.trim();
  if (t.length <= 12) return t;
  return '${t.substring(0, 8)}…';
}

class _DriverMapLayers {
  _DriverMapLayers({required this.markers, required this.polylines, required this.victim});

  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final LatLng victim;

  static _DriverMapLayers build({
    required SosIncident incident,
    required double fleetMapZoom,
    required List<LatLng> routeToVictim,
    required List<LatLng> routeToHospital,
    required List<LatLng> volunteerRouteToScene,
    LatLng? unitPositionOverride,
    LatLng? hospitalLatLng,
    String? hospitalName,
  }) {
    final victim = incident.liveVictimPin;
    final phase = (incident.emsWorkflowPhase ?? '').trim();
    final fbRed = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    final fbAz = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    final fbHosp = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('victim'),
        position: victim,
        zIndexInt: 2,
        infoWindow: InfoWindow(title: incident.userDisplayName, snippet: 'Scene / victim pin'),
        icon: OpsMapMarkers.sceneOr(fbRed),
      ),
    };

    if (hospitalLatLng != null && phase != 'complete') {
      markers.add(
        Marker(
          markerId: const MarkerId('return_hospital'),
          position: hospitalLatLng,
          zIndexInt: 2,
          icon: fbHosp,
          infoWindow: InfoWindow(
            title: (hospitalName ?? '').isNotEmpty ? hospitalName! : 'Accepting hospital',
            snippet: phase == 'returning' ? 'Return destination' : 'Assigned receiving facility',
          ),
        ),
      );
    }

    final amb = incident.ambulanceLiveLocation ?? unitPositionOverride;
    if (amb != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('amb'),
          position: amb,
          zIndexInt: 3,
          icon: FleetMapIcons.ambulanceForZoom(fleetMapZoom, fbAz),
          rotation: incident.ambulanceLiveLocation != null
              ? (incident.ambulanceLiveHeadingDeg ?? 0)
              : 0,
          flat: true,
          anchor: const Offset(0.5, 0.5),
        ),
      );
    }
    final polylines = <Polyline>{};
    final showVictimRoute = phase != 'returning' && phase != 'complete';
    if (routeToVictim.length >= 2 && showVictimRoute) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('drv_route'),
          points: routeToVictim,
          color: const Color(0xFF58A6FF).withValues(alpha: 0.9),
          width: 5,
        ),
      );
    }
    if (routeToHospital.length >= 2 && phase == 'returning') {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('drv_route_hospital'),
          points: routeToHospital,
          color: const Color(0xFF79C0FF).withValues(alpha: 0.95),
          width: 5,
          zIndex: 3,
        ),
      );
    }
    if (volunteerRouteToScene.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('volunteer_to_scene'),
          points: volunteerRouteToScene,
          color: AppColors.primarySafe,
          width: 6,
          zIndex: 2,
          patterns: [PatternItem.dash(14), PatternItem.gap(8)],
        ),
      );
    }
    return _DriverMapLayers(markers: markers, polylines: polylines, victim: victim);
  }
}

class _DriverEtaStatusStrip extends StatelessWidget {
  const _DriverEtaStatusStrip({
    required this.incident,
    required this.role,
  });

  final SosIncident incident;
  final StationUnitRole role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2333),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF58A6FF).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.opsTr('Published ETAs (victim app)'), style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Ambulance · ${incident.ambulanceEta ?? "—"}',
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, height: 1.25),
          ),
          if ((incident.medicalStatus ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Medical line · ${incident.medicalStatus}',
              style: const TextStyle(color: Colors.tealAccent, fontSize: 12, height: 1.3),
            ),
          ],
          if (role == StationUnitRole.medical && (incident.emsWorkflowPhase ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'EMS workflow · ${incident.emsWorkflowPhase}',
              style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}

class _VictimActivityList extends StatelessWidget {
  const _VictimActivityList({required this.incidentId, this.shrinkWrap = false});

  final String incidentId;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sos_incidents')
          .doc(incidentId)
          .collection('victim_activity')
          .orderBy('createdAt', descending: true)
          .limit(12)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text('Feed: ${snap.error}', style: const TextStyle(color: Colors.redAccent, fontSize: 10));
        }
        if (!snap.hasData) {
          return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text(context.opsTr('No activity lines yet.'), style: TextStyle(color: Colors.white38, fontSize: 11)),
          );
        }
        return ListView.separated(
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          padding: const EdgeInsets.only(right: 2),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final text = (d['text'] as String?) ?? '';
            DateTime? t;
            final c = d['createdAt'];
            if (c is Timestamp) t = c.toDate();
            final ts = t == null ? '—' : DateFormat('HH:mm').format(t.toLocal());
            return Material(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        ts,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        text,
                        style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DriverMapPanel extends StatelessWidget {
  const _DriverMapPanel({
    required this.layers,
    required this.onFleetCameraMove,
    required this.onMapCreated,
    this.mapBottomOverlay,
  });

  final _DriverMapLayers layers;
  final ValueChanged<double> onFleetCameraMove;
  final void Function(OpsMapController) onMapCreated;
  final Widget? mapBottomOverlay;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          EosHybridMap(
            cameraTargetBounds: IndiaOpsZones.lucknowCameraTargetBounds,
            initialCameraPosition: IndiaOpsZones.lucknowSafeCamera(layers.victim, preferZoom: 14),
            onCameraMove: (CameraPosition p) => onFleetCameraMove(p.zoom),
            markers: layers.markers,
            polylines: layers.polylines,
            mapType: MapType.normal,
            mapId: AppConstants.googleMapsDarkMapId.isNotEmpty ? AppConstants.googleMapsDarkMapId : null,
            style: effectiveGoogleMapsEmbeddedStyleJson(),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: false,
            onMapCreated: onMapCreated,
          ),
          if (mapBottomOverlay != null)
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: SafeArea(
                top: false,
                child: mapBottomOverlay!,
              ),
            ),
        ],
      ),
    );
  }
}

/// Turn-by-turn and unit GPS share (Map tab).
class _DriverMapShareBar extends StatelessWidget {
  const _DriverMapShareBar({
    required this.onDirections,
    required this.onStartLive,
    required this.onStopLive,
    required this.isLive,
  });

  final VoidCallback onDirections;
  final VoidCallback onStartLive;
  final VoidCallback onStopLive;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: onDirections,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF238636)),
          icon: const Icon(Icons.navigation_rounded, size: 20),
          label: Text(context.opsTr('Turn-by-turn')),
        ),
        if (!isLive)
          OutlinedButton.icon(
            onPressed: onStartLive,
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF58A6FF)),
            icon: const Icon(Icons.gps_fixed, size: 18),
            label: Text(context.opsTr('Share unit location')),
          )
        else
          OutlinedButton.icon(
            onPressed: onStopLive,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.orangeAccent),
            icon: const Icon(Icons.pause_circle_outline, size: 18),
            label: Text(context.opsTr('Stop sharing')),
          ),
      ],
    );
  }
}

/// EMS → receiving physician verbal report structure (SBAR), read-only from incident data.
class _EmsPhysicianHandoffReport extends StatelessWidget {
  const _EmsPhysicianHandoffReport({required this.incident, required this.fleetCallSign});

  final SosIncident incident;
  final String? fleetCallSign;

  String _briefSummary() {
    final m = incident.sharedSituationBrief;
    if (m == null || m.isEmpty) return '—';
    final s = (m['summary'] as String?)?.trim();
    if (s != null && s.isNotEmpty) return s;
    return '—';
  }

  String _triageBlock() {
    final t = incident.triage;
    if (t == null || t.isEmpty) return 'No triage snapshot on file.';
    final buf = StringBuffer();
    for (final e in t.entries) {
      buf.writeln('${e.key}: ${e.value}');
    }
    return buf.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy · HH:mm');
    final idShort = _shortIncidentIdForDisplay(incident.id);

    Widget section(String title, String body) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(color: Color(0xFF79C0FF), fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            SelectableText(
              body,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.45),
            ),
          ],
        ),
      );
    }

    final situation = [
      'Chief / incident type: ${incident.type}',
      'Reported: ${fmt.format(incident.timestamp.toLocal())}',
      'Status: ${incident.status.name}',
      if ((incident.emsWorkflowPhase ?? '').isNotEmpty) 'EMS workflow: ${incident.emsWorkflowPhase}',
      'Victim app ETA: ${incident.ambulanceEta ?? "—"}',
      if ((incident.medicalStatus ?? '').isNotEmpty) 'Medical line (victim UI): ${incident.medicalStatus}',
    ].join('\n');

    final background = [
      'Patient / reporter name: ${incident.userDisplayName}',
      'Incident ID (full in tooltip on subtitle): $idShort',
      if (incident.bloodType != null || incident.allergies != null || incident.medicalConditions != null)
        'Blood: ${incident.bloodType ?? "—"} · Allergies: ${incident.allergies ?? "—"} · Conditions: ${incident.medicalConditions ?? "—"}'
      else
        'Blood / allergies / conditions: not recorded on SOS.',
      if ((incident.emergencyContactPhone ?? '').isNotEmpty)
        'Emergency contact phone: ${incident.emergencyContactPhone} (${incident.useEmergencyContactForSms ? "SMS on" : "SMS off"})',
      if ((incident.emergencyContactEmail ?? '').isNotEmpty) 'Emergency contact email: ${incident.emergencyContactEmail}',
      if (incident.senderPhone != null && incident.senderPhone!.isNotEmpty) 'Relay / GeoSMS phone: ${incident.senderPhone}',
      if (incident.smsRelayOrOrigin) 'Path: SMS-linked',
      if (incident.geoSmsPatternRecognized) 'GeoSMS: parsed',
    ].join('\n');

    final assessment = [
      'Triage / interview snapshot:\n${_triageBlock()}',
      if (incident.volunteerSceneReport != null && incident.volunteerSceneReport!.isNotEmpty)
        '\nVolunteer scene report (excerpt):\n${_sceneReportExcerpt(incident.volunteerSceneReport!)}',
      '\nAI situation brief (if generated):\n${_briefSummary()}',
    ].join();

    final recommendation = [
      if ((incident.adminDispatchNote ?? '').trim().isNotEmpty) 'Dispatch note: ${incident.adminDispatchNote!.trim()}',
      if ((fleetCallSign ?? '').trim().isNotEmpty) 'Reporting unit (call sign): ${fleetCallSign!.trim()}',
      'Receiving facility / destination: use command center assignment if not shown here.',
    ].join('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.opsTr('EMS → physician handoff'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 6),
        Text(context.opsTr('Structured report (SBAR) for bedside sign-out — copy sections as needed.'), style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.35),
        ),
        const SizedBox(height: 14),
        section('Situation', situation),
        section('Background', background),
        section('Assessment', assessment),
        section('Recommendation / report', recommendation),
      ],
    );
  }
}

class _DriverAllotmentStrip extends StatelessWidget {
  const _DriverAllotmentStrip({required this.role, required this.incident});

  final StationUnitRole role;
  final SosIncident incident;

  @override
  Widget build(BuildContext context) {
    final phase = (incident.emsWorkflowPhase ?? '').trim();
    String title;
    String subtitle;
    Color border;
    Color bg;
    if (role == StationUnitRole.medical && phase.isNotEmpty) {
      if (phase == 'inbound') {
        title = 'En route';
        subtitle = 'Within ~200 m of scene → slide to confirm on scene · then rescue · then return';
        border = const Color(0xFF58A6FF);
        bg = const Color(0xFF58A6FF);
      } else if (phase == 'on_scene') {
        title = 'On scene';
        subtitle = 'Slide rescue complete when ready to return · route opens to accepting hospital';
        border = const Color(0xFF238636);
        bg = const Color(0xFF238636);
      } else if (phase == 'returning') {
        title = 'Returning';
        subtitle = 'Within ~200 m of hospital → slide to complete the EMS run';
        border = const Color(0xFFD29922);
        bg = const Color(0xFFD29922);
      } else if (phase == 'complete') {
        title = 'Response complete';
        subtitle = 'Await next assignment';
        border = const Color(0xFF8B949E);
        bg = const Color(0xFF8B949E);
      } else {
        title = 'EMS · $phase';
        subtitle = 'Allotted run';
        border = const Color(0xFF238636);
        bg = const Color(0xFF238636);
      }
    } else {
      title = 'Allotted';
      subtitle = 'Proceed to scene. Live victim GPS when available.';
      border = const Color(0xFF238636);
      bg = const Color(0xFF238636);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            role == StationUnitRole.medical ? Icons.medical_services_rounded : Icons.construction_rounded,
            color: const Color(0xFF79C0FF),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverVictimUpdatesColumn extends StatelessWidget {
  const _DriverVictimUpdatesColumn({
    required this.incident,
    required this.role,
    required this.triageLine,
    required this.showEmergencyVoice,
    required this.showOperatorVoice,
    required this.onEmergencyLiveKit,
    required this.onOperatorLiveKit,
  });

  final SosIncident incident;
  final StationUnitRole role;
  final String triageLine;
  final bool showEmergencyVoice;
  final bool showOperatorVoice;
  final VoidCallback onEmergencyLiveKit;
  final VoidCallback onOperatorLiveKit;

  @override
  Widget build(BuildContext context) {
    final victim = incident.liveVictimPin;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DriverEtaStatusStrip(incident: incident, role: role),
        const SizedBox(height: 12),
        Text(context.opsTr('Live voice (LiveKit)'), style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        if (showEmergencyVoice)
          Semantics(
            label: 'Join emergency LiveKit bridge with victim and responders',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.campaign_rounded, color: Color(0xFF79C0FF)),
              title: Text(context.opsTr('Emergency channel'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              subtitle: Text(context.opsTr('Same room as victim / on-scene responders'), style: TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: onEmergencyLiveKit,
            ),
          ),
        if (showOperatorVoice)
          Semantics(
            label: 'Join operator channel with hospital and command',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.support_agent_rounded, color: Color(0xFF79C0FF)),
              title: Text(context.opsTr('Operator channel'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              subtitle: Text(context.opsTr('Hospital / command operations net'), style: TextStyle(color: Colors.white54, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: onOperatorLiveKit,
            ),
          ),
        const SizedBox(height: 12),
        SharedSituationBriefCard(
          incidentId: incident.id,
          accentColor: const Color(0xFF79C0FF),
          compact: true,
          showRefreshButton: true,
        ),
        const SizedBox(height: 12),
        Text(context.opsTr('Victim GPS'), style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700)),
        Text(
          'Pin · ${victim.latitude.toStringAsFixed(5)}, ${victim.longitude.toStringAsFixed(5)}',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        if (incident.lastLocationAt != null)
          Text(
            'Last breadcrumb: ${DateFormat('MMM d HH:mm').format(incident.lastLocationAt!.toLocal())}',
            style: const TextStyle(color: Colors.white30, fontSize: 10),
          ),
        const SizedBox(height: 8),
        Text('Triage · $triageLine', style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.35)),
        const SizedBox(height: 12),
        Text(context.opsTr('Live feed (victim / dispatch)'), style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        _VictimActivityList(incidentId: incident.id, shrinkWrap: true),
      ],
    );
  }
}

class _DriverReportCommsColumn extends StatelessWidget {
  const _DriverReportCommsColumn({
    required this.incident,
    required this.fleetCallSign,
    required this.operatorUid,
    required this.footer,
  });

  final SosIncident incident;
  final String? fleetCallSign;
  final String operatorUid;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FleetOperatorHandoffSection(
          incidentId: incident.id,
          operatorUid: operatorUid,
        ),
        _EmsPhysicianHandoffReport(incident: incident, fleetCallSign: fleetCallSign),
        footer,
      ],
    );
  }
}

class _DriverDetailView extends StatelessWidget {
  const _DriverDetailView({
    required this.incident,
    required this.queue,
    required this.role,
    required this.fleetCallSign,
    required this.operatorUid,
    required this.fleetMapZoom,
    required this.onFleetCameraMove,
    required this.onMapCreated,
    required this.routeToVictim,
    required this.routeToHospital,
    required this.volunteerRouteToScene,
    this.unitMapOverride,
    required this.withinVictimRadius,
    required this.withinHospitalRadius,
    this.hospitalAssignment,
    required this.onDirections,
    required this.onEmergencyLiveKit,
    required this.onOperatorLiveKit,
    required this.onStartLive,
    required this.onStopLive,
    required this.isLive,
    required this.onSlideOnSceneConfirm,
    required this.onSlideRescueComplete,
    required this.onSlideResponseComplete,
    required this.onSelectQueuedIncident,
  });

  final SosIncident incident;
  final List<SosIncident> queue;
  final StationUnitRole role;
  final String? fleetCallSign;
  final String operatorUid;
  final double fleetMapZoom;
  final ValueChanged<double> onFleetCameraMove;
  final void Function(OpsMapController) onMapCreated;
  final List<LatLng> routeToVictim;
  final List<LatLng> routeToHospital;
  final List<LatLng> volunteerRouteToScene;
  /// Local GPS when Firestore has not yet received live unit position.
  final LatLng? unitMapOverride;
  final bool withinVictimRadius;
  final bool withinHospitalRadius;
  final OpsIncidentHospitalAssignment? hospitalAssignment;
  final VoidCallback onDirections;
  final VoidCallback onEmergencyLiveKit;
  final VoidCallback onOperatorLiveKit;
  final VoidCallback onStartLive;
  final VoidCallback onStopLive;
  final bool isLive;
  final Future<void> Function() onSlideOnSceneConfirm;
  final Future<void> Function() onSlideRescueComplete;
  final Future<void> Function() onSlideResponseComplete;
  final ValueChanged<String> onSelectQueuedIncident;

  @override
  Widget build(BuildContext context) {
    final phase = (incident.emsWorkflowPhase ?? '').trim();
    LatLng? hospitalLatLng;
    String? hospitalName;
    final lat = incident.returnHospitalLat ?? hospitalAssignment?.acceptedHospitalLat;
    final lng = incident.returnHospitalLng ?? hospitalAssignment?.acceptedHospitalLng;
    if (lat != null && lng != null && phase != 'complete') {
      hospitalLatLng = LatLng(lat, lng);
      hospitalName = hospitalAssignment?.acceptedHospitalName?.trim();
    }

    final layers = _DriverMapLayers.build(
      incident: incident,
      fleetMapZoom: fleetMapZoom,
      routeToVictim: routeToVictim,
      routeToHospital: routeToHospital,
      volunteerRouteToScene: volunteerRouteToScene,
      unitPositionOverride: unitMapOverride,
      hospitalLatLng: hospitalLatLng,
      hospitalName: hospitalName,
    );

    Widget? mapOverlay;
    if (role == StationUnitRole.medical) {
      if (phase == 'inbound' && withinVictimRadius) {
        mapOverlay = SlideToConfirmAction(
          label: 'Slide to confirm on scene →',
          idleBadge: 'ON SCENE',
          accentColor: const Color(0xFF58A6FF),
          onConfirm: onSlideOnSceneConfirm,
        );
      } else if (phase == 'on_scene') {
        mapOverlay = SlideToConfirmAction(
          label: 'Slide to confirm rescue complete → return to hospital',
          idleBadge: 'RESCUE',
          accentColor: const Color(0xFF238636),
          onConfirm: onSlideRescueComplete,
        );
      } else if (phase == 'returning' && withinHospitalRadius) {
        mapOverlay = SlideToConfirmAction(
          label: 'Slide to complete response →',
          idleBadge: 'COMPLETE',
          accentColor: const Color(0xFF58A6FF),
          onConfirm: onSlideResponseComplete,
        );
      }
    }

    final triage = incident.triage;
    final triageLine = triage == null || triage.isEmpty
        ? 'No triage snapshot on file.'
        : '${triage['category'] ?? "—"} · score ${triage['severityScore'] ?? "—"}';

    const pad = EdgeInsets.fromLTRB(12, 0, 12, 24);

    final footer = const Padding(
      padding: EdgeInsets.only(top: 10),
      child: Text(
        'Full dispatch, ETAs to victim UI, and roster control are in the admin command center — this screen is for your run only.',
        style: TextStyle(color: Colors.white30, fontSize: 10, height: 1.4),
      ),
    );

    final mapShare = _DriverMapShareBar(
      onDirections: onDirections,
      onStartLive: onStartLive,
      onStopLive: onStopLive,
      isLive: isLive,
    );

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final showEmergencyVoice = role == StationUnitRole.medical && incident.emsAcceptedBy == uid;
    final showOperatorVoice =
        (role == StationUnitRole.medical && incident.emsAcceptedBy == uid) ||
            (role == StationUnitRole.crane && incident.craneUnitAcceptedBy == uid);

    return DefaultTabController(
      length: 3,
      child: Padding(
        padding: pad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (queue.length > 1) ...[
              _QueuedIncidentPager(
                queue: queue,
                currentId: incident.id,
                onSelect: onSelectQueuedIncident,
              ),
              const SizedBox(height: 8),
            ],
            _DriverAllotmentStrip(role: role, incident: incident),
            const SizedBox(height: 8),
            Material(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(12),
              child: TabBar(
                labelColor: const Color(0xFF79C0FF),
                unselectedLabelColor: Colors.white54,
                indicatorColor: const Color(0xFF58A6FF),
                indicatorSize: TabBarIndicatorSize.tab,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                tabs: [
                  Semantics(
                    label: 'Map, scene and route to the victim',
                    child: const Tab(
                      icon: Icon(Icons.map_rounded, size: 22),
                      text: 'Map',
                      height: 48,
                    ),
                  ),
                  Semantics(
                    label: 'Victim updates, ETAs and live activity',
                    child: const Tab(
                      icon: Icon(Icons.update_rounded, size: 22),
                      text: 'Updates',
                      height: 48,
                    ),
                  ),
                  Semantics(
                    label: 'EMS to physician handoff report',
                    child: const Tab(
                      icon: Icon(Icons.assignment_turned_in_rounded, size: 22),
                      text: 'Handoff',
                      height: 48,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  Semantics(
                    label: 'Scene map with victim location and route',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _DriverMapPanel(
                            layers: layers,
                            onFleetCameraMove: onFleetCameraMove,
                            onMapCreated: onMapCreated,
                            mapBottomOverlay: mapOverlay,
                          ),
                        ),
                        const SizedBox(height: 10),
                        mapShare,
                      ],
                    ),
                  ),
                  ListView(
                    padding: const EdgeInsets.only(top: 10, bottom: 8),
                    children: [
                      _DriverVictimUpdatesColumn(
                        incident: incident,
                        role: role,
                        triageLine: triageLine,
                        showEmergencyVoice: showEmergencyVoice,
                        showOperatorVoice: showOperatorVoice,
                        onEmergencyLiveKit: onEmergencyLiveKit,
                        onOperatorLiveKit: onOperatorLiveKit,
                      ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.only(top: 10, bottom: 8),
                    children: [
                      _DriverReportCommsColumn(
                        incident: incident,
                        fleetCallSign: fleetCallSign,
                        operatorUid: operatorUid,
                        footer: footer,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _sceneReportExcerpt(Map<String, dynamic> r) {
  final s = r.toString();
  if (s.length <= 480) return s;
  return '${s.substring(0, 480)}…';
}
