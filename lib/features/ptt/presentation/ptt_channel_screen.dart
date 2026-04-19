import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/ptt_voice_playback.dart';
import '../../../services/voice_comms_service.dart';
import '../data/ptt_service.dart';
import '../domain/ptt_models.dart';
import '../../../core/web_bridge/ptt_recording.dart';

/// Zello-inspired PTT coordination channel per incident.
/// Features:
///   - Real-time Firestore message stream
///   - Hold-to-Talk voice recording (Web Audio MediaRecorder → base64)
///   - Text messaging
///   - Responder PANIC button
///   - Historical comms timeline
class PttChannelScreen extends ConsumerStatefulWidget {
  final String incidentId;
  final String incidentType;

  const PttChannelScreen({
    super.key,
    required this.incidentId,
    required this.incidentType,
  });

  @override
  ConsumerState<PttChannelScreen> createState() => _PttChannelScreenState();
}

class _PttChannelScreenState extends ConsumerState<PttChannelScreen>
    with TickerProviderStateMixin {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  bool _isRecording = false;
  bool _panicConfirmVisible = false;

  late AnimationController _pttPulseCtrl;
  late AnimationController _panicPulseCtrl;
  late Animation<double> _pttPulse;
  late Animation<double> _panicPulse;

  StreamSubscription<List<PttMessage>>? _commsSub;
  final Set<String> _seenPttIds = {};
  bool _pttListHydrated = false;

  User? get _user => FirebaseAuth.instance.currentUser;
  String get _uid => _user?.uid ?? 'anon';
  String get _name => _user?.displayName ?? _user?.email?.split('@').first ?? 'Responder';

  String get _channelId => widget.incidentId;

  @override
  void initState() {
    super.initState();
    _pttPulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _panicPulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))
      ..repeat(reverse: true);
    _pttPulse = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pttPulseCtrl, curve: Curves.easeInOut));
    _panicPulse = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _panicPulseCtrl, curve: Curves.easeInOut));

    // Join channel on screen open (idempotent)
    PttService.ensureChannel(widget.incidentId, widget.incidentType)
        .then((_) => PttService.joinChannel(widget.incidentId, _uid, _name));

    _commsSub = PttService.watchMessages(widget.incidentId).listen((msgs) {
      if (!_pttListHydrated) {
        for (final m in msgs) {
          _seenPttIds.add(m.id);
        }
        _pttListHydrated = true;
        return;
      }
      for (final m in msgs) {
        if (_seenPttIds.contains(m.id)) continue;
        _seenPttIds.add(m.id);
        if (m.senderId == _uid) continue;
        if (m.type == PttMessageType.join) {
          if (!mounted) return;
          final l10n = AppLocalizations.of(context);
          final who = m.senderName.trim().isEmpty
              ? l10n.get('voice_ptt_responder_default')
              : m.senderName.trim();
          unawaited(
            VoiceCommsService.readAloud(
              l10n.get('voice_ptt_joined_comms').replaceAll('{who}', who),
            ),
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _commsSub?.cancel();
    _stopRecording();
    _pttPulseCtrl.dispose();
    _panicPulseCtrl.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Voice Recording (Web Audio MediaRecorder API) ────────────────────

  void _startRecording() {
    setState(() => _isRecording = true);
    HapticFeedback.heavyImpact();
    try {
      pttRecordingStart();
    } catch (_) {}
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    setState(() => _isRecording = false);
    try {
      pttRecordingStop();
      // Give MediaRecorder time to finish encoding
      await Future.delayed(Duration(milliseconds: kIsWeb ? 650 : 500));
      final b64 = pttRecordingReadB64();
      final mime = kIsWeb ? pttRecordingReadMime() : null;
      if (b64 != null && b64.isNotEmpty) {
        await PttService.sendVoice(_channelId, _uid, _name, b64, audioMimeType: mime);
        pttRecordingClearB64();
      }
    } catch (_) {}
  }

  // ─── Play voice clip ──────────────────────────────────────────────────

  void _playAudio(PttMessage msg) {
    final b64 = msg.audioBase64;
    if (b64 == null || b64.isEmpty) return;
    unawaited(playPttVoiceClipBase64(b64, mimeType: msg.audioMimeType));
  }

  // ─── Panic ────────────────────────────────────────────────────────────

  void _triggerPanic() {
    setState(() => _panicConfirmVisible = false);
    HapticFeedback.vibrate();
    PttService.triggerPanic(widget.incidentId, _uid, _name);
  }

  // ─── Send text ────────────────────────────────────────────────────────

  void _sendText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    PttService.sendText(_channelId, _uid, _name, text);
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final channelAsync = ref.watch(pttChannelProvider(_channelId));
    final channel = channelAsync.value;
    final messagesAsync = ref.watch(pttMessagesProvider(_channelId));
    final hasPanic = channel?.hasPanic ?? false;

    // Auto-scroll when new messages arrive
    ref.listen(pttMessagesProvider(_channelId), (_, __) {
      Future.delayed(const Duration(milliseconds: 150), _scrollToBottom);
    });

    return Listener(
      onPointerDown: (_) {
        if (kIsWeb) {
          // Interaction unlock for audio context is now handled via the global AudioMeter/Alarm logic or simply browser default.
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF080B14),
        body: Column(
          children: [
            _buildHeader(channel, hasPanic),
            Expanded(child: _buildMessageList(messagesAsync)),
            if (_panicConfirmVisible) _buildPanicConfirm(),
            _buildBottomBar(hasPanic),
          ],
        ),
      ),
    );
  }

  String get _channelTitleLabel {
    if (widget.incidentType == 'command_operations') return 'Operation channel';
    return widget.incidentType;
  }

  Widget _buildHeader(PttChannel? channel, bool hasPanic) {
    final memberCount = channel?.memberIds.length ?? 1;
    return Container(
      color: const Color(0xFF0A0E1A),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white54, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasPanic
                          ? 'PANIC — ${channel?.panicActiveName ?? "Responder"}'
                          : _channelTitleLabel,
                      style: TextStyle(
                        color: hasPanic ? Colors.red : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$memberCount on channel',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Colors.green, size: 6),
                    SizedBox(width: 4),
                    Text('LIVE', style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList(AsyncValue<List<PttMessage>> messagesAsync) {
    return messagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryDanger)),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
      data: (messages) {
        if (messages.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.radio_rounded, color: Colors.white24, size: 48),
                SizedBox(height: 12),
                Text('Channel open. You are the first responder.',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
                SizedBox(height: 4),
                Text('Hold the button below to broadcast.',
                    style: TextStyle(color: Colors.white24, fontSize: 12)),
              ],
            ),
          );
        }
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          itemCount: messages.length,
          itemBuilder: (context, i) => _buildMessage(messages[i]),
        );
      },
    );
  }

  Widget _buildMessage(PttMessage msg) {
    final isMe = msg.senderId == _uid;
    final timeStr = DateFormat('HH:mm').format(msg.timestamp);

    // System events (join, panic, resolved)
    if (msg.type == PttMessageType.join) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${msg.senderName} joined the channel · $timeStr',
                style: const TextStyle(color: Colors.green, fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }

    if (msg.type == PttMessageType.panic) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PANIC ALERT', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 2)),
                    const SizedBox(height: 2),
                    Text(msg.text ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              Text(timeStr, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
        ),
      );
    }

    // Voice and text bubbles
    return Padding(
      padding: EdgeInsets.only(
        top: 4, bottom: 4,
        left: isMe ? 48 : 0,
        right: isMe ? 0 : 48,
      ),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Text(msg.senderName,
                  style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          Container(
            decoration: BoxDecoration(
              color: isMe
                  ? AppColors.primaryDanger.withValues(alpha: 0.15)
                  : const Color(0xFF1C2340),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 16),
              ),
              border: Border.all(
                color: isMe
                    ? AppColors.primaryDanger.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: msg.type == PttMessageType.voice
                ? _buildVoiceBubble(msg, timeStr)
                : _buildTextBubble(msg, timeStr),
          ),
        ],
      ),
    );
  }

  Widget _buildTextBubble(PttMessage msg, String timeStr) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Text(msg.text ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
        ),
        const SizedBox(width: 8),
        Text(timeStr, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
  }

  Widget _buildVoiceBubble(PttMessage msg, String timeStr) {
    return GestureDetector(
      onTap: () {
        if (msg.audioBase64 != null) _playAudio(msg);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryDanger.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow_rounded, color: AppColors.primaryDanger, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Voice clip', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.mic_rounded, color: Colors.white38, size: 11),
                  const SizedBox(width: 4),
                  Text(timeStr, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Waveform decoration
          Row(
            children: List.generate(8, (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: 8.0 + (i % 3) * 6.0,
              decoration: BoxDecoration(
                color: AppColors.primaryDanger.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
          ),
        ],
      ),
    );
  }

  Widget _buildPanicConfirm() {
    return AnimatedBuilder(
      animation: _panicPulse,
      builder: (context, child) => Transform.scale(scale: _panicPulse.value, child: child),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2D0000),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red, width: 2),
        ),
        child: Column(
          children: [
            const Text('⚠️ CONFIRM PANIC', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 2)),
            const SizedBox(height: 8),
            const Text('This will alert all responders in this channel that you need immediate help.',
                style: TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _panicConfirmVisible = false),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white38)),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _triggerPanic,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('SEND PANIC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(bool hasPanic) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0E1A),
        border: Border(top: BorderSide(color: Color(0xFF161B2E), width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Broadcast: Listener works reliably for press-and-hold on web (GestureDetector often misses paired up/cancel).
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _startRecording(),
            onPointerUp: (_) => _stopRecording(),
            onPointerCancel: (_) => _stopRecording(),
            child: AnimatedBuilder(
              animation: _pttPulse,
              builder: (context, child) => Transform.scale(
                scale: _isRecording ? _pttPulse.value : 1.0,
                child: child,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isRecording
                        ? [const Color(0xFFB71C1C), const Color(0xFF880E4F)]
                        : [AppColors.primaryDanger, const Color(0xFF8B0000)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryDanger.withValues(alpha: _isRecording ? 0.6 : 0.25),
                      blurRadius: _isRecording ? 20 : 8,
                      spreadRadius: _isRecording ? 2 : 0,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isRecording ? Icons.mic_rounded : Icons.cell_tower_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isRecording ? 'BROADCASTING...' : 'HOLD TO BROADCAST',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Text + Panic row (secondary)
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF111625),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF1E2740)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'Text message...',
                            hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _sendText(),
                        ),
                      ),
                      GestureDetector(
                        onTap: _sendText,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(Icons.send_rounded, color: Colors.white38, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _panicConfirmVisible = !_panicConfirmVisible),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: hasPanic ? Colors.red.withValues(alpha: 0.25) : const Color(0xFF1C0A0A),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: hasPanic ? Colors.red : Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(Icons.emergency_rounded,
                      color: hasPanic ? Colors.red : Colors.red.withValues(alpha: 0.5),
                      size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
