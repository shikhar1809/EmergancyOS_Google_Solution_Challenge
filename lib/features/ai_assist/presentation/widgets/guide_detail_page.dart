import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/utils/emergency_numbers.dart';
import '../../../../core/utils/speech_web.dart'
    if (dart.library.io) '../../../../core/utils/speech_io.dart';
import '../../domain/lifeline_training_levels.dart';
import 'technique_visuals.dart';

class GuideDetailPage extends StatefulWidget {
  final LifelineTrainingLevel level;
  final bool isActive;
  final int pageIndex;
  final int totalPages;
  final EdgeInsets safePadding;
  final bool emergencyMode;

  const GuideDetailPage({
    super.key,
    required this.level,
    required this.isActive,
    required this.pageIndex,
    required this.totalPages,
    required this.safePadding,
    this.emergencyMode = false,
  });

  @override
  State<GuideDetailPage> createState() => _GuideDetailPageState();
}

class _GuideDetailPageState extends State<GuideDetailPage> {
  bool _isSpeaking = false;
  bool _ttsAvailable = false;
  int _highlightedStep = -1;
  Timer? _visualTimer;
  /// Safety watchdog: if TTS onDone never fires (Firefox/WebKit), this auto-recovers.
  Timer? _ttsStuckGuard;
  bool _visualWalkthroughActive = false;
  bool _autoVoiceTriggered = false;

  bool get _isEmergency => widget.emergencyMode;

  @override
  void initState() {
    super.initState();
    _ttsAvailable = speechSupported();
  }

  @override
  void dispose() {
    _visualTimer?.cancel();
    _ttsStuckGuard?.cancel();
    if (_isSpeaking) cancelSpeechText();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GuideDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.isActive && _isSpeaking) {
      cancelSpeechText();
      setState(() => _isSpeaking = false);
    }
    if (!widget.isActive && _visualWalkthroughActive) {
      _stopVisualWalkthrough();
    }

