// Volunteer consignment screen keeps weather/preview scaffolding and helper
// widgets reserved for upcoming situation-brief integrations.
// ignore_for_file: unused_field, unused_element, unused_local_variable

import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/maps/eos_hybrid_map.dart';
import '../../../core/maps/ops_map_controller.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_colors.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/google_maps_illustrative_light_style.dart';
import '../../../core/constants/india_ops_zones.dart';
import '../../../core/utils/fleet_map_icons.dart';
import '../../../core/utils/map_marker_generator.dart';
import '../../../core/utils/map_platform.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../sos/domain/emergency_voice_interview_questions.dart';
import '../../ai_assist/domain/protocol_engine.dart';
import '../../ai_assist/presentation/ai_assist_screen.dart';
import '../../../services/incident_report_service.dart';
import '../../../services/incident_service.dart';
import '../../../services/ops_incident_hospital_assignment_service.dart';
import '../../../services/situation_brief_service.dart';
import 'lifeline_bridge_join_card.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../core/providers/drill_session_provider.dart';
import '../../../core/providers/high_contrast_ops_provider.dart';
import '../../../services/dispatch_chain_service.dart';
import '../../../services/voice_comms_service.dart';
import '../../../features/map/domain/emergency_zone_classification.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/widgets/language_switcher_button.dart';

/// One line in the volunteer drill “live triage log”.
class VolunteerDrillLogLine {
  final String text;
  final DateTime at;
  VolunteerDrillLogLine({required this.text, required this.at});
}

class ActiveConsignmentScreen extends ConsumerStatefulWidget {
  final String incidentId;
  final String incidentType;
  final bool isVictim;
  final bool isDrillMode;

  const ActiveConsignmentScreen({
    super.key,
    this.incidentId = 'active_consignment',
    this.incidentType = 'Active Consignment',
    this.isVictim = false,
    this.isDrillMode = false,
  });

  @override
  ConsumerState<ActiveConsignmentScreen> createState() => _ActiveConsignmentScreenState();
}

