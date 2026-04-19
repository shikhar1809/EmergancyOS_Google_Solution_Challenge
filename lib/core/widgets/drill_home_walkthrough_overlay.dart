import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/voice_comms_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

enum DrillHomeWalkthroughMode { sosVictim, volunteer }

class _Step {
  final IconData icon;
  final String titleKey;
  final String bodyKey;
  final DrillTooltipAnchor anchor;
  /// When set, advancing to the *next* step happens automatically when the shell route matches.
  final String? advanceWhenPathContains;

  const _Step({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
    this.anchor = DrillTooltipAnchor.center,
    this.advanceWhenPathContains,
  });
}

enum DrillTooltipAnchor {
  center,
  bottomSos,
  navHome,
  navGrid,
  navLifeline,
  navProfile,
}

/// Full-screen dim overlay over the main tab body; bottom nav + SOS FAB stay tappable.
class DrillHomeWalkthroughOverlay extends StatefulWidget {
  const DrillHomeWalkthroughOverlay({
    super.key,
    required this.mode,
    required this.onComplete,
    this.fabKey,
    this.navHomeKey,
    this.navGridKey,
    this.navLifelineKey,
    this.navProfileKey,
  });

  final DrillHomeWalkthroughMode mode;
  final Future<void> Function() onComplete;
  final GlobalKey? fabKey;
  final GlobalKey? navHomeKey;
  final GlobalKey? navGridKey;
  final GlobalKey? navLifelineKey;
  final GlobalKey? navProfileKey;

  @override
  State<DrillHomeWalkthroughOverlay> createState() => _DrillHomeWalkthroughOverlayState();
}

class _DrillHomeWalkthroughOverlayState extends State<DrillHomeWalkthroughOverlay> {
  late final List<_Step> _steps;
  int _index = 0;
  Rect? _fabRect;
  Rect? _navHomeRect;
  Rect? _navGridRect;
  Rect? _navLifelineRect;
  Rect? _navProfileRect;
  final Set<int> _routeAutoAdvancedFromSteps = {};

  static const _sosSteps = <_Step>[
    _Step(
      icon: Icons.school_rounded,
      titleKey: 'drill_sos_step_0_title',
      bodyKey: 'drill_sos_step_0_body',
    ),
    _Step(
      icon: Icons.touch_app_rounded,
      titleKey: 'drill_sos_step_1_title',
      bodyKey: 'drill_sos_step_1_body',
      anchor: DrillTooltipAnchor.navHome,
    ),
    _Step(
      icon: Icons.near_me_rounded,
      titleKey: 'drill_sos_step_2_title',
      bodyKey: 'drill_sos_step_2_body',
      anchor: DrillTooltipAnchor.navGrid,
      advanceWhenPathContains: '/map',
    ),
    _Step(
      icon: Icons.medical_services_rounded,
      titleKey: 'drill_sos_step_3_title',
      bodyKey: 'drill_sos_step_3_body',
      anchor: DrillTooltipAnchor.navLifeline,
      advanceWhenPathContains: '/lifeline',
    ),
    _Step(
      icon: Icons.person_rounded,
      titleKey: 'drill_sos_step_4_title',
      bodyKey: 'drill_sos_step_4_body',
      anchor: DrillTooltipAnchor.navProfile,
      advanceWhenPathContains: '/profile',
    ),
    _Step(
      icon: Icons.cottage_rounded,
      titleKey: 'drill_sos_step_5_title',
      bodyKey: 'drill_sos_step_5_body',
      anchor: DrillTooltipAnchor.navHome,
    ),
    _Step(
      icon: Icons.warning_amber_rounded,
      titleKey: 'drill_sos_step_6_title',
      bodyKey: 'drill_sos_step_6_body',
      anchor: DrillTooltipAnchor.bottomSos,
    ),
  ];

