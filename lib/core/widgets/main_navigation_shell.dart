import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../widgets/emergency_consent_dialog.dart';
import '../../services/connectivity_service.dart';
import '../../services/offline_sos_status_service.dart';
import '../../services/incident_service.dart';
import '../../services/fcm_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/providers/drill_session_provider.dart';
import '../../core/providers/duty_provider.dart';
import '../widgets/incoming_emergency_overlay.dart';
import '../widgets/drill_home_walkthrough_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/volunteer_presence_service.dart';
import '../../services/voice_comms_service.dart';
import '../../services/drill_entry_service.dart';
import '../../services/drill_session_persistence.dart';
import '../constants/app_constants.dart';
import '../../services/sms_gateway_service.dart';

class MainNavigationShell extends ConsumerStatefulWidget {
  const MainNavigationShell({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<MainNavigationShell> with SingleTickerProviderStateMixin {
  bool _isHoldingSos = false;
  bool _pointerHoldingSos = false;
  bool _webShellSosAwaitRelease = false;
  late AnimationController _sosHoldController;
  final Set<String> _notifiedIncidentIds = {};
  bool _sosSubmitting = false;
  Timer? _pollTimer;
  Future<void>? _incomingDedupeHydrate;
  final List<SosIncident> _incomingAlertQueue = [];
  bool _incomingAlertVisible = false;
  ProviderSubscription<AsyncValue<List<SosIncident>>>? _subActiveIncidents;
  ProviderSubscription<bool>? _subOnDuty;
  bool _volunteerResumeScheduled = false;
  Timer? _dutyPresenceRefreshTimer;
  StreamSubscription<User?>? _authUserSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _forceSignOutSub;
  /// `sos` | `volunteer` — set from login drill; home tooltip tour before drill screens.
  String? _drillWalkthroughMode;
  final GlobalKey _drillFabKey = GlobalKey(debugLabel: 'drill_walkthrough_fab');
  final GlobalKey _drillNavHomeKey = GlobalKey(debugLabel: 'drill_walkthrough_nav_home');
  final GlobalKey _drillNavGridKey = GlobalKey(debugLabel: 'drill_walkthrough_nav_grid');
  final GlobalKey _drillNavLifelineKey = GlobalKey(debugLabel: 'drill_walkthrough_nav_lifeline');
  final GlobalKey _drillNavProfileKey = GlobalKey(debugLabel: 'drill_walkthrough_nav_profile');

  Future<void> _ensureIncomingDedupeHydrated() {
    return _incomingDedupeHydrate ??= () async {
      final ids = await IncidentService.loadRecentlyShownIncomingAlertIds();
      if (!context.mounted) return;
      _notifiedIncidentIds.addAll(ids);
    }();
  }

  Future<void> _consumeDrillArming() async {
    final mode = await DrillEntryService.takeArmedMode();
    if (!context.mounted || mode == null || mode.isEmpty) return;
    if (mode != 'sos' && mode != 'volunteer') return;
    setState(() => _drillWalkthroughMode = mode);
  }

  Future<SosIncident> _syntheticDrillIncomingIncident() async {
    var loc = const LatLng(28.6139, 77.2090);
    try {
      final p = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
          );
      loc = LatLng(p.latitude, p.longitude);
    } catch (_) {}
    final now = DateTime.now();
    return SosIncident(
      id: AppConstants.drillIncidentId,
      userId: 'drill_demo',
      userDisplayName: 'Training scenario',
      location: loc,
      type: 'Nearby training alert',
      timestamp: now,
      goldenHourStart: now,
      bloodType: 'O+',
      allergies: 'None (drill)',
      medicalConditions: 'Practice data only',
    );
  }

  void _dismissDrillHomeTourSosOnly() {
    if (!context.mounted || _drillWalkthroughMode != 'sos') return;
    setState(() => _drillWalkthroughMode = null);
  }

  void _openVictimPracticeSosFromShell() {
    if (!context.mounted) return;
    _isHoldingSos = false;
    _pointerHoldingSos = false;
    _webShellSosAwaitRelease = false;
    _sosHoldController.reset();
    setState(() {
      if (_drillWalkthroughMode == 'sos') {
        _drillWalkthroughMode = null;
      }
    });
    context.go('/sos-active/${Uri.encodeComponent(AppConstants.drillIncidentId)}?drill=1');
  }

  Future<void> _finishDrillHomeTourVolunteer() async {
    final captured = _drillWalkthroughMode;
    if (!context.mounted || captured != 'volunteer') return;
    setState(() => _drillWalkthroughMode = null);
    final incident = await _syntheticDrillIncomingIncident();
    if (!context.mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (ctx, anim, _, child) =>
          FadeTransition(opacity: anim, child: ScaleTransition(scale: anim, child: child)),
      pageBuilder: (ctx, _, __) => IncomingEmergencyOverlay(
        incident: incident,
        isDrillPractice: true,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _sosHoldController = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    _sosHoldController.addListener(() {
      if (_sosHoldController.isCompleted && _pointerHoldingSos) {
        final victimDrill = ref.read(drillVictimPracticeShellProvider);
        if (victimDrill) {
          if (kIsWeb) {
            setState(() => _webShellSosAwaitRelease = true);
          } else {
            _openVictimPracticeSosFromShell();
          }
          return;
        }
        if (kIsWeb) {
          setState(() => _webShellSosAwaitRelease = true);
        } else {
          _triggerImmediateSOS();
        }
      }
    });

    _subActiveIncidents = ref.listenManual<AsyncValue<List<SosIncident>>>(
      activeIncidentsProvider,
      (previous, next) => unawaited(_onActiveIncidentsChanged(previous, next)),
    );
    _subOnDuty = ref.listenManual<bool>(
      isOnDutyProvider,
      (prevDuty, onDuty) {
        if (onDuty != true || prevDuty == true) return;
        final async = ref.read(activeIncidentsProvider);
        if (!async.hasValue || async.value == null) return;
        unawaited(_enqueueIncidentAlerts(async.value!, onlyIdsNewSincePrevious: false));
      },
    );

    // Wire FCM foreground messages into the same in-app incident UX.
    FcmService.setOnMessageCallback((msg) async {
      if (await DrillSessionPersistence.isActive()) return;
      final data = msg.data;
      final id = (data['incidentId'] ?? '').toString().trim();
      if (id.isEmpty) return;
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final reporter = (data['reportingUserId'] ?? '').toString().trim();
      if (reporter.isNotEmpty && uid.isNotEmpty && reporter == uid) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pendingIncidentId', id);
      if (context.mounted) unawaited(_checkPendingIncident());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_checkPendingIncident()));
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_consumeDrillArming()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_volunteerResumeScheduled) return;
      _volunteerResumeScheduled = true;
      unawaited(_tryResumeVolunteerMission());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!context.mounted) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final onDuty = prefs.getBool('volunteer_on_duty') ?? true;
      if (onDuty) {
        await VolunteerPresenceService.publishDutyPresence(onDuty: true);
      }
    });

    _dutyPresenceRefreshTimer = Timer.periodic(const Duration(minutes: 8), (_) async {
      if (!context.mounted) return;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('volunteer_on_duty') ?? true) {
        await VolunteerPresenceService.publishDutyPresence(onDuty: true);
      }
    });