class _ActiveConsignmentScreenState extends ConsumerState<ActiveConsignmentScreen>
    with TickerProviderStateMixin {
  // Tab navigation
  late TabController _tabController;

  final Completer<OpsMapController> _controller = Completer<OpsMapController>();
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _volunteerAssignmentSub;
  Timer? _incidentWriteTimer;
  DateTime _lastVolunteerGpsWrite = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastEtaMergeWrite = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastDispatchFeedHospitalSig;
  String? _lastDispatchFeedFleetSig;
  String? _lastDispatchFeedAmbStatusSig;
  static const String _prefLowPowerConsignment = 'consignment_low_power_location_v1';
  bool _lowPowerConsignment = false;

  Duration get _effectiveWriteInterval =>
      _lowPowerConsignment ? const Duration(seconds: 24) : const Duration(seconds: 5);

  LocationAccuracy get _volunteerStreamAccuracy =>
      _lowPowerConsignment ? LocationAccuracy.low : LocationAccuracy.medium;

  int get _volunteerDistanceFilter => _lowPowerConsignment ? 95 : 20;
  bool _lastSceneMembership = false;

  /// Rebuilding GoogleMap every frame (via setState) crashes many Android/iOS devices (platform view).
  DateTime _lastMapUiPaint = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _mapUiMinInterval = const Duration(milliseconds: 180);

  bool _consignmentAnimHooked = false;
  bool? _lastSuppressConsignmentMotion;

  Position? _currentPosition;
  DateTime _lastPositionStreamSetState = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _positionStreamSetStateMinGap = Duration(milliseconds: 700);
  bool _isLoading = true;
  /// True when volunteer is within [_onSceneRadiusM] of the incident pin (approx. on-scene zone).
  bool _isOnScene = false;

  /// Fresh opens (e.g. right after swipe-accept) can see a snapshot before `acceptedVolunteerIds` includes us.
  DateTime? _volunteerAssignmentClearGraceUntil;

  /// One client archives when the 1-hour window passes; avoids repeat work in the listener.
  bool _expiredHandled = false;

  /// Drives pulsing SOS glow rings on the map (live missions only).
  Timer? _sosPulseTimer;

  Timer? _drillVolunteerTimer;
  final List<VolunteerDrillLogLine> _drillVolunteerLog = [];
  String _drillVictimCategory = 'Medical (practice)';
  final List<String> _drillVictimChips = [];
  String _drillVictimNotes = '';
  final Map<String, String> _drillVoiceQa = {};
  int? _drillDemoAmbMin;
  
  double _distanceInMeters = 0;

  /// Straight-line scene pin ↔ dispatch hospital (map routing origin).
  String get _scenePinDistanceFromHospitalLine {
    final m = Geolocator.distanceBetween(
      _hospOrigin.latitude,
      _hospOrigin.longitude,
      _incidentLocation.latitude,
      _incidentLocation.longitude,
    );
    if (m >= 1000) {
      return 'Scene pin ${(m / 1000).toStringAsFixed(1)} km from hospital';
    }
    return 'Scene pin ${m.round()} m from hospital';
  }

  /// On-scene zone radius (2.5 km). Unlocks on-scene checklist and scene report for responders.
  static const double _onSceneRadiusM = 2500;
  /// Inner ring: **arrived at SOS pin** (automated status + feed line).
  static const double _arrivedAtPinRadiusM = 125;
  /// Clear “arrived at pin” feed latch after moving away (hysteresis).
  static const double _arrivedAtPinResetM = 350;

  bool _arrivedAtPin = false;
  bool _postedPinArrivalFeed = false;
  
  // Live Environmental Data
  bool _isWeatherLoading = true;
  String _weatherTemp = '--';
  String _weatherCondition = 'Fetching API...';
  IconData _weatherIcon = Icons.cloud_sync_rounded;
  Color _weatherColor = Colors.white54;
  BitmapDescriptor? _hospitalIcon;
  BitmapDescriptor? _incidentIcon;
  BitmapDescriptor? _userIcon;

  double _consignmentMapZoom = 17.0;

  // Live vehicle bearings (degrees, 0 = North, clockwise)
  double _ambulanceBearing = 0.0;
  double _userCourseDeg = 0.0;
  LatLng? _prevUserGeo;

  late AnimationController _rotationController;
  late AnimationController _trackingController;

  late LatLng _incidentLocation;
  
  // Origins
  late LatLng _hospOrigin;

  /// Reverse-geocoded label near the simulated EMS hospital corridor (map routing).
  String _dispatchHospitalLabel = '';
  int? _simAmbulanceRouteMinutes;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _dispatchAssignmentSub;
  bool _useLiveAmbulanceFromDispatch = false;
  /// Production volunteers: show the ambulance marker only once `sos_incidents` has live
  /// `ambulanceLiveLat`/`Lng` (same bar as ops consoles). Victim and drill keep prior UX.
  bool _incidentHasAmbulanceLivePing = false;

  StreamSubscription? _dispatchChainSub;
  DispatchChainState? _dispatchChainState;

  // ── Static voice-phase guards ───────────────────────────────────────────
  // Static so they survive widget rebuilds and prevent duplicate announcements.
  static String? _lastVolVoiceHospital;
  static String? _lastVolVoicePhase;
  static String? _lastEmsVoicePhase;
  /// Tracks which incident the static guards belong to. When a new incident
  /// opens, the guards are reset so the first announcement plays correctly.
  static String? _activeIncidentIdForVoice;
  /// True once the user has chosen Audio/Silent in the voice mode dialog.
  /// All TTS calls are suppressed until this is true.
  bool _voiceModeReady = false;

  // True GeoJSON Road Paths
  List<LatLng> _hospRoute = [];
  List<LatLng> _evacRoute = [];
  List<LatLng> _volunteerRoute = [];
  
  // Realtime Incident Data
  int _responderCount = 1;

  // Current Live Tracking Positions
  late LatLng _hospCurrent;

  static const String _darkMapStyle = '[{"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},{"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]},{"elementType":"geometry","stylers":[{"color":"#212121"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#212121"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#000000"}]}]';

  Future<LatLng?> _fetchIncidentLocationFromFirestore() async {
    final id = widget.incidentId.trim();
    if (id.isEmpty) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('sos_incidents')
          .doc(id)
          .get()
          .timeout(const Duration(seconds: 4));
      if (!snap.exists || snap.data() == null) return null;
      final d = snap.data()!;
      final lat = (d['lat'] as num?)?.toDouble();
      final lng = (d['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    } catch (e) {
      debugPrint('[Consignment] Incident fetch failed: $e');
      return null;
    }
  }

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 3, vsync: this);

    _rotationController = AnimationController(vsync: this, duration: const Duration(seconds: 15));
    _trackingController = AnimationController(vsync: this, duration: const Duration(seconds: 90));

    WidgetsBinding.instance.addPostFrameCallback((_) => _syncConsignmentMapMotion());

    // Reset static voice guards when opening a new incident so the first
    // announcement always plays correctly for the new consignment.
    if (_activeIncidentIdForVoice != widget.incidentId) {
      _activeIncidentIdForVoice = widget.incidentId;
      _lastVolVoiceHospital = null;
      _lastVolVoicePhase = null;
      _lastEmsVoicePhase = null;
    }

    unawaited(_bootstrapConsignment());

    _dispatchChainSub = DispatchChainService.watchForIncident(widget.incidentId).listen((state) {
      if (!mounted) return;
      _speakVolunteerDispatchUpdate(state);
      setState(() => _dispatchChainState = state);
      unawaited(_maybeAppendDispatchFeedLinesFromChain(state));
    });

    final cid = widget.incidentId.trim();
    if (!widget.isDrillMode) {
      _sosPulseTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
        if (mounted) setState(() {});
      });
    }

    if (cid.isNotEmpty && !widget.isVictim && !widget.isDrillMode) {
      _volunteerAssignmentClearGraceUntil =
          DateTime.now().add(const Duration(seconds: 6));
      unawaited(
        IncidentService.persistVolunteerAssignment(
          incidentId: cid,
          incidentType: widget.incidentType.trim().isEmpty ? 'Emergency' : widget.incidentType.trim(),
        ),
      );
      _volunteerAssignmentSub = FirebaseFirestore.instance
          .collection('sos_incidents')
          .doc(cid)
          .snapshots()
          .listen((snap) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null || uid.isEmpty) return;

        if (!snap.exists || snap.data() == null) {
          // Cache can briefly miss the doc on cold start — verify with server before wiping prefs.
          Future<void>.delayed(const Duration(milliseconds: 1600), () async {
            if (!mounted) return;
            try {
              final r = await FirebaseFirestore.instance
                  .collection('sos_incidents')
                  .doc(cid)
                  .get(const GetOptions(source: Source.server));
              if (!mounted) return;
              if (!r.exists) {
                unawaited(IncidentService.clearVolunteerAssignment());
              }
            } catch (_) {}
          });
          return;
        }
        final d = snap.data()!;
        final st = (d['status'] as String?) ?? '';
        final accepted = List<String>.from(d['acceptedVolunteerIds'] ?? []);

        if (mounted) {
          setState(() {
            _responderCount = accepted.length;
            final alat = (d['ambulanceLiveLat'] as num?)?.toDouble();
            final alng = (d['ambulanceLiveLng'] as num?)?.toDouble();
            final hdg = (d['ambulanceLiveHeadingDeg'] as num?)?.toDouble();
            final hasLivePing = alat != null && alng != null;
            if (!widget.isDrillMode) {
              _incidentHasAmbulanceLivePing = hasLivePing;
            }
            if (hasLivePing && (!widget.isDrillMode || _useLiveAmbulanceFromDispatch)) {
              if (!widget.isDrillMode) {
                _trackingController.stop();
              }
              _hospCurrent = LatLng(alat!, alng!);
              if (hdg != null) _ambulanceBearing = hdg;
            }
          });
        }
        _maybeEmsWorkflowVoice(d);

        final stillOpen = ['pending', 'dispatched', 'blocked'].contains(st);
        final inAccepted = accepted.contains(uid);

        if (!widget.isVictim &&
            !widget.isDrillMode &&
            !_expiredHandled &&
            stillOpen &&
            IncidentService.incidentMapActiveWindowExpired(d)) {
          _expiredHandled = true;
          unawaited(() async {
            await IncidentService.archiveAndCloseIncident(
              incidentId: cid,
              status: 'expired',
              closedByUid: 'system_auto_expire',
            );
            await _exitBecauseIncidentExpired();
          }());
          return;
        }

        // Stale cache right after refresh can omit acceptedVolunteerIds — confirm on server before clearing.
        if (!stillOpen || !inAccepted) {
          final grace = _volunteerAssignmentClearGraceUntil;
          if (grace != null && DateTime.now().isBefore(grace)) {
            return;
          }
          Future<void>.delayed(const Duration(milliseconds: 1200), () async {
            if (!mounted) return;
            try {
              final r = await FirebaseFirestore.instance
                  .collection('sos_incidents')
                  .doc(cid)
                  .get(const GetOptions(source: Source.server));
              if (!mounted) return;
              if (!r.exists || r.data() == null) {
                unawaited(IncidentService.clearVolunteerAssignment());
                return;
              }
              final d2 = r.data()!;
              final st2 = (d2['status'] as String?) ?? '';
              final accepted2 = List<String>.from(d2['acceptedVolunteerIds'] ?? []);
              final still2 = ['pending', 'dispatched', 'blocked'].contains(st2);
              if (!still2 || !accepted2.contains(uid)) {
                unawaited(IncidentService.clearVolunteerAssignment());
              }
            } catch (_) {}
          });
        }
      });
    }
  }

  void _maybeEmsWorkflowVoice(Map<String, dynamic> d) {
    if (widget.isVictim || !_voiceModeReady) return;
    final phase = (d['emsWorkflowPhase'] as String?)?.trim() ?? '';
    if (phase.isEmpty) return;
    if (phase == _lastEmsVoicePhase) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (phase == 'on_scene') {
      _lastEmsVoicePhase = 'on_scene';
      VoiceCommsService.readAloud(l10n.get('voice_ambulance_on_scene_volunteer'));
    } else if (phase == 'returning') {
      _lastEmsVoicePhase = 'returning';
      VoiceCommsService.readAloud(l10n.get('voice_ambulance_returning'));
    } else if (phase == 'complete') {
      _lastEmsVoicePhase = 'complete';
      DateTime? t0;
      final ts = d['timestamp'];
      if (ts is Timestamp) t0 = ts.toDate();
      DateTime? tend;
      final te = d['emsResponseCompleteAt'];
      if (te is Timestamp) tend = te.toDate();
      if (t0 != null && tend != null) {
        final total = tend.difference(t0);
        final m = total.inMinutes;
        final s = total.inSeconds % 60;
        VoiceCommsService.readAloud(
          l10n
              .get('voice_response_complete_cycle')
              .replaceAll('{minutes}', '$m')
              .replaceAll('{seconds}', '$s'),
        );
      } else {
        VoiceCommsService.readAloud(l10n.get('voice_response_complete_station'));
      }
    }
  }

  void _speakVolunteerDispatchUpdate(DispatchChainState state) {
    // Do not speak until user has chosen a voice mode preference.
    if (!_voiceModeReady) return;
    final status = state.status;
    final hospName = state.currentHospitalName;
    final tier = state.currentTier;
    if (status == 'pending_acceptance' && _lastVolVoiceHospital != hospName) {
      _lastVolVoiceHospital = hospName;
      if (tier > 1 && _lastVolVoicePhase != 'tier_$tier') {
        _lastVolVoicePhase = 'tier_$tier';
        final l10n = AppLocalizations.of(context);
        VoiceCommsService.readAloud(
          l10n
              .get('volunteer_dispatch_escalating_tier_trying_hospital')
              .replaceAll('{tier}', '$tier')
              .replaceAll('{hospital}', hospName),
        );
      } else {
        final l10n = AppLocalizations.of(context);
        VoiceCommsService.readAloud(
          l10n.get('volunteer_dispatch_trying_hospital').replaceAll('{hospital}', hospName),
        );
      }
    }
    if (status == 'accepted' && _lastVolVoicePhase != 'accepted') {
      _lastVolVoicePhase = 'accepted';
      final l10n = AppLocalizations.of(context);
      VoiceCommsService.readAloud(
        l10n
            .get('volunteer_dispatch_hospital_accepted')
            .replaceAll('{hospital}', hospName),
      );
    }
    if (status == 'exhausted' && _lastVolVoicePhase != 'exhausted') {
      _lastVolVoicePhase = 'exhausted';
      VoiceCommsService.readAloud(AppLocalizations.of(context).get('volunteer_dispatch_all_hospitals_notified'));
    }
  }

  Future<void> _bootstrapConsignment() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() => _lowPowerConsignment = p.getBool(_prefLowPowerConsignment) ?? false);
      }
    } catch (_) {}
    if (!mounted) return;
    _loadCustomMarkers();
    await _initLocation();
    // Mark voice mode as ready after bootstrap. The overlay always shows the
    // voice mode dialog BEFORE navigating here, so by this point the user
    // has already chosen audio vs silent (or dismissed). We add a small delay
    // to ensure any pending dialog close animation has completed.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) setState(() => _voiceModeReady = true);
  }

  Future<void> _toggleLowPowerConsignment() async {
    if (widget.isDrillMode || widget.isVictim) return;
    final next = !_lowPowerConsignment;
    setState(() => _lowPowerConsignment = next);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_prefLowPowerConsignment, next);
    } catch (_) {}
    await _positionSub?.cancel();
    if (!mounted || widget.isDrillMode) return;
    final streamPerm = await Geolocator.checkPermission();
    if (streamPerm != LocationPermission.whileInUse && streamPerm != LocationPermission.always) return;
    _positionSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: _volunteerStreamAccuracy,
        distanceFilter: _volunteerDistanceFilter,
      ),
    ).listen((Position position) {
      if (!mounted) return;
      final double d = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        _incidentLocation.latitude,
        _incidentLocation.longitude,
      );
      _bumpUserCourseFrom(position);
      _currentPosition = position;
      _scheduleMapUiRepaint();
      _applyGeofenceForDistance(d, isDrillStream: false);
      _writeVolunteerLiveToIncident();
      _syncOnSceneVolunteerMembership(_isOnScene);
    });
  }

  void _syncConsignmentMapMotion() {
    if (!mounted) return;
    final suppress =
        suppressGoogleMapMarkerAnimations(context) && !widget.isDrillMode;
    if (suppress == _lastSuppressConsignmentMotion) return;
    _lastSuppressConsignmentMotion = suppress;

    if (suppress) {
      _rotationController.removeListener(_scheduleMapUiRepaint);
      _trackingController.removeListener(_updateTrackingPositions);
      _rotationController.stop();
      _trackingController.stop();
      _consignmentAnimHooked = false;
      _mapUiMinInterval = const Duration(milliseconds: 500);
    } else {
      _mapUiMinInterval = const Duration(milliseconds: 180);
      if (!_consignmentAnimHooked) {
        _rotationController.addListener(_scheduleMapUiRepaint);
        _trackingController.addListener(_updateTrackingPositions);
        _rotationController.repeat();
        if (_hospRoute.isNotEmpty) _trackingController.forward(from: _trackingController.value);
        _consignmentAnimHooked = true;
      }
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncConsignmentMapMotion());
  }

  void _scheduleMapUiRepaint() {
    final now = DateTime.now();
    if (now.difference(_lastMapUiPaint) < _mapUiMinInterval) return;
    _lastMapUiPaint = now;
    if (mounted) setState(() {});
  }

  void _updateTrackingPositions() {
    if (!widget.isDrillMode && !widget.isVictim && _incidentHasAmbulanceLivePing) {
      return;
    }
    if (_hospRoute.isEmpty) return;

    final double t = _trackingController.value;

    // Compute new positions
    final newHosp = _lerpSegment(_hospRoute, t);

    // Update bearings only when the vehicle has actually moved
    if (_hospCurrent != newHosp) {
      _ambulanceBearing = _bearingBetween(_hospCurrent, newHosp);
    }

    _hospCurrent = newHosp;
    _scheduleMapUiRepaint();
  }

  /// Returns the compass bearing (0–360°, clockwise from North) from [a] → [b].
  double _bearingBetween(LatLng a, LatLng b) {
    final lat1 = a.latitude  * (math.pi / 180);
    final lat2 = b.latitude  * (math.pi / 180);
    final dLng = (b.longitude - a.longitude) * (math.pi / 180);
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
              math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final bearing = math.atan2(y, x) * (180 / math.pi);
    return (bearing + 360) % 360;
  }

  void _bumpUserCourseFrom(Position p) {
    final prev = _prevUserGeo;
    final h = p.heading;
    if (h >= 0 &&
        h <= 360 &&
        (p.speed > 0.4 || (p.headingAccuracy >= 0 && p.headingAccuracy < 55))) {
      _userCourseDeg = h;
    } else if (prev != null) {
      final d = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        p.latitude,
        p.longitude,
      );
      if (d >= 6) {
        _userCourseDeg = Geolocator.bearingBetween(
          prev.latitude,
          prev.longitude,
          p.latitude,
          p.longitude,
        );
      }
    }
    _prevUserGeo = LatLng(p.latitude, p.longitude);
  }

  // Smoothly interpolates along the segmented GeoJSON road polyline array
  LatLng _lerpSegment(List<LatLng> route, double t) {
    if (route.isEmpty) return const LatLng(0,0);
    if (route.length == 1 || t <= 0.0) return route.first;
    if (t >= 1.0) return route.last;

    double exactIndex = t * (route.length - 1);
    int lowerIdx = exactIndex.floor();
    int upperIdx = exactIndex.ceil();
    if (lowerIdx == upperIdx) return route[lowerIdx];

    double fraction = exactIndex - lowerIdx;
    LatLng a = route[lowerIdx];
    LatLng b = route[upperIdx];
    
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * fraction,
      a.longitude + (b.longitude - a.longitude) * fraction,
    );
  }

  List<LatLng> _fallbackPolyline(LatLng start, LatLng end) => [
        start,
        LatLng(
          start.latitude + (end.latitude - start.latitude) / 2,
          start.longitude + (end.longitude - start.longitude) / 2,
        ),
        end,
      ];

  Future<List<LatLng>> _ensureRoadRoute(LatLng start, LatLng end) async {
    final r = await _getRoadRoute(start, end);
    return r.length >= 2 ? r : _fallbackPolyline(start, end);
  }

  // Fetches true road routing from the free Open Source Routing Machine
  Future<List<LatLng>> _getRoadRoute(LatLng start, LatLng end) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 18));
      if (res.statusCode != 200) return _fallbackPolyline(start, end);

      final dynamic data = json.decode(res.body);
      if (data is! Map<String, dynamic>) return _fallbackPolyline(start, end);
      final routes = data['routes'];
      if (routes is! List || routes.isEmpty) return _fallbackPolyline(start, end);

      final geometry = routes[0]['geometry'];
      if (geometry is! Map<String, dynamic>) return _fallbackPolyline(start, end);
      final coords = geometry['coordinates'];
      if (coords is! List || coords.isEmpty) return _fallbackPolyline(start, end);

      final out = <LatLng>[];
      for (final c in coords) {
        if (c is List && c.length >= 2) {
          final lon = (c[0] as num).toDouble();
          final lat = (c[1] as num).toDouble();
          out.add(LatLng(lat, lon));
        }
      }
      return out.isEmpty ? _fallbackPolyline(start, end) : out;
    } catch (e) {
      debugPrint('OSRM Route Failed: $e');
      return _fallbackPolyline(start, end);
    }
  }

  int? _estimateEtaMinutesFromRoute(List<LatLng> route) {
    if (route.length < 2) return null;
    double meters = 0.0;
    for (var i = 1; i < route.length; i++) {
      meters += Geolocator.distanceBetween(
        route[i - 1].latitude,
        route[i - 1].longitude,
        route[i].latitude,
        route[i].longitude,
      );
    }
    // Conservative city response speed.
    const double kph = 28.0;
    final minutes = (meters / 1000.0) / kph * 60.0;
    if (!minutes.isFinite) return null;
    return minutes.clamp(1, 180).round();
  }

  Future<void> _writeEtasToIncident() async {
    if (widget.isDrillMode) return;
    final id = widget.incidentId.trim();
    if (id.isEmpty) return;
    final now = DateTime.now();
    if (now.difference(_lastEtaMergeWrite) < _effectiveWriteInterval) return;

    final ambSt = (_dispatchChainState?.assignment?.ambulanceDispatchStatus ?? '').trim();
    final enRoute = _useLiveAmbulanceFromDispatch || ambSt == 'ambulance_en_route';

    final ambMin = _estimateEtaMinutesFromRoute(_hospRoute);
    final status = _isOnScene ? 'Volunteer on scene' : 'Volunteer en route';

    final payload = <String, dynamic>{
      'medicalStatus': status,
      'etaUpdatedAt': FieldValue.serverTimestamp(),
    };

    if (ambMin != null) {
      payload['emsCorridorEtaMin'] = ambMin;
    }

    if (enRoute) {
      final etaStr = ambMin != null
          ? '${ambMin} min'
          : (_simAmbulanceRouteMinutes != null ? '${_simAmbulanceRouteMinutes} min' : null);
      if (etaStr != null) {
        payload['ambulanceEta'] = etaStr;
      }
    }

    _lastEtaMergeWrite = now;

    try {
      await FirebaseFirestore.instance.collection('sos_incidents').doc(id).set(
            payload,
            SetOptions(merge: true),
          );
    } catch (e) {
      debugPrint('[Consignment] ETA write failed: $e');
    }
  }

  Future<void> _loadDispatchHospitalLabel() async {
    try {
      final list = await placemarkFromCoordinates(_hospOrigin.latitude, _hospOrigin.longitude);
      if (!mounted || list.isEmpty) return;
      final p = list.first;
      final parts = <String>{
        if ((p.name ?? '').trim().isNotEmpty) p.name!.trim(),
        if ((p.thoroughfare ?? '').trim().isNotEmpty) p.thoroughfare!.trim(),
        if ((p.locality ?? '').trim().isNotEmpty) p.locality!.trim(),
        if ((p.subAdministrativeArea ?? '').trim().isNotEmpty) p.subAdministrativeArea!.trim(),
      }.toList();
      final label = parts.take(4).join(', ');
      if (mounted) {
        setState(() {
          _dispatchHospitalLabel = label.isEmpty ? 'EMS routing corridor (see map)' : label;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _dispatchHospitalLabel = 'Hospital / EMS routing (see map)');
      }
    }
  }

  void _startDispatchAssignmentListener() {
    if (widget.isDrillMode) return;
    final cid = widget.incidentId.trim();
    if (cid.isEmpty) return;
    _dispatchAssignmentSub?.cancel();
    _dispatchAssignmentSub = FirebaseFirestore.instance
        .collection('ops_incident_hospital_assignments')
        .doc(cid)
        .snapshots()
        .listen((snap) => unawaited(_onHospitalAssignmentDispatchUpdate(snap)));
  }

  Future<void> _onHospitalAssignmentDispatchUpdate(DocumentSnapshot<Map<String, dynamic>> snap) async {
    if (!snap.exists || !mounted) return;
    final a = OpsIncidentHospitalAssignment.fromFirestore(snap);
    final ambSt = (a.ambulanceDispatchStatus ?? '').trim();
    if (ambSt == 'ambulance_en_route') {
      if (mounted) {
        setState(() => _useLiveAmbulanceFromDispatch = true);
        _trackingController.stop();
      }
    }
    final hid = (a.acceptedHospitalId ?? '').trim();
    if (hid.isEmpty) return;
    try {
      final hs = await FirebaseFirestore.instance.collection('ops_hospitals').doc(hid).get();
      final h = hs.data();
      if (h == null || !mounted) return;
      final plat = (h['lat'] as num?)?.toDouble();
      final plng = (h['lng'] as num?)?.toDouble();
      if (plat == null || plng == null) return;
      final origin = LatLng(plat, plng);
      final name = (h['name'] as String?)?.trim();
      if (!mounted) return;
      setState(() {
        _hospOrigin = origin;
        if (name != null && name.isNotEmpty) {
          _dispatchHospitalLabel = name;
        }
      });
      final route = await _ensureRoadRoute(origin, _incidentLocation);
      if (!mounted) return;
      final evac = await _ensureRoadRoute(_incidentLocation, origin);
      if (!mounted) return;
      setState(() {
        _hospRoute = route;
        _evacRoute = evac;
        _hospCurrent = origin;
        _simAmbulanceRouteMinutes = _estimateEtaMinutesFromRoute(route);
      });
      if (!_useLiveAmbulanceFromDispatch && mounted) {
        _trackingController.forward(from: 0);
      }
      unawaited(_loadDispatchHospitalLabel());
    } catch (e) {
      debugPrint('[Consignment] dispatch chain hospital: $e');
    }
  }

  Future<void> _fetchVolunteerRoute() async {
    if (!mounted) return;
    setState(() => _volunteerRoute = []);
  }

  Future<void> _runVolunteerDrillEntry() async {
    if (!widget.isDrillMode || !mounted) return;
    _startVolunteerDrillSimulation();
  }

  void _appendDrillLog(String text) {
    if (!mounted) return;
    setState(() {
      _drillVolunteerLog.insert(0, VolunteerDrillLogLine(text: text, at: DateTime.now()));
      if (_drillVolunteerLog.length > 40) {
        _drillVolunteerLog.removeLast();
      }
    });
  }

  void _startVolunteerDrillSimulation() {
    if (!widget.isDrillMode) return;
    _drillVolunteerTimer?.cancel();
    var step = 0;
    _drillVolunteerTimer = Timer.periodic(const Duration(milliseconds: 2100), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      step++;
      switch (step) {
        case 1:
          setState(() {
            _drillVictimCategory = 'Medical — breathing difficulty (practice)';
            _drillVictimChips.addAll(['Conscious', 'Breathing trouble', 'Chest tightness']);
            _drillVictimNotes =
                'Victim reports tight chest, cannot finish sentences; seated, sweating — demo vitals stable.';
            _drillVoiceQa['conscious'] = 'Yes';
            _drillVoiceQa['breathing'] = 'Worse when walking';
            _drillVoiceQa['allergies'] = 'NKDA (practice)';
          });
          _appendDrillLog('Victim app (practice): Awake, answering short phrases.');
          break;
        case 2:
          setState(() {
            _responderCount = 3;
            _drillDemoAmbMin = _simAmbulanceRouteMinutes != null
                ? (_simAmbulanceRouteMinutes! + 1).clamp(4, 24)
                : 10;
          });
          _appendDrillLog('Dispatch (practice): ALS unit ALS-12 assigned — red route animating on MAP.');
          break;
        case 3:
          _appendDrillLog('Dispatch (practice): Ops cleared corridor — routes toward the incident.');
          break;
        case 4:
          _appendDrillLog('Mutual-aid EMS (practice): Secondary unit rolling — backup corridor on MAP.');
          break;
        case 5:
          setState(() {
            _responderCount = 5;
            if (_drillDemoAmbMin != null) _drillDemoAmbMin = (_drillDemoAmbMin! - 1).clamp(2, 30);
            _drillVoiceQa['severeBleeding'] = 'No';
            _drillVoiceQa['safeLocation'] = 'Yes — roadside verge, away from traffic';
          });
          _appendDrillLog('Victim (practice): “Not bleeding heavily” — triage chips updated.');
          break;
        case 6:
          _appendDrillLog('MAP (practice): Your green route shortening — ETA to pin improving each tick.');
          break;
        case 7:
          _appendDrillLog('PTT (simulated): “ALS-12, you have corridor” — echo in triage log.');
          break;
        case 8:
          setState(() {
            _drillDemoAmbMin = ((_drillDemoAmbMin ?? 7) - 2).clamp(2, 30);
          });
          _appendDrillLog('EMS (practice): Bystander crowd pushed back — scene status updates on MAP markers.');
          break;
        case 9:
          setState(() {
            _drillVictimNotes =
                'Victim calmer with rest; still prefers not to walk; pulse ox simulated 96%.';
            _drillVoiceQa['breathing'] = 'Easier sitting forward';
            _drillVictimChips.add('SpO2 96% (demo)');
          });
          _appendDrillLog('Lifeline bridge (practice): Mock vitals line appended for desk review.');
          break;
        case 10:
          setState(() {
            _responderCount = 7;
          });
          _appendDrillLog('Mutual aid (practice): +2 volunteers from adjacent grid — responder count jumps.');
          break;
        case 11:
          _appendDrillLog('Hospital (practice): Trauma bay notified — receiving team standby (demo text).');
          break;
        case 12:
          setState(() {
            _drillDemoAmbMin = 4;
          });
          _appendDrillLog('Scene control (practice): Traffic held short of pin — clearance for ALS sweep.');
          break;
        case 13:
          _appendDrillLog('ON-SCENE tab (practice): Checklist unlocks when you enter 2.5 km zone — try moving map.');
          break;
        case 14:
          setState(() {
            _drillDemoAmbMin = 2;
            _responderCount = 8;
          });
          _appendDrillLog('EMS (practice): ALS visible — lights in corridor; handover prep message.');
          break;
        case 15:
          _appendDrillLog('Victim (practice): “Hearing siren, feeling a bit safer” — morale note for responders.');
          break;
        case 16:
          setState(() {
            _drillDemoAmbMin = 1;
          });
          _appendDrillLog('Handover (practice): Crew at your marker — drill timeline complete. Exit anytime.');
          t.cancel();
          break;
        default:
          t.cancel();
      }
    });
  }

  @override
  void dispose() {
    if (widget.isDrillMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => clearDrillSessionDashboardDemoFromRoot());
    }
    _drillVolunteerTimer?.cancel();
    _sosPulseTimer?.cancel();
    _syncOnSceneVolunteerMembership(false);
    _incidentWriteTimer?.cancel();
    _positionSub?.cancel();
    _volunteerAssignmentSub?.cancel();
    _dispatchAssignmentSub?.cancel();
    _dispatchChainSub?.cancel();
    _rotationController.removeListener(_scheduleMapUiRepaint);
    _trackingController.removeListener(_updateTrackingPositions);
    _tabController.dispose();
    _rotationController.dispose();
    _trackingController.dispose();
    super.dispose();
  }

  Future<void> _writeVolunteerLiveToIncident() async {
    if (widget.isDrillMode || _currentPosition == null) return;
    final id = widget.incidentId.trim();
    if (id.isEmpty) return;

    final now = DateTime.now();
    if (now.difference(_lastVolunteerGpsWrite) < _effectiveWriteInterval) return;
    _lastVolunteerGpsWrite = now;

    try {
      await FirebaseFirestore.instance.collection('sos_incidents').doc(id).set(
        {
          'volunteerLat': _currentPosition!.latitude,
          'volunteerLng': _currentPosition!.longitude,
          'volunteerUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[Consignment] volunteer live write failed: $e');
    }
  }

  Future<void> _maybeAppendDispatchFeedLinesFromChain(DispatchChainState state) async {
    if (widget.isDrillMode) return;
    final id = widget.incidentId.trim();
    if (id.isEmpty) return;
    final a = state.assignment;
    if (a == null) return;

    final hid = (a.acceptedHospitalId ?? '').trim();
    if (hid.isNotEmpty && state.isAccepted) {
      final sig = 'acc|$hid';
      if (_lastDispatchFeedHospitalSig != sig) {
        _lastDispatchFeedHospitalSig = sig;
        final name = (a.acceptedHospitalName ?? a.primaryHospitalName ?? state.currentHospitalName).trim();
        await IncidentService.appendIncidentFeedLine(
          incidentId: id,
          text: 'Hospital accepted: ${name.isEmpty ? hid : name}',
          source: 'dispatch',
        );
      }
    }

    final cs = (a.assignedFleetCallSign ?? '').trim();
    if (cs.isNotEmpty) {
      final sig = 'fleet|$cs';
      if (_lastDispatchFeedFleetSig != sig) {
        _lastDispatchFeedFleetSig = sig;
        await IncidentService.appendIncidentFeedLine(
          incidentId: id,
          text: 'Ambulance unit assigned: $cs',
          source: 'dispatch',
        );
      }
    }

    final ambSt = (a.ambulanceDispatchStatus ?? '').trim();
    if (ambSt == 'ambulance_en_route' && _lastDispatchFeedAmbStatusSig != ambSt) {
      _lastDispatchFeedAmbStatusSig = ambSt;
      await IncidentService.appendIncidentFeedLine(
        incidentId: id,
        text: 'Ambulance en route',
        source: 'dispatch',
      );
    }
  }

  Future<void> _syncOnSceneVolunteerMembership(bool onScene) async {
    if (widget.isDrillMode) return;
    final id = widget.incidentId.trim();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (id.isEmpty || uid.isEmpty) return;
    if (_lastSceneMembership == onScene) return;
    _lastSceneMembership = onScene;
    try {
      await FirebaseFirestore.instance.collection('sos_incidents').doc(id).set(
        {
          'onSceneVolunteerIds': onScene
              ? FieldValue.arrayUnion([uid])
              : FieldValue.arrayRemove([uid]),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('[Consignment] scene membership update failed: $e');
    }
  }

  Future<void> _loadCustomMarkers() async {
    const subtleHospital = Color(0xFF26C6DA);
    await FleetMapIcons.preload();
    _hospitalIcon = await MapMarkerGenerator.getMinimalPin(Icons.local_hospital_rounded, subtleHospital);
    _incidentIcon = await MapMarkerGenerator.getMinimalPin(
      Icons.warning_rounded,
      AppColors.primaryDanger,
      withActiveSosGlow: !widget.isDrillMode,
    );
    _userIcon = await MapMarkerGenerator.getMinimalPin(Icons.navigation_rounded, AppColors.primaryInfo);

    if (mounted) setState(() {});
  }

  Future<void> _initLocation() async {
    if (widget.isDrillMode) {
      try {
        await _initLocationAfterPermission(
          allowMissingUserLocation: true,
          startPositionStream: true,
          isDrillSetup: true,
        );
      } catch (e, st) {
        debugPrint('Drill consignment map init failed: $e\n$st');
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.unableToDetermine) {
      permission = await Geolocator.requestPermission();
    }

    final blocked = permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever;

    // Web: blocked GPS still allows incident map + routing sim; native keeps strict gate.
    if (blocked && kIsWeb) {
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.volunteerActiveBrowserLocationOff),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      try {
        await _initLocationAfterPermission(
          allowMissingUserLocation: true,
          startPositionStream: false,
          skipGpsFetch: true,
        );
      } catch (e, st) {
        debugPrint('Consignment map init failed: $e\n$st');
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
      return;
    }

    if (blocked) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).volunteerActiveLocationRequired)),
        );
        context.pop();
      }
      return;
    }

    try {
      await _initLocationAfterPermission(
        allowMissingUserLocation: false,
        startPositionStream: true,
      );
    } catch (e, st) {
      debugPrint('Consignment map init failed: $e\n$st');
      if (mounted) {
        setState(() => _isLoading = false);
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.volunteerActiveMapLoadFailed(kDebugMode ? e.toString() : 'Please try again.'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _initLocationAfterPermission({
    required bool allowMissingUserLocation,
    required bool startPositionStream,
    bool isDrillSetup = false,
    bool skipGpsFetch = false,
  }) async {
    if (!skipGpsFetch) {
      try {
        _currentPosition = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: isDrillSetup ? LocationAccuracy.medium : _volunteerStreamAccuracy,
            timeLimit: Duration(seconds: kIsWeb ? 18 : 25),
          ),
        );
        if (_currentPosition != null) _bumpUserCourseFrom(_currentPosition!);
      } catch (e) {
        debugPrint('getCurrentPosition failed: $e');
        _currentPosition = await Geolocator.getLastKnownPosition();
        if (_currentPosition != null) _bumpUserCourseFrom(_currentPosition!);
      }
    }

    if (isDrillSetup) {
      final lat = _currentPosition?.latitude ?? 26.8467;
      final lng = _currentPosition?.longitude ?? 80.9462;
      _incidentLocation = LatLng(lat + 0.012, lng + 0.01);
      _currentPosition ??= Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
        accuracy: 25,
        altitude: 0,
        heading: 0,
        speed: 0,
        speedAccuracy: 0,
        altitudeAccuracy: 0,
        headingAccuracy: 0,
      );
      _hospOrigin = LatLng(_incidentLocation.latitude - 0.006, _incidentLocation.longitude - 0.004);
      _hospCurrent = _hospOrigin;
      _hospRoute = await _ensureRoadRoute(_hospOrigin, _incidentLocation);
      _evacRoute = await _ensureRoadRoute(_incidentLocation, _hospOrigin);
      await _fetchVolunteerRoute();
      final ambEst = _estimateEtaMinutesFromRoute(_hospRoute);
      if (mounted) {
        setState(() {
          _updateDistanceFieldsOnly();
          if (_distanceInMeters <= _onSceneRadiusM) _isOnScene = true;
          if (_distanceInMeters <= _arrivedAtPinRadiusM) _arrivedAtPin = true;
          _isLoading = false;
          _simAmbulanceRouteMinutes = ambEst;
        });
      }
      unawaited(_loadDispatchHospitalLabel());
      _trackingController.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncConsignmentMapMotion();
      });
      _fetchLiveWeatherData();
      try {
        final OpsMapController controller = await _controller.future.timeout(
          const Duration(seconds: 12),
        );
        if (!mounted) return;
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _incidentLocation, zoom: 13.8),
          ),
        );
      } catch (e) {
        debugPrint('Drill map camera: $e');
      }
      await _positionSub?.cancel();
      final streamPerm = await Geolocator.checkPermission();
      if (startPositionStream &&
          (streamPerm == LocationPermission.whileInUse || streamPerm == LocationPermission.always)) {
        _positionSub = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 22,
          ),
        ).listen((Position position) {
          if (!mounted) return;
          _bumpUserCourseFrom(position);
          _currentPosition = position;
          _scheduleMapUiRepaint();
          final double d = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            _incidentLocation.latitude,
            _incidentLocation.longitude,
          );
          _applyGeofenceForDistance(d, isDrillStream: true);
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_runVolunteerDrillEntry());
      });
      return;
    }

    final fromFs = await _fetchIncidentLocationFromFirestore();
    if (fromFs == null) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).volunteerActiveNoMapCoords)),
        );
        context.pop();
      }
      return;
    }
    _incidentLocation = fromFs;

    if (_currentPosition == null && !allowMissingUserLocation) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).volunteerActiveGpsUnavailable)),
        );
        context.pop();
      }
      return;
    }
    
    // Dispatch hubs ~700m away to produce realistic 30km/h visual speed over 90 seconds
    // Anchor these around the incident so the simulation stays consistent.
    _hospOrigin = LatLng(_incidentLocation.latitude - 0.006, _incidentLocation.longitude - 0.004);

    _hospCurrent = _hospOrigin;

    // Await True Road Computations from OSRM
    _hospRoute = await _ensureRoadRoute(_hospOrigin, _incidentLocation);
    _evacRoute = await _ensureRoadRoute(_incidentLocation, _hospOrigin); // Evac backwards to hospital

    await _fetchVolunteerRoute();

    final ambEst = _estimateEtaMinutesFromRoute(_hospRoute);

    if (mounted) {
      setState(() {
        _updateDistanceFieldsOnly();
        if (_distanceInMeters <= _onSceneRadiusM) _isOnScene = true;
        if (_distanceInMeters <= _arrivedAtPinRadiusM) _arrivedAtPin = true;
        _isLoading = false;
        _simAmbulanceRouteMinutes = ambEst;
      });
    }

    unawaited(_loadDispatchHospitalLabel());

    // Start playback sequence now that routes are loaded
    _trackingController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncConsignmentMapMotion();
    });

    // Fetch Live Weather for Crash Site
    _fetchLiveWeatherData();
    // Start Live Tracking stream and camera centering

    // Write initial ETAs once routes exist.
    if (!widget.isDrillMode) {
      await _writeEtasToIncident();
      _startDispatchAssignmentListener();
    }

    // Initialize map camera: Zoom to show both volunteer and victim
    try {
      final OpsMapController controller = await _controller.future.timeout(
        const Duration(seconds: 12),
      );
      if (!mounted) return;

      if (_currentPosition != null && !widget.isVictim) {
        final volunteerLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
        LatLngBounds bounds;
        if (volunteerLocation.latitude > _incidentLocation.latitude) {
          bounds = LatLngBounds(
            southwest: LatLng(
                _incidentLocation.latitude,
                volunteerLocation.longitude > _incidentLocation.longitude
                    ? _incidentLocation.longitude
                    : volunteerLocation.longitude),
            northeast: LatLng(
                volunteerLocation.latitude,
                volunteerLocation.longitude > _incidentLocation.longitude
                    ? volunteerLocation.longitude
                    : _incidentLocation.longitude),
          );
        } else {
          bounds = LatLngBounds(
            southwest: LatLng(
                volunteerLocation.latitude,
                volunteerLocation.longitude > _incidentLocation.longitude
                    ? _incidentLocation.longitude
                    : volunteerLocation.longitude),
            northeast: LatLng(
                _incidentLocation.latitude,
                volunteerLocation.longitude > _incidentLocation.longitude
                    ? volunteerLocation.longitude
                    : _incidentLocation.longitude),
          );
        }
        await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
      } else {
        await controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: _incidentLocation, zoom: 15.5),
          ),
        );
      }
    } catch (e) {
      debugPrint('Map camera init skipped: $e');
    }

    // 3. Live position stream (throttled setState — rapid GPS jitter was rebuilding the whole map).
    await _positionSub?.cancel();
    final streamPerm = await Geolocator.checkPermission();
    if (startPositionStream &&
        (streamPerm == LocationPermission.whileInUse || streamPerm == LocationPermission.always)) {
      _positionSub = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: _volunteerStreamAccuracy,
          distanceFilter: _volunteerDistanceFilter,
        ),
      ).listen((Position position) {
        if (!mounted) return;
        final double d = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          _incidentLocation.latitude,
          _incidentLocation.longitude,
        );
        _bumpUserCourseFrom(position);
        _currentPosition = position;
        _scheduleMapUiRepaint();
        _applyGeofenceForDistance(d, isDrillStream: false);
        _writeVolunteerLiveToIncident();
        _syncOnSceneVolunteerMembership(_isOnScene);
      });
    }

    // Periodic ETA refresh (lightweight, throttled).
    _incidentWriteTimer?.cancel();
    if (!widget.isDrillMode) {
      _incidentWriteTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (!mounted) return;
        _writeEtasToIncident();
      });
    }
  }

  /// Updates distance meters only; call from inside an existing setState when needed.
  void _updateDistanceFieldsOnly() {
    if (_currentPosition == null) return;
    _distanceInMeters = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _incidentLocation.latitude,
      _incidentLocation.longitude,
    );
  }

  void _applyGeofenceForDistance(double d, {required bool isDrillStream}) {
    if (d > _arrivedAtPinResetM) {
      _postedPinArrivalFeed = false;
    }

    final bool wasOnScene = _isOnScene;
    final bool onScene = d <= _onSceneRadiusM;
    final bool wasAtPin = _arrivedAtPin;
    final bool atPin = d <= _arrivedAtPinRadiusM;

    _distanceInMeters = d;
    _isOnScene = onScene;
    _arrivedAtPin = atPin;

    final onSceneChanged = wasOnScene != onScene;
    final now = DateTime.now();
    final throttleOk =
        now.difference(_lastPositionStreamSetState) >= _positionStreamSetStateMinGap;

    if (onSceneChanged || throttleOk) {
      _lastPositionStreamSetState = now;
      setState(() {});
    }

    if (!wasOnScene && onScene && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tabController.animateTo(2);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isDrillStream
                  ? 'Within 2.5 km of practice pin — on-scene tools unlocked.'
                  : 'Within 2.5 km of incident — on-scene tools unlocked.',
            ),
            backgroundColor: AppColors.primaryDanger,
            duration: const Duration(seconds: 4),
          ),
        );
      });
    }

    if (!wasAtPin && atPin && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isDrillStream
                  ? 'Practice: within ${_arrivedAtPinRadiusM.round()} m of pin — arrived on scene.'
                  : 'Within ${_arrivedAtPinRadiusM.round()} m of SOS pin — arrived on scene (automated).',
            ),
            backgroundColor: AppColors.primarySafe,
            duration: const Duration(seconds: 5),
          ),
        );
        if (!isDrillStream && !widget.isDrillMode) {
          unawaited(_postAutomatedPinArrivalOnce());
        }
      });
    }
  }

  Future<void> _postAutomatedPinArrivalOnce() async {
    if (_postedPinArrivalFeed) return;
    final id = widget.incidentId.trim();
    if (id.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';
    if (uid.isEmpty) return;
    _postedPinArrivalFeed = true;
    final label = user?.displayName?.trim();
    final who = (label != null && label.isNotEmpty) ? label : 'Responder';
    await IncidentService.appendIncidentFeedLine(
      incidentId: id,
      text: '$who: Arrived at scene pin (automated geofence)',
      source: 'volunteer_geofence',
    );
  }

  Future<void> _fetchLiveWeatherData() async {
    try {
      final url = Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=${_incidentLocation.latitude}&longitude=${_incidentLocation.longitude}&current_weather=true');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current_weather'];
        if (current is! Map<String, dynamic>) return;
        final temp = current['temperature'] ?? '--';
        final wind = (current['windspeed'] as num?)?.toDouble() ?? 0.0;
        final code = (current['weathercode'] as num?)?.toInt() ?? 0;
        
        String condition = 'Clear';
        IconData icon = Icons.wb_sunny_rounded;
        Color color = Colors.orangeAccent;
        
        if (code >= 1 && code <= 3) { condition = 'Cloudy'; icon = Icons.cloud_rounded; color = Colors.grey.shade400; }
        else if (code >= 51 && code <= 67) { condition = 'Rain ($wind km/h wind)'; icon = Icons.water_drop_rounded; color = Colors.lightBlueAccent; }
        else if (code >= 71) { condition = 'Snow/Hazard'; icon = Icons.ac_unit_rounded; color = Colors.white; }
        else if (wind > 30) { condition = 'High Winds ($wind km/h)'; icon = Icons.air_rounded; color = Colors.tealAccent; }
        
        if (mounted) {
          setState(() {
            _weatherTemp = '${temp.toString()}°C';
            _weatherCondition = condition;
            _weatherIcon = icon;
            _weatherColor = color;
            _isWeatherLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() { _weatherCondition = 'Weather API Error'; _isWeatherLoading = false; });
    }
  }

  void _showOfflineQr() {
    final payload = jsonEncode({
      'incidentId': widget.incidentId,
      'incidentType': widget.incidentType,
      'incidentLat': _incidentLocation.latitude,
      'incidentLng': _incidentLocation.longitude,
      'generatedAt': DateTime.now().toIso8601String(),
    });
    showDialog(
      context: context,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(l10n.volunteerActiveOfflineQrTitle,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 10),
              Text(
                l10n.volunteerActiveOfflineQrBody,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.volunteerActiveClose, style: const TextStyle(color: Colors.white70)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmergencyServicesStatus() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10)],
        border: Border.all(color: AppColors.surfaceHighlight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.volunteerActiveDispatchedServices,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildServiceBadge(
                Icons.medical_services_rounded,
                l10n.volunteerActiveAmbulance,
                _trackingController.value >= 0.98 ? l10n.volunteerActiveOnScene : l10n.volunteerActiveEnRoute,
                AppColors.primaryDanger,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildServiceBadge(IconData icon, String label, String status, Color statusColor) {
    return Expanded(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: statusColor, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                Text(status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmExitDialog() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            l10n.volunteerActiveExitTitle,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: Text(
            widget.isVictim ? l10n.volunteerActiveLeaveVictim : l10n.volunteerActiveLeaveVolunteer,
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.volunteerActiveStay, style: const TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryDanger),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.volunteerActiveExit, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  void _openLifelineFirstAid() {
    final iid = widget.incidentId.trim();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) => Stack(
          fit: StackFit.expand,
          children: [
            AIAssistScreen(
              mode: 'volunteer',
              incidentId: iid.isEmpty ? null : iid,
              isDrillShell: widget.isDrillMode,
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, right: 4),
                  child: Material(
                    color: Colors.black45,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: AppLocalizations.of(ctx).volunteerActiveBackToResponse,
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exitBecauseIncidentExpired() async {
    await _volunteerAssignmentSub?.cancel();
    _volunteerAssignmentSub = null;
    await IncidentService.clearVolunteerAssignment();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).volunteerActiveSosExpired),
        backgroundColor: AppColors.surfaceHighlight,
      ),
    );
    context.go('/dashboard');
  }

  Set<Circle> _buildConsignmentMapCircles() {
    final c = _incidentLocation;
    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final pulse = 0.5 + 0.5 * math.sin(t * 3.0);
    final pulseSoft = 0.5 + 0.5 * math.sin(t * 2.2 + 0.9);
    final dc = _dispatchChainState;
    return {
      Circle(
        circleId: const CircleId('incident_danger_zone'),
        center: c,
        radius: 120,
        fillColor: AppColors.primaryDanger.withValues(alpha: 0.15),
        strokeColor: AppColors.primaryDanger,
        strokeWidth: 2,
        zIndex: 80,
      ),
      Circle(
        circleId: const CircleId('dispatch_tier1'),
        center: c,
        radius: kDispatchTier1RadiusM,
        fillColor: Colors.redAccent.withValues(alpha: (dc?.currentTier == 1) ? 0.08 : 0.02),
        strokeColor: Colors.redAccent.withValues(alpha: 0.5),
        strokeWidth: 2,
        zIndex: 60,
      ),
      Circle(
        circleId: const CircleId('dispatch_tier2'),
        center: c,
        radius: kDispatchTier2RadiusM,
        fillColor: Colors.amber.withValues(alpha: (dc != null && dc.currentTier >= 2) ? 0.06 : 0.02),
        strokeColor: Colors.amber.withValues(alpha: 0.4),
        strokeWidth: 2,
        zIndex: 60,
      ),
      Circle(
        circleId: const CircleId('dispatch_tier3'),
        center: c,
        radius: kDispatchTier3RadiusM,
        fillColor: Colors.blueGrey.withValues(alpha: (dc != null && dc.currentTier >= 3) ? 0.05 : 0.01),
        strokeColor: Colors.blueGrey.withValues(alpha: 0.3),
        strokeWidth: 1,
        zIndex: 60,
      ),
      if (!widget.isDrillMode) ...[
        Circle(
          circleId: const CircleId('sos_scene_glow_outer'),
          center: c,
          radius: 52 + 28 * pulse,
          fillColor: AppColors.primaryDanger.withValues(alpha: 0.11 * (0.35 + 0.65 * pulse)),
          strokeColor: AppColors.primaryDanger.withValues(alpha: 0.5 + 0.45 * pulse),
          strokeWidth: 2,
          zIndex: 2000,
        ),
        Circle(
          circleId: const CircleId('sos_scene_glow_inner'),
          center: c,
          radius: 26 + 16 * pulseSoft,
          fillColor: Colors.deepOrangeAccent.withValues(alpha: 0.15 * (0.45 + 0.55 * pulseSoft)),
          strokeColor: Colors.white.withValues(alpha: 0.28 + 0.35 * pulseSoft),
          strokeWidth: 1,
          zIndex: 2001,
        ),
      ],
    };
  }

  Future<void> _leaveActiveConsignment() async {
    if (!widget.isVictim && !widget.isDrillMode) {
      await IncidentService.volunteerWithdrawFromIncident(widget.incidentId.trim());
      await _volunteerAssignmentSub?.cancel();
      _volunteerAssignmentSub = null;
    } else if (!widget.isVictim) {
      await _volunteerAssignmentSub?.cancel();
      _volunteerAssignmentSub = null;
    }
    if (!mounted) return;
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(widget.isDrillMode ? '/drill/dashboard' : '/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Locale>(localeProvider, (prev, next) {
      if (prev?.languageCode == next.languageCode) return;
      VoiceCommsService.clearSpeakQueue();
    });

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.primaryDanger)),
      );
    }

    final bool lowPowerMap = useLowPowerGoogleMapLayer(context);
    final bool suppressMotion =
        suppressGoogleMapMarkerAnimations(context) && !widget.isDrillMode;
    final hcOps = ref.watch(highContrastOpsProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final ok = await _confirmExitDialog();
        if (ok && context.mounted) await _leaveActiveConsignment();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
          ValueListenableBuilder<String?>(
            valueListenable: VoiceCommsService.ttsStatusNotifier,
            builder: (context, msg, _) {
              if (msg == null || msg.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.deepOrange.shade900.withValues(alpha: 0.94),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      msg,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // ── Tab bar ──────────────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Container(
              color: AppColors.surface,
              child: Row(
                children: [
                  Expanded(
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: AppColors.primaryDanger,
                      indicatorWeight: 3,
                      labelColor: AppColors.primaryDanger,
                      unselectedLabelColor: Colors.white54,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
                      tabs: const [
                        Tab(icon: Icon(Icons.near_me_rounded, size: 18), text: 'MAP', height: 48),
                        Tab(icon: Icon(Icons.monitor_heart_rounded, size: 18), text: 'TRIAGE', height: 48),
                        Tab(icon: Icon(Icons.checklist_rounded, size: 18), text: 'ON-SCENE', height: 48),
                      ],
                    ),
                  ),
                  const LanguageSwitcherButton(),
                  if (!widget.isVictim)
                    IconButton(
                      tooltip: AppLocalizations.of(context).get('vol_tooltip_lifeline_first_aid'),
                      onPressed: _openLifelineFirstAid,
                      icon: const Icon(Icons.medical_services_rounded, color: AppColors.primaryInfo),
                    ),
                  IconButton(
                    tooltip: AppLocalizations.of(context).get('vol_tooltip_exit_mission'),
                    onPressed: () async {
                      final ok = await _confirmExitDialog();
                      if (ok && context.mounted) await _leaveActiveConsignment();
                    },
                    icon: const Icon(Icons.logout_rounded, color: AppColors.primaryDanger),
                  ),
                ],
              ),
            ),
          ),
          if (!widget.isVictim && !widget.isDrillMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Material(
                color: AppColors.surface.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _lowPowerConsignment ? Icons.battery_saver_rounded : Icons.share_location_rounded,
                        color: Colors.white60,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lowPowerConsignment
                              ? AppLocalizations.of(context)
                                  .get('vol_low_power_tracking_hint')
                              : AppLocalizations.of(context)
                                  .get('volunteer_consignment_live_location_hint'),
                          style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.35),
                        ),
                      ),
                      TextButton(
                        onPressed: _toggleLowPowerConsignment,
                        child: Text(_lowPowerConsignment
                            ? AppLocalizations.of(context)
                                .get('volunteer_consignment_normal_gps_label')
                            : AppLocalizations.of(context)
                                .get('volunteer_consignment_low_power_label')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // ── Tab body ─────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [

                // ─────────────────────────────────────────────────────────
                // TAB 1: MAP
                // ─────────────────────────────────────────────────────────
                Stack(
                  children: [
                    EosHybridMap(
                      ignoreRemoteLeafletTiles: false,
                      mapId: AppConstants.googleMapsDarkMapId.isNotEmpty ? AppConstants.googleMapsDarkMapId : null,
                      style: effectiveGoogleMapsEmbeddedStyleJson(),
                      mapType: lowPowerMap ? MapType.normal : MapType.hybrid,
                      trafficEnabled: kIsWeb ? false : !lowPowerMap,
                      googleMapLoadTimeout:
                          kIsWeb ? const Duration(seconds: 8) : const Duration(seconds: 14),
                      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                      },
                      cameraTargetBounds: IndiaOpsZones.lucknowCameraTargetBounds,
                      initialCameraPosition: IndiaOpsZones.lucknowSafeCamera(
                        _currentPosition != null
                            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                            : null,
                        preferZoom: 17,
                      ),
                      onCameraMove: (CameraPosition p) {
                        if (!mounted) return;
                        if (FleetMapIcons.zoomTierChanged(_consignmentMapZoom, p.zoom)) {
                          setState(() => _consignmentMapZoom = p.zoom);
                        }
                      },
                      onMapCreated: (OpsMapController controller) {
                        if (!_controller.isCompleted) _controller.complete(controller);
                      },
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      compassEnabled: false,
                      polylines: _currentPosition != null
                          ? {
                              if (_hospRoute.isNotEmpty)
                                Polyline(
                                  polylineId: const PolylineId('ambulancePath'),
                                  points: _hospRoute,
                                  color: const Color(0xFF2E7D32),
                                  width: 7,
                                  patterns: [PatternItem.dash(20), PatternItem.gap(15)],
                                  zIndex: 20,
                                ),
                              if (_evacRoute.isNotEmpty)
                                Polyline(
                                  polylineId: const PolylineId('evacPath'),
                                  points: _evacRoute,
                                  color: suppressMotion
                                      ? const Color(0xFF1B5E20)
                                      : (Color.lerp(
                                              const Color(0xFF1B5E20),
                                              const Color(0xFF1B5E20).withValues(alpha: 0.35),
                                              _rotationController.value * 30 % 1.0) ??
                                          const Color(0xFF1B5E20)),
                                  width: 8,
                                  patterns: [PatternItem.dash(20), PatternItem.gap(15)],
                                  zIndex: 10,
                                ),
                            }
                          : {},
                      circles: _buildConsignmentMapCircles(),
                      markers: {
                        if (_currentPosition != null)
                          Marker(
                            markerId: const MarkerId('user'),
                            position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                            icon: _userIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueMagenta),
                            rotation: suppressMotion ? 0.0 : _userCourseDeg,
                            flat: true,
                            anchor: const Offset(0.5, 0.5),
                            infoWindow: InfoWindow(
                              title: AppLocalizations.of(context).get('vol_marker_you'),
                              snippet: AppLocalizations.of(context).get('vol_marker_active_unit'),
                            ),
                          ),
                        Marker(
                          markerId: const MarkerId('incident'),
                          position: _incidentLocation,
                          zIndexInt: 12,
                          icon: _incidentIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                          rotation: suppressMotion ? 0.0 : _rotationController.value * -360,
                          infoWindow: InfoWindow(
                            title: widget.isDrillMode
                                ? AppLocalizations.of(context).get('vol_marker_practice_incident')
                                : AppLocalizations.of(context).get('vol_marker_accident_scene'),
                            snippet: widget.isDrillMode
                                ? AppLocalizations.of(context).get('vol_marker_training_pin')
                                : AppLocalizations.of(context).get('vol_marker_high_severity'),
                          ),
                        ),
                        if (_dispatchChainState?.notifiedHospitalPosition != null || _dispatchChainState?.acceptedHospitalPosition != null)
                          Marker(
                            markerId: const MarkerId('dispatch_hospital'),
                            position: (_dispatchChainState?.isAccepted == true
                                    ? _dispatchChainState?.acceptedHospitalPosition
                                    : _dispatchChainState?.notifiedHospitalPosition) ??
                                _incidentLocation,
                            infoWindow: InfoWindow(
                              title: _dispatchChainState?.isAccepted == true
                                  ? AppLocalizations.of(context)
                                      .get('vol_marker_accepted_hospital')
                                      .replaceAll('{hospital}', _dispatchChainState?.currentHospitalName ?? '')
                                  : AppLocalizations.of(context)
                                      .get('vol_marker_trying_hospital')
                                      .replaceAll('{hospital}', _dispatchChainState?.currentHospitalName ?? ''),
                            ),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              _dispatchChainState?.isAccepted == true
                                  ? BitmapDescriptor.hueGreen
                                  : BitmapDescriptor.hueOrange,
                            ),
                          ),
                        // --- Ambulance: same asset as ops; volunteers only after live GPS pings ---
                        if (widget.isDrillMode ||
                            widget.isVictim ||
                            _incidentHasAmbulanceLivePing)
                          Marker(
                            markerId: const MarkerId('hospital_unit'),
                            position: _hospCurrent,
                            icon: FleetMapIcons.ambulanceForZoom(
                              _consignmentMapZoom,
                              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
                            ),
                            rotation: suppressMotion ? 0.0 : _ambulanceBearing,
                            flat: true,
                            anchor: const Offset(0.5, 0.5),
                            infoWindow: InfoWindow(
                              title: _trackingController.value >= 0.98
                                  ? AppLocalizations.of(context).get('vol_marker_ambulance_on_scene')
                                  : AppLocalizations.of(context).get('vol_marker_ambulance_en_route'),
                            ),
                          ),
                      },
                    ),

                    // Minimal Top HUD (non-clutter)
                    Positioned(
                      top: 50,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: hcOps ? Colors.black.withValues(alpha: 0.94) : AppColors.surface.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(20),
                          border: hcOps ? Border.all(color: Colors.white, width: 2) : null,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10)],
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () async {
                                final ok = await _confirmExitDialog();
                                if (ok && context.mounted) await _leaveActiveConsignment();
                              },
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Proximity progress dots
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.circle,
                                        size: 8,
                                        color: !_isOnScene && !_arrivedAtPin
                                            ? AppColors.primarySafe
                                            : Colors.white30,
                                      ),
                                      Container(
                                        width: 16,
                                        height: 1,
                                        color: Colors.white24,
                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                      ),
                                      Icon(
                                        Icons.circle,
                                        size: 8,
                                        color: _isOnScene && !_arrivedAtPin
                                            ? AppColors.primaryWarning
                                            : Colors.white30,
                                      ),
                                      Container(
                                        width: 16,
                                        height: 1,
                                        color: Colors.white24,
                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                      ),
                                      Icon(
                                        Icons.circle,
                                        size: 8,
                                        color: _arrivedAtPin
                                            ? AppColors.primaryDanger
                                            : Colors.white30,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _arrivedAtPin
                                        ? AppLocalizations.of(context).get('vol_badge_at_scene_pin')
                                        : (_isOnScene
                                            ? AppLocalizations.of(context).get('vol_badge_in_5km_zone')
                                            : AppLocalizations.of(context).get('vol_badge_en_route')),
                                    style: TextStyle(
                                      color: _arrivedAtPin
                                          ? AppColors.primarySafe
                                          : (_isOnScene ? AppColors.primaryDanger : AppColors.primaryWarning),
                                      fontWeight: FontWeight.w900,
                                      fontSize: hcOps ? 16 : 14,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _currentPosition == null
                                        ? ''
                                        : _distanceInMeters >= 1000
                                            ? '${(_distanceInMeters / 1000).toStringAsFixed(1)} km away'
                                            : '${_distanceInMeters.toStringAsFixed(0)} m away',
                                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      _scenePinDistanceFromHospitalLine,
                                      style: const TextStyle(
                                        color: Colors.cyanAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.people_alt_rounded, size: 14, color: Colors.white70),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$_responderCount Responders Active',
                                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                  if ((_drillDemoAmbMin ?? _simAmbulanceRouteMinutes) != null) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(Icons.emergency_rounded, size: 14, color: Colors.redAccent),
                                        const SizedBox(width: 4),
                                        Text(
                                          'EMS ETA: ~${_drillDemoAmbMin ?? _simAmbulanceRouteMinutes} min',
                                          style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Primary Actions (kept minimal, no overlap)
                    Positioned(
                      bottom: 40,
                      left: 20,
                      right: 20,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _showOfflineQr,
                            icon: const Icon(Icons.qr_code_rounded, color: Colors.white),
                            label: Text(
                              AppLocalizations.of(context).volunteerActiveOfflineQrAccess,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E2740),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: const BorderSide(color: AppColors.primaryDanger, width: 1.5),
                              ),
                              elevation: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_dispatchChainState != null && _dispatchChainState!.assignment != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _dispatchChainState!.isAccepted
                                  ? Colors.greenAccent
                                  : _dispatchChainState!.isPendingAcceptance
                                      ? Colors.orangeAccent
                                      : Colors.white24,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _dispatchChainState!.currentTierLabel,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _dispatchChainState!.isAccepted
                                    ? 'Accepted: ${_dispatchChainState!.currentHospitalName}'
                                    : 'Trying: ${_dispatchChainState!.currentHospitalName}',
                                style: TextStyle(
                                  color: _dispatchChainState!.isAccepted ? Colors.greenAccent : Colors.orangeAccent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ], // end map Stack children
                ), // end Stack (TAB 1)

                // ─────────────────────────────────────────────────────────
                // TAB 2: Triage — voice channel + victim status + live log (+ Lifeline for volunteers)
                // ─────────────────────────────────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!widget.isVictim)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: LifelineBridgeJoinCard(
                          initialIncidentId: widget.incidentId,
                          lockIncidentId: true,
                          showJoinCalmDisclaimer: true,
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, widget.isVictim ? 12 : 8, 16, 12),
                        child: ListView(
                          children: [
                            _VictimInfoSection(
                              incidentId: widget.incidentId,
                              isDrillMode: widget.isDrillMode,
                              drillCategory: widget.isDrillMode ? _drillVictimCategory : null,
                              drillChips: widget.isDrillMode ? List<String>.from(_drillVictimChips) : const [],
                              drillNotes: widget.isDrillMode ? _drillVictimNotes : null,
                              drillVoiceQa: widget.isDrillMode ? Map<String, String>.from(_drillVoiceQa) : const {},
                            ),
                            const SizedBox(height: 8),
                            _VolunteerDispatchMilestoneStrip(dispatch: _dispatchChainState),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(context).get('volunteer_major_updates_log'),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 300),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: _VictimLiveUpdatesSection(
                                  incidentId: widget.incidentId,
                                  isDrillMode: widget.isDrillMode,
                                  drillLogLines: widget.isDrillMode ? _drillVolunteerLog : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // ─────────────────────────────────────────────────────────
                // TAB 3: ON-SCENE (within 2.5 km)
                // ─────────────────────────────────────────────────────────
                _OnSceneVolunteerPanel(
                  incidentId: widget.incidentId,
                  isDrillMode: widget.isDrillMode,
                  isOnScene: _isOnScene,
                ),

              ], // end TabBarView children
            ), // end TabBarView
          ), // end Expanded
          ], // end Column children
        ), // end Column
      ), // end Scaffold
    );
  }
}