  static const _volunteerSteps = <_Step>[
    _Step(
      icon: Icons.volunteer_activism_rounded,
      titleKey: 'drill_vol_step_0_title',
      bodyKey: 'drill_vol_step_0_body',
    ),
    _Step(
      icon: Icons.cottage_rounded,
      titleKey: 'drill_vol_step_1_title',
      bodyKey: 'drill_vol_step_1_body',
      anchor: DrillTooltipAnchor.navHome,
    ),
    _Step(
      icon: Icons.map_rounded,
      titleKey: 'drill_vol_step_2_title',
      bodyKey: 'drill_vol_step_2_body',
    ),
    _Step(
      icon: Icons.notifications_active_rounded,
      titleKey: 'drill_vol_step_3_title',
      bodyKey: 'drill_vol_step_3_body',
      anchor: DrillTooltipAnchor.center,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _steps = widget.mode == DrillHomeWalkthroughMode.sosVictim ? _sosSteps : _volunteerSteps;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureTargets();
      _playVoiceForCurrentStep();
    });
  }

  @override
  void dispose() {
    VoiceCommsService.clearSpeakQueue();
    super.dispose();
  }

  void _measureTargets() {
    if (!context.mounted) return;
    setState(() {
      _fabRect = _globalRect(widget.fabKey);
      _navHomeRect = _globalRect(widget.navHomeKey);
      _navGridRect = _globalRect(widget.navGridKey);
      _navLifelineRect = _globalRect(widget.navLifelineKey);
      _navProfileRect = _globalRect(widget.navProfileKey);
    });
  }

  Rect? _globalRect(GlobalKey? key) {
    final ctx = key?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return null;
    final o = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(o.dx, o.dy, box.size.width, box.size.height);
  }

  void _tryAutoAdvanceFromRoute(String path) {
    if (_index >= _steps.length - 1) return;
    if (_routeAutoAdvancedFromSteps.contains(_index)) return;
    final need = _steps[_index].advanceWhenPathContains;
    if (need == null || need.isEmpty) return;
    if (!path.contains(need)) return;
    _routeAutoAdvancedFromSteps.add(_index);
    setState(() => _index++);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureTargets();
      _playVoiceForCurrentStep();
    });
  }

  Future<void> _onNext() async {
    if (_index < _steps.length - 1) {
      if (kIsWeb) VoiceCommsService.primeForVoiceGuidance();
      setState(() => _index++);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _measureTargets();
        _playVoiceForCurrentStep();
      });
      return;
    }
    await widget.onComplete();
  }

  void _onBack() {
    if (_index <= 0) return;
    _routeAutoAdvancedFromSteps.remove(_index - 1);
    if (kIsWeb) VoiceCommsService.primeForVoiceGuidance();
    setState(() => _index--);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureTargets();
      _playVoiceForCurrentStep();
    });
  }

  void _playVoiceForCurrentStep() {
    if (!context.mounted) return;
    VoiceCommsService.clearSpeakQueue();
    final l10n = AppLocalizations.of(context);
    VoiceCommsService.readAloud(l10n.get(_steps[_index].bodyKey));
  }

  Rect? _targetForStep(_Step step) {
    return switch (step.anchor) {
      DrillTooltipAnchor.bottomSos => _fabRect,
      DrillTooltipAnchor.navHome => _navHomeRect,
      DrillTooltipAnchor.navGrid => _navGridRect,
      DrillTooltipAnchor.navLifeline => _navLifelineRect,
      DrillTooltipAnchor.navProfile => _navProfileRect,
      DrillTooltipAnchor.center => null,
    };
  }

  Color _highlightColor(DrillTooltipAnchor a) {
    return switch (a) {
      DrillTooltipAnchor.bottomSos => AppColors.primaryDanger.withValues(alpha: 0.95),
      _ => Colors.cyanAccent.withValues(alpha: 0.9),
    };
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      _tryAutoAdvanceFromRoute(path);
    });

    final step = _steps[_index];
    final last = _index >= _steps.length - 1;
    final padding = MediaQuery.paddingOf(context);
    final size = MediaQuery.sizeOf(context);

    final target = _targetForStep(step);

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: Container(color: Colors.black.withValues(alpha: 0.84)),
            ),
          ),
          if (step.anchor == DrillTooltipAnchor.bottomSos && _fabRect != null)
            Positioned(
              left: _fabRect!.left - 6,
              top: _fabRect!.top - 6,
              width: _fabRect!.width + 12,
              height: _fabRect!.height + 12,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primaryDanger.withValues(alpha: 0.95), width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryDanger.withValues(alpha: 0.45),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (step.anchor != DrillTooltipAnchor.bottomSos &&
              step.anchor != DrillTooltipAnchor.center &&
              target != null)
            Positioned(
              left: target.left - 4,
              top: target.top - 4,
              width: target.width + 8,
              height: target.height + 8,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _highlightColor(step.anchor), width: 2),
                  ),
                ),
              ),
            ),
          if (target != null)
            _AnchoredTooltip(
              index: _index,
              targetRect: target,
              safeTop: padding.top + 6,
              screenWidth: size.width,
              child: _TooltipCard(
                step: step,
                stepIndex: _index,
                stepCount: _steps.length,
                last: last,
                primaryLabel: last && widget.mode == DrillHomeWalkthroughMode.sosVictim ? 'Got it' : null,
                onBack: _onBack,
                onNext: _onNext,
              ),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                  child: KeyedSubtree(
                    key: ValueKey<int>(_index),
                    child: _TooltipCard(
                      step: step,
                      stepIndex: _index,
                      stepCount: _steps.length,
                      last: last,
                      primaryLabel: last && widget.mode == DrillHomeWalkthroughMode.sosVictim ? 'Got it' : null,
                      onBack: _onBack,
                      onNext: _onNext,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TooltipCard extends StatelessWidget {
  const _TooltipCard({
    required this.step,
    required this.stepIndex,
    required this.stepCount,
    required this.last,
    required this.onBack,
    required this.onNext,
    this.primaryLabel,
  });

  final _Step step;
  final int stepIndex;
  final int stepCount;
  final bool last;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final String? primaryLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Material(
        color: const Color(0xFF1A1F2E),
        elevation: 14,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(step.icon, color: Colors.cyanAccent, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.get(step.titleKey),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.get(step.bodyKey),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  height: 1.45,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    '${stepIndex + 1} / $stepCount',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (stepIndex > 0)
                    TextButton(onPressed: onBack, child: const Text('Back'))
                  else
                    const SizedBox(width: 64),
                  FilledButton(
                    onPressed: onNext,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF00B8D4),
                      foregroundColor: Colors.black,
                    ),
                    child: Text(
                      primaryLabel ?? (last ? 'Continue' : 'Next'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnchoredTooltip extends StatelessWidget {
  const _AnchoredTooltip({
    required this.index,
    required this.targetRect,
    required this.safeTop,
    required this.screenWidth,
    required this.child,
  });

  final int index;
  final Rect targetRect;
  final double safeTop;
  final double screenWidth;
  final Widget child;

  static const double _arrowH = 28;
  static const double _gap = 10;
  static const double _cardBudget = 248;

  @override
  Widget build(BuildContext context) {
    const maxCardW = 400.0;
    final cardW = math.min(maxCardW, screenWidth - 32);
    final targetCx = targetRect.center.dx;
    var left = targetCx - cardW / 2;
    left = left.clamp(16.0, screenWidth - cardW - 16);

    final topIdeal = targetRect.top - _gap - _arrowH - _cardBudget;
    final top = topIdeal < safeTop ? safeTop : topIdeal;
    final tipX = (targetRect.center.dx - left).clamp(28.0, cardW - 28.0);

    return Positioned(
      left: left,
      top: top,
      width: cardW,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
        child: KeyedSubtree(
          key: ValueKey<int>(index),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(child: child),
              ),
              SizedBox(
                height: _arrowH,
                width: cardW,
                child: CustomPaint(
                  painter: _DownArrowPainter(
                    tipX: tipX,
                    tipY: _arrowH,
                    stemWidth: 16,
                    color: Colors.cyanAccent.withValues(alpha: 0.95),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownArrowPainter extends CustomPainter {
  _DownArrowPainter({
    required this.tipX,
    required this.tipY,
    required this.stemWidth,
    required this.color,
  });

  final double tipX;
  final double tipY;
  final double stemWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    const topY = 0.0;
    final stemHalf = stemWidth / 2;
    final path = Path()
      ..moveTo(tipX - stemHalf, topY)
      ..lineTo(tipX + stemHalf, topY)
      ..lineTo(tipX, tipY)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DownArrowPainter oldDelegate) =>
      oldDelegate.tipX != tipX || oldDelegate.tipY != tipY || oldDelegate.color != color;
}
