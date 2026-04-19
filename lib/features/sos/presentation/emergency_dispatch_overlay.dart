import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'dart:async';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/sos_escalation_service.dart';
import '../../../services/voice_comms_service.dart';
import '../../../core/utils/ptt_voice_playback.dart';
import '../../ptt/data/ptt_service.dart';
import '../../ptt/domain/ptt_models.dart';
import '../../../core/web_bridge/victim_recording.dart';

class EmergencyDispatchOverlay extends StatefulWidget {
  final String? incidentId;
  final VoidCallback onComplete;

  const EmergencyDispatchOverlay({
    super.key, 
    this.incidentId,
    required this.onComplete,
  });

  @override
  State<EmergencyDispatchOverlay> createState() => _EmergencyDispatchOverlayState();
}

enum _EscalationTier { tier1, tier2, tier3 }

class _EmergencyDispatchOverlayState extends State<EmergencyDispatchOverlay> {
  final List<String> _logs = [];
  int _step = 0;
  Timer? _seqTimer;
  Timer? _countdownTimer;
  int _secondsElapsed = 0;
  _EscalationTier _tier = _EscalationTier.tier1;
  int _acceptedCount = 0;
  StreamSubscription? _incidentSub;
  StreamSubscription<List<PttMessage>>? _pttSub;
  final Set<String> _pttSeen = {};
  bool _pttHydrated = false;
  final SosEscalationService _escalation = SosEscalationService();

  // Voice note state
  bool _isRecording = false;

  String? _lastSpokenKey;

  User? get _user => FirebaseAuth.instance.currentUser;
  String get _uid => _user?.uid ?? 'anon';
  String get _name => _user?.displayName ?? _user?.email?.split('@').first ?? 'Victim';

  final List<String> _sequence = [
    '📍 Analyzing GPS Coordinates...',
    '⚠️  Severity Classified: HIGH IMPACT',
    '🏥 Nearest Trauma Centre: Lucknow Trauma [NOTIFIED]',
    '👥 Tier 1 — Alerting Volunteers in 5 km radius...',
    '🛰️  Emergency Grid Active. Monitoring...',
  ];

  @override
  void initState() {
    super.initState();
    _startSequence();
    _startCountdown();
    _escalation.startEscalation(
      onTier2: _escalateToTier2,
      onTier3: _escalateToTier3,
    );

    final incId = widget.incidentId;
    if (incId != null && incId.isNotEmpty) {
      _pttSub = PttService.watchMessages(incId).listen((msgs) {
        if (!context.mounted) return;
        if (!_pttHydrated) {
          for (final m in msgs) {
            _pttSeen.add(m.id);
          }
          _pttHydrated = true;
          return;
        }
        for (final m in msgs) {
          if (_pttSeen.contains(m.id)) continue;
          _pttSeen.add(m.id);
          if (m.senderId == _uid) continue;
          if (m.type == PttMessageType.join) {
            if (!context.mounted) return;
            final l10n = AppLocalizations.of(context);
            final who = m.senderName.trim().isEmpty
                ? l10n.get('voice_ptt_responder_default')
                : m.senderName.trim();
            unawaited(
              VoiceCommsService.readAloud(
                l10n.get('voice_ptt_joined_comms').replaceAll('{who}', who),
              ),
            );
          } else if (m.type == PttMessageType.voice &&
              (m.audioBase64 != null && m.audioBase64!.isNotEmpty)) {
            unawaited(playPttVoiceClipBase64(m.audioBase64, mimeType: m.audioMimeType));
          }
        }
      });
    }

    if (widget.incidentId != null) {
      _incidentSub = FirebaseFirestore.instance
          .collection('sos_incidents')
          .doc(widget.incidentId)
          .snapshots()
          .listen((snap) {
        if (!snap.exists || !context.mounted) return;
        final data = snap.data();
        if (data == null) return;
        
        final ids = List<String>.from(data['acceptedVolunteerIds'] ?? []);
        if (ids.length > _acceptedCount) {
          _escalation.cancel(); // stop escalation timers once someone accepts
          setState(() {
            _acceptedCount = ids.length;
            _logs.add('✅ VOLUNTEER #$_acceptedCount ACCEPTED — En route to you!');
          });
          final id = widget.incidentId;
          if (id != null && id.isNotEmpty && context.mounted) {
            final l10n = AppLocalizations.of(context);
            unawaited(
              VoiceCommsService.readAloudForIncident(
                incidentId: id,
                text: l10n.get('voice_volunteer_accepted'),
              ),
            );
          }
        }

        final amb = data['ambulanceEta'] as String?;
        final med = data['medicalStatus'] as String?;
        final vLat = (data['volunteerLat'] as num?)?.toDouble();
        final vLng = (data['volunteerLng'] as num?)?.toDouble();

        final key = '${amb ?? ''}|${med ?? ''}|${vLat ?? ''}|${vLng ?? ''}';
        if (key != _lastSpokenKey) {
          _lastSpokenKey = key;
          if (!context.mounted) return;
          final l10n = AppLocalizations.of(context);
          final out = <String>[];
          if (amb != null && amb.isNotEmpty) {
            out.add(l10n.get('voice_ambulance_dispatched_eta').replaceAll('{eta}', amb));
          }
          if (med != null && med.isNotEmpty) out.add(med);
          if (out.isNotEmpty) {
            final id = widget.incidentId;
            if (id != null && id.isNotEmpty) {
              unawaited(
                VoiceCommsService.readAloudForIncident(
                  incidentId: id,
                  text: out.join(' '),
                ),
              );
            }
          }
        }

      });
    }
  }

