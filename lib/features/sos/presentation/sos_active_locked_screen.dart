// SOS active-locked screen retains scaffolded tabs, helpers and voice-note
// state reserved for the extended victim console. Suppressed until wired up.
// ignore_for_file: unused_field, unused_element, unused_local_variable

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/maps/eos_hybrid_map.dart';
import '../../../core/providers/ops_integration_routing_provider.dart';
import '../../../core/maps/ops_map_controller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/google_maps_illustrative_light_style.dart';
import '../../../core/constants/india_ops_zones.dart';
import '../../../core/utils/fleet_map_icons.dart';
import '../../../core/utils/map_marker_generator.dart';
import '../../../core/utils/osrm_route_util.dart';
import '../domain/emergency_voice_interview_questions.dart';
import '../../../core/utils/speech_web.dart' if (dart.library.io) '../../../core/utils/speech_io.dart';
import '../../../features/ptt/data/ptt_service.dart';
import '../../../features/ptt/domain/ptt_models.dart';
import '../../../core/utils/ptt_voice_playback.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/livekit_emergency_bridge_service.dart';
import '../../../services/voice_comms_service.dart' show VoiceCommsService;
import '../../../core/providers/drill_session_provider.dart'
    show clearDrillSessionDashboardDemoFromRoot, clearDrillVictimPracticeShellFromRoot;
import '../../../services/incident_service.dart';
import '../../../services/ops_integration_routing_service.dart';
import '../../../services/offline_sos_status_service.dart';
import '../../../services/sms_gateway_service.dart';
import '../../../core/web_bridge/victim_recording.dart';
import '../../../services/dispatch_chain_service.dart';
import '../../../features/map/domain/emergency_zone_classification.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/widgets/language_switcher_button.dart';

class _DrillFeedEntry {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _DrillFeedEntry({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });
}

class SosActiveLockedScreen extends ConsumerStatefulWidget {
  final String incidentId;
  /// Practice flow from login: no LiveKit/PTT to real incident, no Firestore writes.
  final bool isDrillMode;
  /// True if the user arrived via the Quick Intake form (1-Tap), bypassing the initial AI voice interview.
  final bool skipInitialVoiceIntake;

  const SosActiveLockedScreen({
    super.key,
    required this.incidentId,
    this.isDrillMode = false,
    this.skipInitialVoiceIntake = false,
  });

  @override
  ConsumerState<SosActiveLockedScreen> createState() => _SosActiveLockedScreenState();
}

class _SosActiveLockedScreenState extends ConsumerState<SosActiveLockedScreen> {
  StreamSubscription? _incidentSub;
  DateTime _startedAt = DateTime.now();
  Timer? _timer;
  Timer? _breadcrumbTimer;
  Timer? _emergencyTypePromptTimer;
  final List<Map<String, dynamic>> _breadcrumbs = [];

  int _acceptedCount = 0;
  String? _ambulanceEta;
  String? _medicalStatus;
  /// EMS workflow from incident doc (`inbound` → driver confirms `on_scene` near scene → `returning` → complete at hospital).
  String? _emsWorkflowPhase;
  double? _volunteerLat;
  double? _volunteerLng;
  String? _lastSpokenKey;
  String? _incidentStatus;
  bool _useEmergencyContactForSms = false;
  String? _emergencyContactPhone;
  String? _emergencyContactEmail;
  /// Incident-driven TTS (volunteer, ETAs, etc.) held until QA prompts are idle.
  final List<String> _deferredIncidentVoiceLines = [];

  String _userLocale = 'en';
  String _userBcp47 = 'en-IN';

  bool _emergencyTypeSelected = false;
  String? _selectedEmergencyType;
  final bool _audioUnlocked = false; // To track if we unblocked Web AudioContext
  AreaIntelligence? _areaIntel;

  // channel updates
  final TextEditingController _textUpdate = TextEditingController();
  bool _sendingUpdate = false;
  /// Legacy PTT press state; LiveKit victim mic stays on when connected.
  bool _isRecording = false;

  // LiveKit emergency bridge (victim voice -> emergency desk).
  lk.Room? _livekitRoom;
  bool _livekitConnected = false;
  bool _livekitStartAttempted = false;
  /// True after we muted LiveKit so device STT can capture the mic (WebRTC otherwise owns it).
  bool _livekitMicPausedForStt = false;
  // Voice channel: mic only while holding Broadcast (no separate hot-mic toggle).
  String _bridgeStatus = 'connecting'; // connecting | connected | failed | reconnecting | ptt_only
  final List<_BridgeParticipant> _bridgeParticipants = [];
  lk.EventsListener<lk.RoomEvent>? _roomEventsListener;

  // lock state
  bool _unlocking = false;

  // map state
  LatLng? _victimLatLng;
  OpsMapController? _mapController;
  double _victimMapZoom = 15.0;
  BitmapDescriptor? _victimPinIcon;
  BitmapDescriptor? _volunteerResponderPinIcon;
  double _ambulanceSimulatedBearing = 0.0;

  LatLng? _ambulanceLivePos;
  double? _ambulanceLiveHdg;
  /// Dispatch paths to the incident pin (same hub offsets as volunteer consignment map).
  List<LatLng> _ambulancePath = [];
  List<LatLng> _volunteerResponderPath = [];
  int? _routeEtaAmbMin;
  int? _routeEtaVolMin;
  bool _dispatchRoutesLoading = false;
  StreamSubscription? _dispatchMapSub;
  DispatchChainState? _dispatchMapState;
  String? _lastSosFeedHospitalSig;
  String? _lastSosFeedFleetSig;
  String? _lastSosFeedAmbEnRouteSig;
  Timer? _routeDebounce;
  Timer? _drillScenarioTimer;
  Timer? _drillVehicleAlongRouteTimer;
  double _drillDispatchVehicleT = 0;
  final List<_DrillFeedEntry> _drillTimeline = [];

  // triage
  String _triageCategory = 'Medical';
  bool _triageBleeding = false;
  bool _triageChestPain = false;
  bool _triageBreathingTrouble = false;
  bool _triageUnconscious = false;
  bool _triageTrapped = false;
  String _triageNotes = '';
  final TextEditingController _triageNotesController = TextEditingController();
  Timer? _triageDebounce;
  Timer? _questionTimer;
  Timer? _consciousPulseTimer;
  int _responseCountdown = 0;
  bool _isQaRunning = false;
  bool _qaVoiceInProgress = false;
  String _qaPrompt = '';
  bool _qaListening = false;
  /// User chose to stop all automated yes/no prompts (consciousness + vital questions).
  bool _userStoppedAllQuestions = false;
  /// True only after the current question TTS finished — avoids early taps breaking the interview flow.
  bool _qaPromptHeard = false;
  /// Bumped when the user answers or skips; stale _askYesNo continuations bail out.
  int _qaEpoch = 0;
  String _voiceNoteTranscript = '';
  int _onSceneVolunteerCount = 0;

  // Voice interview state
  late bool _consciousConfirmedOnce;
  late bool _interviewCompleted;
  int _interviewStep = -1; // -1 = not started, 0+ = question index
  /// Captured when the interview starts so step indices stay stable.
  List<Map<String, String>>? _frozenInterviewFlow;
  /// Chip-style interview options (context questions) — canonical English for Firestore / triage.
  List<String> _chipOptionsForInterview = [];
  /// Parallel display labels (localized); same length as [_chipOptionsForInterview] when set.
  List<String> _chipLabelsForInterview = [];
  String? _currentChipQuestionKey;
  String? _incidentTypeFirestore;
  StreamSubscription<List<PttMessage>>? _pttCommsAnnounceSub;
  final Set<String> _heardPttAnnouncementIds = {};
  bool _pttAnnounceHydrated = false;
  String? _aiHospitalRationaleText;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _aiRationaleSub;
  final Map<String, String> _interviewAnswers = {};
  DateTime? _lastConsciousCheckEndedAt;
  /// Missed voice responses to "Are you conscious?" — need [kConsciousVoiceMissesRequired] before marking unresponsive.
  int _consciousVoiceMissCount = 0;
  static const int kConsciousVoiceMissesRequired = 3;
  static const Duration kConsciousCheckMinGap = Duration(seconds: 60);

  /// True after opening guidance hands off to consciousness checks + fixed interview.
  bool _postOpeningSafetyFlowStarted = false;

  /// Web: show the Silence / Voice-Guided mode picker until the user chooses.
  bool _webVoiceGateVisible = false;

  /// True when this incident was created while offline — Firestore will sync when connectivity returns.
  bool _offlineSosSyncBanner = false;
  StreamSubscription<bool>? _connectivityForOfflineBannerSub;

  bool _hasNavigatedToFeedback = false;
  bool _hasSeenIncidentExist = false;
  bool _autoExpireHandled = false;
  /// One-shot TTS line when profile emergency contact phone/email is on the incident doc.
  bool _spokenEmergencyContactTts = false;

  static const String _voiceCommsBrief =
      'The emergency LiveKit channel joins automatically. The Lifeline agent receives the same guidance text as your device TTS. Your microphone is live on the channel when connected.';

  User? get _user => FirebaseAuth.instance.currentUser;
  String get _uid => _user?.uid ?? 'anon';

  String? _effectiveEmergencyType() {
    final a = _incidentTypeFirestore?.trim();
    if (a != null && a.isNotEmpty) return a;
    final b = _selectedEmergencyType?.trim();
    if (b != null && b.isNotEmpty) return b;
    final c = _triageCategory.trim();
    return c.isNotEmpty ? c : null;
  }