/// Volunteer Triage tab: only victim pulse lines + dispatch/ambulance/hospital style updates.
bool _isMajorVictimActivityLineForVolunteer(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return false;
  final low = text.toLowerCase();
  if (low.startsWith('victim update')) return true;
  if (low.contains('ambulance')) return true;
  if (low.contains('hospital') &&
      (low.contains('accept') ||
          low.contains('assigned') ||
          low.contains('trying') ||
          low.contains('tier') ||
          low.contains('notified'))) {
    return true;
  }
  if (low.contains('ems')) return true;
  if (low.contains('en route') || low.contains('en-route')) return true;
  if (low.contains('police') && low.contains('dispatch')) return true;
  if (low.contains('conscious') || low.contains('unresponsive') || low.contains('unconscious')) {
    return true;
  }
  if (low.startsWith('voice interview:')) return false;
  if (low.contains('stopped automated')) return false;
  if (low.contains('arrived at scene pin')) return false;
  if (low.contains('geofence')) return false;
  return false;
}

class _VictimLiveUpdatesSection extends StatelessWidget {
  final String incidentId;
  final bool isDrillMode;
  final List<VolunteerDrillLogLine>? drillLogLines;
  const _VictimLiveUpdatesSection({
    required this.incidentId,
    this.isDrillMode = false,
    this.drillLogLines,
  });