  void _startSequence() {
    _seqTimer = Timer.periodic(const Duration(milliseconds: 900), (timer) {
      if (!context.mounted) return;
      if (_step < _sequence.length) {
        setState(() => _logs.add(_sequence[_step++]));
      } else {
        timer.cancel();
      }
    });
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!context.mounted) return;
      setState(() => _secondsElapsed++);
    });
  }

  void _escalateToTier2() {
    if (!context.mounted || _acceptedCount > 0) return;
    setState(() {
      _tier = _EscalationTier.tier2;
      _logs.add('⬆️  No response — expanding to 15 km radius (Tier 2)...');
    });
    SemanticsService.announce(
      'Expanding search to fifteen kilometre radius. Tier two.',
      Directionality.of(context),
    );
  }

  void _escalateToTier3() {
    if (!context.mounted || _acceptedCount > 0) return;
    setState(() {
      _tier = _EscalationTier.tier3;
      _logs.add('🚨 Still no response — Auto-dialing Emergency 112...');
    });
    SemanticsService.announce(
      'Still no response. Auto-dialing emergency one one two.',
      Directionality.of(context),
    );
    _autoDial();
  }

  Future<void> _autoDial() async {
    final uri = Uri.parse('tel:112');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // ─── Voice Note Recording ─────────────────────────────────────────────────

  void _startRecording() {
    if (widget.incidentId == null) return;
    setState(() => _isRecording = true);
    try {
      victimRecordingStart();
    } catch (e) {
      debugPrint('[Dispatch] mic start failed: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || widget.incidentId == null) return;
    setState(() => _isRecording = false);
    try {
      victimRecordingStop();
      await Future.delayed(const Duration(milliseconds: 600));
      final b64 = victimRecordingReadB64();
      if (b64 != null && b64.isNotEmpty) {
        // Ensure the PTT channel exists before sending
        await PttService.ensureChannel(widget.incidentId!, 'SOS Emergency');
        await PttService.sendVoice(widget.incidentId!, _uid, '$_name (Victim)', b64);
        victimRecordingClearB64();
        if (context.mounted) {
          setState(() => _logs.add('🎙️  Voice note sent to Incident Channel.'));
        }
      }
    } catch (e) {
      debugPrint('[Dispatch] stopRecording failed: $e');
      if (context.mounted) {
        setState(() => _logs.add('Voice note failed to send. Try again.'));
      }
    }
  }



  // ─── UI Helpers ─────────────────────────────────────────────────────────

  Color get _tierColor {
    if (_acceptedCount > 0) return AppColors.primarySafe;
    switch (_tier) {
      case _EscalationTier.tier1: return AppColors.primarySafe;
      case _EscalationTier.tier2: return Colors.orangeAccent;
      case _EscalationTier.tier3: return AppColors.primaryDanger;
    }
  }

  String get _tierLabel {
    if (_acceptedCount > 0) return '✅ $_acceptedCount VOLUNTEER${_acceptedCount > 1 ? 'S' : ''} EN ROUTE';
    switch (_tier) {
      case _EscalationTier.tier1: return '🟢 TIER 1 — 5 km Alert Zone';
      case _EscalationTier.tier2: return '🟡 TIER 2 — 15 km Alert Zone';
      case _EscalationTier.tier3: return '🔴 TIER 3 — AUTO-DIAL 112';
    }
  }

  @override
  void dispose() {
    _seqTimer?.cancel();
    _countdownTimer?.cancel();
    _incidentSub?.cancel();
    _pttSub?.cancel();
    _escalation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mins = _secondsElapsed ~/ 60;
    final secs = _secondsElapsed % 60;
    final timeStr = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    final hasResponder = _acceptedCount > 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // Header
              Row(
                children: [
                  ExcludeSemantics(
                    child: const Icon(Icons.satellite_alt_rounded, color: AppColors.primaryDanger, size: 36)
                        .animate(onPlay: (c) => c.repeat())
                        .shimmer(duration: const Duration(seconds: 2))
                        .rotate(duration: const Duration(seconds: 4)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('EMERGENCY GRID ACTIVE',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.primaryDanger, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                        Text('Elapsed: $timeStr',
                          style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace')),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Escalation Tier Banner
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: _tierColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _tierColor, width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(Icons.radar_rounded, color: _tierColor),
                    const SizedBox(width: 10),
                    Text(_tierLabel, style: TextStyle(color: _tierColor, fontWeight: FontWeight.bold, fontSize: 13)),
                    const Spacer(),
                    if (_acceptedCount == 0)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('60s → Tier 2', style: TextStyle(color: _tier == _EscalationTier.tier1 ? Colors.white54 : Colors.orangeAccent, fontSize: 9)),
                          Text('120s → 112 Auto-dial', style: TextStyle(color: _tier == _EscalationTier.tier3 ? AppColors.primaryDanger : Colors.white38, fontSize: 9)),
                        ],
                      ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),

              const SizedBox(height: 20),

              // Log Feed
              Expanded(
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final isLast = index == _logs.length - 1;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 18.0),
                      child: Text(
                        _logs[index],
                        style: TextStyle(
                          color: isLast ? Colors.white : Colors.white70,
                          fontSize: isLast ? 16 : 14,
                          fontWeight: isLast ? FontWeight.w800 : FontWeight.w500,
                          fontFamily: 'monospace',
                        ),
                      ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.08),
                    );
                  },
                ),
              ),

              // ── Voice Note Button (always visible when incidentId is set) ──
              if (widget.incidentId != null) ...[
                GestureDetector(
                  onTapDown: (_) => _startRecording(),
                  onTapUp: (_) => _stopRecording(),
                  onTapCancel: () => _stopRecording(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isRecording
                            ? [const Color(0xFFB71C1C), const Color(0xFF880E4F)]
                            : [const Color(0xFF1A1A2E), const Color(0xFF0D0D20)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _isRecording
                            ? AppColors.primaryDanger
                            : AppColors.primaryDanger.withValues(alpha: 0.4),
                        width: _isRecording ? 2 : 1,
                      ),
                      boxShadow: _isRecording
                          ? [BoxShadow(color: AppColors.primaryDanger.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 4)]
                          : [],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isRecording ? Icons.mic_rounded : Icons.mic_none_rounded,
                          color: _isRecording ? Colors.white : AppColors.primaryDanger,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isRecording ? '🔴 RECORDING — RELEASE TO SEND' : 'HOLD TO SEND VOICE NOTE',
                          style: TextStyle(
                            color: _isRecording ? Colors.white : AppColors.primaryDanger,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // ── Action Buttons ────────────────────────────────────────────
              if (hasResponder) ...[
                // Open Live Tracking & Incident Channel to communicate with the volunteer
                ElevatedButton.icon(
                  onPressed: () {
                    if (widget.incidentId == null) return;
                    context.push('/active-consignment/${widget.incidentId}?type=SOS+Emergency+(Victim)&isVictim=true');
                  },
                  icon: const Icon(Icons.satellite_alt_rounded, color: Colors.white),
                  label: Text(
                    'OPEN LIVE TRACKING ($_acceptedCount EN ROUTE)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primarySafe,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () async {
                    final incidentId = widget.incidentId;
                    if (incidentId == null) return;
                    
                    final proceed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: AppColors.surface,
                        title: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: AppColors.primaryDanger),
                            SizedBox(width: 10),
                            Expanded(child: Text('Important Notice', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                          ],
                        ),
                        content: const Text(
                          'These AI guidelines are for informational purposes only.\n\nThe safest and most immediate course of action is to call 911 (or your local emergency number).',
                          style: TextStyle(color: Colors.white70, height: 1.4),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryDanger),
                            child: const Text('I UNDERSTAND', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );

                    if (proceed == true && context.mounted) {
                      context.push('/lifeline?mode=victim&incidentId=${Uri.encodeComponent(incidentId)}');
                    }
                  },
                  icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
                  label: const Text(
                    'OPEN LIFELINE VOICE ASSISTANT',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E2740),
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.onComplete,
                  icon: const Icon(Icons.home_rounded, color: Colors.white54),
                  label: const Text('RETURN TO HOME', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: _autoDial,
                  icon: const Icon(Icons.call_rounded, color: Colors.redAccent),
                  label: const Text('CALL 112 NOW', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