    // Auto-play when page becomes active.
    // On web, TTS needs a user gesture so we start the visual walkthrough first;
    // the user can still tap the voice button to unlock audio manually.
    // On native (mobile/desktop), start full TTS immediately.
    if (_isEmergency &&
        widget.isActive &&
        !oldWidget.isActive &&
        !_autoVoiceTriggered) {
      _autoVoiceTriggered = true;
      Future.microtask(() => _startWalkthrough());
    }
    if (!widget.isActive) {
      _autoVoiceTriggered = false;
    }
  }

  // ─── WALKTHROUGH LOGIC ───

  String _buildVoiceScript() {
    final l = AppLocalizations.of(context);
    final buf = StringBuffer();
    buf.write('${widget.level.title}. ${widget.level.subtitle}. ');
    for (var i = 0; i < widget.level.infographic.length; i++) {
      final step = widget.level.infographic[i];
      buf.write('${l.stepPrefix} ${i + 1}: ${step.headline}. ${step.detail}. ');
    }
    if (widget.level.cautions.isNotEmpty) {
      buf.write('${l.cautions}. ');
      for (final c in widget.level.cautions) {
        buf.write('$c. ');
      }
    }
    return buf.toString().trim();
  }

  void _startWalkthrough() {
    if (_ttsAvailable) {
      _startSpeech();
    } else {
      _startVisualWalkthrough();
    }
  }

  void _stopWalkthrough() {
    if (_isSpeaking) {
      cancelSpeechText();
      setState(() => _isSpeaking = false);
    }
    if (_visualWalkthroughActive) {
      _stopVisualWalkthrough();
    }
  }

  void _toggleWalkthrough() {
    // Must call synchronously inside a user gesture so the Web Speech
    // Synthesis autoplay gate is satisfied before speakText() fires.
    primeSpeechAudioContext();
    if (_isSpeaking || _visualWalkthroughActive) {
      _stopWalkthrough();
    } else {
      _startWalkthrough();
    }
  }

  void _startSpeech() {
    primeSpeechAudioContext();
    final script = _buildVoiceScript();
    setState(() => _isSpeaking = true);

    void _onTtsDone() {
      _ttsStuckGuard?.cancel();
      _ttsStuckGuard = null;
      if (context.mounted) setState(() => _isSpeaking = false);
    }

    try {
      speakText(script, onDone: _onTtsDone);
    } catch (_) {
      // TTS threw synchronously — fall back to visual walkthrough.
      _ttsStuckGuard?.cancel();
      setState(() {
        _isSpeaking = false;
        _ttsAvailable = false;
      });
      _startVisualWalkthrough();
      return;
    }

    // Stuck-guard: if onDone never fires (Firefox/WebKit speechSynthesis.onend bug),
    // force recovery after estimated duration + 5 s buffer.
    _ttsStuckGuard?.cancel();
    final estMs = (script.length * 80 + 5000).clamp(8000, 120000);
    _ttsStuckGuard = Timer(Duration(milliseconds: estMs), () {
      debugPrint('[Lifeline] TTS stuck after ${estMs}ms — falling back to visual');
      if (!context.mounted) return;
      cancelSpeechText();
      setState(() => _isSpeaking = false);
      if (!_visualWalkthroughActive) _startVisualWalkthrough();
    });
  }

  void _startVisualWalkthrough() {
    final totalSteps = widget.level.infographic.length +
        (widget.level.cautions.isNotEmpty ? 1 : 0);
    setState(() {
      _visualWalkthroughActive = true;
      _highlightedStep = 0;
    });
    _visualTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!context.mounted) {
        timer.cancel();
        return;
      }
      final next = _highlightedStep + 1;
      if (next >= totalSteps) {
        _stopVisualWalkthrough();
      } else {
        setState(() => _highlightedStep = next);
      }
    });
  }

  void _stopVisualWalkthrough() {
    _visualTimer?.cancel();
    _visualTimer = null;
    if (context.mounted) {
      setState(() {
        _visualWalkthroughActive = false;
        _highlightedStep = -1;
      });
    }
  }

  bool get _walkthroughActive => _isSpeaking || _visualWalkthroughActive;

  Future<void> _callEmergency() async {
    final locale = Localizations.localeOf(context);
    final number = EmergencyNumbers.primaryNumberForLocale(locale);
    final url = Uri.parse('tel:$number');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _openVideo() async {
    final url = Uri.parse(
        'https://www.youtube.com/watch?v=${widget.level.youtubeVideoId}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // ─── sizing helpers ───

  double _titleSize() => _isEmergency ? 28 : 22;
  double _subtitleSize() => _isEmergency ? 16 : 13;
  double _stepHeadlineSize() => _isEmergency ? 18 : 15;
  double _stepDetailSize() => _isEmergency ? 16 : 13.5;
  double _flagTextSize() => _isEmergency ? 15 : 13;
  double _voiceLabelSize() => _isEmergency ? 17 : 14;
  double _voiceIconSize() => _isEmergency ? 56.0 : 44.0;
  double _stepBadgeSize() => _isEmergency ? 40.0 : 32.0;

  int _animDelay(int baseMs) => _isEmergency ? 0 : baseMs;

  // ─── BUILD ───

  @override
  Widget build(BuildContext context) {
    final level = widget.level;
    final accent = _isEmergency ? AppColors.primaryDanger : level.accent;

    return Padding(
      padding: EdgeInsets.only(
        top: widget.safePadding.top + 8,
        bottom: widget.safePadding.bottom + 8,
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroHeader(level, accent),
            if (_isEmergency) ...[
              const SizedBox(height: 16),
              _buildCallBanner(),
            ],
            const SizedBox(height: 16),
            _buildVoiceBar(accent),
            const SizedBox(height: 20),
            _buildVisualDiagram(level, accent),
            const SizedBox(height: 20),
            _buildDetailedSteps(level, accent),
            if (level.redFlags.isNotEmpty) ...[
              const SizedBox(height: 18),
              _buildRedFlags(level.redFlags),
            ],
            if (level.cautions.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildCautions(level.cautions),
            ],
            if (!_isEmergency) ...[
              const SizedBox(height: 18),
              _buildVideoLink(accent),
            ],
            const SizedBox(height: 14),
            _buildSwipeHint(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ─── CALL 112 BANNER ───

  Widget _buildCallBanner() {
    final locale = Localizations.localeOf(context);
    final number = EmergencyNumbers.primaryNumberForLocale(locale);

    return GestureDetector(
      onTap: _callEmergency,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: AppColors.dangerGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDanger.withValues(alpha: 0.4),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.phone_in_talk_rounded,
                color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Text(
              '${AppLocalizations.of(context).callNow} $number',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── HERO HEADER ───

  Widget _buildHeroHeader(LifelineTrainingLevel level, Color accent) {
    return Row(
      children: [
        Container(
          width: _isEmergency ? 60 : 52,
          height: _isEmergency ? 60 : 52,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                accent.withValues(alpha: 0.25),
                accent.withValues(alpha: 0.05),
              ],
              radius: 0.8,
            ),
            borderRadius: BorderRadius.circular(_isEmergency ? 18 : 15),
            border: Border.all(
              color: accent.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Icon(level.icon, color: accent,
              size: _isEmergency ? 30 : 26),
        )
            .animate(target: widget.isActive ? 1 : 0)
            .scale(
              begin: const Offset(0.5, 0.5),
              end: const Offset(1.0, 1.0),
              curve: Curves.elasticOut,
              duration: _isEmergency ? 200.ms : 600.ms,
            )
            .fadeIn(duration: _isEmergency ? 100.ms : 300.ms),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                level.title,
                style: GoogleFonts.outfit(
                  fontSize: _titleSize(),
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              )
                  .animate(target: widget.isActive ? 1 : 0)
                  .fadeIn(duration: 400.ms, delay: _animDelay(100).ms)
                  .slideX(begin: 0.15, end: 0, curve: Curves.easeOutCubic,
                      duration: 400.ms, delay: _animDelay(100).ms),
              const SizedBox(height: 3),
              Text(
                level.subtitle,
                style: GoogleFonts.inter(
                  fontSize: _subtitleSize(),
                  color: accent.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w500,
                ),
              )
                  .animate(target: widget.isActive ? 1 : 0)
                  .fadeIn(duration: 400.ms, delay: _animDelay(180).ms)
                  .slideX(begin: 0.15, end: 0, curve: Curves.easeOutCubic,
                      duration: 400.ms, delay: _animDelay(180).ms),
            ],
          ),
        ),
      ],
    );
  }

  // ─── VOICE / VISUAL WALKTHROUGH BAR ───

  Widget _buildVoiceBar(Color accent) {
    final isActive = _walkthroughActive;
    final l = AppLocalizations.of(context);
    final label = !_ttsAvailable
        ? (isActive ? '${l.visualWalkthrough}...' : l.visualWalkthrough)
        : (isActive ? l.playing : l.voiceWalkthrough);

    final progressFraction = _visualWalkthroughActive
        ? (_highlightedStep + 1) /
            (widget.level.infographic.length +
                (widget.level.cautions.isNotEmpty ? 1 : 0))
        : null;

    return GestureDetector(
      onTap: _toggleWalkthrough,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: _isEmergency ? 14 : 10,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? accent.withValues(alpha: 0.15)
              : accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? accent.withValues(alpha: 0.4)
                : accent.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: _voiceIconSize(),
                  height: _voiceIconSize(),
                  decoration: BoxDecoration(
                    color: isActive
                        ? accent
                        : accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(
                        _isEmergency ? 16 : 12),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.4),
                              blurRadius: 14,
                            )
                          ]
                        : null,
                  ),
                  child: Icon(
                    isActive
                        ? Icons.stop_rounded
                        : (_ttsAvailable
                            ? Icons.volume_up_rounded
                            : Icons.text_fields_rounded),
                    color: isActive ? Colors.white : accent,
                    size: _isEmergency ? 26 : 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: _voiceLabelSize(),
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (!_ttsAvailable && !isActive)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            l.highlightsSteps,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_isSpeaking)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: accent,
                    ),
                  ),
              ],
            ),
            if (progressFraction != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progressFraction,
                  minHeight: 4,
                  backgroundColor: accent.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
            ],
          ],
        ),
      ),
    )
        .animate(target: widget.isActive ? 1 : 0)
        .fadeIn(duration: 400.ms, delay: _animDelay(220).ms)
        .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic,
            duration: 400.ms, delay: _animDelay(220).ms);
  }

  // ─── VISUAL DIAGRAM ───

  Widget _buildVisualDiagram(LifelineTrainingLevel level, Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surface,
            accent.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: accent.withValues(alpha: 0.14),
            blurRadius: 20,
            spreadRadius: -4,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            AppLocalizations.of(context).quickGuide,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accent.withValues(alpha: 0.7),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420, minHeight: 160),
            child: techniqueVisualFor(level.id, accent),
          ),
        ],
      ),
    )
        .animate(target: widget.isActive ? 1 : 0)
        .fadeIn(duration: 500.ms, delay: _animDelay(300).ms)
        .scaleXY(
          begin: _isEmergency ? 1.0 : 0.92,
          end: 1.0,
          curve: Curves.easeOutCubic,
          duration: 500.ms,
          delay: _animDelay(300).ms,
        );
  }

  // ─── DETAILED STEPS ───

  Widget _buildDetailedSteps(LifelineTrainingLevel level, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).detailedInstructions,
          style: GoogleFonts.inter(
            fontSize: _isEmergency ? 12 : 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 1.5,
          ),
        )
            .animate(target: widget.isActive ? 1 : 0)
            .fadeIn(duration: 300.ms, delay: _animDelay(550).ms),
        const SizedBox(height: 12),
        ...List.generate(level.infographic.length, (i) {
          final step = level.infographic[i];
          final stagger = _animDelay(580 + (i * 80));
          final isHighlighted = _visualWalkthroughActive && _highlightedStep == i;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.only(bottom: 10),
            padding: isHighlighted
                ? const EdgeInsets.all(8)
                : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: isHighlighted
                  ? accent.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isHighlighted
                  ? Border.all(color: accent.withValues(alpha: 0.4), width: 1.5)
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: isHighlighted ? _stepBadgeSize() + 6 : _stepBadgeSize(),
                  height: isHighlighted ? _stepBadgeSize() + 6 : _stepBadgeSize(),
                  decoration: BoxDecoration(
                    color: isHighlighted
                        ? accent.withValues(alpha: 0.25)
                        : accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: isHighlighted
                        ? Border.all(color: accent, width: 2)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: GoogleFonts.outfit(
                      fontSize: _isEmergency ? 16 : 13,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.headline,
                        style: GoogleFonts.inter(
                          fontSize: _stepHeadlineSize(),
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        step.detail,
                        style: GoogleFonts.inter(
                          fontSize: _stepDetailSize(),
                          color: isHighlighted
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
              .animate(target: widget.isActive ? 1 : 0)
              .fadeIn(duration: 350.ms, delay: stagger.ms)
              .slideX(begin: 0.08, end: 0, curve: Curves.easeOutCubic,
                  duration: 350.ms, delay: stagger.ms);
        }),
      ],
    );
  }

  // ─── RED FLAGS ───

  Widget _buildRedFlags(List<String> redFlags) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryDanger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primaryDanger.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryDanger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.error_rounded,
                    color: AppColors.primaryDanger, size: _isEmergency ? 18 : 14),
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).redFlags,
                style: GoogleFonts.inter(
                  fontSize: _isEmergency ? 13 : 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDanger,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...redFlags.map((flag) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryDanger,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        flag,
                        style: GoogleFonts.inter(
                          fontSize: _flagTextSize(),
                          color: AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    )
        .animate(target: widget.isActive ? 1 : 0)
        .fadeIn(duration: 400.ms, delay: _animDelay(750).ms)
        .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic,
            duration: 400.ms, delay: _animDelay(750).ms);
  }

  // ─── CAUTIONS ───

  Widget _buildCautions(List<String> cautions) {
    final isHighlighted = _visualWalkthroughActive &&
        _highlightedStep == widget.level.infographic.length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isHighlighted
            ? AppColors.primaryWarning.withValues(alpha: 0.12)
            : AppColors.primaryWarning.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHighlighted
              ? AppColors.primaryWarning.withValues(alpha: 0.5)
              : AppColors.primaryWarning.withValues(alpha: 0.2),
          width: isHighlighted ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryWarning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.warning_amber_rounded,
                    color: AppColors.primaryWarning, size: _isEmergency ? 18 : 14),
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context).cautions,
                style: GoogleFonts.inter(
                  fontSize: _isEmergency ? 13 : 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryWarning,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...cautions.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryWarning,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c,
                        style: GoogleFonts.inter(
                          fontSize: _flagTextSize(),
                          color: isHighlighted
                              ? AppColors.textPrimary
                              : AppColors.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    )
        .animate(target: widget.isActive ? 1 : 0)
        .fadeIn(duration: 400.ms, delay: _animDelay(830).ms)
        .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic,
            duration: 400.ms, delay: _animDelay(830).ms);
  }

  // ─── VIDEO LINK ───

  Widget _buildVideoLink(Color accent) {
    return Center(
      child: TextButton.icon(
        onPressed: _openVideo,
        icon: Icon(Icons.play_circle_outline_rounded, color: accent, size: 18),
        label: Text(
          AppLocalizations.of(context).watchVideoGuide,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: accent,
          ),
        ),
      ),
    )
        .animate(target: widget.isActive ? 1 : 0)
        .fadeIn(duration: 400.ms, delay: _animDelay(900).ms);
  }

  // ─── SWIPE HINT ───

  Widget _buildSwipeHint() {
    if (widget.pageIndex >= widget.totalPages - 1) {
      return const SizedBox.shrink();
    }

    if (_isEmergency) {
      return Center(
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          color: AppColors.textSecondary.withValues(alpha: 0.3),
          size: 30,
        ),
      );
    }

    return Center(
      child: Column(
        children: [
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textSecondary.withValues(alpha: 0.35),
            size: 26,
          ),
          Text(
            AppLocalizations.of(context).swipeNextGuide,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppColors.textSecondary.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    )
        .animate(target: widget.isActive ? 1 : 0)
        .fadeIn(duration: 600.ms, delay: 1200.ms)
        .then()
        .slideY(
            begin: 0, end: 0.15, duration: 1200.ms, curve: Curves.easeInOut)
        .then()
        .slideY(
            begin: 0.15, end: 0, duration: 1200.ms, curve: Curves.easeInOut);
  }
}