  @override
  Widget build(BuildContext context) {
    if (isDrillMode) {
      final lines = drillLogLines ?? const <VolunteerDrillLogLine>[];
      if (lines.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Practice log — victim and ambulance updates will appear here as the drill runs.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
            ),
          ),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: lines.length,
        separatorBuilder: (context, _) => const Divider(height: 1, color: Colors.white10),
        itemBuilder: (ctx, i) {
          final line = lines[i];
          final isLatest = i == 0;
          return _FeedTile(
            icon: Icons.sim_card_download_rounded,
            iconColor: Colors.amberAccent,
            text: line.text,
            createdAt: line.at,
            isLatest: isLatest,
            type: _FeedEventType.drill,
          );
        },
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sos_incidents')
          .doc(incidentId)
          .collection('victim_activity')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Could not load updates. ${snap.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final docs = snap.data?.docs ?? [];
        final filtered = docs
            .where((d) => _isMajorVictimActivityLineForVolunteer(
                  (d.data()['text'] as String?) ?? '',
                ))
            .toList();
        if (filtered.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No major victim or dispatch updates yet.\nAmbulance, hospital routing, and victim consciousness summaries appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: filtered.length,
          separatorBuilder: (context, _) => const Divider(height: 1, color: Colors.white10),
          itemBuilder: (ctx, i) {
            final d = filtered[i].data();
            final text = (d['text'] as String?) ?? '';
            DateTime? t;
            final c = d['createdAt'];
            if (c is Timestamp) t = c.toDate();

            final String lower = text.toLowerCase();
            _FeedEventType type;
            IconData icon;
            Color color;

            if (lower.contains('ambulance') || lower.contains('ems') || lower.contains('en route')) {
              type = _FeedEventType.ambulance;
              icon = Icons.emergency_rounded;
              color = AppColors.primaryDanger;
            } else if (lower.contains('triage') || lower.contains('updated') || lower.contains('category')) {
              type = _FeedEventType.triage;
              icon = Icons.analytics_rounded;
              color = Colors.orangeAccent;
            } else if (lower.contains('conscious') || lower.contains('check-in') || lower.contains('breathing')) {
              type = _FeedEventType.vitals;
              icon = Icons.monitor_heart_rounded;
              color = AppColors.primarySafe;
            } else {
              type = _FeedEventType.other;
              icon = Icons.person_pin_circle_rounded;
              color = AppColors.primaryInfo;
            }

            return _FeedTile(
              icon: icon,
              iconColor: color,
              text: text,
              createdAt: t,
              isLatest: i == 0,
              type: type,
            );
          },
        );
      },
    );
  }
}

