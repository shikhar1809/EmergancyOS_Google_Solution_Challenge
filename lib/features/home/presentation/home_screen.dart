import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/maps/eos_hybrid_map.dart';
import '../../../core/maps/ops_map_controller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/google_maps_illustrative_light_style.dart';
import '../../../core/constants/india_ops_zones.dart';
import '../../../core/widgets/emergency_consent_dialog.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/incident_service.dart';
import '../../../services/offline_sos_status_service.dart';
import '../../../services/voice_comms_service.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'sos_countdown_overlay.dart';
import '../../sos/presentation/sms_sos_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Completer<OpsMapController> _controller = Completer<OpsMapController>();
  Position? _currentPosition;
  bool _isLoadingLocation = true;
  bool _showDailyTasks = false;

  // Daily actionable task checklist state
  final List<Map<String, dynamic>> _dailyTasks = [
    {'icon': Icons.access_time_rounded, 'color': Colors.blueAccent, 'label': '2-hour on-duty patrol', 'done': false},
    {'icon': Icons.medical_services_rounded, 'color': Colors.greenAccent, 'label': 'Learn a new first aid technique', 'done': false},
    {'icon': Icons.favorite_rounded, 'color': Colors.redAccent, 'label': 'CPR refresher drill (5 min)', 'done': false},
    {'icon': Icons.location_on_rounded, 'color': Colors.orangeAccent, 'label': 'Scout nearest AED locations', 'done': false},
  ];

  static final CameraPosition _initialPosition = IndiaOpsZones.lucknowCameraPosition(zoom: 14.5);

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _isLoadingLocation = false);
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _isLoadingLocation = false);
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _isLoadingLocation = false);
      return Future.error('Location permissions are permanently denied, we cannot request permissions.');
    }

    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = position;
        _isLoadingLocation = false;
      });
      
      final OpsMapController controller = await _controller.future;
      final cam = IndiaOpsZones.lucknowSafeCamera(
        LatLng(position.latitude, position.longitude),
        preferZoom: 16.0,
      );
      await controller.animateCamera(CameraUpdate.newCameraPosition(cam));
    } catch (e) {
      setState(() => _isLoadingLocation = false);
    }
  }

  // --- Map Dark Styling ---
  void _onMapCreated(OpsMapController controller) {
    if (!_controller.isCompleted) _controller.complete(controller);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: Stack(
        children: [
          // 1. Full Screen Map
          Semantics(
            label: l.homeMapSemantics,
            child: EosHybridMap(
            ignoreRemoteLeafletTiles: false,
            mapType: MapType.normal,
            cloudMapId: AppConstants.googleMapsDarkMapId.isNotEmpty
                ? AppConstants.googleMapsDarkMapId
                : null,
            style: effectiveGoogleMapsEmbeddedStyleJson(),
            cameraTargetBounds: IndiaOpsZones.lucknowCameraTargetBounds,
            initialCameraPosition: _currentPosition != null
                ? IndiaOpsZones.lucknowSafeCamera(
                    LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                    preferZoom: 16.0,
                  )
                : _initialPosition,
            onMapCreated: _onMapCreated,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            ),
          ),

          // 2. Loading State Overlay
          if (_isLoadingLocation)
            Container(
              color: AppColors.background.withValues(alpha: 0.5),
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.primaryDanger),
              ),
            ),

          // 3. Top Gradient / Search Bar Area
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0.9),
                    AppColors.background.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppConstants.appName,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      CircleAvatar(
                        backgroundColor: AppColors.surfaceHighlight,
                        child: IconButton(
                          icon: const Icon(Icons.my_location, color: Colors.white),
                          tooltip: l.homeRecenterMap,
                          onPressed: _determinePosition,
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 4. Daily Tasks Toggle Button (Top Right)
          Positioned(
            top: 65,
            right: 16,
            child: SafeArea(
              child: Semantics(
                button: true,
                label: _showDailyTasks ? l.cancel : l.todaysDuty,
                child: GestureDetector(
                onTap: () => setState(() => _showDailyTasks = !_showDailyTasks),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _showDailyTasks ? Colors.blueAccent : AppColors.surfaceHighlight,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 8, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_showDailyTasks ? Icons.close_rounded : Icons.checklist_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        _showDailyTasks ? l.cancel : l.todaysDuty,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      if (!_showDailyTasks) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10)),
                          child: Text(
                            '${_dailyTasks.where((t) => t['done'] == false).length}',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
                ),
            ),
          ),

          // 5. Daily Tasks Panel
          if (_showDailyTasks)
            Positioned(
              top: 110,
              right: 16,
              child: SafeArea(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 280,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.97),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                      boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20, offset: const Offset(0, 8))],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l.homeDutyHeading, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.5)),
                            Text(
                              l.homeDutyProgress(
                                _dailyTasks.where((t) => t['done'] == true).length,
                                _dailyTasks.length,
                              ),
                              style: TextStyle(
                                color: _dailyTasks.every((t) => t['done'] == true) ? Colors.greenAccent : Colors.white38,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Progress bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _dailyTasks.where((t) => t['done'] == true).length / _dailyTasks.length,
                            backgroundColor: Colors.white10,
                            color: Colors.blueAccent,
                            minHeight: 3,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ..._dailyTasks.asMap().entries.map((entry) {
                          final i = entry.key;
                          final task = entry.value;
                          final isDone = task['done'] as bool;
                          return Semantics(
                            checked: isDone,
                            label: task['label'] as String,
                            child: GestureDetector(
                            onTap: () => setState(() {
                              _dailyTasks[i]['done'] = !isDone;
                            }),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: isDone ? (task['color'] as Color).withValues(alpha: 0.2) : Colors.white10,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: isDone ? task['color'] as Color : Colors.white24, width: 1.5),
                                    ),
                                    child: Icon(
                                      isDone ? Icons.check_rounded : task['icon'] as IconData,
                                      color: isDone ? task['color'] as Color : Colors.white38,
                                      size: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      task['label'] as String,
                                      style: TextStyle(
                                        color: isDone ? Colors.white38 : Colors.white,
                                        fontSize: 13,
                                        decoration: isDone ? TextDecoration.lineThrough : null,
                                        decorationColor: Colors.white38,
                                        fontWeight: isDone ? FontWeight.normal : FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          );
                        }),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: Material(
                            color: AppColors.primaryDanger,
                            borderRadius: BorderRadius.circular(14),
                            elevation: 4,
                            child: InkWell(
                              onTap: _showSosCountdown,
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: Center(
                                  child: Text(
                                    l.sosButton,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ).animate().fadeIn(duration: 200.ms).slideX(begin: 0.2, end: 0),

          // 6. Floating SOS Button (Bottom Center)
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: Semantics(
                button: true,
                label: l.homeSosLargeFabHint,
                child: GestureDetector(
                onTap: _showSosCountdown,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.dangerGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryDanger.withValues(alpha: 0.6),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 4),
                  ),
                  child: Center(
                    child: ExcludeSemantics(
                      child: Text(
                        l.sosButton,
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ).animate(onPlay: (controller) => controller.repeat())
                 .shimmer(duration: const Duration(seconds: 3), color: Colors.white30)
                 .scale(begin: const Offset(1, 1), end: const Offset(1.05, 1.05), duration: const Duration(seconds: 1), curve: Curves.easeInOutSine)
                 .then(delay: const Duration(milliseconds: 0))
                 .scale(begin: const Offset(1.05, 1.05), end: const Offset(1, 1), duration: const Duration(seconds: 1), curve: Curves.easeInOutSine),
              ),
                ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSosCountdown() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return SosCountdownOverlay(
          onCancel: () {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context).homeSosCancelledSnack),
                backgroundColor: AppColors.surfaceHighlight,
              ),
            );
          },
          onConfirm: () {
            Navigator.of(context).pop();
            _submitSosIncident();
          },
        );
      },
    );
  }

  void _submitSosIncident() async {
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

    // Detect connectivity and route to the appropriate SOS path
    final connectivity = await Connectivity().checkConnectivity();
    final isOffline = connectivity.every((r) => r == ConnectivityResult.none);

    if (isOffline && context.mounted) {
      if (kIsWeb) VoiceCommsService.discardSosVoicePriming();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SmsSosScreen()),
      );
      return;
    }

    // Online: create Firestore incident
    try {
      final pos = await Geolocator.getCurrentPosition();
      final user = FirebaseAuth.instance.currentUser;
      final userId = user?.uid ?? 'guest';
      final name = user?.displayName ?? user?.email?.split('@').first ?? 'User';
      final incident = await IncidentService.createIncident(
        userId: userId,
        userDisplayName: name,
        location: LatLng(pos.latitude, pos.longitude),
        type: 'Rapid SOS',
      );
      ConnectivityService().start();
      unawaited(
        OfflineSosStatusService.markPendingIfOffline(
          incidentId: incident.id,
          likelyOffline: !ConnectivityService().isOnline,
        ),
      );
      try {
        await IncidentService.persistActiveSos(incident.id);
      } catch (e) {
        debugPrint('[Home] persistActiveSos: $e');
      }
      if (!context.mounted) return;
      context.go('/sos-active/${Uri.encodeComponent(incident.id)}');
      return;
    } catch (_) {
      if (kIsWeb) VoiceCommsService.discardSosVoicePriming();
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).homeSosSentSnack),
        backgroundColor: AppColors.primaryDanger,
      ),
    );
  }

  Future<bool> _ensureSosPinReady() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null || uid.isEmpty) return true; // guest flow unchanged

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
      context.go('/profile');
    }
    return false;
  }
}
