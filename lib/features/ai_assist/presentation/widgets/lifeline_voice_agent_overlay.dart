import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:emergency_os/core/theme/app_colors.dart';
import 'package:emergency_os/features/ai_assist/domain/lifeline_training_levels.dart';
import 'package:emergency_os/services/lifeline_voice_agent_service.dart';
import 'package:emergency_os/services/voice_comms_service.dart';

/// Floating push-to-talk mic bubble + compact transcript card while the agent speaks.
class LifelineVoiceAgentOverlay extends StatefulWidget {
  final int? activeLevelIndex;
  final String? activeLevelTitle;
  final EdgeInsets safePadding;
  final bool isDrillShell;

  const LifelineVoiceAgentOverlay({
    super.key,
    this.activeLevelIndex,
    this.activeLevelTitle,
    this.safePadding = EdgeInsets.zero,
    this.isDrillShell = false,
  });

  @override
  State<LifelineVoiceAgentOverlay> createState() =>
      _LifelineVoiceAgentOverlayState();
}

class _LifelineVoiceAgentOverlayState extends State<LifelineVoiceAgentOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  LifelineVoiceState _uiState = LifelineVoiceState.idle;
  bool _callbacksAttached = false;

  String? _voiceReplyText;
  int? _voiceReplyLibraryId;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_callbacksAttached) {
      _callbacksAttached = true;
      _attachCallbacks();
    }
  }

  void _attachCallbacks() {
    final service = LifelineVoiceAgentService.instance;
    service.setOnStateChanged((state) {
      if (!mounted) return;
      setState(() => _uiState = state);
      if (state == LifelineVoiceState.listening) {
        setState(() {
          _voiceReplyText = null;
          _voiceReplyLibraryId = null;
        });
        _pulseController.repeat(reverse: true);
      } else if (state == LifelineVoiceState.speaking) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    });

    service.setOnVoiceReply((spoken, openLibraryLevelId) {
      if (!mounted) return;
      setState(() {
        _voiceReplyText = spoken;
        _voiceReplyLibraryId = openLibraryLevelId;
      });
      // Auto-open the matching Lifeline library level if Gemini linked one.
      // The reply card stays visible with the transcript + quick jump button.
      if (openLibraryLevelId != null &&
          widget.activeLevelIndex != openLibraryLevelId) {
        final known = _libraryTitleFor(openLibraryLevelId) != null;
        if (known) {
          _goToLibraryLevel(openLibraryLevelId);
        }
      }
    });

    service.setOnMicError((code) {
      if (!mounted) return;
      final msg = code == 'not_available'
          ? 'Speech recognition is not available. Check microphone permission or try another device.'
          : 'Voice input error: $code';
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    });
  }

  String get _lifelineBase =>
      widget.isDrillShell ? '/drill/lifeline' : '/lifeline';

  void _goToLibraryLevel(int levelId) {
    context.go('$_lifelineBase?openAid=$levelId');
  }

  String? _libraryTitleFor(int? id) {
    if (id == null) return null;
    for (final l in kLifelineTrainingLevels) {
      if (l.id == id) return l.title;
    }
    return null;
  }

  void _dismissReplyCard() {
    setState(() {
      _voiceReplyText = null;
      _voiceReplyLibraryId = null;
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    LifelineVoiceAgentService.instance.detachOverlay();
    super.dispose();
  }

  void _onLongPressStart() {
    if (kIsWeb) {
      VoiceCommsService.primeForVoiceGuidance();
    }
    HapticFeedback.mediumImpact();
    LifelineVoiceAgentService.instance.beginHold();
  }

  void _onLongPressEnd() {
    HapticFeedback.lightImpact();
    LifelineVoiceAgentService.instance.endHold();
  }

  void _onTap() {
    final s = LifelineVoiceAgentService.instance.state;
    switch (s) {
      case LifelineVoiceState.speaking:
        HapticFeedback.lightImpact();
        LifelineVoiceAgentService.instance.cancelSpeaking();
        _dismissReplyCard();
        break;
      case LifelineVoiceState.listening:
        HapticFeedback.lightImpact();
        LifelineVoiceAgentService.instance.abortListening();
        break;
      case LifelineVoiceState.idle:
      case LifelineVoiceState.thinking:
        break;
    }
  }

  Color _agentColor() {
    switch (_uiState) {
      case LifelineVoiceState.idle:
        return AppColors.textSecondary;
      case LifelineVoiceState.listening:
        return const Color(0xFFFF1744);
      case LifelineVoiceState.thinking:
        return const Color(0xFF2979FF);
      case LifelineVoiceState.speaking:
        return const Color(0xFF00E676);
    }
  }

  List<BoxShadow> _agentShadows() {
    final pulse = (_uiState == LifelineVoiceState.listening ||
            _uiState == LifelineVoiceState.speaking)
        ? 0.4 + 0.45 * _pulseController.value
        : 0.3;

    switch (_uiState) {
      case LifelineVoiceState.idle:
        return [];
      case LifelineVoiceState.listening:
        return [
          BoxShadow(
            color: const Color(0xFFFF1744).withValues(alpha: pulse),
            blurRadius: 18 + 14 * _pulseController.value,
            spreadRadius: 2 + 2 * _pulseController.value,
          ),
          BoxShadow(
            color: Colors.orangeAccent.withValues(alpha: 0.35 * pulse),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ];
      case LifelineVoiceState.thinking:
        return [
          BoxShadow(
            color: const Color(0xFF2979FF).withValues(alpha: 0.45),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ];
      case LifelineVoiceState.speaking:
        return [
          BoxShadow(
            color: const Color(0xFF00E676).withValues(alpha: 0.5),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ];
    }
  }

  String _tooltipText() {
    switch (_uiState) {
      case LifelineVoiceState.idle:
        return 'Hold to speak';
      case LifelineVoiceState.listening:
        return 'Release to send';
      case LifelineVoiceState.thinking:
        return 'Thinking…';
      case LifelineVoiceState.speaking:
        return 'Tap to stop';
    }
  }

  double _agentScale() {
    if (_uiState != LifelineVoiceState.listening) return 1.0;
    return 1.0 + 0.08 * _pulseController.value;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = widget.safePadding.bottom + 16;
    const right = 16.0;
    final maxCardW = math.min(
      MediaQuery.sizeOf(context).width - 78,
      320.0,
    );
    final libTitle = _libraryTitleFor(_voiceReplyLibraryId);
    final showCard = _voiceReplyText != null && _voiceReplyText!.trim().isNotEmpty;

    return Positioned(
      right: right,
      bottom: bottom,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showCard)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                elevation: 12,
                color: AppColors.surface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(14),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxCardW,
                    maxHeight: 220,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.record_voice_over_rounded,
                              size: 18,
                              color: AppColors.primaryInfo,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Speaking',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              tooltip: 'Dismiss',
                              onPressed: _dismissReplyCard,
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: AppColors.stroke.withValues(alpha: 0.5),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                          child: Text(
                            _voiceReplyText!.trim(),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      if (libTitle != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: TextButton.icon(
                            onPressed: () {
                              final id = _voiceReplyLibraryId;
                              if (id == null) return;
                              HapticFeedback.lightImpact();
                              _goToLibraryLevel(id);
                            },
                            icon: Icon(
                              Icons.menu_book_rounded,
                              size: 18,
                              color: AppColors.primaryInfo,
                            ),
                            label: Text(
                              'Open: $libTitle',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryInfo,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          Tooltip(
            message: _tooltipText(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPressStart: (_) => _onLongPressStart(),
              onLongPressEnd: (_) => _onLongPressEnd(),
              onLongPressCancel: _onLongPressEnd,
              onTap: _onTap,
              child: Transform.scale(
                scale: _agentScale(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _agentColor().withValues(alpha: 0.2),
                        _agentColor().withValues(alpha: 0.1),
                      ],
                    ),
                    border: Border.all(
                      color: _agentColor(),
                      width: _uiState == LifelineVoiceState.idle ? 1.5 : 2.5,
                    ),
                    boxShadow: _agentShadows(),
                  ),
                  child: _buildAvatar(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (_uiState == LifelineVoiceState.speaking) _buildSoundWaves(),
        if (_uiState == LifelineVoiceState.listening) _buildListeningIndicator(),
        Icon(
          Icons.medical_services_rounded,
          size: 28,
          color: _agentColor(),
        ),
      ],
    );
  }

  Widget _buildListeningIndicator() {
    return Positioned(
      bottom: 4,
      right: 4,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _agentColor(),
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }

  Widget _buildSoundWaves() {
    return SizedBox(
      width: 50,
      height: 50,
      child: CustomPaint(
        painter: _SoundWavePainter(
          color: _agentColor(),
          progress: _pulseController.value,
        ),
      ),
    );
  }
}

class _SoundWavePainter extends CustomPainter {
  final Color color;
  final double progress;

  _SoundWavePainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (var i = 0; i < 3; i++) {
      final delay = i * 0.2;
      final adjustedProgress = ((progress + delay) % 1.0);
      final radius = maxRadius * 0.6 + (maxRadius * 0.5 * adjustedProgress);
      final opacity = (1.0 - adjustedProgress) * 0.5;

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SoundWavePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