enum _FeedEventType { vitals, triage, ambulance, drill, other }

class _FeedTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final DateTime? createdAt;
  final bool isLatest;
  final _FeedEventType type;

  const _FeedTile({
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.createdAt,
    required this.isLatest,
    required this.type,
  });

  String _relativeTime(DateTime? t) {
    if (t == null) return '—';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    final h = diff.inHours;
    if (h < 24) return '${h}h ago';
    final d = diff.inDays;
    return '${d}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final bool highlight = isLatest && type != _FeedEventType.drill;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, color: iconColor, size: 22),
          if (highlight)
            Positioned(
              top: -4,
              right: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.primaryDanger,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        text,
        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
      ),
      subtitle: Text(
        _relativeTime(createdAt),
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
    );
  }
}

class _OnSceneEtaCard extends StatelessWidget {
  final String incidentId;
  final LatLng incidentLatLng;
  final String routedHospitalHint;
  final int? simulatedAmbulanceMinutes;

  const _OnSceneEtaCard({
    required this.incidentId,
    required this.incidentLatLng,
    required this.routedHospitalHint,
    required this.simulatedAmbulanceMinutes,
  });

  Future<void> _openNearbyHospitals() async {
    final lat = incidentLatLng.latitude;
    final lng = incidentLatLng.longitude;
    final u = Uri.parse('https://www.google.com/maps/search/hospital/@$lat,$lng,14z');
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('sos_incidents').doc(incidentId).snapshots(),
      builder: (context, snap) {
        final l10n = AppLocalizations.of(context);
        final data = snap.data?.data();
        final amb = (data?['ambulanceEta'] as String?)?.trim() ?? '—';
        final med = (data?['medicalStatus'] as String?)?.trim() ?? '—';
        final sim = simulatedAmbulanceMinutes;
        final emsPhase = (data?['emsWorkflowPhase'] as String?)?.trim() ?? '';
        String? emsBanner;
        if (emsPhase == 'inbound') {
          emsBanner = l10n.get('vol_ems_banner_en_route');
        } else if (emsPhase == 'on_scene') {
          emsBanner = l10n.get('vol_ems_banner_on_scene');
        } else if (emsPhase == 'returning') {
          emsBanner = l10n.get('vol_ems_banner_returning');
        } else if (emsPhase == 'complete') {
          DateTime? t0;
          final ts = data?['timestamp'];
          if (ts is Timestamp) t0 = ts.toDate();
          DateTime? tend;
          final te = data?['emsResponseCompleteAt'];
          if (te is Timestamp) tend = te.toDate();
          if (t0 != null && tend != null) {
            final total = tend.difference(t0);
            emsBanner = l10n
                .get('vol_ems_banner_complete_with_cycle')
                .replaceAll('{m}', '${total.inMinutes}')
                .replaceAll('{s}', '${total.inSeconds % 60}');
          } else {
            emsBanner = l10n.get('vol_ems_banner_complete');
          }
        }
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.volunteerActiveHospitalEvLabel,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                l10n.volunteerActiveHospitalEvSubtitle,
                style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.3),
              ),
              if (emsBanner != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    emsBanner,
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (routedHospitalHint.isNotEmpty)
                _etaRow(Icons.local_hospital_rounded, 'EMS corridor (map area)', routedHospitalHint, Colors.cyanAccent),
              if (routedHospitalHint.isNotEmpty) const SizedBox(height: 6),
              if (sim != null)
                _etaRow(Icons.airport_shuttle_rounded, 'Simulated ambulance run (routing)', '~$sim min to scene', AppColors.primaryDanger),
              if (sim != null) const SizedBox(height: 6),
              _etaRow(Icons.medical_services_rounded, 'Ambulance ETA (incident doc)', amb, AppColors.primaryDanger),
              const SizedBox(height: 6),
              _etaRow(Icons.info_outline_rounded, 'Responder / dispatch status', med, Colors.white70),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openNearbyHospitals,
                  icon: const Icon(Icons.near_me_rounded, color: Colors.white, size: 20),
                  label: Text(l10n.volunteerActiveNearbyHospitalsMaps,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _etaRow(IconData icon, String label, String value, Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800)),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

class _OnSceneVolunteerPanel extends StatefulWidget {
  final String incidentId;
  final bool isDrillMode;
  final bool isOnScene;

  const _OnSceneVolunteerPanel({
    required this.incidentId,
    this.isDrillMode = false,
    required this.isOnScene,
  });

  @override
  State<_OnSceneVolunteerPanel> createState() => _OnSceneVolunteerPanelState();
}

class _OnSceneVolunteerPanelState extends State<_OnSceneVolunteerPanel> {
  static const int kMaxScenePhotos = 3;

  final _incidentDescCtrl = TextEditingController();
  final List<String> _photoPaths = [];
  bool _uploadingPhoto = false;
  bool _saving = false;

  String _emergencyType = '';
  bool? _isBleeding;
  bool? _isTrapped;
  bool? _isConscious;
  String _breathingStatus = 'Normal';
  bool? _sceneSafe;
  int _victimCount = 1;

  @override
  void initState() {
    super.initState();
    _loadSceneReport();
  }

  @override
  void dispose() {
    _incidentDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSceneReport() async {
    if (widget.isDrillMode) return;
    final id = widget.incidentId.trim();
    if (id.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('sos_incidents').doc(id).get();
      final m = (snap.data()?['volunteerSceneReport'] as Map?)?.cast<String, dynamic>();
      if (!mounted || m == null) return;
      setState(() {
        _incidentDescCtrl.text = (m['incidentDescription'] as String?) ?? '';
        _emergencyType = (m['emergencyType'] as String?) ?? '';
        _isBleeding = m['isBleeding'] as bool?;
        _isTrapped = m['isTrapped'] as bool?;
        _isConscious = m['isConscious'] as bool?;
        _breathingStatus = (m['breathingStatus'] as String?) ?? 'Normal';
        _sceneSafe = m['sceneSafe'] as bool?;
        _victimCount = (m['victimCount'] as int?) ?? 1;
        final photos = m['photoPaths'];
        if (photos is List) {
          _photoPaths
            ..clear()
            ..addAll(photos.whereType<String>().take(kMaxScenePhotos));
        }
      });
    } catch (_) {}
  }

  Future<void> _saveSceneReport() async {
    if (widget.isDrillMode) return;
    final id = widget.incidentId.trim();
    if (id.isEmpty || !widget.isOnScene) return;

    if (_emergencyType.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an emergency type')),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('sos_incidents').doc(id).set(
        {
          'volunteerSceneReport': {
            'emergencyType': _emergencyType,
            'isBleeding': _isBleeding,
            'isTrapped': _isTrapped,
            'isConscious': _isConscious,
            'breathingStatus': _breathingStatus,
            'sceneSafe': _sceneSafe,
            'victimCount': _victimCount,
            'incidentDescription': _incidentDescCtrl.text.trim(),
            'photoPaths': _photoPaths.take(kMaxScenePhotos).toList(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        },
        SetOptions(merge: true),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).volunteerActiveChecklistSaved)),
        );
      }
      final desc = _incidentDescCtrl.text.trim();
      if (!widget.isDrillMode && desc.isNotEmpty && _photoPaths.length >= kMaxScenePhotos) {
        unawaited(IncidentService.tryGrantOnSceneChecklistXp(id));
      }
      SituationBriefService.requestGeneration(id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).volunteerActiveSaveFailed(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickPhoto() async {
    if (!widget.isOnScene || widget.isDrillMode) return;
    if (_photoPaths.length >= kMaxScenePhotos) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).volunteerActivePhotoLimit)),
        );
      }
      return;
    }
    setState(() => _uploadingPhoto = true);
    try {
      final picker = ImagePicker();
      ImageSource source = ImageSource.camera;
      final hasCamera = await picker.pickImage(source: ImageSource.camera, maxWidth: 1) != null;
      if (!hasCamera) {
        source = ImageSource.gallery;
      }
      final picked = await picker.pickImage(source: source, imageQuality: 70, maxWidth: 1280);
      if (picked == null) {
        if (mounted) setState(() => _uploadingPhoto = false);
        return;
      }
      final bytes = await picked.readAsBytes();
      final incidentId =
          widget.incidentId.trim().isEmpty ? 'unassigned' : widget.incidentId.trim();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$uid.jpg';
      final ref = FirebaseStorage.instance
          .ref('incident_photos/$incidentId/$fileName');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      if (mounted) {
        setState(() {
          if (_photoPaths.length < kMaxScenePhotos) _photoPaths.add(url);
          _uploadingPhoto = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).volunteerActivePhotoError(e.toString()))),
        );
        setState(() => _uploadingPhoto = false);
      }
    }
  }

  InputDecoration _fieldDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: AppColors.background,
    );
  }

  @override
  Widget build(BuildContext context) {
    const emergencyTypes = [
      'Drowning',
      'Electric Shock',
      'General Medical Emergency',
      'Road Traffic Collision',
      'Fire/Burn Injury',
      'Fall/Injury',
      'Cardiac Emergency',
      'Snake Bite',
      'Heat Stroke',
      'Chemical Exposure',
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!widget.isOnScene)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.route_rounded, color: Colors.white60, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Move within 2.5 km of the pin to unlock the on-scene checklist.',
                    style: TextStyle(color: Colors.white70, height: 1.35, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        Text(
          'On-scene checklist',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        const Text('Emergency Type', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _emergencyType.isEmpty ? null : _emergencyType,
          decoration: _fieldDeco('Select emergency type'),
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: Colors.white),
          items: emergencyTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: widget.isOnScene ? (v) => setState(() => _emergencyType = v ?? '') : null,
        ),
        const SizedBox(height: 16),
        const Text('Is Victim Bleeding?', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildYesNoBtn('Yes', _isBleeding == true, () => setState(() => _isBleeding = true))),
            const SizedBox(width: 12),
            Expanded(child: _buildYesNoBtn('No', _isBleeding == false, () => setState(() => _isBleeding = false))),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Is Victim Trapped?', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildYesNoBtn('Yes', _isTrapped == true, () => setState(() => _isTrapped = true))),
            const SizedBox(width: 12),
            Expanded(child: _buildYesNoBtn('No', _isTrapped == false, () => setState(() => _isTrapped = false))),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Is Victim Conscious?', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildYesNoBtn('Yes', _isConscious == true, () => setState(() => _isConscious = true))),
            const SizedBox(width: 12),
            Expanded(child: _buildYesNoBtn('No', _isConscious == false, () => setState(() => _isConscious = false))),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Breathing Status', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _breathingStatus,
          decoration: _fieldDeco('Select breathing status'),
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: Colors.white),
          items: ['Normal', 'Difficulty', 'Not Breathing'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: widget.isOnScene ? (v) => setState(() => _breathingStatus = v ?? 'Normal') : null,
        ),
        const SizedBox(height: 16),
        const Text('Is Scene Safe?', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildYesNoBtn('Yes', _sceneSafe == true, () => setState(() => _sceneSafe = true))),
            const SizedBox(width: 12),
            Expanded(child: _buildYesNoBtn('No', _sceneSafe == false, () => setState(() => _sceneSafe = false))),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Number of Victims', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              onPressed: widget.isOnScene && _victimCount > 1 ? () => setState(() => _victimCount--) : null,
              icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
              child: Text('$_victimCount', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              onPressed: widget.isOnScene && _victimCount < 10 ? () => setState(() => _victimCount++) : null,
              icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _incidentDescCtrl,
          style: const TextStyle(color: Colors.white),
          maxLines: 3,
          enabled: widget.isOnScene,
          decoration: _fieldDeco('Additional notes…'),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Text(
              'Scene photos (${_photoPaths.length}/$kMaxScenePhotos)',
              style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5),
            ),
            const Spacer(),
            if (_uploadingPhoto)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
              )
            else
              TextButton.icon(
                onPressed: (widget.isOnScene && !widget.isDrillMode) ? _pickPhoto : null,
                icon: const Icon(Icons.add_a_photo_rounded, color: Colors.amberAccent, size: 18),
                label: const Text('Add photo', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w800)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_photoPaths.isNotEmpty)
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photoPaths.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        _photoPaths[i],
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, prog) =>
                            prog == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                    if (widget.isOnScene)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() => _photoPaths.removeAt(i)),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          )
        else
          const Text('No photos yet.', style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_saving || !widget.isOnScene || _emergencyType.isEmpty) ? null : _saveSceneReport,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryDanger,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('SUBMIT CHECKLIST', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ),
      ],
    );
  }

  Widget _buildYesNoBtn(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryDanger : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppColors.primaryDanger : Colors.white24),
        ),
        child: Center(child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
      ),
    );
  }
}