  void _startPttVoiceCommsListener() {
    _pttCommsAnnounceSub?.cancel();
    if (widget.incidentId.isEmpty) return;
    _pttCommsAnnounceSub = PttService.watchMessages(widget.incidentId).listen((msgs) {
      if (!context.mounted) return;
      if (!_pttAnnounceHydrated) {
        for (final m in msgs) {
          _heardPttAnnouncementIds.add(m.id);
        }
        _pttAnnounceHydrated = true;
        return;
      }
      for (final m in msgs) {
        if (_heardPttAnnouncementIds.contains(m.id)) continue;
        _heardPttAnnouncementIds.add(m.id);
        if (m.senderId == _uid) continue;
        if (m.type == PttMessageType.join) {
          final who = m.senderName.trim().isEmpty ? 'A responder' : m.senderName.trim();
          final line = '$who joined voice communications.';
          final hold = !_interviewCompleted || _isQaRunning || _qaVoiceInProgress;
          if (hold) {
            _deferredIncidentVoiceLines.add(line);
          } else {
            _speakGuidance(line);
          }
        } else if (m.type == PttMessageType.voice &&
            (m.audioBase64 != null && m.audioBase64!.isNotEmpty)) {
          unawaited(playPttVoiceClipBase64(m.audioBase64, mimeType: m.audioMimeType));
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _consciousConfirmedOnce = widget.skipInitialVoiceIntake;
    _interviewCompleted = widget.skipInitialVoiceIntake;
    final id = widget.incidentId.trim();
    if (id.isNotEmpty && !widget.isDrillMode) {
      unawaited(IncidentService.persistActiveSos(id));
    }
    _loadUserLocale();
    if (widget.isDrillMode) {
      _drillVehicleAlongRouteTimer = Timer.periodic(const Duration(milliseconds: 110), (_) {
        if (!context.mounted) return;
        setState(() {
          _drillDispatchVehicleT += 0.00115;
          if (_drillDispatchVehicleT >= 1) _drillDispatchVehicleT = 0;
        });
      });
      unawaited(_bootstrapDrillVictim());
    } else {
      _wireIncidentListener();
    }
    if (!widget.isDrillMode && widget.incidentId.trim().isNotEmpty) {
      _dispatchMapSub = DispatchChainService.watchForIncident(widget.incidentId).listen((state) {
        if (!mounted) return;
        setState(() => _dispatchMapState = state);
        _scheduleDispatchRoutesRebuild();
        unawaited(_maybeAppendSosDispatchFeedLines(state));
      });
    }
    if (!widget.isDrillMode) {
      _startPttVoiceCommsListener();
    }
    if (!widget.isDrillMode) {
      _fetchAreaIntel();
    }
    _beginVoiceAutomation();
    _ambulanceSimulatedBearing = 135.0; // Simulated entry angle
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!context.mounted) return;
      setState(() {});
    });
    _startBreadcrumbs();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAmbulanceMapMarker());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isDrillMode || widget.incidentId.trim().isEmpty || _uid == 'anon') return;
      unawaited(_startLivekitEmergencyBridge());
    });
    if (!widget.isDrillMode && widget.incidentId.trim().isNotEmpty) {
      unawaited(_hydrateOfflineSosBanner());
    }
    // Subscribe to the Gemini-generated hospital rationale field on the
    // incident doc. Mirrored server-side from the dispatch assignment.
    if (!widget.isDrillMode && widget.incidentId.trim().isNotEmpty) {
      _aiRationaleSub = FirebaseFirestore.instance
          .collection('sos_incidents')
          .doc(widget.incidentId.trim())
          .snapshots()
          .listen((snap) {
        final data = snap.data();
        if (!mounted || data == null) return;
        final raw = data['aiHospitalRationale'];
        if (raw is! Map) return;
        final text = raw['text']?.toString().trim();
        if (text == null || text.isEmpty) return;
        if (text != _aiHospitalRationaleText) {
          setState(() => _aiHospitalRationaleText = text);
        }
      });
    }
  }

  @override
  void dispose() {
    VoiceCommsService.clearSpeakQueue();
    _questionTimer?.cancel();
    _consciousPulseTimer?.cancel();
    if (speechSupported()) stopListening();
    _incidentSub?.cancel();
    _timer?.cancel();
    _textUpdate.dispose();
    _triageNotesController.dispose();
    _breadcrumbTimer?.cancel();
    _roomEventsListener?.dispose();
    _emergencyTypePromptTimer?.cancel();
    _pttCommsAnnounceSub?.cancel();
    _routeDebounce?.cancel();
    _drillScenarioTimer?.cancel();
    _drillVehicleAlongRouteTimer?.cancel();
    _triageDebounce?.cancel();
    _connectivityForOfflineBannerSub?.cancel();
    _dispatchMapSub?.cancel();
    _aiRationaleSub?.cancel();
    if (widget.isDrillMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        clearDrillSessionDashboardDemoFromRoot();
        clearDrillVictimPracticeShellFromRoot();
      });
    }
    unawaited(_resumeLivekitMicAfterStt());
    if (_livekitRoom != null) {
      unawaited(_livekitRoom!.disconnect());
      unawaited(_livekitRoom!.dispose());
      _livekitRoom = null;
    }
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _hydrateOfflineSosBanner() async {
    final (pendingId, _) = await OfflineSosStatusService.peekPending();
    final myId = widget.incidentId.trim();
    if (pendingId == null || pendingId != myId) return;

    if (ref.read(connectivityProvider).value == true) {
      await OfflineSosStatusService.clearPending();
      return;
    }
    if (!context.mounted) return;
    setState(() => _offlineSosSyncBanner = true);

    _connectivityForOfflineBannerSub?.cancel();
    _connectivityForOfflineBannerSub = ConnectivityService().onlineStream.listen((online) {
      if (!context.mounted) return;
      if (online) {
        unawaited(OfflineSosStatusService.clearPending());
        if (_offlineSosSyncBanner) setState(() => _offlineSosSyncBanner = false);
      } else if (!_offlineSosSyncBanner) {
        setState(() => _offlineSosSyncBanner = true);
      }
    });
  }

  Future<void> _bootstrapDrillVictim() async {
    await _seedDrillVictimState();
    if (!context.mounted) return;
    _scheduleDispatchRoutesRebuild();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      _startDrillVictimSimulation();
    });
  }

  Future<void> _seedDrillVictimState() async {
    try {
      final p = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
          );
      if (!context.mounted) return;
      setState(() {
        _victimLatLng = LatLng(p.latitude, p.longitude);
        _acceptedCount = 4;
        _ambulanceEta = '~11 min';
        _volunteerLat = p.latitude + 0.011;
        _volunteerLng = p.longitude - 0.008;
        _onSceneVolunteerCount = 0;
        _medicalStatus =
            'Practice · Tier-1 grid live — 4 demo responders, ambulance staging corridors';
        _incidentStatus = 'dispatched';
        _drillTimeline.clear();
      });
    } catch (_) {
      if (!context.mounted) return;
      setState(() {
        const lat = 26.8467;
        const lng = 80.9462;
        _victimLatLng = const LatLng(lat, lng);
        _acceptedCount = 4;
        _ambulanceEta = '~11 min';
        _volunteerLat = lat + 0.011;
        _volunteerLng = lng - 0.008;
        _onSceneVolunteerCount = 0;
        _medicalStatus =
            'Practice · Tier-1 grid live — 4 demo responders, ambulance staging corridors';
        _incidentStatus = 'dispatched';
        _drillTimeline.clear();
      });
    }
  }

  void _startDrillVictimSimulation() {
    if (!widget.isDrillMode) return;
    _drillScenarioTimer?.cancel();
    var step = 0;
    _drillScenarioTimer = Timer.periodic(const Duration(milliseconds: 2200), (t) {
      if (!context.mounted) {
        t.cancel();
        return;
      }
      final scene = _victimLatLng;
      if (scene == null) return;
      step++;
      switch (step) {
        case 1:
          setState(() {
            _drillTimeline.add(
              const _DrillFeedEntry(
                icon: Icons.hub_rounded,
                color: Color(0xFF4FC3F7),
                title: 'Dispatch hub (demo)',
                subtitle: 'Incident keyed to your GPS — duplicate SMS relay simulated as “linked”.',
              ),
            );
            _acceptedCount = 6;
            _medicalStatus = 'Practice · 6 volunteers in 5 km ring acknowledged push';
          });
          _scheduleDispatchRoutesRebuild();
          break;
        case 2:
          setState(() {
            _ambulanceEta = '~9 min';
            _drillTimeline.add(
              const _DrillFeedEntry(
                icon: Icons.airport_shuttle_rounded,
                color: Color(0xFF80DEEA),
                title: 'Ambulance ALS-12 (demo)',
                subtitle: 'Unit diverted from standby — ETA improving on MAP (red polyline).',
              ),
            );
          });
          break;
        case 3:
          setState(() {
            _drillTimeline.add(
              const _DrillFeedEntry(
                icon: Icons.construction_rounded,
                color: Color(0xFF64B5F6),
                title: 'Corridor clear (demo)',
                subtitle: 'Staging routes on MAP align with primary EMS approach.',
              ),
            );
          });
          break;
        case 4:
          setState(() {
            _drillTimeline.add(
              const _DrillFeedEntry(
                icon: Icons.construction_rounded,
                color: Color(0xFFFFF176),
                title: 'Mutual-aid EMS (demo)',
                subtitle: 'Backup unit rolling — secondary approach path on MAP.',
              ),
            );
          });
          _scheduleDispatchRoutesRebuild();
          break;
        case 5:
          setState(() {
            _volunteerLat = scene.latitude + 0.007;
            _volunteerLng = scene.longitude - 0.005;
            _drillTimeline.add(
              const _DrillFeedEntry(
                icon: Icons.volunteer_activism_rounded,
                color: Color(0xFF69F0AE),
                title: 'Nearest volunteer (demo)',
                subtitle: 'Green route — 2.1 km out, moving; voice bridge “listen-only” simulated.',
              ),
            );
          });
          _scheduleDispatchRoutesRebuild();
          break;
        case 6:
          setState(() {
            _ambulanceEta = '~7 min';
            _drillTimeline.add(
              const _DrillFeedEntry(
                icon: Icons.mic_rounded,
                color: Color(0xFFE1BEE7),
                title: 'PTT burst (simulated)',
                subtitle: '“ALS-12, clear to corridor” — appears in comms-style timeline.',
              ),
            );
          });
          break;
        case 7:
          setState(() {
            _acceptedCount = 8;
            _medicalStatus = 'Practice · Mutual-aid unit from adjacent grid (demo)';
            _drillTimeline.add(
              const _DrillFeedEntry(
                icon: Icons.groups_rounded,
                color: Color(0xFFB39DDB),
                title: 'Tier-2 expansion (demo)',
                subtitle: 'If Tier-1 had gaps, wider ring would open — here shown as +2 responders.',
              ),
            );
          });
          break;
        case 8:
          setState(() {
            _volunteerLat = scene.latitude + 0.004;
            _volunteerLng = scene.longitude - 0.003;
            _drillTimeline.add(
              const _DrillFeedEntry(
                icon: Icons.chat_rounded,
                color: Color(0xFFFFCC80),
                title: 'Victim ping (demo)',
                subtitle: '“Still conscious, pain stable” — triage card updates for Lifeline.',
              ),
            );
          });
          _scheduleDispatchRoutesRebuild();
          break;
        case 9:
          setState(() {
            _ambulanceEta = '~5 min';
            _drillTimeline.add(
              const _DrillFeedEntry(
                icon: Icons.local_hospital_rounded,
                color: Color(0xFF80CBC4),
                title: 'Receiving hospital (demo)',
                subtitle: 'Trauma bay notified — bed count and blood bank standby (simulated).',
              ),
            );
          });
          break;
        case 10:
          setState(() {
            _onSceneVolunteerCount = 2;
            _drillTimeline.add(
              const _DrillFeedEntry(
                icon: Icons.flag_rounded,
                color: Color(0xFFFFB74D),
                title: 'On-scene check-in (demo)',
                subtitle: 'Two volunteers marked on-scene — MAP markers cluster near you.',
              ),
            );
          });
          break;
        case 11:
          setState(() {
            _ambulanceEta = '~3 min';
            _volunteerLat = scene.latitude + 0.0018;
            _volunteerLng = scene.longitude - 0.0012;
            _drillTimeline.add(
              const _DrillFeedEntry(
                icon: Icons.route_rounded,
                color: Color(0xFF90CAF9),
                title: 'Route refresh (demo)',
                subtitle: 'OSRM polylines tightened after road closure cleared (simulated).',
              ),
            );
          });
          _scheduleDispatchRoutesRebuild();
          break;
        case 12:
          setState(() {
            _drillTimeline.add(
              const _DrillFeedEntry(
                icon: Icons.health_and_safety_rounded,
                color: Color(0xFFA5D6A7),
                title: 'Scene safety (demo)',
                subtitle: 'Traffic diverted on approach; hold position for ALS.',
              ),
            );
          });
          break;
        case 13:
          setState(() {
            _ambulanceEta = '~2 min';
            _medicalStatus = 'Practice · Ambulance visual on approach — crew waving off bystanders';
            _drillTimeline.add(
              const _DrillFeedEntry(
                icon: Icons.medical_services_rounded,
                color: Color(0xFFFF8A80),
                title: 'ALS on final (demo)',
                subtitle: 'Stretcher and monitor visible — handover to volunteer lead.',
              ),
            );
          });
          break;
        case 14:
          setState(() {
            _drillTimeline.add(
              const _DrillFeedEntry(
                icon: Icons.check_circle_rounded,
                color: Color(0xFF81C784),
                title: 'Drill wrap (demo)',
                subtitle: 'Full workflow shown: dispatch → multi-agency routes → on-scene → EMS arrival. UNLOCK anytime.',
              ),
            );
          });
          t.cancel();
          break;
        default:
          t.cancel();
      }
    });
  }

  Future<void> _loadAmbulanceMapMarker() async {
    await FleetMapIcons.preload();
    final icons = await Future.wait([
      MapMarkerGenerator.getMinimalPin(
        Icons.emergency_rounded,
        AppColors.primaryDanger,
        withActiveSosGlow: !widget.isDrillMode,
      ),
      MapMarkerGenerator.getMinimalPin(Icons.volunteer_activism_rounded, const Color(0xFF69F0AE)),
    ]);
    if (!context.mounted) return;
    setState(() {
      _victimPinIcon = icons[0];
      _volunteerResponderPinIcon = icons[1];
    });
  }

  /// Compass bearing 0–360° from [from] → [to] (north-up art).
  double _bearingDeg(LatLng from, LatLng to) {
    final lat1 = from.latitude * (math.pi / 180);
    final lat2 = to.latitude * (math.pi / 180);
    final dLng = (to.longitude - from.longitude) * (math.pi / 180);
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final br = math.atan2(y, x) * (180 / math.pi);
    return (br + 360) % 360;
  }

  LatLng _pointAlongPath(List<LatLng> path, double t) {
    if (path.isEmpty) {
      return _victimLatLng ?? const LatLng(0, 0);
    }
    if (path.length == 1 || t <= 0) return path.first;
    if (t >= 1) return path.last;
    final exact = t * (path.length - 1);
    final lo = exact.floor();
    final hi = exact.ceil();
    if (lo == hi) return path[lo];
    final f = exact - lo;
    final a = path[lo];
    final b = path[hi];
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * f,
      a.longitude + (b.longitude - a.longitude) * f,
    );
  }

  Future<void> _fetchAreaIntel() async {
    try {
      final pos = await Geolocator.getLastKnownPosition() ?? await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      final list = await IncidentService.fetchPastIncidents(
        center: LatLng(pos.latitude, pos.longitude),
        radiusMeters: 15000.0,
      );
      if (!context.mounted) return;
      final intel = IncidentService.computeAreaIntel(list, LatLng(pos.latitude, pos.longitude));
      setState(() => _areaIntel = intel);
    } catch (_) {}
  }

  void _startBreadcrumbs() {
    _captureBreadcrumb();
    // Slightly longer interval + medium accuracy on device to reduce battery use during long SOS.
    final gap = widget.isDrillMode ? 90 : 45;
    _breadcrumbTimer = Timer.periodic(Duration(seconds: gap), (_) {
      if (!context.mounted) return;
      _captureBreadcrumb();
    });
  }

  Future<void> _captureBreadcrumb() async {
    if (widget.isDrillMode) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 12),
        ),
      );
      final crumb = {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
        'timestamp': DateTime.now().toIso8601String(),
        'speed': pos.speed,
      };
      _breadcrumbs.add(crumb);

      if (widget.incidentId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('sos_incidents')
            .doc(widget.incidentId)
            .set({
          'breadcrumbs': _breadcrumbs,
          'lastKnownLat': pos.latitude,
          'lastKnownLng': pos.longitude,
          'lastLocationAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (context.mounted && _victimLatLng == null) {
        setState(() => _victimLatLng = LatLng(pos.latitude, pos.longitude));
        _scheduleDispatchRoutesRebuild();
      }
    } catch (e) {
      debugPrint('[SOS] breadcrumb capture failed: $e');
    }
  }

  Future<void> _loadUserLocale() async {
    final locale = await VoiceCommsService.getLocale();
    if (context.mounted) {
      setState(() {
        _userLocale = locale;
        _userBcp47 = VoiceCommsService.bcp47ForLocale(locale);
      });
    }
  }

  /// Device TTS plus [LivekitEmergencyBridgeService.dispatchLifelineComms] so the Lifeline agent speaks in-room.
  void _speakGuidance(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    final pttOnly =
        ref.read(opsIntegrationRoutingProvider).whenOrNull(data: (v) => v.useFirebasePttOnly) ?? false;
    if (!widget.isDrillMode && _uid != 'anon' && widget.incidentId.isNotEmpty && !pttOnly) {
      unawaited(() async {
        try {
          await LivekitEmergencyBridgeService.dispatchLifelineComms(
            incidentId: widget.incidentId,
            text: t,
          );
        } catch (e) {
          debugPrint('[SOS] Lifeline guidance dispatch: $e');
        }
      }());
    }
    unawaited(VoiceCommsService.readAloud(t));
  }

  Future<void> _speakGuidanceAndWait(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final pttOnly =
        ref.read(opsIntegrationRoutingProvider).whenOrNull(data: (v) => v.useFirebasePttOnly) ?? false;
    if (!widget.isDrillMode && _uid != 'anon' && widget.incidentId.isNotEmpty && !pttOnly) {
      unawaited(() async {
        try {
          await LivekitEmergencyBridgeService.dispatchLifelineComms(
            incidentId: widget.incidentId,
            text: t,
          );
        } catch (e) {
          debugPrint('[SOS] Lifeline guidance dispatch: $e');
        }
      }());
    }
    try {
      await VoiceCommsService.readAloudAndWait(t);
    } catch (_) {}
  }

  Future<void> _enableVictimLivekitMicAfterCategory() async {
    if (!context.mounted || _uid == 'anon') return;
    if (ref.read(opsIntegrationRoutingProvider).whenOrNull(data: (v) => v.useFirebasePttOnly) ?? false) {
      return;
    }
    if (_livekitConnected && _livekitRoom != null) {
      try {
        await _livekitRoom!.localParticipant?.setMicrophoneEnabled(true);
      } catch (e) {
        debugPrint('[LiveKit] mic on after category: $e');
      }
      return;
    }
    unawaited(_startLivekitEmergencyBridge());
  }

  void _scheduleFlushDeferredIncidentVoice() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      _flushDeferredIncidentVoiceIfQuiet();
    });
  }

  /// Speaks backlog via TTS + Lifeline agent dispatch.
  void _flushDeferredIncidentVoiceIfQuiet() {
    if (!context.mounted) return;
    if (_isQaRunning || _qaVoiceInProgress) return;
    if (_deferredIncidentVoiceLines.isEmpty) return;
    final msg = _deferredIncidentVoiceLines.join(' ');
    _deferredIncidentVoiceLines.clear();
    _speakGuidance(msg);
  }

  /// Speaks once when the incident includes an emergency contact phone or email (matches UI row).
  void _maybeSpeakEmergencyContactTtsAfterSnapshot() {
    if (!context.mounted || widget.isDrillMode || _spokenEmergencyContactTts) return;
    if (VoiceCommsService.silenceMode) return;
    final p = _emergencyContactPhone;
    final e = _emergencyContactEmail;
    if ((p == null || p.isEmpty) && (e == null || e.isEmpty)) return;
    _spokenEmergencyContactTts = true;
    final msg = AppLocalizations.of(context).get('sos_tts_emergency_contacts_on_file');
    final holdForFlow = !_interviewCompleted || _isQaRunning || _qaVoiceInProgress;
    if (holdForFlow) {
      _deferredIncidentVoiceLines.add(msg);
    } else {
      _speakGuidance(msg);
    }
  }

  void _wireIncidentListener() {
    _incidentSub = FirebaseFirestore.instance
        .collection('sos_incidents')
        .doc(widget.incidentId)
        .snapshots()
        .listen((snap) {
      if (!context.mounted) return;
      if (!snap.exists) {
        // Archived/deleted or never existed (offline edge). Stay on screen but stop listening.
        _incidentSub?.cancel();
        _incidentSub = null;
        if (_hasSeenIncidentExist && !_hasNavigatedToFeedback && !widget.isDrillMode) {
          _hasNavigatedToFeedback = true;
          context.go(
            '/incident-feedback/${Uri.encodeComponent(widget.incidentId.trim())}?closed=archived',
          );
        }
        return;
      }
      _hasSeenIncidentExist = true;
      final data = snap.data();
      if (data == null) return;

      final ts = data['timestamp'];
      if (ts is String) {
        _startedAt = DateTime.tryParse(ts) ?? _startedAt;
      } else if (ts is Timestamp) {
        _startedAt = ts.toDate();
      }

      if (!widget.isDrillMode && !_autoExpireHandled) {
        final rSt = data['status'] as String? ?? '';
        if (['pending', 'dispatched', 'blocked'].contains(rSt) &&
            IncidentService.isIncidentActiveWindowExpired(_startedAt)) {
          _autoExpireHandled = true;
          final iid = widget.incidentId.trim();
          unawaited(() async {
            await IncidentService.archiveAndCloseIncident(
              incidentId: iid,
              status: 'expired',
              closedByUid: 'system_auto_expire',
            );
            await IncidentService.clearActiveSos();
            if (!context.mounted) return;
            if (_hasNavigatedToFeedback) return;
            _hasNavigatedToFeedback = true;
            context.go(
              '/incident-feedback/${Uri.encodeComponent(iid)}?closed=expired',
            );
          }());
          return;
        }
      }

      final ids = List<String>.from(data['acceptedVolunteerIds'] ?? []);
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      final amb = data['ambulanceEta'] as String?;
      final med = data['medicalStatus'] as String?;
      final vLat = (data['volunteerLat'] as num?)?.toDouble();
      final vLng = (data['volunteerLng'] as num?)?.toDouble();
      final ambLLat = (data['ambulanceLiveLat'] as num?)?.toDouble();
      final ambLLng = (data['ambulanceLiveLng'] as num?)?.toDouble();
      final ambLHdg = (data['ambulanceLiveHeadingDeg'] as num?)?.toDouble();
      final triage = (data['triage'] as Map?)?.cast<String, dynamic>();
      final onSceneIds = List<String>.from(data['onSceneVolunteerIds'] ?? const []);
      final onSceneCount = onSceneIds.length;
      final emsPhase = (data['emsWorkflowPhase'] as String?)?.trim() ?? '';

      final key = '${ids.length}|${amb ?? ''}|${med ?? ''}|${vLat ?? ''}|${vLng ?? ''}|$onSceneCount|$emsPhase';
      if (key != _lastSpokenKey) {
        _lastSpokenKey = key;
        final parts = <String>[];
        if (!context.mounted) return;
        final l10n = AppLocalizations.of(context);
        if (ids.length > _acceptedCount) {
          parts.add(l10n.get('voice_volunteer_accepted'));
        }
        final ambDispatchEnRoute =
            (_dispatchMapState?.assignment?.ambulanceDispatchStatus ?? '').trim() == 'ambulance_en_route';
        final hasLiveAmbVehicle = ambLLat != null && ambLLng != null;
        if (amb != null && amb.isNotEmpty && (hasLiveAmbVehicle || ambDispatchEnRoute)) {
          parts.add(l10n.get('voice_ambulance_dispatched_eta').replaceAll('{eta}', amb));
        }
        if (!widget.isDrillMode && emsPhase == 'on_scene') {
          parts.add(l10n.get('voice_ambulance_on_scene_victim'));
        }
        if (med != null && med.isNotEmpty) parts.add(med);
        if (onSceneCount >= 2 && onSceneCount > _onSceneVolunteerCount) {
          parts.add(l10n.get('voice_volunteers_on_scene_count').replaceAll('{n}', '$onSceneCount'));
        } else if (onSceneCount == 1 && _onSceneVolunteerCount == 0) {
          parts.add(l10n.get('voice_one_volunteer_on_scene'));
        }
        if (parts.isNotEmpty) {
          final msg = parts.join(' ');
          final holdForFlow = !_interviewCompleted || _isQaRunning || _qaVoiceInProgress;
          if (holdForFlow) {
            _deferredIncidentVoiceLines.add(msg);
          } else {
            _speakGuidance(msg);
          }
        }
      }

      final incType = (data['type'] as String?)?.trim();
      setState(() {
        _acceptedCount = ids.length;
        _ambulanceEta = amb;
        _medicalStatus = med;
        _emsWorkflowPhase = emsPhase.isEmpty ? null : emsPhase;
        _volunteerLat = vLat;
        _volunteerLng = vLng;
        _ambulanceLivePos =
            (ambLLat != null && ambLLng != null) ? LatLng(ambLLat, ambLLng) : null;
        _ambulanceLiveHdg = ambLHdg;
        _onSceneVolunteerCount = onSceneCount;
        if (incType != null && incType.isNotEmpty) {
          _incidentTypeFirestore = incType;
        }
        _incidentStatus = data['status'] as String?;
        if ((_incidentStatus == 'resolved' || _incidentStatus == 'cancelled') && !_hasNavigatedToFeedback && !widget.isDrillMode) {
          _hasNavigatedToFeedback = true;
          final iid = widget.incidentId.trim();
          context.go(
            '/incident-feedback/${Uri.encodeComponent(iid)}?closed=${Uri.encodeComponent(_incidentStatus!)}',
          );
        }
        _useEmergencyContactForSms = (data['useEmergencyContactForSms'] as bool?) ?? false;
        _emergencyContactPhone = (data['emergencyContactPhone'] as String?)?.trim();
        _emergencyContactEmail = (data['emergencyContactEmail'] as String?)?.trim();
        if (lat != null && lng != null) _victimLatLng = LatLng(lat, lng);
        if (triage != null) {
          _triageCategory = (triage['category'] as String?) ?? _triageCategory;
          _triageBleeding = (triage['bleeding'] as bool?) ?? _triageBleeding;
          _triageChestPain = (triage['chestPain'] as bool?) ?? _triageChestPain;
          _triageBreathingTrouble = (triage['breathingTrouble'] as bool?) ?? _triageBreathingTrouble;
          _triageUnconscious = (triage['unconscious'] as bool?) ?? _triageUnconscious;
          final miss = (triage['consciousVoiceMissCount'] as num?)?.toInt();
          if (miss != null && miss >= 0 && miss <= kConsciousVoiceMissesRequired) {
            _consciousVoiceMissCount = miss;
          }
          _triageTrapped = (triage['trapped'] as bool?) ?? _triageTrapped;
          final nextNotes = (triage['notes'] as String?) ?? _triageNotes;
          _triageNotes = nextNotes;
          if (_triageNotesController.text != nextNotes) {
            _triageNotesController.text = nextNotes;
          }
        }
      });
      _maybeSpeakEmergencyContactTtsAfterSnapshot();
      _scheduleDispatchRoutesRebuild();
    });
  }

  void _scheduleDispatchRoutesRebuild() {
    final scene = _victimLatLng;
    if (scene == null) return;
    _routeDebounce?.cancel();
    _routeDebounce = Timer(const Duration(milliseconds: 700), () {
      if (!context.mounted) return;
      final s = _victimLatLng;
      if (s == null) return;
      unawaited(_rebuildVictimDispatchRoutes(s));
    });
  }

  Future<void> _maybeAppendSosDispatchFeedLines(DispatchChainState state) async {
    if (widget.isDrillMode) return;
    final id = widget.incidentId.trim();
    if (id.isEmpty) return;
    final a = state.assignment;
    if (a == null) return;

    final hid = (a.acceptedHospitalId ?? '').trim();
    if (hid.isNotEmpty && state.isAccepted) {
      final sig = 'acc|$hid';
      if (_lastSosFeedHospitalSig != sig) {
        _lastSosFeedHospitalSig = sig;
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
      if (_lastSosFeedFleetSig != sig) {
        _lastSosFeedFleetSig = sig;
        await IncidentService.appendIncidentFeedLine(
          incidentId: id,
          text: 'Ambulance unit assigned: $cs',
          source: 'dispatch',
        );
      }
    }

    final ambSt = (a.ambulanceDispatchStatus ?? '').trim();
    if (ambSt == 'ambulance_en_route' && _lastSosFeedAmbEnRouteSig != ambSt) {
      _lastSosFeedAmbEnRouteSig = ambSt;
      await IncidentService.appendIncidentFeedLine(
        incidentId: id,
        text: 'Ambulance en route',
        source: 'dispatch',
      );
    }
  }

  bool _victimAmbulanceMinuteEtaVisible() {
    if (_ambulanceLivePos != null) return true;
    final ambSt = (_dispatchMapState?.assignment?.ambulanceDispatchStatus ?? '').trim();
    return ambSt == 'ambulance_en_route';
  }

  String? _victimAmbulanceHeaderStat() {
    final l10n = AppLocalizations.of(context);
    if (!_victimAmbulanceMinuteEtaVisible()) {
      final ambSt = (_dispatchMapState?.assignment?.ambulanceDispatchStatus ?? '').trim();
      if (ambSt == 'pending_operator') {
        return l10n.get('sos_active_header_stat_coordinating_crew');
      }
      if (_dispatchMapState?.isAccepted == true) {
        return l10n.get('sos_active_header_stat_coordinating');
      }
      return l10n.get('sos_active_dash');
    }
    final doc = _ambulanceEta?.trim();
    if (doc != null && doc.isNotEmpty) return doc;
    if (_routeEtaAmbMin != null) {
      return l10n
          .get('sos_active_header_stat_route_min')
          .replaceAll('{n}', '${_routeEtaAmbMin}');
    }
    return l10n.get('sos_active_header_stat_en_route');
  }

  String? _victimAmbulanceLegendDocEta() {
    if (!_victimAmbulanceMinuteEtaVisible()) return null;
    final doc = _ambulanceEta?.trim();
    if (doc != null && doc.isNotEmpty) return doc;
    return null;
  }

  String? _volunteerMapLegendCaption() {
    final vl = _volunteerLat;
    final vg = _volunteerLng;
    final scene = _victimLatLng;
    if (vl == null || vg == null || scene == null) return null;
    return 'Live GPS marker';
  }

  Future<void> _rebuildVictimDispatchRoutes(LatLng scene) async {
    final vl = _volunteerLat;
    final vg = _volunteerLng;
    final hospTarget = _dispatchHospitalTarget;
    if (!context.mounted) return;
    setState(() => _dispatchRoutesLoading = true);
    List<LatLng> amb;
    if (hospTarget != null) {
      amb = await OsrmRouteUtil.drivingRoute(scene, hospTarget);
      if (amb.length < 2) amb = OsrmRouteUtil.fallbackPolyline(scene, hospTarget);
    } else {
      final hospOrigin = LatLng(scene.latitude - 0.006, scene.longitude - 0.004);
      amb = await OsrmRouteUtil.drivingRoute(hospOrigin, scene);
      if (amb.length < 2) amb = OsrmRouteUtil.fallbackPolyline(hospOrigin, scene);
    }
    int? volEtaMin;
    if (vl != null && vg != null) {
      final m = Geolocator.distanceBetween(
        vl,
        vg,
        scene.latitude,
        scene.longitude,
      );
      const kph = 28.0;
      final min = (m / 1000.0) / kph * 60.0;
      if (min.isFinite) volEtaMin = min.clamp(1, 180).round();
    }
    if (!context.mounted) return;
    setState(() {
      _ambulancePath = amb;
      _volunteerResponderPath = [];
      _routeEtaAmbMin = OsrmRouteUtil.etaMinutesFromRoute(amb);
      _routeEtaVolMin = volEtaMin;
      _dispatchRoutesLoading = false;
    });
  }

  Future<void> _tearDownLiveKitForFirebasePttRouting() async {
    _roomEventsListener?.dispose();
    _roomEventsListener = null;
    final r = _livekitRoom;
    _livekitRoom = null;
    _livekitConnected = false;
    _bridgeParticipants.clear();
    if (r != null) {
      try {
        await r.disconnect();
        await r.dispose();
      } catch (_) {}
    }
  }

  Future<void> _startLivekitEmergencyBridge() async {
    if (_livekitStartAttempted) return;
    if (widget.incidentId.trim().isEmpty) return;
    if (_uid == 'anon') return;
    if (ref.read(opsIntegrationRoutingProvider).whenOrNull(data: (v) => v.useFirebasePttOnly) ?? false) {
      _livekitStartAttempted = true;
      if (context.mounted) setState(() => _bridgeStatus = 'ptt_only');
      return;
    }

    _livekitStartAttempted = true;

    try {
      await LivekitEmergencyBridgeService.ensureEmergencyBridge(
        incidentId: widget.incidentId,
      );

      final room = await LivekitEmergencyBridgeService.connectToEmergencyBridge(
        incidentId: widget.incidentId,
        uid: _uid,
        variant: 'sos',
        canPublishAudio: true,
        muteOnConnect: true,
      );

      if (!context.mounted) {
        await room.disconnect();
        await room.dispose();
        return;
      }

      try {
        if (_emergencyTypeSelected) {
          await room.localParticipant?.setMicrophoneEnabled(true);
        }
      } catch (e) {
        debugPrint('[LiveKit] mic on: $e');
      }

      setState(() {
        _livekitRoom = room;
        _bridgeStatus = 'connected';
      });
      _livekitConnected = true;

      if (kIsWeb) {
        unawaited(room.startAudio());
      }

      _wireRoomEvents(room);
      _syncParticipants(room);
    } catch (e) {
      debugPrint('[LiveKit] bridge connect failed: $e');
      _livekitConnected = false;
      if (context.mounted) setState(() => _bridgeStatus = 'failed');

      // Retry once after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (!context.mounted || _livekitConnected) return;
        _livekitStartAttempted = false;
        _startLivekitEmergencyBridge();
      });
    }
  }

  Future<void> _pauseLivekitMicForStt() async {
    // Web + native: WebRTC otherwise keeps the mic; device/browser STT cannot hear the user.
    if (!_livekitConnected || _livekitRoom == null) return;
    try {
      await _livekitRoom!.localParticipant?.setMicrophoneEnabled(false);
      if (context.mounted) setState(() => _livekitMicPausedForStt = true);
      await Future<void>.delayed(const Duration(milliseconds: 750));
    } catch (e) {
      debugPrint('[SOS] pause LiveKit mic for speech recognition: $e');
    }
  }

  Future<void> _resumeLivekitMicAfterStt() async {
    if (!_livekitMicPausedForStt) return;
    if (context.mounted) setState(() => _livekitMicPausedForStt = false);
    if (!context.mounted || !_livekitConnected || _livekitRoom == null) return;
    try {
      await _livekitRoom!.localParticipant?.setMicrophoneEnabled(true);
    } catch (e) {
      debugPrint('[SOS] resume LiveKit mic: $e');
    }
  }

  void _scheduleResumeLivekitMic() {
    unawaited(Future<void>.delayed(const Duration(milliseconds: 350), () async {
      if (!context.mounted) return;
      await _resumeLivekitMicAfterStt();
    }));
  }

  void _wireRoomEvents(lk.Room room) {
    _roomEventsListener?.dispose();
    _roomEventsListener = room.createListener();

    _roomEventsListener!
      ..on<lk.RoomConnectedEvent>((_) {
        if (context.mounted) _syncParticipants(room);
      })
      ..on<lk.ParticipantConnectedEvent>((e) {
        if (context.mounted) _syncParticipants(room);
      })
      ..on<lk.ParticipantDisconnectedEvent>((e) {
        if (context.mounted) _syncParticipants(room);
      })
      ..on<lk.TrackPublishedEvent>((_) {
        if (context.mounted) _syncParticipants(room);
      })
      ..on<lk.TrackSubscribedEvent>((_) {
        if (context.mounted) _syncParticipants(room);
      })
      ..on<lk.RoomDisconnectedEvent>((e) {
        if (context.mounted) {
          setState(() {
            _bridgeStatus = 'reconnecting';
            _livekitConnected = false;
          });
        }
      })
      ..on<lk.RoomReconnectedEvent>((e) {
        if (context.mounted) {
          setState(() {
            _bridgeStatus = 'connected';
            _livekitConnected = true;
          });
          if (kIsWeb) {
            unawaited(room.startAudio());
          }
          _syncParticipants(room);
        }
      })
      ..on<lk.ActiveSpeakersChangedEvent>((e) {
        if (!context.mounted) return;
        final speakingIds = e.speakers.map((s) => s.identity).toSet();
        setState(() {
          for (var i = 0; i < _bridgeParticipants.length; i++) {
            final p = _bridgeParticipants[i];
            final speaking = speakingIds.contains(p.identity);
            if (p.isSpeaking != speaking) {
              _bridgeParticipants[i] = _BridgeParticipant(
                identity: p.identity,
                role: p.role,
                displayName: p.displayName,
                isSpeaking: speaking,
              );
            }
          }
        });
      });
  }

  void _syncParticipants(lk.Room room) {
    final list = <_BridgeParticipant>[];

    // Add self (victim)
    final local = room.localParticipant;
    if (local != null) {
      final id = local.identity;
      list.add(_BridgeParticipant(
        identity: id.isEmpty ? 'victim_$_uid' : id,
        role: _BridgeRole.victim,
        displayName: 'You',
      ));
    }

    // Add remote participants
    for (final entry in room.remoteParticipants.entries) {
      final p = entry.value;
      final pid = p.identity;
      final id = pid.isEmpty ? entry.key : pid;
      final role = _BridgeParticipant.roleFromIdentity(id);
      list.add(_BridgeParticipant(
        identity: id,
        role: role,
        displayName: _BridgeParticipant.nameForRole(role, id),
      ));
    }

    list.sort((a, b) => a.role.index.compareTo(b.role.index));

    if (context.mounted) setState(() {
      _bridgeParticipants.clear();
      _bridgeParticipants.addAll(list);
    });
  }



  void _beginVoiceAutomation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      // Web: speechSynthesis requires a fresh user gesture on this route — always use the tap gate.
      if (kIsWeb) {
        setState(() => _webVoiceGateVisible = true);
        return;
      }
      unawaited(_runVoiceGuidanceSequence());
    });
  }

  /// User chose Voice-Guided mode — prime audio and start TTS sequence.
  void _onWebVoiceGateTapped() {
    VoiceCommsService.silenceMode = false;
    VoiceCommsService.voiceGuidanceEnabled = true;
    VoiceCommsService.clearSpeakQueue();
    // Prime AudioContext + speechSynthesis inside this user-gesture handler.
    VoiceCommsService.primeForVoiceGuidance();
    setState(() => _webVoiceGateVisible = false);
    unawaited(_runVoiceGuidanceSequence());
  }

  /// User chose Silence Mode — skip all TTS, go straight to visual questionnaire.
  void _onWebSilenceModeTapped() {
    VoiceCommsService.silenceMode = true;
    VoiceCommsService.clearSpeakQueue();
    setState(() => _webVoiceGateVisible = false);
    unawaited(_runVoiceGuidanceSequence());
  }

  Future<void> _runVoiceGuidanceSequence() async {
    if (!context.mounted || _userStoppedAllQuestions) return;
    // Drain legacy "primed during navigation" flag — web tap gate handles the actual priming.
    VoiceCommsService.takeSosOpeningPrimedForActiveScreen();
    await VoiceCommsService.getLocale();
    // On web the tap gate already called clearSpeakQueue + primeForVoiceGuidance synchronously
    // inside the user-gesture handler. On native we prime here.
    if (!kIsWeb) VoiceCommsService.primeForVoiceGuidance();
    // Give the browser 100 ms for speechSynthesis.cancel() to fully settle before enqueuing
    // the first utterance. Chrome silently drops a speak() that immediately follows cancel().
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!context.mounted || _userStoppedAllQuestions) return;
    // Do not await opening TTS — a stalled Web Speech callback would block the whole questionnaire.
    _speakGuidance(AppLocalizations.of(context).get('sos_tts_opening_guidance'));
    if (!context.mounted || _userStoppedAllQuestions) return;
    await Future.delayed(const Duration(milliseconds: 400));
    if (!context.mounted) return;

    String? prefilledType;
    if (!widget.isDrillMode) {
      try {
        final snap =
            await FirebaseFirestore.instance.collection('sos_incidents').doc(widget.incidentId).get();
        if (!context.mounted) return;
        final d = snap.data();
        if (d != null && d['intakeCompleted'] == true) {
          final t = (d['type'] as String?)?.trim();
          if (t != null && t.isNotEmpty) prefilledType = t;
        }
      } catch (_) {}
    }

    if (!context.mounted || _userStoppedAllQuestions) return;
    await _beginPostOpeningSafetyFlow(intakePrefillType: prefilledType);
  }

  /// Opening handoff: optional intake type, then consciousness checks on a 60s cadence.
  Future<void> _beginPostOpeningSafetyFlow({
    String? intakePrefillType,
    String? voiceNoteDetails,
  }) async {
    if (!context.mounted || _userStoppedAllQuestions || _postOpeningSafetyFlowStarted) return;
    _postOpeningSafetyFlowStarted = true;

    final pre = intakePrefillType?.trim();
    if (pre != null && pre.isNotEmpty) {
      _selectedEmergencyType = pre;
      _triageCategory = pre;
      _interviewAnswers[EmergencyVoiceInterviewQuestions.categoryAnswerKey] = pre;
      if (!widget.isDrillMode && widget.incidentId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('sos_incidents').doc(widget.incidentId).set(
            {
              'type': pre,
              'victimCategoryChosenAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        } catch (_) {}
      }
    } else {
      final vn = voiceNoteDetails?.trim();
      if (vn != null && vn.isNotEmpty) {
        _interviewAnswers[EmergencyVoiceInterviewQuestions.categoryAnswerKey] = 'Voice note — $vn';
        final merged = _triageNotes.trim().isEmpty ? vn : '${_triageNotes.trim()}\n$vn';
        _triageNotes = merged;
        _triageNotesController.text = merged;
      }
    }

    setState(() {
      _emergencyTypeSelected = true;
      _isQaRunning = false;
    });
    _scheduleTriageSave();
    _scheduleFlushDeferredIncidentVoice();
    unawaited(_enableVictimLivekitMicAfterCategory());

    if (!_userStoppedAllQuestions) {
      unawaited(_askConsciousness());
      _startConsciousPulse();
    }
  }

  void _showOtherEmergencyTypeDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        final ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            l10n.get('sos_other_emergency_title'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: l10n.get('sos_other_emergency_hint'),
              hintStyle: const TextStyle(color: Colors.white38),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel, style: const TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                final val = ctrl.text.trim();
                final line = val.isEmpty
                    ? l10n.get('sos_other_emergency_value_other')
                    : l10n
                        .get('sos_other_emergency_value_other_with_detail')
                        .replaceAll('{detail}', val);
                _handleInterviewAnswer(EmergencyVoiceInterviewQuestions.q1EmergencyTypeKey, line);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryDanger, foregroundColor: Colors.white),
              child: Text(l10n.get('continue')),
            ),
          ],
        );
      },
    );
  }

  void _stopQuestionsFlow() {
    VoiceCommsService.clearSpeakQueue();
    _qaEpoch++;
    _questionTimer?.cancel();
    if (_qaListening && speechSupported()) stopListening();
    _qaListening = false;
    _scheduleResumeLivekitMic();
    _qaVoiceInProgress = false;
    _consciousPulseTimer?.cancel();

    final wasInterview = _interviewStep >= 0;
    _userStoppedAllQuestions = true;
    _interviewStep = -1;
    _interviewCompleted = true;
    _chipOptionsForInterview = [];
    _chipLabelsForInterview = [];
    _currentChipQuestionKey = null;

    if (wasInterview && _interviewAnswers.isNotEmpty) {
      unawaited(_saveInterviewToFirestore());
    }
    unawaited(_appendVictimActivity('Stopped automated safety questions'));

    if (!context.mounted) return;
    setState(() {
      _isQaRunning = false;
      _qaPrompt = 'Questions stopped. Keep using the voice channel and Updates as needed.';
    });
    _scheduleFlushDeferredIncidentVoice();
  }

  void _startConsciousPulse() {
    _consciousPulseTimer?.cancel();
    _consciousPulseTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!context.mounted || _userStoppedAllQuestions || _isQaRunning || _interviewStep >= 0) return;
      final ended = _lastConsciousCheckEndedAt;
      if (ended != null && DateTime.now().difference(ended) < kConsciousCheckMinGap) return;
      unawaited(_askConsciousness());
    });
  }

  Future<void> _announceAndWait(String text) async {
    await _speakGuidanceAndWait(text);
  }

  Future<void> _askConsciousness() async {
    await _askYesNo(AppLocalizations.of(context).get('sos_are_you_conscious'));
  }

  Future<void> _askYesNo(String prompt, {String? questionKey}) async {
    if (_qaVoiceInProgress) return;
    final epoch = _qaEpoch;
    _qaVoiceInProgress = true;
    _questionTimer?.cancel();
    VoiceCommsService.clearSpeakQueue();
    VoiceCommsService.primeForVoiceGuidance();
    setState(() {
      _isQaRunning = true;
      _qaPrompt = prompt;
      _responseCountdown = 20;
      _qaListening = false;
      // Enable YES/NO immediately; TTS may lag or fail on web if onDone never fires.
      _qaPromptHeard = true;
    });
    unawaited(_announceAndWait(prompt));
    _qaVoiceInProgress = false;

    if (!context.mounted || epoch != _qaEpoch) return;

    _questionTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!context.mounted) return;
      if (_responseCountdown <= 1) {
        t.cancel();
        if (questionKey != null) {
          _handleInterviewAnswer(questionKey, null);
        } else {
          _handleQaAnswer(null);
        }
      } else {
        setState(() => _responseCountdown--);
      }
    });
  }

  void _handleQaAnswer(bool? yes) {
    _qaEpoch++;
    _questionTimer?.cancel();
    if (_qaListening && speechSupported()) stopListening();
    _qaListening = false;
    _scheduleResumeLivekitMic();
    _qaPromptHeard = false;
    _lastConsciousCheckEndedAt = DateTime.now();

    if (yes == true) {
      setState(() {
        _consciousVoiceMissCount = 0;
        _triageUnconscious = false;
        _isQaRunning = false;
      });
      _scheduleTriageSave();
      _scheduleFlushDeferredIncidentVoice();

      if (!_consciousConfirmedOnce && !_interviewCompleted) {
        // First time confirming consciousness — start the fixed three-question interview
        _consciousConfirmedOnce = true;
        setState(() {
          _qaPrompt = 'Conscious confirmed. Three quick questions for responders.';
        });
        // Start interview after a brief pause
        Future.delayed(const Duration(seconds: 3), () {
          if (!context.mounted || _userStoppedAllQuestions) return;
          _startInterview();
        });
      } else {
        setState(() {
          _qaPrompt = 'Conscious confirmed. We will check again in 60 seconds.';
        });
      }
      return;
    }

    if (yes == false) {
      setState(() {
        _consciousVoiceMissCount = 0;
        _triageUnconscious = true;
        _isQaRunning = false;
        _qaPrompt = 'You indicated you are not conscious. Marked for responders.';
      });
      _scheduleTriageSave();
      _scheduleFlushDeferredIncidentVoice();
      return;
    }

    // No voice / timed out — require 3 misses at least 60s apart (pulse + end time) before unresponsive.
    final nextCount = _consciousVoiceMissCount + 1;
    final markUnresponsive = nextCount >= kConsciousVoiceMissesRequired;
    setState(() {
      _consciousVoiceMissCount = nextCount;
      _triageUnconscious = markUnresponsive;
      _isQaRunning = false;
      _qaPrompt = markUnresponsive
          ? 'No response detected. Marked as unconscious for responders.'
          : 'No answer. Consciousness check $nextCount of $kConsciousVoiceMissesRequired. We will ask again in one minute.';
    });
    _scheduleTriageSave();

    if (markUnresponsive) {
      _scheduleFlushDeferredIncidentVoice();
    } else {
      final l10n = AppLocalizations.of(context);
      final msg = l10n
          .get('sos_tts_conscious_no_answer_attempt')
          .replaceAll('{n}', '$nextCount')
          .replaceAll('{max}', '$kConsciousVoiceMissesRequired');
      unawaited(
        _announceAndWait(msg).then((_) {
          if (context.mounted) _flushDeferredIncidentVoiceIfQuiet();
        }),
      );
    }
  }

  void _startInterview() {
    if (_userStoppedAllQuestions) return;
    _frozenInterviewFlow =
        EmergencyVoiceInterviewQuestions.localizedFlow(AppLocalizations.of(context));
    _interviewStep = 0;
    _chipOptionsForInterview = [];
    _chipLabelsForInterview = [];
    _currentChipQuestionKey = null;
    _askNextInterviewQuestion();
  }

  void _askNextInterviewQuestion() {
    if (!context.mounted || _userStoppedAllQuestions) return;
    final flow = _frozenInterviewFlow;
    if (flow == null || flow.isEmpty || _interviewStep < 0 || _interviewStep >= flow.length) {
      _finishInterview();
      return;
    }

    final q = flow[_interviewStep];
    final key = q['key']!;
    final prompt = q['prompt']!;
    final type = q['type'] ?? 'yesno';
    if (type == 'chip') {
      _presentChipQuestion(q);
      return;
    }
    setState(() {
      _chipOptionsForInterview = [];
      _chipLabelsForInterview = [];
      _currentChipQuestionKey = null;
    });
    unawaited(_askYesNo(prompt, questionKey: key));
  }

  void _presentChipQuestion(Map<String, String> q) {
    _qaEpoch++;
    _questionTimer?.cancel();
    if (_qaListening && speechSupported()) stopListening();
    _qaListening = false;
    VoiceCommsService.clearSpeakQueue();
    VoiceCommsService.primeForVoiceGuidance();
    final opts = (q['options'] ?? '')
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final labelParts = (q['labels'] ?? '')
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final labels = labelParts.length == opts.length ? labelParts : opts;
    final key = q['key']!;
    final prompt = q['prompt']!;
    setState(() {
      _isQaRunning = true;
      _qaPrompt = prompt;
      _qaPromptHeard = true;
      _chipOptionsForInterview = opts;
      _chipLabelsForInterview = labels;
      _currentChipQuestionKey = key;
      _responseCountdown = 120;
    });
    unawaited(_announceAndWait(prompt));
    _questionTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!context.mounted) return;
      if (_responseCountdown <= 1) {
        t.cancel();
        _handleInterviewAnswer(key, null);
      } else {
        setState(() => _responseCountdown--);
      }
    });
  }

  void _handleInterviewAnswer(String key, String? answer) {
    _qaEpoch++;
    _questionTimer?.cancel();
    if (_qaListening && speechSupported()) stopListening();
    _qaListening = false;
    _scheduleResumeLivekitMic();
    _qaPromptHeard = false;

    final displayAnswer = answer ?? 'No response';
    _interviewAnswers[key] = displayAnswer;

    if (key == EmergencyVoiceInterviewQuestions.q1EmergencyTypeKey &&
        answer != null &&
        answer != 'No response') {
      final headline = answer.split(':').first.trim();
      _selectedEmergencyType = headline;
      _triageCategory = headline;
      _interviewAnswers[EmergencyVoiceInterviewQuestions.categoryAnswerKey] = answer;
      if (!widget.isDrillMode && widget.incidentId.isNotEmpty) {
        unawaited(
          FirebaseFirestore.instance.collection('sos_incidents').doc(widget.incidentId).set(
            {
              'type': headline,
              'victimCategoryChosenAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          ),
        );
      }
    }

    _refreshTriageDerivedFromFixedInterview();

    final flow = _frozenInterviewFlow;
    final flowLen = flow?.length ?? 0;
    setState(() {
      _isQaRunning = false;
      _chipOptionsForInterview = [];
      _chipLabelsForInterview = [];
      _currentChipQuestionKey = null;
      _qaPrompt = 'Got it. ${_interviewStep < flowLen - 1 ? "Next question..." : "Thank you. All information sent to responders."}';
    });
    _scheduleFlushDeferredIncidentVoice();

    _interviewStep++;

    if (flow == null || _interviewStep >= flow.length) {
      _finishInterview();
    } else {
      Future.delayed(const Duration(seconds: 2), () {
        if (!context.mounted) return;
        _askNextInterviewQuestion();
      });
    }
  }

  /// Maps the fixed Q2/Q3 answers into legacy triage flags used by activity lines and dispatch.
  void _refreshTriageDerivedFromFixedInterview() {
    final q2 =
        (_interviewAnswers[EmergencyVoiceInterviewQuestions.q2SafetySeriousKey] ?? '').toLowerCase();
    _triageChestPain = false;
    _triageBleeding = false;
    _triageBreathingTrouble = q2.contains('critical');
    _triageTrapped = q2.contains('not injured') && q2.contains('danger');
  }

  void _finishInterview() {
    _interviewStep = -1;
    _interviewCompleted = true;
    _refreshTriageDerivedFromFixedInterview();
    _scheduleTriageSave();
    _saveInterviewToFirestore();

    setState(() {
      _qaPrompt = 'All vital information collected. Responders have been updated. We will check your consciousness every 60 seconds.';
    });
    unawaited(() async {
      final l10n = AppLocalizations.of(context);
      await _speakGuidanceAndWait(l10n.get('sos_tts_interview_saved'));
      if (!context.mounted) return;
      await _speakGuidanceAndWait(l10n.get('sos_tts_map_routes'));
      if (context.mounted) _scheduleFlushDeferredIncidentVoice();
    }());
  }

  String _buildInterviewSummary() {
    final parts = <String>[];
    final flow = _frozenInterviewFlow;
    if (flow == null) return '';
    for (final q in flow) {
      final key = q['key']!;
      final answer = _interviewAnswers[key];
      if (answer != null && answer != 'No response') {
        final label = q['prompt']!.split('?').first.split('.').first;
        parts.add('$label: $answer');
      }
    }
    return parts.join('. ');
  }

  Future<void> _saveInterviewToFirestore() async {
    if (widget.isDrillMode || widget.incidentId.isEmpty || _interviewAnswers.isEmpty) return;
    try {
      final et = (_effectiveEmergencyType() ?? '').trim();
      final b = EmergencyVoiceInterviewQuestions.bucketFor(et);
      final req = <String>[];
      if (b.isNotEmpty && b != 'generic') req.add(b);
      if (et.isNotEmpty) req.add(et.toLowerCase());
      var urgency = 0;
      if (_triageUnconscious) urgency += 40;
      if (_triageChestPain) urgency += 18;
      if (_triageBreathingTrouble) urgency += 18;
      if (_triageBleeding) urgency += 12;
      if (_triageTrapped) urgency += 15;
      final q2Ans =
          (_interviewAnswers[EmergencyVoiceInterviewQuestions.q2SafetySeriousKey] ?? '').toLowerCase();
      if (q2Ans.contains('critical')) urgency += 35;
      if (q2Ans.contains('injured but stable')) urgency += 14;
      if (q2Ans.contains('not injured') && q2Ans.contains('danger')) urgency += 22;
      final q3Ans =
          (_interviewAnswers[EmergencyVoiceInterviewQuestions.q3PeopleCountKey] ?? '').toLowerCase();
      if (q3Ans.contains('more than two')) urgency += 12;
      if (q3Ans.contains('two')) urgency += 4;
      await FirebaseFirestore.instance
          .collection('sos_incidents')
          .doc(widget.incidentId)
          .set({
        'voiceInterview': {
          ..._interviewAnswers,
          'completedAt': FieldValue.serverTimestamp(),
          'interviewComplete': _interviewCompleted,
        },
        'dispatchHints': {
          'emergencyType': et,
          'requiredServices': req,
          'triageUrgency': urgency,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
      await _appendVictimActivity('Voice interview: ${_buildInterviewSummary()}');
    } catch (e) {
      debugPrint('[SOS] interview save failed: $e');
    }
  }

  Duration get _elapsed => DateTime.now().difference(_startedAt);

  Future<String?> _loadHashedPin() async {
    // Local cache first for offline unlock.
    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getString('sos_pin_hash');
    if (local != null && local.isNotEmpty) return local;

    final uid = _user?.uid;
    if (uid == null || uid.isEmpty || uid == 'anon') return null;

    if (!ConnectivityService().isOnline) return null;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final remote = (doc.data()?['sosPinHash'] as String?)?.trim();
      if (remote != null && remote.isNotEmpty) {
        await prefs.setString('sos_pin_hash', remote);
        return remote;
      }
    } catch (_) {}
    return null;
  }

  String _pinHash(String uid, String pin) {
    final bytes = utf8.encode('$uid:${pin.trim()}');
    return sha256.convert(bytes).toString();
  }

  Future<void> _unlockAndCloseActions() async {
    if (_unlocking) return;
    setState(() => _unlocking = true);
    try {
      final pin = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) {
          final ctrl = TextEditingController();
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(
              widget.isDrillMode ? 'Practice SOS — enter PIN' : 'Enter SOS PIN',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.isDrillMode) ...[
                  Text(
                    'Drill only. Use practice PIN:',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppConstants.drillSosPracticePin,
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(dialogCtx).get('pin'),
                    hintStyle: const TextStyle(color: Colors.white38),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(null),
                child: Text(AppLocalizations.of(dialogCtx).get('close'),
                    style: const TextStyle(color: Colors.white70)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogCtx).pop(ctrl.text),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryDanger),
                child: Text(AppLocalizations.of(dialogCtx).get('unlock')),
              ),
            ],
          );
        },
      );

      if (!context.mounted) return;
      if (pin == null) return;

      if (widget.isDrillMode) {
        if (pin.trim() != AppConstants.drillSosPracticePin) {
          final l10n = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n
                    .get('wrong_pin_practice')
                    .replaceAll('{pin}', AppConstants.drillSosPracticePin),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              backgroundColor: AppColors.primaryDanger,
            ),
          );
          return;
        }
      } else {
        final storedHash = await _loadHashedPin();
        if (!context.mounted) return;

        if (storedHash == null || storedHash.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).get('no_sos_pin_set')),
              backgroundColor: AppColors.surfaceHighlight,
            ),
          );
          return;
        }

        final uid = _user?.uid ?? '';
        if (uid.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).get('sign_in_to_unlock')),
              backgroundColor: AppColors.surfaceHighlight,
            ),
          );
          return;
        }

        if (_pinHash(uid, pin) != storedHash) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).get('wrong_pin')),
              backgroundColor: AppColors.primaryDanger,
            ),
          );
          return;
        }
      }

      if (!context.mounted) return;
      final action = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.surface,
        showDragHandle: true,
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.get('sos_actions_title'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop('cancelled'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryDanger),
                    icon: const Icon(Icons.cancel_rounded, color: Colors.white),
                    label: Text(
                      l10n.get('sos_actions_cancel_false_alarm'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop('resolved'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySafe),
                    icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
                    label: Text(
                      l10n.get('sos_actions_mark_resolved_safe'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop('leave'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                    child: Text(l10n.get('sos_actions_unlock_and_leave')),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (!context.mounted || action == null) return;
      if (action == 'cancelled' || action == 'resolved') {
        if (!widget.isDrillMode) {
          await IncidentService.archiveAndCloseIncident(
            incidentId: widget.incidentId,
            status: action,
            closedByUid: _uid,
          );
          await IncidentService.clearActiveSos();
        }
        if (!context.mounted) return;
        if (!widget.isDrillMode) {
          context.go(
            '/incident-feedback/${Uri.encodeComponent(widget.incidentId)}?closed=${Uri.encodeComponent(action)}',
          );
        } else {
          context.go('/drill/dashboard');
        }
        return;
      }

      if (action == 'leave') {
        context.go(widget.isDrillMode ? '/drill/dashboard' : '/dashboard');
      }
    } finally {
      if (context.mounted) setState(() => _unlocking = false);
    }
  }

  Future<void> _sendTextUpdate() async {
    final text = _textUpdate.text.trim();
    if (text.isEmpty || _sendingUpdate) return;
    setState(() => _sendingUpdate = true);
    try {
      if (_livekitConnected && _livekitRoom != null) {
        // LiveKit path: publish to connected bridge listeners.
        await LivekitEmergencyBridgeService.sendImportantComms(
          room: _livekitRoom!,
          incidentId: widget.incidentId,
          text: text,
        );
      } else {
        // Fallback path: keep the old incident channel update for volunteers.
        await PttService.ensureChannel(widget.incidentId, 'SOS Emergency');
        await PttService.sendText(widget.incidentId, _uid, 'Victim', text);
      }
      _textUpdate.clear();
      if (context.mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _livekitConnected ? l10n.sosActiveUpdateSentLivekit : l10n.sosActiveUpdateSentChannel,
            ),
            backgroundColor: AppColors.primarySafe,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).sosActiveCouldNotSendUpdate),
            backgroundColor: AppColors.primaryDanger,
          ),
        );
      }
    } finally {
      if (context.mounted) setState(() => _sendingUpdate = false);
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;

    // WebRTC/LiveKit otherwise owns the mic; browser/device STT cannot hear the user.
    if (_livekitConnected && _livekitRoom != null) {
      await _pauseLivekitMicForStt();
    }

    if (!context.mounted) return;
    setState(() {
      _isRecording = true;
      _voiceNoteTranscript = '';
    });

    if (speechSupported()) {
      if (!kIsWeb) {
        try {
          final st = await Permission.microphone.status;
          if (!st.isGranted) {
            await Permission.microphone.request();
          }
        } catch (e) {
          debugPrint('[SOS] voice note mic permission: $e');
        }
      }
      startListening(
        _userBcp47,
        (t) {
          if (!context.mounted) return;
          setState(() => _voiceNoteTranscript = t);
        },
        () {},
        (_) {},
        () {},
      );
    }

    // Web fallback: record a short clip for the incident PTT channel when LiveKit is off.
    if (kIsWeb && !_livekitConnected) {
      try {
        victimRecordingStart();
      } catch (_) {}
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    setState(() => _isRecording = false);

    if (speechSupported()) stopListening();

    if (_livekitConnected && _livekitRoom != null) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      _scheduleResumeLivekitMic();
      final transcript = _voiceNoteTranscript.trim();
      _voiceNoteTranscript = '';
      if (transcript.isNotEmpty) {
        try {
          await LivekitEmergencyBridgeService.sendImportantComms(
            room: _livekitRoom!,
            incidentId: widget.incidentId,
            text: transcript,
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context).sosActiveVoiceTextSent),
                backgroundColor: AppColors.primarySafe,
              ),
            );
          }
        } catch (e) {
          debugPrint('[SOS] LiveKit voice update failed: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context).sosActiveCouldNotSendVoice),
                backgroundColor: AppColors.primaryDanger,
              ),
            );
          }
        }
      }
      return;
    }
    try {
      victimRecordingStop();
      await Future.delayed(const Duration(milliseconds: 600));
      final b64 = victimRecordingReadB64();
      if (b64 != null && b64.isNotEmpty) {
        await PttService.ensureChannel(widget.incidentId, 'SOS Emergency');
        final name = _user?.displayName ?? _user?.email?.split('@').first ?? 'Victim';
        await PttService.sendVoice(widget.incidentId, _uid, '$name (Victim)', b64);
        victimRecordingClearB64();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).sosActiveVoiceUpdateSent),
              backgroundColor: AppColors.primarySafe,
            ),
          );
        }
      }

      final transcript = _voiceNoteTranscript.trim();
      if (transcript.isNotEmpty) {
        if (_livekitConnected && _livekitRoom != null) {
          await LivekitEmergencyBridgeService.sendImportantComms(
            room: _livekitRoom!,
            incidentId: widget.incidentId,
            text: transcript,
          );
        } else {
          // Fallback: keep text in the incident channel and SMS relay.
          await PttService.sendText(widget.incidentId, _uid, 'Victim', transcript);
          final pos = _victimLatLng;
          if (pos != null) {
            await SmsGatewayService.sendSmsViaIntent(
              lat: pos.latitude,
              lng: pos.longitude,
              type: 'SOS_UPDATE',
              victimCount: 1,
              freeText: 'Victim voice transcript update',
              incidentId: widget.incidentId,
              channelText: transcript,
            );
          }
        }
      }

      if (!_postOpeningSafetyFlowStarted && transcript.isNotEmpty) {
        unawaited(_beginPostOpeningSafetyFlow(voiceNoteDetails: transcript));
      } else if (transcript.isNotEmpty) {
        final merged = _triageNotes.trim().isEmpty ? transcript : '${_triageNotes.trim()}\n$transcript';
        if (mounted) {
          setState(() {
            _triageNotes = merged;
            _triageNotesController.text = merged;
          });
          _scheduleTriageSave();
        }
      }
    } catch (e) {
      debugPrint('[SOS] stopRecording failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).sosActiveVoiceRecordFailed),
            backgroundColor: AppColors.primaryDanger,
          ),
        );
      }
    }
  }

  Future<void> _appendVictimActivity(String text) async {
    if (widget.isDrillMode || widget.incidentId.isEmpty || text.trim().isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('sos_incidents')
          .doc(widget.incidentId)
          .collection('victim_activity')
          .add({
        'text': text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[SOS] appendVictimActivity failed: $e');
    }
  }

  String _triageActivityLine() {
    final parts = <String>[];
    if (_triageUnconscious) {
      parts.add('Not conscious / unresponsive');
    } else if (_consciousVoiceMissCount > 0) {
      parts.add(
        'Conscious / responding · voice check misses $_consciousVoiceMissCount/$kConsciousVoiceMissesRequired (not unresponsive yet)',
      );
    } else {
      parts.add('Conscious / responding');
    }
    if (_triageBleeding) parts.add('severe bleeding');
    if (_triageBreathingTrouble) parts.add('breathing difficulty');
    if (_triageChestPain) parts.add('chest pain');
    if (_triageTrapped) parts.add('trapped');
    final notes = _triageNotes.trim();
    if (notes.isNotEmpty) parts.add('notes: $notes');
    return 'Victim update — ${parts.join(' · ')}';
  }

  void _scheduleTriageSave() {
    if (widget.isDrillMode) return;
    _triageDebounce?.cancel();
    _triageDebounce = Timer(const Duration(milliseconds: 550), () async {
      try {
        final flags = <String>[];
        if (_triageBleeding) flags.add('severe_bleeding');
        if (_triageBreathingTrouble) flags.add('breathing_trouble');
        if (_triageUnconscious) flags.add('unconscious');
        if (_triageChestPain) flags.add('chest_pain');
        if (_triageTrapped) flags.add('trapped');

        // Simple severity score for responder UI sorting (0-100).
        var score = 0;
        if (_triageBleeding) score += 40;
        if (_triageBreathingTrouble) score += 30;
        if (_triageUnconscious) score += 45;
        if (_triageChestPain) score += 25;
        if (_triageTrapped) score += 15;
        if (score > 100) score = 100;

        await FirebaseFirestore.instance.collection('sos_incidents').doc(widget.incidentId).set(
          {
            'triage': {
              'category': _triageCategory,
              'bleeding': _triageBleeding,
              'chestPain': _triageChestPain,
              'breathingTrouble': _triageBreathingTrouble,
              'unconscious': _triageUnconscious,
              'consciousVoiceMissCount': _consciousVoiceMissCount,
              'trapped': _triageTrapped,
              'notes': _triageNotes.trim(),
              'severityFlags': flags,
              'severityScore': score,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          },
          SetOptions(merge: true),
        );
        await _appendVictimActivity(_triageActivityLine());
      } catch (_) {}
    });
  }

  Set<Marker> _buildMapMarkers() {
    final markers = <Marker>{};
    final z = _victimMapZoom;
    final fbAz = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
    final victim = _victimLatLng;
    if (victim != null) {
      markers.add(Marker(
        markerId: const MarkerId('victim'),
        position: victim,
        zIndexInt: 10,
        infoWindow: const InfoWindow(title: 'You', snippet: 'Incident location'),
        icon: _victimPinIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
      if (!widget.isDrillMode && _ambulanceLivePos != null) {
        markers.add(Marker(
          markerId: const MarkerId('ambulance_live'),
          position: _ambulanceLivePos!,
          infoWindow: const InfoWindow(title: 'Ambulance', snippet: 'Live unit position'),
          icon: FleetMapIcons.ambulanceForZoom(z, fbAz),
          rotation: _ambulanceLiveHdg ?? 0,
          flat: true,
          anchor: const Offset(0.5, 0.5),
        ));
      } else if (widget.isDrillMode && _ambulancePath.length >= 2) {
        final t = _drillDispatchVehicleT.clamp(0.0, 1.0);
        final ambPos = _pointAlongPath(_ambulancePath, t);
        final ambAhead = _pointAlongPath(_ambulancePath, (t + 0.025).clamp(0.0, 1.0));
        final ambRot = _bearingDeg(ambPos, ambAhead);
        markers.add(Marker(
          markerId: const MarkerId('ambulance_drill'),
          position: ambPos,
          infoWindow: const InfoWindow(title: 'Ambulance (practice)', snippet: 'Following road route'),
          icon: FleetMapIcons.ambulanceForZoom(z, fbAz),
          rotation: ambRot,
          flat: true,
          anchor: const Offset(0.5, 0.5),
        ));
      } else if (_ambulancePath.length < 2) {
        final ambPos = LatLng(victim.latitude + 0.0025, victim.longitude + 0.0025);
        markers.add(Marker(
          markerId: const MarkerId('ambulance_cached'),
          position: ambPos,
          infoWindow: const InfoWindow(title: 'Ambulance (approx.)'),
          icon: FleetMapIcons.ambulanceForZoom(z, fbAz),
          rotation: _ambulanceSimulatedBearing,
          flat: true,
          anchor: const Offset(0.5, 0.5),
        ));
      }
      final vl = _volunteerLat;
      final vg = _volunteerLng;
      if (vl != null && vg != null) {
        markers.add(Marker(
          markerId: const MarkerId('volunteer_live'),
          position: LatLng(vl, vg),
          infoWindow: const InfoWindow(title: 'Responder', snippet: 'Assigned volunteer'),
          icon: _volunteerResponderPinIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ));
      }
    }
    final dispHospPos = _dispatchMapState?.notifiedHospitalPosition;
    final dispAccPos = _dispatchMapState?.acceptedHospitalPosition;
    final hospTarget = _dispatchMapState?.isAccepted == true ? dispAccPos : dispHospPos;
    if (hospTarget != null) {
      markers.add(Marker(
        markerId: const MarkerId('dispatch_hospital'),
        position: hospTarget,
        infoWindow: InfoWindow(
          title: _dispatchMapState?.isAccepted == true
              ? 'Accepted: ${_dispatchMapState?.currentHospitalName ?? ''}'
              : 'Trying: ${_dispatchMapState?.currentHospitalName ?? ''}',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          _dispatchMapState?.isAccepted == true
              ? BitmapDescriptor.hueGreen
              : BitmapDescriptor.hueOrange,
        ),
      ));
    }
    return markers;
  }

  Widget _dispatchPathLegendRow(Color lineColor, String label, int? routeMin, String? docEta) {
    final routed = routeMin != null ? '~$routeMin min (route)' : null;
    final doc = (docEta != null && docEta.isNotEmpty) ? docEta : null;
    final sub = [routed, doc].whereType<String>().join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(width: 14, height: 4, decoration: BoxDecoration(color: lineColor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11)),
                if (sub.isNotEmpty)
                  Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openHospitalDirections() async {
    final pos = _victimLatLng;
    final origin = pos == null ? '' : '${pos.latitude},${pos.longitude}';
    final url = Uri.parse(
      origin.isEmpty
          ? 'https://www.google.com/maps/dir/?api=1&destination=hospital'
          : 'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=hospital',
    );
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  String? _maskedEmergencyContactSuffix() {
    final p = _emergencyContactPhone;
    if (p == null || p.isEmpty) return null;
    if (p.length <= 4) return '••••';
    return '•••• ${p.substring(p.length - 4)}';
  }

  String? _maskedEmergencyContactEmailDisplay() {
    final e = _emergencyContactEmail;
    if (e == null || e.isEmpty) return null;
    final at = e.indexOf('@');
    if (at <= 0 || at >= e.length - 1) return '••••';
    final domain = e.substring(at + 1);
    return '••••@$domain';
  }

  String? _emergencyContactNotifySubtitle() {
    final phoneMask = _maskedEmergencyContactSuffix();
    final emailMask = _maskedEmergencyContactEmailDisplay();
    if (phoneMask == null && emailMask == null) return null;
    final buf = StringBuffer();
    if (phoneMask != null) {
      buf.write(
        _useEmergencyContactForSms
            ? 'Profile number $phoneMask · SMS relay enabled for key updates.'
            : 'Profile number $phoneMask on file for this SOS.',
      );
    }
    if (emailMask != null) {
      if (buf.isNotEmpty) buf.write(' ');
      if (phoneMask == null) {
        buf.write('Profile email $emailMask on file for this SOS.');
      } else {
        buf.write('Email $emailMask on file.');
      }
    }
    return buf.toString();
  }

  Widget _liveUpdateRow(IconData icon, Color color, String title, String? subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, height: 1.2),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact strip for victim mic / LiveKit bridge state (replaces hold-to-dictate control).
  Widget _buildLiveChannelMicStatusStrip() {
    final l10n = AppLocalizations.of(context);
    final IconData icon;
    final Color accent;
    final String label;
    final String detail;

    if (!_livekitConnected) {
      switch (_bridgeStatus) {
        case 'ptt_only':
          icon = Icons.phone_in_talk_rounded;
          accent = AppColors.primaryInfo;
          label = l10n.get('sos_active_mic_ptt_only');
          detail = l10n.get('sos_active_mic_ptt_only_detail');
        case 'failed':
          icon = Icons.mic_off_rounded;
          accent = AppColors.primaryDanger;
          label = l10n.get('sos_active_mic_failed');
          detail = l10n.get('sos_active_mic_failed_detail');
        case 'reconnecting':
          icon = Icons.sync_rounded;
          accent = AppColors.primaryWarning;
          label = l10n.get('sos_active_mic_reconnecting');
          detail = l10n.get('sos_active_mic_reconnecting_detail');
        case 'connecting':
          icon = Icons.mic_none_rounded;
          accent = AppColors.primaryWarning;
          label = l10n.get('sos_active_mic_connecting');
          detail = l10n.get('sos_active_mic_connecting_detail');
        default:
          icon = Icons.mic_none_rounded;
          accent = Colors.white38;
          label = l10n.get('sos_active_mic_standby');
          detail = l10n.get('sos_active_mic_standby_detail');
      }
    } else if (_livekitMicPausedForStt) {
      icon = Icons.mic_rounded;
      accent = AppColors.primaryWarning;
      label = l10n.get('sos_active_mic_interrupted');
      detail = l10n.get('sos_active_mic_interrupted_detail');
    } else {
      icon = Icons.mic_rounded;
      accent = AppColors.primarySafe;
      label = l10n.get('sos_active_mic_active');
      detail = l10n.get('sos_active_mic_active_detail');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _incidentDrivenLiveUpdateRows() {
    final l10n = AppLocalizations.of(context);
    final rows = <Widget>[];
    if (widget.isDrillMode) {
      rows.add(_liveUpdateRow(
        Icons.construction_rounded,
        Colors.amberAccent,
        'Practice SOS',
        'Timeline below is simulated. MAP tab shows demo routes for ambulance and volunteer.',
      ));
      for (final e in _drillTimeline) {
        rows.add(_liveUpdateRow(e.icon, e.color, e.title, e.subtitle));
      }
    } else {
      rows.add(_liveUpdateRow(
        Icons.podcasts_rounded,
        AppColors.primaryDanger,
        l10n.get('sos_active_live_sos_is_live_title'),
        l10n.get('sos_active_live_sos_is_live_detail'),
      ));
      rows.add(_liveUpdateRow(
        Icons.notifications_active_rounded,
        AppColors.primaryWarning,
        l10n.get('sos_active_live_volunteers_notified_title'),
        l10n.get('sos_active_live_volunteers_notified_detail'),
      ));

      final contactSub = _emergencyContactNotifySubtitle();
      if (contactSub != null) {
        rows.add(_liveUpdateRow(
          Icons.contact_phone_rounded,
          AppColors.primaryInfo,
          l10n.get('sos_active_live_contacts_notified_title'),
          contactSub,
        ));
      }
    }

    final st = _incidentStatus?.toLowerCase();
    if (st == 'dispatched') {
      rows.add(_liveUpdateRow(
        Icons.local_shipping_rounded,
        AppColors.primarySafe,
        l10n.get('sos_active_live_professional_dispatch_title'),
        l10n.get('sos_active_live_professional_dispatch_detail'),
      ));
    }

    final pttOnly =
        ref.watch(opsIntegrationRoutingProvider).whenOrNull(data: (v) => v.useFirebasePttOnly) ?? false;
    if (pttOnly) {
      rows.add(_liveUpdateRow(
        Icons.speaker_phone_rounded,
        AppColors.primaryInfo,
        l10n.get('sos_active_live_ptt_title'),
        l10n.get('sos_active_live_ptt_detail'),
      ));
    } else if (_livekitConnected) {
      rows.add(_liveUpdateRow(
        Icons.wifi_tethering_rounded,
        AppColors.primarySafe,
        l10n.get('sos_active_live_bridge_connected_title'),
        l10n.get('sos_active_live_bridge_connected_detail'),
      ));
    }

    final assign = _dispatchMapState?.assignment;
    if (assign != null && _dispatchMapState!.isAccepted) {
      rows.add(_liveUpdateRow(
        Icons.local_hospital_rounded,
        Colors.greenAccent,
        l10n.get('sos_active_live_hospital_accepted_title'),
        _dispatchMapState!.currentHospitalName,
      ));
      // Surface the Gemini-generated rationale for the current hospital pick
      // (written server-side by hospital_dispatch_v2 → dispatch_rationale.js).
      final rationaleText = _aiHospitalRationaleText;
      if (rationaleText != null && rationaleText.isNotEmpty) {
        rows.add(_liveUpdateRow(
          Icons.auto_awesome_rounded,
          const Color(0xFFBA68C8),
          'Why this hospital (Gemini)',
          rationaleText,
        ));
      }
    }
    final fleetCs = (assign?.assignedFleetCallSign ?? '').trim();
    if (fleetCs.isNotEmpty) {
      rows.add(_liveUpdateRow(
        Icons.local_shipping_rounded,
        AppColors.primaryInfo,
        l10n.get('sos_active_live_ambulance_unit_assigned_title'),
        l10n
            .get('sos_active_live_ambulance_unit_assigned_subtitle')
            .replaceAll('{unit}', fleetCs),
      ));
    }

    final amb = _ambulanceEta?.trim();
    if (_victimAmbulanceMinuteEtaVisible()) {
      final etaLine = amb != null && amb.isNotEmpty
          ? amb
          : (_routeEtaAmbMin != null
              ? l10n
                  .get('sos_active_live_ambulance_en_route_route_eta')
                  .replaceAll('{n}', '${_routeEtaAmbMin}')
              : l10n.get('sos_active_live_ambulance_en_route_default_eta'));
      rows.add(_liveUpdateRow(
        Icons.airport_shuttle_rounded,
        Colors.cyanAccent,
        l10n.get('sos_active_live_ambulance_en_route_title'),
        l10n
            .get('sos_active_live_ambulance_en_route_subtitle')
            .replaceAll('{eta}', etaLine),
      ));
    } else {
      final a = _dispatchMapState?.assignment;
      final ambSt = (a?.ambulanceDispatchStatus ?? '').trim();
      if (a != null &&
          (ambSt == 'pending_operator' ||
              (_dispatchMapState!.isAccepted && ambSt.isNotEmpty && ambSt != 'ambulance_en_route'))) {
        rows.add(_liveUpdateRow(
          Icons.hourglass_bottom_rounded,
          Colors.amberAccent,
          l10n.get('sos_active_live_ambulance_coordination_title'),
          ambSt == 'pending_operator'
              ? l10n.get('sos_active_live_ambulance_coordination_pending')
              : l10n.get('sos_active_live_ambulance_coordination_arranging'),
        ));
      }
    }

    final med = _medicalStatus?.trim();
    if (med != null && med.isNotEmpty) {
      rows.add(_liveUpdateRow(
        Icons.medical_information_rounded,
        Colors.lightGreenAccent,
        l10n.get('sos_active_live_responder_status_title'),
        med,
      ));
    }

    if (_acceptedCount > 0) {
      rows.add(_liveUpdateRow(
        Icons.volunteer_activism_rounded,
        AppColors.primarySafe,
        _acceptedCount == 1
            ? l10n.get('sos_active_live_volunteer_accepted_single_title')
            : l10n.get('sos_active_live_volunteer_accepted_many_title'),
        _acceptedCount == 1
            ? l10n.get('sos_active_live_volunteer_accepted_single_detail')
            : l10n
                .get('sos_active_live_volunteer_accepted_many_detail')
                .replaceAll('{n}', '$_acceptedCount'),
      ));
    }

    if (_onSceneVolunteerCount > 0) {
      rows.add(_liveUpdateRow(
        Icons.flag_rounded,
        Colors.orangeAccent,
        _onSceneVolunteerCount == 1
            ? l10n.get('sos_active_live_volunteer_on_scene_single_title')
            : l10n.get('sos_active_live_volunteer_on_scene_many_title'),
        _onSceneVolunteerCount == 1
            ? l10n.get('sos_active_live_volunteer_on_scene_single_detail')
            : l10n
                .get('sos_active_live_volunteer_on_scene_many_detail')
                .replaceAll('{n}', '$_onSceneVolunteerCount'),
      ));
    }

    final vLat = _volunteerLat;
    final vLng = _volunteerLng;
    if (vLat != null && vLng != null) {
      rows.add(_liveUpdateRow(
        Icons.navigation_rounded,
        AppColors.primaryInfo,
        l10n.get('sos_active_live_responder_location_title'),
        l10n.get('sos_active_live_responder_location_detail'),
      ));
    }

    return rows;
  }

  int _visibleBridgeParticipantCount() =>
      _bridgeParticipants.where((p) => p.role != _BridgeRole.lifeline).length;

  String _bridgeMicTitleLabel() {
    final l10n = AppLocalizations.of(context);
    final n = _visibleBridgeParticipantCount();
    final suffix = n == 0
        ? ''
        : l10n.get('sos_active_bridge_channel_on_suffix').replaceAll('{n}', '$n');
    if (_livekitConnected) return '${l10n.get('sos_active_bridge_channel_voice')}$suffix';
    if (_bridgeStatus == 'ptt_only') return '${l10n.get('sos_active_bridge_channel_ptt')}$suffix';
    if (_bridgeStatus == 'failed') return '${l10n.get('sos_active_bridge_channel_failed')}$suffix';
    if (_livekitStartAttempted) {
      return '${l10n.get('sos_active_bridge_channel_connecting')}$suffix';
    }
    return '${l10n.get('sos_active_bridge_channel_voice')}$suffix';
  }

  LatLng? get _dispatchHospitalTarget {
    final dispHospPos = _dispatchMapState?.notifiedHospitalPosition;
    final dispAccPos = _dispatchMapState?.acceptedHospitalPosition;
    return _dispatchMapState?.isAccepted == true ? dispAccPos : dispHospPos;
  }

  Set<Circle> _buildDispatchTierCircles() {
    final victim = _victimLatLng;
    if (victim == null) return const {};
    final tier = _dispatchMapState?.currentTier ?? 1;
    return {
      Circle(
        circleId: const CircleId('dispatch_tier1'),
        center: victim,
        radius: kDispatchTier1RadiusM,
        fillColor: Colors.red.withValues(alpha: 0.08),
        strokeColor: Colors.redAccent,
        strokeWidth: 2,
      ),
      Circle(
        circleId: const CircleId('dispatch_tier2'),
        center: victim,
        radius: kDispatchTier2RadiusM,
        fillColor: Colors.amber.withValues(alpha: tier >= 2 ? 0.06 : 0.02),
        strokeColor: Colors.amber,
        strokeWidth: 2,
      ),
      Circle(
        circleId: const CircleId('dispatch_tier3'),
        center: victim,
        radius: kDispatchTier3RadiusM,
        fillColor: Colors.blueGrey.withValues(alpha: tier >= 3 ? 0.05 : 0.01),
        strokeColor: Colors.blueGrey,
        strokeWidth: 2,
      ),
    };
  }

  /// Pulsing red/orange rings at the victim pin so an active SOS is obvious on the map.
  Set<Circle> _buildMapCircles() {
    final victim = _victimLatLng;
    if (victim == null) return const {};
    final base = _buildDispatchTierCircles();
    if (widget.isDrillMode) return base;
    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final pulse = 0.5 + 0.5 * math.sin(t * 3.0);
    final pulseSoft = 0.5 + 0.5 * math.sin(t * 2.2 + 0.9);
    return {
      ...base,
      Circle(
        circleId: const CircleId('sos_active_glow_outer'),
        center: victim,
        radius: 52 + 28 * pulse,
        fillColor: AppColors.primaryDanger.withValues(alpha: 0.11 * (0.35 + 0.65 * pulse)),
        strokeColor: AppColors.primaryDanger.withValues(alpha: 0.5 + 0.45 * pulse),
        strokeWidth: 2,
        zIndex: 2000,
      ),
      Circle(
        circleId: const CircleId('sos_active_glow_inner'),
        center: victim,
        radius: 26 + 16 * pulseSoft,
        fillColor: Colors.deepOrangeAccent.withValues(alpha: 0.15 * (0.45 + 0.55 * pulseSoft)),
        strokeColor: Colors.white.withValues(alpha: 0.28 + 0.35 * pulseSoft),
        strokeWidth: 1,
        zIndex: 2001,
      ),
    };
  }

  Widget _buildMapTab() {
    if (_victimLatLng == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primaryDanger),
            SizedBox(height: 16),
            Text('Acquiring location...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    return Stack(
      children: [
        EosHybridMap(
          ignoreRemoteLeafletTiles: false,
          googleMapLoadTimeout: kIsWeb ? const Duration(seconds: 8) : const Duration(seconds: 14),
          cameraTargetBounds: IndiaOpsZones.lucknowCameraTargetBounds,
          initialCameraPosition: IndiaOpsZones.lucknowSafeCamera(_victimLatLng, preferZoom: 15.0),
          onCameraMove: (CameraPosition p) {
            if (!context.mounted) return;
            if (FleetMapIcons.zoomTierChanged(_victimMapZoom, p.zoom)) {
              setState(() => _victimMapZoom = p.zoom);
            }
          },
          markers: _buildMapMarkers(),
          circles: _buildMapCircles(),
          polylines: {
            if (_ambulancePath.length >= 2)
              Polyline(
                polylineId: const PolylineId('victim_amb'),
                points: _ambulancePath,
                color: const Color(0xFFC62828),
                width: 7,
                zIndex: 2,
              ),
          },
          mapId: AppConstants.googleMapsDarkMapId.isNotEmpty ? AppConstants.googleMapsDarkMapId : null,
          style: effectiveGoogleMapsEmbeddedStyleJson(),
          myLocationEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
          onMapCreated: (ctrl) => _mapController = ctrl,
        ),
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.near_me_rounded, color: Colors.cyanAccent, size: 14),
                const SizedBox(width: 4),
                Text(
                  _dispatchRoutesLoading ? 'ROUTING…' : 'DISPATCH PATHS',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ],
            ),
          ),
        ),
        if (_dispatchMapState != null && _dispatchMapState!.assignment != null)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _dispatchMapState!.isAccepted
                      ? Colors.greenAccent
                      : _dispatchMapState!.isPendingAcceptance
                          ? Colors.orangeAccent
                          : Colors.white24,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dispatchMapState!.currentTierLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dispatchMapState!.isAccepted
                        ? 'Accepted: ${_dispatchMapState!.currentHospitalName}'
                        : 'Trying: ${_dispatchMapState!.currentHospitalName}',
                    style: TextStyle(
                      color: _dispatchMapState!.isAccepted ? Colors.greenAccent : Colors.orangeAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(AppLocalizations.of(context).sosActiveRoutesToYou,
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 10)),
                const SizedBox(height: 6),
                _dispatchPathLegendRow(
                  Colors.redAccent,
                  'Ambulance',
                  _victimAmbulanceMinuteEtaVisible() ? _routeEtaAmbMin : null,
                  _victimAmbulanceLegendDocEta(),
                ),
                _dispatchPathLegendRow(
                  AppColors.primarySafe,
                  'Volunteer',
                  _routeEtaVolMin,
                  _volunteerMapLegendCaption(),
                ),
              ],
            ),
          ),
        ),
        if (_areaIntel != null)
          Positioned(
            top: 40,
            left: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.analytics_rounded, color: Colors.amberAccent, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'AREA INTELLIGENCE',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(AppLocalizations.of(context).sosActiveAvgResponseTime,
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(width: 6),
                      Text(
                        '${_areaIntel!.avgResponseMinutes} mins',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(AppLocalizations.of(context).sosActiveRecentVolume,
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(width: 6),
                      Text(
                        '${_areaIntel!.totalPastIncidents} past incidents',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(AppLocalizations.of(context).sosActiveCongestionWarning,
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(width: 6),
                      Text(
                        _areaIntel!.riskScore > 50 ? 'High (Expect delays)' : 'Low',
                        style: TextStyle(
                            color: _areaIntel!.riskScore > 50 ? AppColors.primaryDanger : AppColors.primarySafe,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLiveUpdatesCard() {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.update_rounded, color: AppColors.primaryInfo, size: 16),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context).get('sos_active_live_updates_header'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10.5, letterSpacing: 0.8),
                ),
                const Spacer(),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.primarySafe,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  AppLocalizations.of(context).get('sos_active_live_tag'),
                  style: TextStyle(color: AppColors.primarySafe.withValues(alpha: 0.9), fontSize: 9, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              AppLocalizations.of(context).get('sos_active_live_updates_subtitle'),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 9, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ..._incidentDrivenLiveUpdateRows(),
            const Divider(height: 14, color: Colors.white12),
            Text(
              AppLocalizations.of(context).get('sos_active_activity_log'),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.42), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
            const SizedBox(height: 6),
            if (widget.incidentId.isEmpty)
              const Text('—', style: TextStyle(color: Colors.white38, fontSize: 11))
            else
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('sos_incidents')
                    .doc(widget.incidentId)
                    .collection('victim_activity')
                    .limit(24)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Loading…', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    );
                  }
                  if (snap.hasError) {
                    return Text('Log unavailable', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11));
                  }
                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Text(
                      'Triage updates appear here.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.32), fontSize: 9, height: 1.3),
                    );
                  }
                  int tsOf(QueryDocumentSnapshot<Map<String, dynamic>> d) {
                    final c = d.data()['createdAt'];
                    if (c is Timestamp) return c.millisecondsSinceEpoch;
                    return 0;
                  }

                  final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs)
                    ..sort((a, b) => tsOf(b).compareTo(tsOf(a)));
                  final show = sorted.take(4).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: show.map((d) {
                      final text = (d.data()['text'] as String?)?.trim() ?? '';
                      final c = d.data()['createdAt'];
                      String timeStr = '';
                      if (c is Timestamp) {
                        final t = c.toDate();
                        timeStr = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                      }
                      if (text.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (timeStr.isNotEmpty)
                              SizedBox(
                                width: 34,
                                child: Text(
                                  timeStr,
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.32), fontSize: 8.5, fontWeight: FontWeight.w700),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 9.5,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(opsIntegrationRoutingProvider);
    ref.listen<AsyncValue<OpsIntegrationRouting>>(
      opsIntegrationRoutingProvider,
      (prev, next) {
        if (widget.isDrillMode) return;
        final was = prev?.whenOrNull(data: (v) => v.useFirebasePttOnly) ?? false;
        final now = next.whenOrNull(data: (v) => v.useFirebasePttOnly) ?? false;
        if (was == now) return;
        if (now) {
          unawaited(() async {
            await _tearDownLiveKitForFirebasePttRouting();
            if (mounted) {
              setState(() {
                _bridgeStatus = 'ptt_only';
                _livekitStartAttempted = true;
              });
            }
          }());
        } else {
          _livekitStartAttempted = false;
          if (mounted) setState(() => _bridgeStatus = 'connecting');
          unawaited(_startLivekitEmergencyBridge());
        }
      },
    );

    ref.listen<Locale>(localeProvider, (prev, next) {
      if (prev?.languageCode == next.languageCode) return;
      VoiceCommsService.clearSpeakQueue();
    });

    final mins = _elapsed.inMinutes;
    final secs = _elapsed.inSeconds % 60;
    final timeStr = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    return DefaultTabController(
      length: 2,
      child: PopScope(
        canPop: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.isDrillMode ? 'SOS PRACTICE (DRILL)' : 'SOS ACTIVE',
                    style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 17),
                  ),
                  if (widget.isDrillMode) ...[
                    Text(
                      'No real dispatch · location not shared with responders',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.amberAccent.withValues(alpha: 0.95),
                        letterSpacing: 0.2,
                      ),
                    ),
                    // Drill PIN is intentionally *not* printed in the AppBar
                    // to avoid a visible cheat-code in demo reels. Long-press
                    // the drill banner to reveal.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: const Duration(seconds: 4),
                            backgroundColor: Colors.black87,
                            content: Text(
                              'Drill unlock PIN: ${AppConstants.drillSosPracticePin}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        );
                      },
                      child: Text(
                        'Long-press for practice unlock hint',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.cyanAccent.withValues(alpha: 0.75),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                const LanguageSwitcherButton(),
                IconButton(
                  tooltip: 'Stop speaking',
                  onPressed: VoiceCommsService.clearSpeakQueue,
                  icon: const Icon(Icons.volume_off_rounded),
                ),
                TextButton.icon(
                  onPressed: _unlocking ? null : _unlockAndCloseActions,
                  icon: const Icon(Icons.lock_open_rounded, color: Colors.white),
                  label: Text(_unlocking ? '...' : 'UNLOCK', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
              ],
              bottom: const TabBar(
                indicatorColor: AppColors.primaryDanger,
                labelColor: AppColors.primaryDanger,
                unselectedLabelColor: Colors.white70,
                tabs: [
                  Tab(text: 'STATUS', icon: Icon(Icons.warning_rounded)),
                  Tab(text: 'LIVE MAP', icon: Icon(Icons.near_me_rounded)),
                ],
              ),
            ),
            body: TabBarView(
              physics: const NeverScrollableScrollPhysics(), // Prevent swipe interference with map
              children: [
                // TAB 1: STATUS
                Stack(
                  fit: StackFit.expand,
                  children: [
                    SafeArea(
                      child: Column(
                        children: [
                          if (_offlineSosSyncBanner && !widget.isDrillMode)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              child: Semantics(
                                label:
                                    'SOS is queued on this device. It will sync to responders when you are back online.',
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.orangeAccent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.35)),
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.cloud_upload_outlined, color: Colors.orangeAccent, size: 22),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'SOS is saved on this device and will sync to responders when you are back online. '
                                          'Keep the app open; reconnect on Wi‑Fi or mobile data when you can.',
                                          style: TextStyle(
                                            color: Colors.orangeAccent.shade100,
                                            fontSize: 12,
                                            height: 1.35,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: _StatusHeader(
                              timeStr: timeStr,
                              acceptedCount: _acceptedCount,
                              onSceneVolunteerCount: _onSceneVolunteerCount,
                              ambulanceEta: _victimAmbulanceHeaderStat(),
                              medicalStatus: _medicalStatus,
                            ),
                          ),
                          if (!widget.isDrillMode && (_emsWorkflowPhase ?? '') == 'on_scene')
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: Semantics(
                                label: AppLocalizations.of(context)
                                    .get('sos_active_ambulance_200m_semantic_label'),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF004D40).withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.5)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.medical_services_rounded, color: Colors.tealAccent, size: 26),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          AppLocalizations.of(context)
                                              .get('sos_active_ambulance_200m_detail'),
                                          style: TextStyle(
                                            color: Colors.tealAccent.withValues(alpha: 0.95),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: _DispatchChainStatusStrip(
                              incidentId: widget.incidentId,
                              onSpeakGuidance: _speakGuidance,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Semantics(
                              label:
                                  'Battery tip: position updates about every 45 seconds while SOS is active to reduce battery use.',
                              child: Text(
                                widget.isDrillMode
                                    ? 'Practice mode: voice prompts run as normal; nothing is sent to real responders.'
                                    : AppLocalizations.of(context)
                                        .get('sos_active_position_refresh_note'),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 11.5,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: ListView(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                children: [
                                      const SizedBox(height: 4),
                                      Theme(
                                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                                        child: Material(
                                          color: AppColors.surface,
                                          borderRadius: BorderRadius.circular(12),
                                          child: ExpansionTile(
                                            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                                            initiallyExpanded: true,
                                            title: Row(
                                              children: [
                                                // Pulse-dot status indicator —
                                                // replaces the emoji blobs with a
                                                // sized colour dot that reads as
                                                // a real systems console.
                                                Container(
                                                  width: 10,
                                                  height: 10,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: _livekitConnected
                                                        ? AppColors.primarySafe
                                                        : _bridgeStatus == 'failed'
                                                            ? AppColors.primaryDanger
                                                            : _bridgeStatus == 'ptt_only'
                                                                ? AppColors.primaryInfo
                                                                : AppColors.primaryWarning,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: (_livekitConnected
                                                                ? AppColors.primarySafe
                                                                : _bridgeStatus == 'failed'
                                                                    ? AppColors.primaryDanger
                                                                    : _bridgeStatus == 'ptt_only'
                                                                        ? AppColors.primaryInfo
                                                                        : AppColors.primaryWarning)
                                                            .withValues(alpha: 0.55),
                                                        blurRadius: 6,
                                                        spreadRadius: 1,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Icon(
                                                  _bridgeStatus == 'failed'
                                                      ? Icons.wifi_tethering_error_rounded
                                                      : _bridgeStatus == 'ptt_only'
                                                          ? Icons.phone_in_talk_rounded
                                                          : Icons.wifi_tethering_rounded,
                                                  color: _livekitConnected
                                                      ? AppColors.primarySafe
                                                      : _bridgeStatus == 'failed'
                                                          ? AppColors.primaryDanger
                                                          : _bridgeStatus == 'ptt_only'
                                                              ? AppColors.primaryInfo
                                                              : AppColors.primaryWarning,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  _bridgeMicTitleLabel(),
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                                                ),
                                              ],
                                            ),
                                            subtitle: null,
                                            children: [
                                              Text(
                                                _voiceCommsBrief,
                                                style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11, height: 1.35, fontWeight: FontWeight.w600),
                                              ),
                                              const SizedBox(height: 10),
                                              if (_emergencyTypeSelected &&
                                                  !_livekitConnected &&
                                                  _bridgeStatus != 'failed' &&
                                                  _bridgeStatus != 'ptt_only' &&
                                                  !_livekitStartAttempted)
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 8),
                                                  child: Text(
                                                    'Joining the emergency voice channel…',
                                                    style: TextStyle(
                                                      color: Colors.white.withValues(alpha: 0.5),
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              if (_bridgeStatus == 'failed')
                                                Padding(
                                                  padding: const EdgeInsets.only(bottom: 8),
                                                  child: OutlinedButton.icon(
                                                    onPressed: () {
                                                      setState(() {
                                                        _bridgeStatus = 'connecting';
                                                        _livekitStartAttempted = false;
                                                      });
                                                      _startLivekitEmergencyBridge();
                                                    },
                                                    icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 18),
                                                    label: const Text('RETRY', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 11)),
                                                  ),
                                                ),
                                              if (_visibleBridgeParticipantCount() > 0)
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: _bridgeParticipants
                                                      .where((p) => p.role != _BridgeRole.lifeline)
                                                      .map(
                                                        (p) => Container(
                                                          padding: const EdgeInsets.symmetric(
                                                              horizontal: 8, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: p.isSpeaking
                                                                ? AppColors.primarySafe
                                                                    .withValues(alpha: 0.18)
                                                                : Colors.white
                                                                    .withValues(alpha: 0.06),
                                                            borderRadius:
                                                                BorderRadius.circular(20),
                                                            border: Border.all(
                                                              color: p.isSpeaking
                                                                  ? AppColors.primarySafe
                                                                      .withValues(alpha: 0.6)
                                                                  : Colors.white
                                                                      .withValues(alpha: 0.12),
                                                              width: 1,
                                                            ),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              Icon(
                                                                _BridgeParticipant.iconForRole(p.role),
                                                                size: 14,
                                                                color: p.isSpeaking
                                                                    ? AppColors.primarySafe
                                                                    : Colors.white
                                                                        .withValues(alpha: 0.72),
                                                              ),
                                                              const SizedBox(width: 6),
                                                              Text(
                                                                _BridgeParticipant.shortLabelForRole(p.role),
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  fontWeight: FontWeight.w700,
                                                                  color: p.isSpeaking
                                                                      ? AppColors.primarySafe
                                                                      : Colors.white
                                                                          .withValues(alpha: 0.78),
                                                                ),
                                                              ),
                                                              if (p.isSpeaking) ...[
                                                                const SizedBox(width: 4),
                                                                const Icon(
                                                                  Icons.graphic_eq_rounded,
                                                                  size: 12,
                                                                  color:
                                                                      AppColors.primarySafe,
                                                                ),
                                                              ],
                                                            ],
                                                          ),
                                                        ),
                                                      )
                                                      .toList(),
                                                )
                                              else if (_livekitConnected)
                                                Row(
                                                  children: [
                                                    SizedBox(
                                                      width: 12,
                                                      height: 12,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white
                                                            .withValues(alpha: 0.55),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      'Waiting for responders…',
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withValues(alpha: 0.6),
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      if (_livekitStartAttempted ||
                                          _livekitConnected ||
                                          _bridgeStatus == 'ptt_only') ...[
                                        _buildLiveChannelMicStatusStrip(),
                                        if (_livekitConnected)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 6),
                                            child: Text(
                                              AppLocalizations.of(context)
                                                  .get('sos_active_consciousness_note'),
                                              style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 9, height: 1.25),
                                            ),
                                          ),
                                      ],
                                      const SizedBox(height: 12),
                                      _buildLiveUpdatesCard(),
                                      if (!_userStoppedAllQuestions)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Text(
                                            'Consciousness checks every 60 seconds. Three missed checks in a row marks you unresponsive for responders.',
                                            style: TextStyle(color: Colors.white.withValues(alpha: 0.36), fontSize: 10, height: 1.35),
                                          ),
                                        ),
                                      const SizedBox(height: 12),
                                      if (!_isQaRunning && _qaPrompt.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 12),
                                          child: Text(
                                            _qaPrompt,
                                            style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 15, height: 1.35, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      if (!_isQaRunning && _interviewAnswers.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 10),
                                          child: Text(
                                            '${_interviewAnswers.length} responses saved for responders.',
                                            style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                    if (_isQaRunning)
                      Positioned.fill(
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.94),
                          child: SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextButton(
                                    onPressed: _stopQuestionsFlow,
                                    child: Text(
                                      'Stop questions',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.65),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        decoration: TextDecoration.underline,
                                        decorationColor: Colors.white.withValues(alpha: 0.45),
                                      ),
                                    ),
                                  ),
                                  if (_interviewStep >= 0 &&
                                      _frozenInterviewFlow != null &&
                                      _interviewStep < _frozenInterviewFlow!.length)
                                    Text(
                                      'QUESTION ${_interviewStep + 1} / ${_frozenInterviewFlow!.length}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.primaryInfo.withValues(alpha: 0.95),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  if (_interviewStep >= 0) const SizedBox(height: 10),
                                  Expanded(
                                    child: Center(
                                      child: SingleChildScrollView(
                                        child: Text(
                                          _qaPrompt.isEmpty ? '…' : _qaPrompt,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 32,
                                            fontWeight: FontWeight.w800,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    _chipOptionsForInterview.isNotEmpty
                                        ? 'Tap an option · $_responseCountdown s'
                                        : 'Tap YES or NO · $_responseCountdown s',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 15, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 14),
                                  if (_chipOptionsForInterview.isNotEmpty)
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      alignment: WrapAlignment.center,
                                      children: List<Widget>.generate(_chipOptionsForInterview.length, (i) {
                                        final canonical = _chipOptionsForInterview[i];
                                        final display = i < _chipLabelsForInterview.length
                                            ? _chipLabelsForInterview[i]
                                            : canonical;
                                        return ActionChip(
                                          label: Text(
                                            display,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                          ),
                                          onPressed: (_isQaRunning && _qaPromptHeard)
                                              ? () {
                                                  final k = _currentChipQuestionKey ??
                                                      (_frozenInterviewFlow != null &&
                                                              _interviewStep >= 0 &&
                                                              _interviewStep < _frozenInterviewFlow!.length
                                                          ? _frozenInterviewFlow![_interviewStep]['key']
                                                          : null);
                                                  if (k == null) return;
                                                  if (k == EmergencyVoiceInterviewQuestions.q1EmergencyTypeKey &&
                                                      canonical ==
                                                          EmergencyVoiceInterviewQuestions
                                                              .otherEmergencyTypeChipLabel) {
                                                    _showOtherEmergencyTypeDialog();
                                                    return;
                                                  }
                                                  _handleInterviewAnswer(k, canonical);
                                                }
                                              : null,
                                        );
                                      }),
                                    )
                                  else
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: (_isQaRunning && _qaPromptHeard)
                                                ? () {
                                                    if (_interviewStep >= 0 &&
                                                        _frozenInterviewFlow != null &&
                                                        _interviewStep < _frozenInterviewFlow!.length) {
                                                      _handleInterviewAnswer(
                                                          _frozenInterviewFlow![_interviewStep]['key']!, 'yes');
                                                    } else {
                                                      _handleQaAnswer(true);
                                                    }
                                                  }
                                                : null,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.primarySafe,
                                              minimumSize: const Size.fromHeight(88),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                            ),
                                            child: const Text('YES', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: Colors.white)),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: (_isQaRunning && _qaPromptHeard)
                                                ? () {
                                                    if (_interviewStep >= 0 &&
                                                        _frozenInterviewFlow != null &&
                                                        _interviewStep < _frozenInterviewFlow!.length) {
                                                      _handleInterviewAnswer(
                                                          _frozenInterviewFlow![_interviewStep]['key']!, 'no');
                                                    } else {
                                                      _handleQaAnswer(false);
                                                    }
                                                  }
                                                : null,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.primaryDanger,
                                              minimumSize: const Size.fromHeight(88),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                            ),
                                            child: const Text('NO', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: Colors.white)),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // TAB 2: MAP
                _buildMapTab(),
              ],
            ),
        ),
            if (_webVoiceGateVisible)
              Positioned.fill(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.82),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Header
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.primaryDanger.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.primaryDanger.withValues(alpha: 0.45), width: 2),
                              ),
                              child: const Icon(Icons.sos_rounded, size: 42, color: AppColors.primaryDanger),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Choose your SOS mode',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.97),
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Your browser requires one tap to activate audio. Choose how you want to receive emergency guidance.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.60),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 28),
                            // Voice-Guided button
                            SizedBox(
                              width: double.infinity,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _onWebVoiceGateTapped,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          AppColors.primarySafe.withValues(alpha: 0.25),
                                          AppColors.primarySafe.withValues(alpha: 0.12),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AppColors.primarySafe.withValues(alpha: 0.55),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: AppColors.primarySafe.withValues(alpha: 0.18),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.volume_up_rounded, color: AppColors.primarySafe, size: 26),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Voice-Guided Mode',
                                                  style: TextStyle(
                                                    color: AppColors.primarySafe,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  'Spoken safety prompts, questions & alerts',
                                                  style: TextStyle(
                                                    color: Colors.white.withValues(alpha: 0.65),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(Icons.arrow_forward_ios_rounded, color: AppColors.primarySafe.withValues(alpha: 0.7), size: 16),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            // Silence Mode button
                            SizedBox(
                              width: double.infinity,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _onWebSilenceModeTapped,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.065),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.18),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.08),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(Icons.volume_off_rounded, color: Colors.white.withValues(alpha: 0.75), size: 26),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Silence Mode',
                                                  style: TextStyle(
                                                    color: Colors.white.withValues(alpha: 0.85),
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  'Visual-only — no audio will play',
                                                  style: TextStyle(
                                                    color: Colors.white.withValues(alpha: 0.50),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withValues(alpha: 0.35), size: 16),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'You can change this anytime from the SOS screen',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ValueListenableBuilder<String?>(
              valueListenable: VoiceCommsService.ttsStatusNotifier,
              builder: (context, msg, _) {
                if (msg == null || msg.isEmpty) return const SizedBox.shrink();
                return Positioned(
                  top: MediaQuery.paddingOf(context).top + 6,
                  left: 12,
                  right: 12,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.deepOrange.shade900.withValues(alpha: 0.94),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(
                        msg,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final String timeStr;
  final int acceptedCount;
  final int onSceneVolunteerCount;
  final String? ambulanceEta;
  final String? medicalStatus;

  const _StatusHeader({
    required this.timeStr,
    required this.acceptedCount,
    required this.onSceneVolunteerCount,
    required this.ambulanceEta,
    required this.medicalStatus,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dash = l10n.get('sos_active_dash');
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.surfaceGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sos_rounded, color: AppColors.primaryDanger, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.get('sos_active_title_big'),
                      style: const TextStyle(color: AppColors.primaryDanger, fontWeight: FontWeight.w900, fontFamily: 'monospace', fontSize: 24, letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.get('sos_active_help_coming'),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (acceptedCount > 0 ? AppColors.primarySafe : AppColors.primaryDanger).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: (acceptedCount > 0 ? AppColors.primarySafe : AppColors.primaryDanger).withValues(alpha: 0.7)),
                ),
                child: Text(
                  acceptedCount > 0
                      ? l10n
                          .get('sos_active_badge_en_route_count')
                          .replaceAll('{n}', '$acceptedCount')
                      : l10n.get('sos_active_badge_waiting'),
                  style: TextStyle(
                    color: acceptedCount > 0 ? AppColors.primarySafe : AppColors.primaryDanger,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MiniStat(
                label: l10n.get('sos_active_mini_ambulance'),
                value: ambulanceEta ?? dash,
              ),
              _MiniStat(
                label: l10n.get('sos_active_mini_on_scene'),
                value: onSceneVolunteerCount <= 0
                    ? '0'
                    : l10n
                        .get('sos_active_volunteers_count_short')
                        .replaceAll('{n}', '$onSceneVolunteerCount'),
              ),
              _MiniStat(
                label: l10n.get('sos_active_mini_status'),
                value: medicalStatus ?? dash,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DispatchChainStatusStrip extends StatefulWidget {
  final String incidentId;
  final void Function(String text)? onSpeakGuidance;

  const _DispatchChainStatusStrip({
    required this.incidentId,
    this.onSpeakGuidance,
  });

  @override
  State<_DispatchChainStatusStrip> createState() => _DispatchChainStatusStripState();
}

class _DispatchChainStatusStripState extends State<_DispatchChainStatusStrip> {
  bool _consciousConfirmedOnce = false;
  bool _interviewCompleted = false;
  String? _intakeMode;
  String? _lastSpokenPhase;
  String? _lastSpokenHospital;
  int? _lastSpokenTier;
  StreamSubscription<DispatchChainState>? _dispatchSpeakSub;

  @override
  void initState() {
    super.initState();
    _dispatchSpeakSub = DispatchChainService.watchForIncident(widget.incidentId).listen((state) {
      if (!mounted) return;
      final assignment = state.assignment;
      final status = state.status;
      if (assignment == null || status == 'none') return;
      _maybeSpeak(state);
    });
  }

  @override
  void dispose() {
    _dispatchSpeakSub?.cancel();
    super.dispose();
  }

  void _maybeSpeak(DispatchChainState state) {
    final speak = widget.onSpeakGuidance;
    if (speak == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    final status = state.status;
    final hospName = state.currentHospitalName;
    final tier = state.currentTier;

    if (status == 'pending_acceptance' && _lastSpokenHospital != hospName) {
      _lastSpokenHospital = hospName;
      if (_lastSpokenTier != tier) {
        _lastSpokenTier = tier;
        if (tier == 1) {
          speak(
            l10n
                .get('sos_dispatch_alerting_nearest_trying')
                .replaceAll('{hospital}', hospName),
          );
        } else {
          speak(
            l10n
                .get('sos_dispatch_escalating_tier_trying')
                .replaceAll('{tier}', '$tier')
                .replaceAll('{hospital}', hospName),
          );
        }
      } else {
        speak(
          l10n
              .get('sos_dispatch_retry_previous_trying')
              .replaceAll('{hospital}', hospName),
        );
      }
    }
    if (status == 'accepted' && _lastSpokenPhase != 'accepted') {
      _lastSpokenPhase = 'accepted';
      speak(
        l10n
            .get('volunteer_dispatch_hospital_accepted')
            .replaceAll('{hospital}', hospName),
      );
    }
    if (status == 'exhausted' && _lastSpokenPhase != 'exhausted') {
      _lastSpokenPhase = 'exhausted';
      speak(l10n.get('sos_dispatch_all_hospitals_call_112'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<DispatchChainState>(
      stream: DispatchChainService.watchForIncident(widget.incidentId),
      builder: (context, snap) {
        final state = snap.data;
        if (state == null) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(
              l10n.get('sos_active_dispatch_contact_hospitals_default'),
              style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35),
            ),
          );
        }
        final assignment = state.assignment;
        final status = state.status;
        if (assignment == null || status == 'none') {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(
              l10n.get('sos_active_dispatch_contact_hospitals_default'),
              style: const TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.35),
            ),
          );
        }

        final hospName = state.currentHospitalName;
        final tierLabel = state.currentTierLabel;
        final countdown = state.countdownSecondsRemaining;
        final ambSt = (assignment.ambulanceDispatchStatus ?? '').trim();
        String title;
        String subtitle;
        Color? tierColor;

        if (ambSt == 'pending_operator') {
          title = l10n.get('sos_active_dispatch_ambulance_crew_notified_title');
          subtitle =
              l10n.get('sos_active_dispatch_ambulance_crew_notified_subtitle');
        } else if (ambSt == 'ambulance_en_route') {
          title = l10n.get('sos_active_dispatch_ambulance_confirmed_title');
          final unit = (assignment.assignedFleetCallSign ?? '').trim();
          subtitle = unit.isNotEmpty
              ? l10n
                  .get('sos_active_dispatch_ambulance_confirmed_subtitle_unit')
                  .replaceAll('{unit}', unit)
              : l10n
                  .get('sos_active_dispatch_ambulance_confirmed_subtitle_generic');
        } else if (ambSt == 'no_operator') {
          title = l10n.get('sos_active_dispatch_ambulance_handoff_delayed_title');
          subtitle =
              l10n.get('sos_active_dispatch_ambulance_handoff_delayed_subtitle');
        } else {
          switch (status) {
            case 'pending_acceptance':
              title = l10n
                  .get('sos_active_dispatch_pending_title_trying')
                  .replaceAll('{hospital}', hospName);
              subtitle = l10n
                  .get('sos_active_dispatch_pending_subtitle_waiting')
                  .replaceAll('{tier}', tierLabel);
              tierColor = state.currentTier == 1
                  ? Colors.redAccent
                  : state.currentTier == 2
                      ? Colors.amber
                      : Colors.blueGrey;
              break;
            case 'accepted':
              title = l10n
                  .get('sos_active_dispatch_accepted_title')
                  .replaceAll('{hospital}', hospName);
              subtitle = l10n.get('sos_active_dispatch_accepted_subtitle');
              tierColor = Colors.greenAccent;
              break;
            case 'exhausted':
              title = 'No Hospital Available';
              subtitle = 'All nearby hospitals declined. Please call 102 immediately for a government ambulance.';
              tierColor = AppColors.primaryDanger;
              break;
            default:
              title = l10n.get('sos_active_dispatch_generic_title');
              subtitle = l10n
                  .get('sos_active_dispatch_generic_subtitle')
                  .replaceAll('{hospital}', hospName)
                  .replaceAll('{status}', status);
              break;
          }
        }

        final countdownStr = countdown != null && countdown > 0
            ? '${(countdown ~/ 60).toString().padLeft(2, '0')}:${(countdown % 60).toString().padLeft(2, '0')}'
            : null;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: tierColor?.withValues(alpha: 0.5) ?? Colors.white10,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                status == 'accepted'
                    ? Icons.check_circle_rounded
                    : Icons.local_hospital_rounded,
                color: tierColor ?? Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: tierColor ?? Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                    if (status == 'exhausted') ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => launchUrl(Uri.parse('tel:102')),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryDanger,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.call, size: 18),
                        label: const Text(
                          'Call 102',
                          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (countdownStr != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: (countdown != null && countdown <= 30)
                        ? AppColors.primaryDanger.withValues(alpha: 0.25)
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    countdownStr,
                    style: TextStyle(
                      color: (countdown != null && countdown <= 30)
                          ? AppColors.primaryDanger
                          : Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _PlaceholderCard({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Colors.white60, height: 1.35)),
        ],
      ),
    );
  }
}

class _ChannelTab extends StatelessWidget {
  final String incidentId;
  final String uid;
  final VoidCallback onStartRecording;
  final Future<void> Function() onStopRecording;
  final bool isRecording;
  final TextEditingController textController;
  final bool sending;
  final Future<void> Function() onSendText;

  const _ChannelTab({
    required this.incidentId,
    required this.uid,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.isRecording,
    required this.textController,
    required this.sending,
    required this.onSendText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder(
            stream: PttService.watchMessages(incidentId),
            builder: (context, snap) {
              final msgs = (snap.data ?? const []);
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: msgs.length,
                itemBuilder: (context, i) {
                  final m = msgs[i];
                  final isMe = m.senderId == uid;
                  final bg = isMe ? AppColors.primarySafe.withValues(alpha: 0.12) : Colors.white10;
                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.senderName,
                            style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          if ((m.text ?? '').isNotEmpty)
                            Text(m.text!, style: const TextStyle(color: Colors.white, height: 1.3)),
                          if ((m.audioBase64 ?? '').isNotEmpty)
                            const Text('🎙️ Voice message', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: Colors.white10)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: textController,
                      style: const TextStyle(color: Colors.white),
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Send a quick update…',
                        hintStyle: TextStyle(color: Colors.white38),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: sending ? null : onSendText,
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTapDown: (_) => onStartRecording(),
                onTapUp: (_) => onStopRecording(),
                onTapCancel: () => onStopRecording(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isRecording
                          ? [const Color(0xFFB71C1C), const Color(0xFF880E4F)]
                          : [const Color(0xFF1A1A2E), const Color(0xFF0D0D20)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isRecording ? AppColors.primaryDanger : Colors.white24,
                      width: isRecording ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(isRecording ? Icons.mic_rounded : Icons.mic_none_rounded, color: Colors.white),
                      const SizedBox(width: 10),
                      Text(
                        isRecording ? 'RECORDING — RELEASE TO SEND' : 'HOLD TO SEND VOICE',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.1),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => context.push('/ptt-channel/$incidentId?type=SOS+Emergency'),
                icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70),
                label: const Text('OPEN FULL CHANNEL', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MapTab extends StatelessWidget {
  final LatLng? victimLatLng;
  final Set<Marker> markers;
  final void Function(OpsMapController) onMapCreated;
  final Future<void> Function() onOpenHospitalDirections;

  const _MapTab({
    required this.victimLatLng,
    required this.markers,
    required this.onMapCreated,
    required this.onOpenHospitalDirections,
  });

  @override
  Widget build(BuildContext context) {
    final center = victimLatLng ?? const LatLng(0, 0);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          height: 320,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          clipBehavior: Clip.antiAlias,
          child: EosHybridMap(
            ignoreRemoteLeafletTiles: false,
            googleMapLoadTimeout: kIsWeb ? const Duration(seconds: 8) : const Duration(seconds: 14),
            cameraTargetBounds: IndiaOpsZones.lucknowCameraTargetBounds,
            initialCameraPosition: victimLatLng == null
                ? IndiaOpsZones.lucknowCameraPosition(zoom: IndiaOpsZones.lucknow.defaultZoom)
                : IndiaOpsZones.lucknowSafeCamera(victimLatLng, preferZoom: 15),
            markers: markers,
            mapType: MapType.normal,
            mapId: AppConstants.googleMapsDarkMapId.isNotEmpty ? AppConstants.googleMapsDarkMapId : null,
            style: effectiveGoogleMapsEmbeddedStyleJson(),
            onMapCreated: onMapCreated,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
        ),
        const SizedBox(height: 12),
        _PlaceholderCard(
          title: 'Nearest hospital guidance',
          subtitle: 'If you can safely move, tap below to open directions to a hospital near you.',
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: onOpenHospitalDirections,
          icon: const Icon(Icons.local_hospital_rounded, color: Colors.white),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primarySafe, minimumSize: const Size(double.infinity, 52)),
          label: const Text('OPEN HOSPITAL DIRECTIONS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => context.push('/map'),
          icon: const Icon(Icons.near_me_rounded, color: Colors.white70),
          label: const Text('OPEN FULL MAP (IN-APP)', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _TriageTab extends StatelessWidget {
  final String category;
  final ValueChanged<String> onCategoryChanged;
  final bool bleeding;
  final ValueChanged<bool> onBleedingChanged;
  final bool chestPain;
  final ValueChanged<bool> onChestPainChanged;
  final bool breathingTrouble;
  final ValueChanged<bool> onBreathingTroubleChanged;
  final bool unconscious;
  final ValueChanged<bool> onUnconsciousChanged;
  final bool trapped;
  final ValueChanged<bool> onTrappedChanged;
  final TextEditingController notesController;
  final ValueChanged<String> onNotesChanged;

  const _TriageTab({
    required this.category,
    required this.onCategoryChanged,
    required this.bleeding,
    required this.onBleedingChanged,
    required this.chestPain,
    required this.onChestPainChanged,
    required this.breathingTrouble,
    required this.onBreathingTroubleChanged,
    required this.unconscious,
    required this.onUnconsciousChanged,
    required this.trapped,
    required this.onTrappedChanged,
    required this.notesController,
    required this.onNotesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PlaceholderCard(
          title: 'Triage for responders',
          subtitle: 'Answer these quickly. Responders will see this context live.',
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Incident category', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: category,
                dropdownColor: AppColors.surfaceHighlight,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                items: const ['Medical', 'Fire', 'Traffic', 'Violence', 'Disaster']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(color: Colors.white))))
                    .toList(),
                onChanged: (v) => onCategoryChanged(v ?? 'Medical'),
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Severe bleeding', style: TextStyle(color: Colors.white)),
                value: bleeding,
                activeColor: AppColors.primaryDanger,
                onChanged: onBleedingChanged,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Chest pain / heart symptoms', style: TextStyle(color: Colors.white)),
                value: chestPain,
                activeColor: AppColors.primaryDanger,
                onChanged: onChestPainChanged,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Breathing trouble', style: TextStyle(color: Colors.white)),
                value: breathingTrouble,
                activeColor: AppColors.primaryDanger,
                onChanged: onBreathingTroubleChanged,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Unconscious / not responding', style: TextStyle(color: Colors.white)),
                value: unconscious,
                activeColor: AppColors.primaryDanger,
                onChanged: onUnconsciousChanged,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Trapped / cannot move safely', style: TextStyle(color: Colors.white)),
                value: trapped,
                activeColor: AppColors.primaryDanger,
                onChanged: onTrappedChanged,
              ),
              const SizedBox(height: 10),
              const Text('Extra notes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              TextField(
                controller: notesController,
                onChanged: onNotesChanged,
                minLines: 3,
                maxLines: 6,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Hazards, landmarks, number of people, symptoms…',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Participant model for the voice bridge UI.
enum _BridgeRole { lifeline, emergencyDesk, emergencyContact, volunteerElite, acceptedVolunteer, victim, unknown }

class _BridgeParticipant {
  final String identity;
  final _BridgeRole role;
  final String displayName;
  final bool isSpeaking;

  const _BridgeParticipant({
    required this.identity,
    required this.role,
    required this.displayName,
    this.isSpeaking = false,
  });

  static _BridgeRole roleFromIdentity(String id) {
    // Prefixes first — a Firebase UID can contain substrings like "agent".
    if (id.startsWith('vol_elite_')) return _BridgeRole.volunteerElite;
    if (id.startsWith('volunteer_')) return _BridgeRole.acceptedVolunteer;
    if (id.startsWith('victim_')) return _BridgeRole.victim;
    if (id.startsWith('ems_')) return _BridgeRole.emergencyDesk;
    if (id.startsWith('contact_')) return _BridgeRole.emergencyContact;
    if (id.startsWith('lifeline') || id.contains('agent')) return _BridgeRole.lifeline;
    return _BridgeRole.unknown;
  }

  static String emojiForRole(_BridgeRole role) {
    switch (role) {
      case _BridgeRole.lifeline:
        return '🤖';
      case _BridgeRole.emergencyDesk:
        return '🚑';
      case _BridgeRole.emergencyContact:
        return '📞';
      case _BridgeRole.volunteerElite:
        return '🛡️';
      case _BridgeRole.acceptedVolunteer:
        return '🤝';
      case _BridgeRole.victim:
        return '🎤';
      case _BridgeRole.unknown:
        return '👤';
    }
  }

  static IconData iconForRole(_BridgeRole role) {
    switch (role) {
      case _BridgeRole.lifeline:
        return Icons.smart_toy_rounded;
      case _BridgeRole.emergencyDesk:
        return Icons.local_hospital_rounded;
      case _BridgeRole.emergencyContact:
        return Icons.phone_rounded;
      case _BridgeRole.volunteerElite:
        return Icons.shield_rounded;
      case _BridgeRole.acceptedVolunteer:
        return Icons.volunteer_activism_rounded;
      case _BridgeRole.victim:
        return Icons.mic_rounded;
      case _BridgeRole.unknown:
        return Icons.person_rounded;
    }
  }

  static String shortLabelForRole(_BridgeRole role) {
    switch (role) {
      case _BridgeRole.lifeline:
        return 'Lifeline AI';
      case _BridgeRole.emergencyDesk:
        return 'EMS';
      case _BridgeRole.emergencyContact:
        return 'Contact';
      case _BridgeRole.volunteerElite:
        return 'Elite Vol.';
      case _BridgeRole.acceptedVolunteer:
        return 'Volunteer';
      case _BridgeRole.victim:
        return 'You';
      case _BridgeRole.unknown:
        return 'Peer';
    }
  }

  static String nameForRole(_BridgeRole role, String identity) {
    switch (role) {
      case _BridgeRole.lifeline:
        return 'Assist';
      case _BridgeRole.emergencyDesk:
        return 'Emergency Services';
      case _BridgeRole.emergencyContact:
        return 'Emergency Contact';
      case _BridgeRole.volunteerElite:
        return 'Elite Volunteer';
      case _BridgeRole.acceptedVolunteer:
        return 'Volunteer';
      case _BridgeRole.victim:
        return 'You';
      case _BridgeRole.unknown:
        return identity.length > 16 ? '${identity.substring(0, 16)}...' : identity;
    }
  }

}

