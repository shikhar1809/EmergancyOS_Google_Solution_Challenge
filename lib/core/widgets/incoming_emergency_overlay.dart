// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import '../../services/dispatch_chain_service.dart';
import '../../services/incident_service.dart';
import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import '../utils/ems_workflow_labels.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../web_bridge/emergency_alarm.dart';
import 'volunteer_voice_mode_prompt.dart';

/// iPhone-style full-screen incoming emergency overlay with:
/// - Swipe-to-accept handle (must drag >85% of the track width)
/// - Web Audio API alarm (via dart:js_interop) that loops until dismissed
class IncomingEmergencyOverlay extends StatefulWidget {
  final SosIncident incident;
  /// Practice from login: no Firestore accept; navigate to drill consignment.
  final bool isDrillPractice;
  const IncomingEmergencyOverlay({
    super.key,
    required this.incident,
    this.isDrillPractice = false,
  });

  @override
  State<IncomingEmergencyOverlay> createState() => _IncomingEmergencyOverlayState();
}

class _IncomingEmergencyOverlayState extends State<IncomingEmergencyOverlay>
    with SingleTickerProviderStateMixin {
  // Swipe state
  double _dragX = 0.0;
  bool _accepted = false;

  late SosIncident _inc;
  DispatchChainState? _dispatchState;
  String? _profileDisplayName;
  bool _profileFetchStarted = false;

  StreamSubscription<SosIncident?>? _incidentSub;
  StreamSubscription<DispatchChainState>? _dispatchSub;

  // Pulse animation
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _inc = widget.incident;
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _startAlarm();
    if (!widget.isDrillPractice) {
      final id = _inc.id.trim();
      if (id.isNotEmpty) {
        _incidentSub = IncidentService.watchIncidentById(id).listen((doc) {
          if (!mounted || doc == null) return;
          setState(() => _inc = doc);
          unawaited(_maybeFetchProfileName());
        });
        _dispatchSub = DispatchChainService.watchForIncident(id).listen((s) {
          if (!mounted) return;
          setState(() => _dispatchState = s);
        });
      }
      unawaited(_maybeFetchProfileName());
    }
  }

  Future<void> _maybeFetchProfileName() async {
    if (widget.isDrillPractice) return;
    final uid = _inc.userId.trim();
    if (uid.isEmpty || uid == 'anonymous') return;
    final raw = _inc.userDisplayName.trim();
    if (raw.isNotEmpty && raw.toLowerCase() != 'unknown') return;
    if (_profileFetchStarted) return;
    _profileFetchStarted = true;
    try {
      final d = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!d.exists || !mounted) return;
      final data = d.data();
      final n = (data?['name'] as String?)?.trim();
      final email = (data?['email'] as String?)?.trim();
      final resolved = (n != null && n.isNotEmpty)
          ? n
          : (email != null && email.contains('@') ? email.split('@').first : null);
      if (resolved != null && resolved.isNotEmpty && mounted) {
        setState(() => _profileDisplayName = resolved);
      }
    } catch (e) {
      debugPrint('[IncomingEmergency] profile fallback: $e');
    }
  }

  void _startAlarm() {
    if (widget.isDrillPractice) return;
    emergencyAlarmStart();
  }

  void _stopAlarm() {
    emergencyAlarmStop();
  }

  void _deny() {
    _stopAlarm();
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _accept() async {
    if (_accepted) return;
    _accepted = true;
    _stopAlarm();

    final router = GoRouter.of(context);
    final incidentId = _inc.id.trim();
    final typeRaw = _inc.type.trim().isEmpty ? 'Emergency' : _inc.type.trim();

    if (widget.isDrillPractice) {
      if (!context.mounted) return;
      await VolunteerVoiceModePrompt.show(context);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final drillId = AppConstants.drillIncidentId;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        router.go(
          '/active-consignment/${Uri.encodeComponent(drillId)}?drill=1&type=${Uri.encodeComponent('Training')}',
        );
      });
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (context.mounted) {
        setState(() {
          _accepted = false;
          _dragX = 0.0;
        });
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Sign in to accept alerts.'),
            backgroundColor: AppColors.primaryDanger,
          ),
        );
      }
      return;
    }

    try {
      await IncidentService.acceptIncident(incidentId, currentUser.uid);
      await IncidentService.persistVolunteerAssignment(
        incidentId: incidentId,
        incidentType: typeRaw,
      );
      if (!mounted) return;
      await VolunteerVoiceModePrompt.show(context);
    } catch (e, st) {
      debugPrint('[IncomingEmergency] accept failed: $e\n$st');
      var msg = 'Could not accept this alert. Check your connection and try again.';
      if (e is FirebaseException) {
        if (e.code == 'permission-denied') {
          msg = 'Could not accept (access denied). If this keeps happening, the app rules may need updating.';
        } else if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
          msg = 'Network issue — check your connection and try again.';
        }
      }
      if (context.mounted) {
        setState(() {
          _accepted = false;
          _dragX = 0.0;
        });
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.primaryDanger,
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).pop();
    final path =
        '/active-consignment/${Uri.encodeComponent(incidentId)}?type=${Uri.encodeComponent(typeRaw)}';
    SchedulerBinding.instance.addPostFrameCallback((_) {
      router.go(path);
    });
  }

  @override
  void dispose() {
    _incidentSub?.cancel();
    _dispatchSub?.cancel();
    _stopAlarm();
    _pulseCtrl.dispose();
    super.dispose();
  }

  static bool _isCprAedType(String? type) {
    final t = (type ?? '').toLowerCase();
    return t.contains('cpr') || t.contains('aed') || t.contains('cardiac') || t.contains('defib');
  }

  String _resolvedReporterName() {
    final raw = _inc.userDisplayName.trim();
    if (raw.isNotEmpty && raw.toLowerCase() != 'unknown') return raw;
    final p = _profileDisplayName?.trim();
    if (p != null && p.isNotEmpty) return p;
    if (raw.isNotEmpty) return raw;
    return 'Unknown';
  }

  String _heroHeadline(String reporter) {
    final type = _inc.type.trim();
    final typeOk = type.isNotEmpty && type.toLowerCase() != 'unknown';
    if (typeOk) return type;
    final nameOk = reporter.isNotEmpty && reporter.toLowerCase() != 'unknown';
    if (nameOk) return reporter;
    return 'Emergency';
  }

  String _hospitalAssignLabel() {
    final state = _dispatchState;
    final a = state?.assignment;
    if (a == null) return 'Pending';
    final ds = (a.dispatchStatus ?? '').trim();
    switch (ds) {
      case 'pending_notify':
        return 'Notifying hospitals…';
      case 'pending_acceptance':
        final h = state?.currentHospitalName ?? '—';
        return h != '—' ? 'Awaiting acceptance · $h' : 'Awaiting hospital';
      case 'accepted':
        return 'Accepted · ${a.acceptedHospitalName ?? a.primaryHospitalName ?? 'Hospital'}';
      case 'exhausted':
        return 'No hospital available (chain exhausted)';
      case '':
        return 'Pending';
      default:
        return ds.replaceAll('_', ' ');
    }
  }

  String _emsDispatchLabel() {
    final parts = <String>[];
    final phase = (_inc.emsWorkflowPhase ?? '').trim();
    if (phase.isNotEmpty) {
      parts.add(emsWorkflowPhaseShortLabel(phase));
    }
    final amb = _dispatchState?.assignment?.ambulanceDispatchStatus?.trim();
    if (amb != null && amb.isNotEmpty) parts.add(amb);
    final cs = _dispatchState?.assignment?.assignedFleetCallSign?.trim();
    if (cs != null && cs.isNotEmpty) parts.add('Unit $cs');
    if (parts.isEmpty) return '—';
    return parts.join(' · ');
  }

  String _bgEmoji(String typeLower) {
    if (typeLower.contains('cpr') || typeLower.contains('aed') || typeLower.contains('defib')) {
      return '⚡';
    }
    if (typeLower.contains('cardiac')) return '❤️';
    if (typeLower.contains('fire')) return '🔥';
    if (typeLower.contains('collision') || typeLower.contains('accident')) return '🚗';
    if (typeLower.contains('drowning')) return '🌊';
    return '🚨';
  }

  bool get _showEmergencyContactCard {
    if ((_inc.emergencyContactPhone ?? '').trim().isNotEmpty) return true;
    if ((_inc.emergencyContactEmail ?? '').trim().isNotEmpty) return true;
    if (_inc.smsOrigin && (_inc.senderPhone ?? '').trim().isNotEmpty) return true;
    return false;
  }

  String? get _emergencyContactPhoneLine {
    final p = (_inc.emergencyContactPhone ?? '').trim();
    if (p.isNotEmpty) return p;
    if (_inc.smsOrigin) {
      final s = (_inc.senderPhone ?? '').trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final trackWidth = (screenW - 64.0).clamp(200.0, 400.0);
    const handleSize = 60.0;
    final maxDrag = trackWidth - handleSize;

    final reporter = _resolvedReporterName();
    final hero = _heroHeadline(reporter);
    final typeLower = _inc.type.toLowerCase();
    final cpr = _isCprAedType(_inc.type);
    final accent = cpr ? const Color(0xFF00BFA5) : AppColors.primaryDanger;
    final bannerColor = cpr ? const Color(0xFF26C6DA) : AppColors.primaryDanger;
    final medAccent = cpr ? const Color(0xFF4DD0E1) : AppColors.primaryWarning;
    final contactBg = const Color(0xFF0D2A2E);
    final contactBorder = const Color(0xFF26C6DA).withValues(alpha: 0.55);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, child) => Transform.scale(scale: _pulseAnim.value, child: child),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D0D),
            border: Border.all(color: accent, width: 3),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent, width: 2),
                  ),
                  child: Text(_bgEmoji(typeLower), style: const TextStyle(fontSize: 48)),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.isDrillPractice ? 'PRACTICE ALERT (DRILL)' : 'INCOMING EMERGENCY',
                  style: TextStyle(
                    color: bannerColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hero,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Reported by $reporter',
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 24),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: medAccent.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.local_hospital_rounded, color: medAccent, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              cpr ? 'CPR / AED — scene info' : 'Emergency Medical Data',
                              style: TextStyle(
                                color: medAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _medRow(Icons.bloodtype, 'Blood Type', _inc.bloodType ?? 'Unknown'),
                        const SizedBox(height: 8),
                        _medRow(Icons.apartment_rounded, 'Hospital assign status', _hospitalAssignLabel()),
                        const SizedBox(height: 8),
                        _medRow(Icons.local_shipping_rounded, 'EMS dispatch status', _emsDispatchLabel()),
                        const SizedBox(height: 8),
                        _medRow(Icons.location_on, 'Location', 'Within your response radius'),
                      ],
                    ),
                  ),
                ),

                if (_showEmergencyContactCard) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: contactBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: contactBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.contact_phone_rounded, color: contactBorder.withValues(alpha: 1.0), size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Emergency contact',
                                style: TextStyle(
                                  color: contactBorder.withValues(alpha: 0.95),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_emergencyContactPhoneLine != null)
                            _medRow(Icons.phone_rounded, 'Phone', _emergencyContactPhoneLine!),
                          if ((_inc.emergencyContactEmail ?? '').trim().isNotEmpty) ...[
                            if (_emergencyContactPhoneLine != null) const SizedBox(height: 6),
                            _medRow(Icons.email_outlined, 'Email', _inc.emergencyContactEmail!.trim()),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],

                const Spacer(),

                TextButton.icon(
                  onPressed: _deny,
                  icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                  label: const Text('DENY', style: TextStyle(color: Colors.white38, letterSpacing: 2, fontSize: 12)),
                ),
                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      const Text('Slide to Accept →',
                          style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
                      const SizedBox(height: 10),
                      Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Container(
                            width: trackWidth,
                            height: 64,
                            decoration: BoxDecoration(
                              border: Border.all(color: accent.withValues(alpha: 0.4)),
                              borderRadius: BorderRadius.circular(32),
                              color: accent.withValues(alpha: 0.1),
                            ),
                            child: const Center(
                              child: Text('ACCEPT',
                                  style: TextStyle(color: Colors.white24, letterSpacing: 4, fontSize: 13,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                          Container(
                            width: (_dragX + handleSize).clamp(handleSize, trackWidth),
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(32),
                              gradient: LinearGradient(
                                colors: [
                                  accent.withValues(alpha: (_dragX / maxDrag).clamp(0.0, 1.0) * 0.6),
                                  accent.withValues(alpha: (_dragX / maxDrag).clamp(0.0, 1.0) * 0.2),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: _dragX.clamp(0.0, maxDrag),
                            child: GestureDetector(
                              onHorizontalDragUpdate: (details) {
                                setState(() {
                                  _dragX = (_dragX + details.delta.dx).clamp(0.0, maxDrag);
                                });
                                if (_dragX >= maxDrag * 0.85) unawaited(_accept());
                              },
                              onHorizontalDragEnd: (_) {
                                if (!_accepted) setState(() => _dragX = 0.0);
                              },
                              child: Container(
                                width: handleSize,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(32),
                                  boxShadow: [
                                    BoxShadow(
                                      color: accent.withValues(alpha: 0.7),
                                      blurRadius: 20,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 22),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _medRow(IconData icon, String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white38, size: 14),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      );
}