class _VolunteerDispatchMilestoneStrip extends StatelessWidget {
  final DispatchChainState? dispatch;

  const _VolunteerDispatchMilestoneStrip({required this.dispatch});

  @override
  Widget build(BuildContext context) {
    final s = dispatch;
    if (s == null || s.assignment == null) return const SizedBox.shrink();
    final cs = (s.assignment!.assignedFleetCallSign ?? '').trim();
    final ambSt = (s.assignment!.ambulanceDispatchStatus ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).get('volunteer_dispatch_milestone_title'),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 10, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          if (s.isAccepted)
            Text(
              AppLocalizations.of(context)
                  .get('volunteer_dispatch_milestone_hospital')
                  .replaceAll('{hospital}', s.currentHospitalName),
              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          if (cs.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context).get('volunteer_dispatch_milestone_unit').replaceAll('{unit}', cs),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
          if (ambSt == 'pending_operator') ...[
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context).get('volunteer_dispatch_milestone_crew_pending'),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
          if (ambSt == 'ambulance_en_route') ...[
            const SizedBox(height: 4),
            Text(
              AppLocalizations.of(context).get('volunteer_dispatch_milestone_en_route'),
              style: const TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _VolunteerTriageQrReportCard extends StatelessWidget {
  final String incidentId;
  final double? incidentLat;
  final double? incidentLng;
  final bool fromCache;

  const _VolunteerTriageQrReportCard({
    required this.incidentId,
    this.incidentLat,
    this.incidentLng,
    this.fromCache = false,
  });

  Future<void> _onTapReport(BuildContext context) async {
    final id = incidentId.trim();
    if (id.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('sos_incidents').doc(id).get();
      if (!snap.exists || !context.mounted) return;
      final inc = SosIncident.fromFirestore(snap);
      await IncidentReportService.generateAndStoreReport(inc);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).get('volunteer_triage_report_saved')),
          backgroundColor: AppColors.primarySafe,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppLocalizations.of(context).get('volunteer_triage_report_failed')}$e'),
          backgroundColor: AppColors.primaryDanger,
        ),
      );
    }
  }