    // Polling fallback: query Firestore every 10s as a safety net for
    // cases where the real-time listener silently disconnects.
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!context.mounted) return;
      unawaited(_pollForMissedIncidents());
    });

    _authUserSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      unawaited(_attachForceSignOutListener(user?.uid));
    });
  }

  Future<void> _attachForceSignOutListener(String? uid) async {
    await _forceSignOutSub?.cancel();
    _forceSignOutSub = null;
    if (uid == null || uid.isEmpty) return;
    _forceSignOutSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) => unawaited(_onUserSecurityDoc(snap, uid)));
  }

  Future<void> _onUserSecurityDoc(DocumentSnapshot<Map<String, dynamic>> snap, String uid) async {
    if (!snap.exists || !context.mounted) return;
    final ts = snap.data()?['securityForceSignOutAt'];
    if (ts is! Timestamp) return;
    final ms = ts.millisecondsSinceEpoch;
    final p = await SharedPreferences.getInstance();
    final key = 'last_processed_force_signout_ms_$uid';
    final last = p.getInt(key) ?? 0;
    if (ms <= last) return;
    await p.setInt(key, ms);
    try {
      await FcmService.setOffline(uid);
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _pollForMissedIncidents() async {
    if (await DrillSessionPersistence.isActive()) return;
    try {
      unawaited(IncidentService.autoArchiveExpiredIncidents());
      final incidents = await IncidentService.pollRecentIncidents();
      if (incidents.isEmpty || !context.mounted) return;
      await _enqueueIncidentAlerts(incidents, onlyIdsNewSincePrevious: false);
    } catch (_) {}
  }

  /// Re-opens active consignment after restart while still on duty + assignment valid.
  Future<void> _tryResumeVolunteerMission() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty || !context.mounted) return;
    if (await DrillSessionPersistence.isActive()) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final onDuty = prefs.getBool('volunteer_on_duty') ?? true;
      if (!onDuty) {
        await IncidentService.clearVolunteerAssignment();
        return;
      }

      final a = await IncidentService.loadVolunteerAssignment();
      final id = (a.incidentId ?? '').trim();
      if (id.isEmpty) return;

      final doc = await FirebaseFirestore.instance
          .collection('sos_incidents')
          .doc(id)
          .get(const GetOptions(source: Source.server));
      if (!doc.exists || doc.data() == null) {
        await IncidentService.clearVolunteerAssignment();
        return;
      }
      final data = doc.data()!;
      if (IncidentService.incidentMapActiveWindowExpired(data)) {
        final st0 = (data['status'] as String?) ?? '';
        if (['pending', 'dispatched', 'blocked'].contains(st0)) {
          unawaited(
            IncidentService.archiveAndCloseIncident(
              incidentId: id,
              status: 'expired',
              closedByUid: 'system_auto_expire',
            ),
          );
        }
        await IncidentService.clearVolunteerAssignment();
        return;
      }
      final st = (data['status'] as String?) ?? '';
      final accepted = List<String>.from(data['acceptedVolunteerIds'] ?? []);
      if (!['pending', 'dispatched', 'blocked'].contains(st) || !accepted.contains(uid)) {
        await IncidentService.clearVolunteerAssignment();
        return;
      }

      if (!context.mounted) return;
      final loc = GoRouterState.of(context).uri.path;
      if (loc.contains('/active-consignment/')) return;
      if (loc.startsWith('/drill/')) return;

      final type = (a.incidentType ?? data['type'] ?? 'Emergency').toString();
      final drillQ = id == AppConstants.drillIncidentId ? '&drill=1' : '';
      context.go('/active-consignment/$id?type=${Uri.encodeComponent(type)}$drillQ');
    } catch (e) {
      debugPrint('[Shell] volunteer resume skipped: $e');
    }
  }

  Future<void> _checkPendingIncident() async {
    if (await DrillSessionPersistence.isActive()) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pendingIncidentId');
      return;
    }
    await _ensureIncomingDedupeHydrated();
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getString(IncidentService.prefVolunteerIncidentId) ?? '').trim().isNotEmpty) return;
    final pending = (prefs.getString('pendingIncidentId') ?? '').trim();
    if (pending.isEmpty) return;
    if (_notifiedIncidentIds.contains(pending)) {
      await prefs.remove('pendingIncidentId');
      return;
    }
    final asyncIncidents = ref.read(activeIncidentsProvider);
    if (!asyncIncidents.hasValue) return;
    final incidents = asyncIncidents.value ?? [];
    final match = incidents.where((i) => i.id == pending).toList();
    if (match.isEmpty) {
      await prefs.remove('pendingIncidentId');
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final inc = match.first;
    if (inc.id.startsWith('demo_ops_')) {
      await prefs.remove('pendingIncidentId');
      return;
    }
    if (uid.isNotEmpty &&
        inc.userId.isNotEmpty &&
        inc.userId != 'anonymous' &&
        inc.userId == uid) {
      await prefs.remove('pendingIncidentId');
      return;
    }
    _notifiedIncidentIds.add(pending);
    unawaited(IncidentService.rememberIncomingAlertShown(pending));
    await prefs.remove('pendingIncidentId');
    if (!context.mounted) return;
    _incomingAlertQueue.add(inc);
    _pumpIncomingAlertQueue();
  }

  @override
  void dispose() {
    _subActiveIncidents?.close();
    _subOnDuty?.close();
    _dutyPresenceRefreshTimer?.cancel();
    _pollTimer?.cancel();
    _authUserSub?.cancel();
    _forceSignOutSub?.cancel();
    _sosHoldController.dispose();
    super.dispose();
  }

  Future<void> _onActiveIncidentsChanged(
    AsyncValue<List<SosIncident>>? previous,
    AsyncValue<List<SosIncident>> next,
  ) async {
    if (!context.mounted) return;
    if (!next.hasValue || next.value == null) return;
    if (await DrillSessionPersistence.isActive()) return;

    final prevIds = <String>{};
    if (previous != null && previous.hasValue && previous.value != null) {
      prevIds.addAll(previous.value!.map((e) => e.id));
    }
    final noPriorSnapshot =
        previous == null || previous.isLoading || !previous.hasValue || previous.value == null;

    if (noPriorSnapshot) {
      await _enqueueIncidentAlerts(next.value!, onlyIdsNewSincePrevious: false);
    } else {
      await _enqueueIncidentAlerts(
        next.value!,
        onlyIdsNewSincePrevious: true,
        previousSnapshotIds: prevIds,
      );
    }
  }

  Future<void> _enqueueIncidentAlerts(
    List<SosIncident> incidents, {
    required bool onlyIdsNewSincePrevious,
    Set<String> previousSnapshotIds = const {},
  }  ) async {
    await _ensureIncomingDedupeHydrated();
    if (await DrillSessionPersistence.isActive()) return;
    if (ref.read(drillSessionDashboardDemoProvider) || ref.read(drillVictimPracticeShellProvider)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    
    // Prevent double alerts if already on a volunteer call or victims side active SOS
    final isAlreadyBusy = (prefs.getString(IncidentService.prefVolunteerIncidentId) ?? '').trim().isNotEmpty;
    final currentPath = GoRouterState.of(context).uri.path;
    final isOnActiveScreen = currentPath.contains('/active-consignment/') || currentPath.contains('/sos-active/');
    
    if (currentPath.startsWith('/drill/')) return;
    if (isAlreadyBusy || isOnActiveScreen) return;
    if (!context.mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();
    var queued = false;
    for (final incident in incidents) {
      // Seeded analytics / command-center demos — not real volunteer dispatch on the main app.
      if (incident.id.startsWith('demo_ops_')) continue;
      final age = now.difference(incident.timestamp);
      if (_notifiedIncidentIds.contains(incident.id)) continue;
      if (IncidentService.volunteerWithdrewIncidentIds.contains(incident.id)) {
        _notifiedIncidentIds.add(incident.id);
        continue;
      }
      // Already accepted this SOS (e.g. shell was recreated after leaving Active Consignment).
      if (uid.isNotEmpty && incident.acceptedVolunteerIds.contains(uid)) {
        _notifiedIncidentIds.add(incident.id);
        continue;
      }
      // Never treat your own reported incident as an incoming volunteer alert
      // (covers FCM topic + race before device-created set is populated).
      if (uid.isNotEmpty &&
          incident.userId.isNotEmpty &&
          incident.userId != 'anonymous' &&
          incident.userId == uid) {
        _notifiedIncidentIds.add(incident.id);
        continue;
      }
      // Skip incidents created on THIS DEVICE (anonymous / same-session create).
      if (IncidentService.wasCreatedOnThisDevice(incident.id)) continue;
      if (age.inMinutes > 10) continue; // Only show fresh alerts (last 10 mins)
      if (onlyIdsNewSincePrevious && previousSnapshotIds.contains(incident.id)) {
        continue;
      }
      _notifiedIncidentIds.add(incident.id);
      unawaited(IncidentService.rememberIncomingAlertShown(incident.id));
      _incomingAlertQueue.add(incident);
      queued = true;
    }
    if (queued && context.mounted) _pumpIncomingAlertQueue();
  }

  void _pumpIncomingAlertQueue() {
    if (!context.mounted || _incomingAlertVisible || _incomingAlertQueue.isEmpty) return;
    _incomingAlertVisible = true;
    final incident = _incomingAlertQueue.removeAt(0);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (ctx, anim, _, child) =>
          FadeTransition(opacity: anim, child: ScaleTransition(scale: anim, child: child)),
      pageBuilder: (ctx, _, __) => IncomingEmergencyOverlay(incident: incident),
    ).whenComplete(() {
      _incomingAlertVisible = false;
      if (context.mounted) _pumpIncomingAlertQueue();
    });
  }

  void _triggerImmediateSOS() {
    _isHoldingSos = false;
    _sosHoldController.reset();
    _startImmediateSos();
  }

  Future<void> _startImmediateSos() async {
    String? createdId;
    try {
      if (_sosSubmitting) return;
      _sosSubmitting = true;

      final pinReady = await _ensureSosPinReady();
      if (!pinReady) {
        if (kIsWeb) VoiceCommsService.discardSosVoicePriming();
        return;
      }

      if (!context.mounted) return;
      final consented = await showEmergencyDataConsentIfNeeded(context);
      if (!consented) {
        if (kIsWeb) VoiceCommsService.discardSosVoicePriming();
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? '';

      final pos = await Geolocator.getCurrentPosition();
      final incident = await IncidentService.createIncident(
        userId: uid.isNotEmpty ? uid : 'anonymous',
        userDisplayName: (user?.displayName?.trim().isNotEmpty ?? false)
            ? user!.displayName!.trim()
            : (user?.email?.split('@').first.toUpperCase() ?? 'Local Hero'),
        location: LatLng(pos.latitude, pos.longitude),
        type: 'General Emergency',
      );
      createdId = incident.id;
      ConnectivityService().start();
      unawaited(
        OfflineSosStatusService.markPendingIfOffline(
          incidentId: createdId,
          likelyOffline: !ConnectivityService().isOnline,
        ),
      );
      try {
        await IncidentService.persistActiveSos(createdId);
      } catch (e) {
        debugPrint('[Shell] persistActiveSos: $e');
      }
      if (kIsWeb) {
        await SmsGatewayService.offerWebParallelGeoSmsIfNeeded(
          context,
          lat: pos.latitude,
          lng: pos.longitude,
          type: 'General Emergency',
          incidentId: createdId,
          victimCount: 1,
          freeText: 'emergencyOS shell SOS',
        );
      } else {
        unawaited(
          SmsGatewayService.tryOpenParallelGeoSmsRelay(
            lat: pos.latitude,
            lng: pos.longitude,
            type: 'General Emergency',
            incidentId: createdId,
            victimCount: 1,
            freeText: 'emergencyOS shell SOS',
          ),
        );
      }
    } catch (e) {
      debugPrint('[Shell] SOS creation failed: $e');
      if (kIsWeb) VoiceCommsService.discardSosVoicePriming();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('SOS failed: ${e.toString().length > 80 ? 'Check connection and retry.' : e.toString()}'),
            backgroundColor: AppColors.primaryDanger,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      _sosSubmitting = false;
    }

    if (!context.mounted) return;
    if (createdId != null && createdId.isNotEmpty) {
      context.go('/sos-active/${Uri.encodeComponent(createdId)}');
    }
  }

  /// `/drill/...` practice shell vs live tab paths.
  String _shellTabPath(String tab) {
    final path = GoRouterState.of(context).uri.path;
    final drill = path.startsWith('/drill/');
    return drill ? '/drill/$tab' : '/$tab';
  }

  Future<bool> _ensureSosPinReady() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null || uid.isEmpty) return true;

    final prefs = await SharedPreferences.getInstance();
    var hash = (prefs.getString('sos_pin_hash') ?? '').trim();
    if (hash.isEmpty) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        hash = ((doc.data()?['sosPinHash'] as String?) ?? '').trim();
        if (hash.isNotEmpty) {
          await prefs.setString('sos_pin_hash', hash);
        }
      } catch (_) {}
    }
    if (hash.isNotEmpty) return true;
    if (!context.mounted) return false;

    final l = AppLocalizations.of(context);
    final goSet = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(l.setSosPinFirst, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: Text(
          l.setPinSafetyMsg,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.later, style: const TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryDanger),
            child: Text(l.setPinNow),
          ),
        ],
      ),
    );
    if (goSet == true && context.mounted) {
      context.go(_shellTabPath('profile'));
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final int currentIndex = _calculateSelectedIndex(context);
    final isOnlineAsync = ref.watch(connectivityProvider);
    final isOnline = isOnlineAsync.value ?? true;
    final netQuality = ref.watch(networkQualityProvider).value ?? (isOnline ? NetworkQuality.good : NetworkQuality.offline);

    return Scaffold(
      body: Stack(
        children: [
          widget.child,
          if (_drillWalkthroughMode != null)
            Positioned.fill(
              child: DrillHomeWalkthroughOverlay(
                fabKey: _drillFabKey,
                navHomeKey: _drillNavHomeKey,
                navGridKey: _drillNavGridKey,
                navLifelineKey: _drillNavLifelineKey,
                navProfileKey: _drillNavProfileKey,
                mode: _drillWalkthroughMode == 'sos'
                    ? DrillHomeWalkthroughMode.sosVictim
                    : DrillHomeWalkthroughMode.volunteer,
                onComplete: () async {
                  final m = _drillWalkthroughMode;
                  if (m == 'sos') {
                    _dismissDrillHomeTourSosOnly();
                  } else if (m == 'volunteer') {
                    await _finishDrillHomeTourVolunteer();
                  }
                },
              ),
            ),
          if (!isOnline)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  width: double.infinity,
                  color: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    AppLocalizations.of(context).offlineMode,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ),
              ),
            )
          else if (netQuality == NetworkQuality.poor || netQuality == NetworkQuality.unstable)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Material(
                  color: Colors.deepOrange.withValues(alpha: 0.9),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      'Limited connectivity — maps and sync may be slower. Emergency SOS still queues offline.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Network quality indicator line (above bottom nav)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _NetworkQualityLine(quality: netQuality),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Semantics(
        button: true,
        label: 'SOS Emergency. Tap for SOS screen. Long press 3 seconds to trigger immediate SOS.',
        child: GestureDetector(
        onTapDown: (_) {
          _pointerHoldingSos = true;
          _webShellSosAwaitRelease = false;
          VoiceCommsService.primeForVoiceGuidance();
          setState(() => _isHoldingSos = true);
          _sosHoldController.forward();
        },
        onTapUp: (_) {
          if (kIsWeb && _webShellSosAwaitRelease) {
            _webShellSosAwaitRelease = false;
            _pointerHoldingSos = false;
            VoiceCommsService.primeForVoiceGuidance();
            final victimDrill = ref.read(drillVictimPracticeShellProvider);
            _sosHoldController.reset();
            setState(() => _isHoldingSos = false);
            if (victimDrill) {
              _openVictimPracticeSosFromShell();
            } else {
              unawaited(_startImmediateSos());
            }
            return;
          }
          _pointerHoldingSos = false;
          if (_isHoldingSos && !_sosHoldController.isCompleted) {
            _sosHoldController.reverse();
            setState(() => _isHoldingSos = false);
            if (ref.read(drillVictimPracticeShellProvider)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Practice: hold the red SOS button for 3 full seconds to open the drill screen. Nothing is dispatched.',
                  ),
                  duration: Duration(seconds: 4),
                ),
              );
            } else {
              context.go(_shellTabPath('sos-intake'));
            }
          }
        },
        onTapCancel: () {
          _pointerHoldingSos = false;
          _webShellSosAwaitRelease = false;
          _sosHoldController.reverse();
          setState(() => _isHoldingSos = false);
        },
        child: AnimatedBuilder(
          animation: _sosHoldController,
          builder: (context, _) {
            final v = _sosHoldController.value;
            return KeyedSubtree(
              key: _drillFabKey,
              child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryDanger,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryDanger.withValues(alpha: 0.5),
                    blurRadius: 10 + (v * 20),
                    spreadRadius: v * 10,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: v,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 4,
                  ),
                  Transform.scale(
                    scale: 1.0 + (v * 0.3),
                    child: const Icon(Icons.warning_amber_rounded, size: 32, color: Colors.white),
                  ),
                ],
              ),
            ),
            );
          },
        ),
      )),
      bottomNavigationBar: BottomAppBar(
        color: AppColors.surface,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        height: 75, // Explicit safe height
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Builder(
          builder: (ctx) {
            final l = AppLocalizations.of(ctx);
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildNavItem(ctx, Icons.cottage_rounded, l.navHome, 0, currentIndex, 'dashboard', layoutKey: _drillNavHomeKey),
                _buildNavItem(ctx, Icons.near_me_rounded, l.navGrid, 1, currentIndex, 'map', layoutKey: _drillNavGridKey),
                const SizedBox(width: 48),
                _buildNavItem(ctx, Icons.medical_services_rounded, l.lifeline, 3, currentIndex, 'lifeline', layoutKey: _drillNavLifelineKey),
                _buildNavItem(ctx, Icons.person_rounded, l.navProfile, 4, currentIndex, 'profile', layoutKey: _drillNavProfileKey),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    IconData icon,
    String label,
    int index,
    int currentIndex,
    String tabName, {
    Key? layoutKey,
  }) {
    final isSelected = index == currentIndex;
    final color = isSelected ? AppColors.primaryDanger : AppColors.textSecondary;
    Widget tile = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go(_shellTabPath(tabName)),
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: isSelected ? 24 : 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (layoutKey != null) {
      tile = KeyedSubtree(key: layoutKey, child: tile);
    }
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label tab${isSelected ? ", currently selected" : ""}',
      child: tile,
    );
  }

  static int _calculateSelectedIndex(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final tail = path.startsWith('/drill/') ? path.substring('/drill'.length) : path;
    if (tail.startsWith('/dashboard') || tail == '/' || tail.isEmpty) return 0;
    if (tail.startsWith('/map')) return 1;
    if (tail.startsWith('/sos-intake') || (tail.startsWith('/sos') && !tail.startsWith('/sos-active'))) return 2;
    if (tail.startsWith('/lifeline')) return 3;
    if (tail.startsWith('/profile')) return 4;
    return 0;
  }
}

class _NetworkQualityLine extends StatelessWidget {
  final NetworkQuality quality;
  const _NetworkQualityLine({required this.quality});

  @override
  Widget build(BuildContext context) {
    final color = quality.color;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      height: 3,
      decoration: BoxDecoration(
        color: color,
        boxShadow: [
          BoxShadow(color: quality.glowColor, blurRadius: 8, spreadRadius: 1),
        ],
      ),
    );
  }
}