  void _showQrDialog(BuildContext context) {
    final l = AppLocalizations.of(context);
    final payload = jsonEncode({
      'incidentId': incidentId,
      if (incidentLat != null) 'incidentLat': incidentLat,
      if (incidentLng != null) 'incidentLng': incidentLng,
      'generatedAt': DateTime.now().toIso8601String(),
      'kind': 'volunteer_triage_handoff',
    });
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          l.get('volunteer_triage_qr_title'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: payload,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 10),
            Text(
              l.get('volunteer_triage_qr_body'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.volunteerActiveClose, style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySafe.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primarySafe.withValues(alpha: 0.45), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: AppColors.primarySafe.withValues(alpha: 0.95), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.get('volunteer_triage_qr_report_title'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
            ],
          ),
          if (fromCache)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l.get('volunteer_victim_medical_offline_hint'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 10.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            l.get('volunteer_triage_qr_report_subtitle'),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showQrDialog(context),
                  icon: const Icon(Icons.qr_code_rounded, color: Colors.white, size: 18),
                  label: Text(
                    l.get('volunteer_triage_show_qr'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => unawaited(_onTapReport(context)),
                  icon: const Icon(Icons.description_rounded, color: Colors.white, size: 18),
                  label: Text(
                    l.get('volunteer_triage_tap_report'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primarySafe.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VictimInfoSection extends StatelessWidget {
  final String incidentId;
  final bool isDrillMode;
  final String? drillCategory;
  final List<String> drillChips;
  final String? drillNotes;
  final Map<String, String> drillVoiceQa;
  const _VictimInfoSection({
    required this.incidentId,
    this.isDrillMode = false,
    this.drillCategory,
    this.drillChips = const [],
    this.drillNotes,
    this.drillVoiceQa = const {},
  });

  static String _drillQaLabel(String key) {
    switch (key) {
      case 'conscious':
        return 'Conscious?';
      case 'breathing':
        return 'Breathing';
      case 'severeBleeding':
        return 'Severe bleeding?';
      case 'safeLocation':
        return 'Safe location?';
      default:
        return key;
    }
  }

  /// Full question text + victim answer (ordered like the victim app flow). Empty if no Q&A rows.
  static List<Widget> voiceInterviewPanel({
    required Map<String, dynamic>? voiceInterview,
    required String categoryPick,
    required String incidentType,
    AppLocalizations? l10n,
  }) {
    if (voiceInterview == null || voiceInterview.isEmpty) return const [];

    const skip = {
      'completedAt',
      'interviewComplete',
      'emergencyCategory',
      'emergencyDescription',
      'victimCategoryDetails',
      'victimCategoryChosenAt',
    };

    final entries = voiceInterview.entries
        .where((e) => !skip.contains(e.key) && '${e.value}'.trim().isNotEmpty)
        .toList();

    if (entries.isEmpty) return const [];

    var typeHint = categoryPick.trim();
    if (typeHint.isEmpty) typeHint = incidentType.trim();
    final order = EmergencyVoiceInterviewQuestions.flowForType(
      typeHint.isEmpty ? null : typeHint,
    ).map((m) => m['key']!).toList();

    int rank(String k) {
      final i = order.indexOf(k);
      return i >= 0 ? i : 1000;
    }

    entries.sort((a, b) {
      final c = rank(a.key).compareTo(rank(b.key));
      return c != 0 ? c : a.key.compareTo(b.key);
    });

    return [
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primaryInfo.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.record_voice_over_rounded, color: AppColors.primaryInfo.withValues(alpha: 0.95), size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Victim safety Q&A (live)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Full questions from the victim app — answers update as they respond.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 10.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            ...entries.map((e) {
              final prompt = l10n != null
                  ? (EmergencyVoiceInterviewQuestions.promptForAnswerKeyWithL10n(e.key, l10n) ??
                      'Question (code: ${e.key})')
                  : (EmergencyVoiceInterviewQuestions.promptForAnswerKey(e.key) ??
                      'Question (code: ${e.key})');
              final ans = _formatVictimVoiceAnswer(e.value);
              final lower = ans.toLowerCase();
              final yes = lower == 'yes';
              final no = lower == 'no';
              final ansColor =
                  yes ? AppColors.primarySafe : (no ? AppColors.primaryDanger : Colors.white.withValues(alpha: 0.72));
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prompt,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Answer: $ans',
                      style: TextStyle(
                        color: ansColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    ];
  }

  static String _formatVictimVoiceAnswer(dynamic v) {
    final s = '$v'.trim();
    if (s.isEmpty) return '—';
    final lower = s.toLowerCase();
    if (lower == 'yes') return 'Yes';
    if (lower == 'no') return 'No';
    if (lower == 'no response') return 'No response';
    if (s == 'NOT SAFE') return 'No / not safe';
    return s;
  }

  /// First three chip questions only (type, safety, headcount) for volunteer triage hero.
  static List<Widget> _threeInitialVictimAnswers(
    Map<String, dynamic>? voiceInterview,
    AppLocalizations l,
  ) {
    if (voiceInterview == null) return const [];
    const keys = <String>[
      EmergencyVoiceInterviewQuestions.q1EmergencyTypeKey,
      EmergencyVoiceInterviewQuestions.q2SafetySeriousKey,
      EmergencyVoiceInterviewQuestions.q3PeopleCountKey,
    ];
    final rows = <Widget>[];
    for (final k in keys) {
      final v = voiceInterview[k];
      if (v == null || '$v'.trim().isEmpty) continue;
      final prompt = EmergencyVoiceInterviewQuestions.promptForAnswerKeyWithL10n(k, l) ??
          EmergencyVoiceInterviewQuestions.promptForAnswerKey(k) ??
          k;
      final ans = _formatVictimVoiceAnswer(v);
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                prompt,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                ans,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (rows.isEmpty) return const [];
    return [
      const SizedBox(height: 12),
      Text(
        l.get('volunteer_victim_three_questions'),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
      ),
      const SizedBox(height: 8),
      ...rows,
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (isDrillMode) {
      return Semantics(
        container: true,
        label: 'Practice mode victim summary',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.person_pin_circle_rounded, color: Colors.amberAccent.withValues(alpha: 0.95), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      drillCategory ?? 'Practice victim (drill)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                  ),
                ],
              ),
              if (drillChips.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: drillChips
                      .map(
                        (c) => Chip(
                          label: Text(c, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          side: BorderSide(color: AppColors.primaryDanger.withValues(alpha: 0.35)),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                      )
                      .toList(),
                ),
              ],
              if ((drillNotes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  drillNotes!.trim(),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 12, height: 1.35, fontWeight: FontWeight.w600),
                ),
              ],
              if (drillVoiceQa.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primaryInfo.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.record_voice_over_rounded, color: AppColors.primaryInfo.withValues(alpha: 0.9), size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Victim Q&A (simulated)',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontWeight: FontWeight.w900, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...drillVoiceQa.entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _drillQaLabel(e.key),
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  e.value,
                                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Data fills in over time to mimic a live victim app. Real missions use Firestore.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 10.5, height: 1.3, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('sos_incidents').doc(incidentId).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        if (data == null) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_search_rounded, color: Colors.white54, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context).volunteerActiveVictimLoading,
                    style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          );
        }

        final triage = (data['triage'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        final chips = <String>[];
        final cat = (triage['category'] as String?)?.trim();
        if (cat != null && cat.isNotEmpty) chips.add(cat);
        for (final k in ['bleeding', 'chestPain', 'breathingTrouble', 'unconscious', 'trapped']) {
          final v = triage[k];
          if (v is bool && v) chips.add(k);
        }

        final unw = triage['unconscious'];
        final isUnconscious = unw == true;
        final consciousnessKnown = unw is bool;
        final voiceMiss = (triage['consciousVoiceMissCount'] as num?)?.toInt() ?? 0;
        String yn(dynamic v) => v == true ? 'Yes' : 'No';

        String labelize(String k) {
          switch (k) {
            case 'bleeding': return 'Severe bleeding';
            case 'chestPain': return 'Chest pain';
            case 'breathingTrouble': return 'Breathing trouble';
            case 'unconscious': return 'Unconscious';
            case 'trapped': return 'Trapped';
            default: return k;
          }
        }

        final notes = (triage['notes'] as String?)?.trim() ?? '';
        final updatedAtRaw = triage['updatedAt'];
        DateTime? updatedAt;
        if (updatedAtRaw is Timestamp) updatedAt = updatedAtRaw.toDate();
        if (updatedAtRaw is String) updatedAt = DateTime.tryParse(updatedAtRaw);
        final updatedLabel = updatedAt == null ? '—' : DateFormat.Hm().format(updatedAt.toLocal());

        final flags = (triage['severityFlags'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
        final score = triage['severityScore'];
        final sevScore = (score is num) ? score.toInt() : null;
        final bool critical = flags.contains('severe_bleeding') || flags.contains('unconscious') || flags.contains('breathing_trouble');
        final Color sevColor = critical ? AppColors.primaryDanger : (sevScore != null && sevScore >= 40 ? Colors.orangeAccent : AppColors.primarySafe);
        final intakeDone = data['intakeCompleted'] == true;
        final forSomeoneElse = data['forSomeoneElse'];
        final peopleCount = data['peopleCount'];
        final victimConscious = data['victimConscious'];
        final victimBreathing = data['victimBreathing'];
        final voiceInterview = (data['voiceInterview'] as Map?)?.cast<String, dynamic>();
        final categoryPick = (voiceInterview?['emergencyCategory'] ?? voiceInterview?['emergencyDescription'])?.toString().trim() ?? '';
        String _relativeLabel(DateTime? t) {
          if (t == null) return '—';
          final diff = DateTime.now().difference(t);
          if (diff.inMinutes < 1) return 'just now';
          if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
          final h = diff.inHours;
          if (h < 24) return '${h}h ago';
          final d = diff.inDays;
          return '${d}d ago';
        }

        String _tileLabel(String key, dynamic value) {
          if (value == null) return '—';
          if (value is bool) return value ? 'Yes' : 'No';
          return value.toString();
        }

        Color _tileColor({required bool danger, required bool warning, required bool ok}) {
          if (danger) return AppColors.primaryDanger;
          if (warning) return Colors.orangeAccent;
          if (ok) return AppColors.primarySafe;
          return Colors.white54;
        }

        final consciousLabel = !consciousnessKnown
            ? 'Unknown'
            : (isUnconscious ? 'Unresponsive' : 'Responsive');
        final consciousColor = !consciousnessKnown
            ? Colors.white54
            : (isUnconscious ? AppColors.primaryDanger : AppColors.primarySafe);

        final bleedingVal = triage['bleeding'];
        final breathingTroubleVal = triage['breathingTrouble'];
        final trappedVal = triage['trapped'];
        final chestPainVal = triage['chestPain'];

        final l = AppLocalizations.of(context);
        final fromCache = snap.data?.metadata.isFromCache == true;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _VolunteerTriageQrReportCard(
                incidentId: incidentId,
                incidentLat: (data['lat'] as num?)?.toDouble(),
                incidentLng: (data['lng'] as num?)?.toDouble(),
                fromCache: fromCache,
              ),
              const SizedBox(height: 12),
              Text(
                l.get('volunteer_victim_consciousness_title'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _miniVitalTile(
                      icon: Icons.psychology_rounded,
                      label: l.get('volunteer_victim_label_conscious'),
                      value: consciousLabel,
                      color: consciousColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _miniVitalTile(
                      icon: Icons.monitor_heart_rounded,
                      label: l.get('volunteer_victim_label_breathing'),
                      value: _tileLabel('breathingTrouble', breathingTroubleVal),
                      color: _tileColor(
                        danger: breathingTroubleVal == true,
                        warning: false,
                        ok: breathingTroubleVal == false,
                      ),
                    ),
                  ),
                ],
              ),
              ..._VictimInfoSection._threeInitialVictimAnswers(voiceInterview, l),
              const SizedBox(height: 6),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  initiallyExpanded: false,
                  title: Text(
                    l.get('volunteer_more_triage_details'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  childrenPadding: const EdgeInsets.only(top: 6, bottom: 4),
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: sevColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: sevColor.withValues(alpha: 0.7)),
                          ),
                          child: Text(
                            critical ? 'CRITICAL' : (sevScore != null ? 'SEV $sevScore' : 'SEV —'),
                            style: TextStyle(
                              color: sevColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.9,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            categoryPick.isNotEmpty
                                ? categoryPick
                                : ((data['type'] as String?)?.trim().isNotEmpty == true
                                    ? (data['type'] as String).trim()
                                    : 'Victim info'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Updated ${_relativeLabel(updatedAt)}',
                          style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _miniVitalTile(
                                  icon: Icons.water_drop_rounded,
                                  label: 'Bleeding',
                                  value: _tileLabel('bleeding', bleedingVal),
                                  color: _tileColor(
                                    danger: bleedingVal == true,
                                    warning: false,
                                    ok: bleedingVal == false,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _miniVitalTile(
                                  icon: Icons.personal_injury_rounded,
                                  label: 'Trapped',
                                  value: _tileLabel('trapped', trappedVal),
                                  color: _tileColor(
                                    danger: trappedVal == true,
                                    warning: false,
                                    ok: trappedVal == false,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (consciousnessKnown && !isUnconscious && voiceMiss > 0) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Voice misses: $voiceMiss (3 misses ≥1 min apart → unresponsive)',
                                style: TextStyle(
                                  color: Colors.orangeAccent.withValues(alpha: 0.95),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Chest pain: ${_tileLabel('chestPain', chestPainVal)}',
                              style: const TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  initiallyExpanded: false,
                  title: Text(
                    l.get('volunteer_more_victim_details'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  childrenPadding: const EdgeInsets.only(top: 6),
                  children: [
                    if (intakeDone) ...[
                      Text(
                        l.get('volunteer_sos_intake_title'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (forSomeoneElse == true) 'Helping someone else',
                          if (forSomeoneElse == false) 'Self emergency',
                          if (peopleCount != null) 'People involved: $peopleCount',
                          if (forSomeoneElse == true && victimConscious != null) 'Victim conscious: $victimConscious',
                          if (forSomeoneElse == true && victimBreathing != null) 'Victim breathing: $victimBreathing',
                        ].where((s) => s.trim().isNotEmpty).join(' · '),
                        style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(notes, style: const TextStyle(color: Colors.white70, height: 1.3)),
                    ],
                    if (voiceInterview != null && voiceInterview.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () {
                            showModalBottomSheet<void>(
                              context: context,
                              backgroundColor: AppColors.surface,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                              ),
                              builder: (ctx) {
                                return SafeArea(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          l.get('volunteer_full_qa_sheet_title'),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                          ),
                                        ),
                                        ..._VictimInfoSection.voiceInterviewPanel(
                                          voiceInterview: voiceInterview,
                                          categoryPick: categoryPick,
                                          incidentType: (data['type'] as String?)?.trim() ?? '',
                                          l10n: l,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                          child: Text(l.get('volunteer_show_full_qa')),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _miniVitalTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 10, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _miniField(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _QuickActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                  letterSpacing: 0.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncidentLifelineCard extends StatefulWidget {
  final String incidentType;
  const _IncidentLifelineCard({required this.incidentType});

  @override
  State<_IncidentLifelineCard> createState() => _IncidentLifelineCardState();
}

class _IncidentLifelineCardState extends State<_IncidentLifelineCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final protocol = ProtocolEngine.forScenario(widget.incidentType);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: protocol.color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: protocol.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.local_hospital_rounded, color: protocol.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          protocol.title.toUpperCase(),
                          style: TextStyle(color: protocol.color, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Lifeline guide matched to this emergency',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: Colors.white54),
                ],
              ),
            ),
          ),

          if (_expanded) ...[
            if (protocol.redFlags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                      SizedBox(width: 6),
                      Text('WATCH FOR', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
                    ]),
                    const SizedBox(height: 6),
                    ...protocol.redFlags.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('\u2022 ', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                          Expanded(child: Text(f, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3))),
                        ],
                      ),
                    )),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('STEP BY STEP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  ...protocol.steps.asMap().entries.map((e) {
                    final i = e.key;
                    final step = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: protocol.color.withValues(alpha: 0.2), shape: BoxShape.circle),
                            child: Text('${i + 1}', style: TextStyle(color: protocol.color, fontWeight: FontWeight.w900, fontSize: 12)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(step.action, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13, height: 1.3)),
                                if (step.caution.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(step.caution, style: const TextStyle(color: Colors.amberAccent, fontSize: 11, height: 1.3)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),

            if (protocol.dontDo.isNotEmpty)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.do_not_disturb_rounded, color: Colors.redAccent, size: 16),
                      SizedBox(width: 6),
                      Text('DO NOT', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
                    ]),
                    const SizedBox(height: 6),
                    ...protocol.dontDo.map((d) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('\u2715 ', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                          Expanded(child: Text(d, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3))),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
