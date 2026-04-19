import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:emergency_os/core/l10n/app_localizations.dart';
import 'package:emergency_os/core/theme/app_colors.dart';
import 'package:emergency_os/services/voice_comms_service.dart';
import 'package:emergency_os/features/ai_assist/domain/lifeline_training_levels.dart';
import 'widgets/guide_detail_page.dart';
import 'widgets/lifeline_voice_agent_overlay.dart';

class AIAssistScreen extends StatefulWidget {
  final String? openAid;
  final String? mode;
  final String? incidentId;
  final bool isDrillShell;

  const AIAssistScreen({
    super.key,
    this.openAid,
    this.mode,
    this.incidentId,
    this.isDrillShell = false,
  });

  @override
  State<AIAssistScreen> createState() => _AIAssistScreenState();
}

class _AIAssistScreenState extends State<AIAssistScreen> {
  late final PageController _pageController;
  int _activePage = 0;
  double _pageValue = 0;
  bool _emergencyMode = false;
  String? _handledOpenAid;

  static const _levels = kLifelineTrainingLevels;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _pageController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyOpenAid());
  }

  @override
  void didUpdateWidget(covariant AIAssistScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.openAid != widget.openAid) {
      _handledOpenAid = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyOpenAid());
    }
  }

  void _applyOpenAid() {
    final raw = widget.openAid?.trim();
    if (raw == null || raw.isEmpty) return;
    if (raw == _handledOpenAid) return;
    final id = int.tryParse(raw);
    if (id == null) return;
    final idx = _levels.indexWhere((l) => l.id == id);
    if (idx < 0) return;
    _handledOpenAid = raw;
    _goToPage(idx);
  }

  void _onScroll() {
    final p = _pageController.page;
    if (p != null) {
      setState(() => _pageValue = p);
    }
  }

  /// [fromSearch] uses [PageController.jumpToPage] and syncs [_activePage] /
  /// [_pageValue] immediately so the correct guide opens even when custom
  /// snap physics or overlay timing would fight a long [animateToPage].
  void _goToPage(int index, {bool fromSearch = false}) {
    if (index < 0 || index >= _levels.length) return;
    HapticFeedback.lightImpact();

    void run(int retries) {
      if (!_pageController.hasClients) {
        if (retries > 12) return;
        WidgetsBinding.instance.addPostFrameCallback((_) => run(retries + 1));
        return;
      }
      if (fromSearch) {
        _pageController.jumpToPage(index);
        if (mounted) {
          setState(() {
            _activePage = index;
            _pageValue = index.toDouble();
          });
        }
      } else {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        );
      }
    }

    run(0);
  }

  void _toggleEmergencyMode() {
    HapticFeedback.heavyImpact();
    if (kIsWeb) {
      VoiceCommsService.primeForVoiceGuidance();
    }
    setState(() => _emergencyMode = !_emergencyMode);
  }

  @override
  void dispose() {
    _pageController.removeListener(_onScroll);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safePad = MediaQuery.of(context).padding;
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.isDrillShell)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Material(
                  color: Colors.cyan.shade900.withValues(alpha: 0.88),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      l.aiAssistPracticeBanner,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Row(
            children: [
              _SlidingRail(
                levels: _levels,
                currentPage: _pageValue,
                activePage: _activePage,
                onTap: _goToPage,
                safePad: safePad,
                emergencyMode: _emergencyMode,
                onToggleEmergency: _toggleEmergencyMode,
                l10n: l,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        top: safePad.top +
                            (widget.isDrillShell ? 46 : 12) +
                            4,
                        left: 10,
                        right: 10,
                        bottom: 10,
                      ),
                      child: _ScenarioSearchBar(
                        levels: _levels,
                        onSelect: (idx) => _goToPage(idx, fromSearch: true),
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        scrollDirection: Axis.vertical,
                        physics: const PageScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        itemCount: _levels.length,
                        onPageChanged: (i) {
                          HapticFeedback.selectionClick();
                          setState(() => _activePage = i);
                          SemanticsService.announce(
                            l.aiAssistRailSemantics(i + 1, _levels[i].title),
                            Directionality.of(context),
                          );
                        },
                        itemBuilder: (context, index) {
                          return GuideDetailPage(
                            key: ValueKey('guide_${index}_$_emergencyMode'),
                            level: _levels[index],
                            isActive: _activePage == index,
                            pageIndex: index,
                            totalPages: _levels.length,
                            safePadding: safePad,
                            emergencyMode: _emergencyMode,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          LifelineVoiceAgentOverlay(
            activeLevelIndex: _activePage,
            activeLevelTitle: _levels[_activePage].title,
            safePadding: safePad,
            isDrillShell: widget.isDrillShell,
          ),
        ],
      ),
    );
  }
}

/// Compact, glassmorphic search bar that filters the Lifeline scenario library
/// by title / subtitle / red flags / cautions and jumps to the chosen entry.
class _ScenarioSearchBar extends StatefulWidget {
  final List<LifelineTrainingLevel> levels;
  final ValueChanged<int> onSelect;

  const _ScenarioSearchBar({
    required this.levels,
    required this.onSelect,
  });

  @override
  State<_ScenarioSearchBar> createState() => _ScenarioSearchBarState();
}

class _ScenarioSearchBarState extends State<_ScenarioSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<_ScenarioMatch> _matches() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final results = <_ScenarioMatch>[];
    for (var i = 0; i < widget.levels.length; i++) {
      final lvl = widget.levels[i];
      final title = lvl.title.toLowerCase();
      final subtitle = lvl.subtitle.toLowerCase();
      final redFlags = lvl.redFlags.join(' ').toLowerCase();
      final cautions = lvl.cautions.join(' ').toLowerCase();

      int score;
      if (title.startsWith(q)) {
        score = 0;
      } else if (title.contains(q)) {
        score = 1;
      } else if (subtitle.contains(q)) {
        score = 2;
      } else if (redFlags.contains(q)) {
        score = 3;
      } else if (cautions.contains(q)) {
        score = 4;
      } else {
        continue;
      }
      results.add(_ScenarioMatch(index: i, level: lvl, score: score));
    }
    results.sort((a, b) {
      final c = a.score.compareTo(b.score);
      if (c != 0) return c;
      return a.level.title.compareTo(b.level.title);
    });
    return results.take(8).toList();
  }

  void _clear() {
    _controller.clear();
    setState(() => _query = '');
  }

  void _jumpTo(int idx) {
    // Navigate first so PageView updates before the dropdown collapses
    // (unfocusing first can drop the result list and swallow follow-up work).
    widget.onSelect(idx);
    _controller.clear();
    setState(() => _query = '');
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches();
    final hasQuery = _query.trim().isNotEmpty;
    final showResults = hasQuery && _focusNode.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focusNode.hasFocus
                  ? AppColors.primaryInfo.withValues(alpha: 0.55)
                  : AppColors.stroke.withValues(alpha: 0.6),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(
                Icons.search_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onChanged: (v) => setState(() => _query = v),
                  onSubmitted: (_) {
                    if (matches.isNotEmpty) _jumpTo(matches.first.index);
                  },
                  textInputAction: TextInputAction.search,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  cursorColor: AppColors.primaryInfo,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    hintText: 'Search emergency scenarios…',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ),
              if (hasQuery)
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: AppColors.textSecondary,
                  splashRadius: 16,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  onPressed: _clear,
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
        if (showResults)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.stroke.withValues(alpha: 0.6),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: matches.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14, horizontal: 14),
                          child: Text(
                            'No scenarios match "${_query.trim()}"',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: matches.length,
                          separatorBuilder: (context, _) => Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.stroke.withValues(alpha: 0.35),
                          ),
                          itemBuilder: (ctx, i) {
                            final m = matches[i];
                            return InkWell(
                              onTap: () => _jumpTo(m.index),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: m.level.accent
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(9),
                                        border: Border.all(
                                          color: m.level.accent
                                              .withValues(alpha: 0.5),
                                          width: 1,
                                        ),
                                      ),
                                      child: Icon(
                                        m.level.icon,
                                        size: 18,
                                        color: m.level.accent,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            m.level.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            m.level.subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 16,
                                      color: AppColors.textSecondary
                                          .withValues(alpha: 0.7),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScenarioMatch {
  final int index;
  final LifelineTrainingLevel level;
  final int score;
  const _ScenarioMatch({
    required this.index,
    required this.level,
    required this.score,
  });
}

class _SlidingRail extends StatelessWidget {
  final List<LifelineTrainingLevel> levels;
  final double currentPage;
  final int activePage;
  final ValueChanged<int> onTap;
  final EdgeInsets safePad;
  final bool emergencyMode;
  final VoidCallback onToggleEmergency;
  final AppLocalizations l10n;

  const _SlidingRail({
    required this.levels,
    required this.currentPage,
    required this.activePage,
    required this.onTap,
    required this.safePad,
    required this.emergencyMode,
    required this.onToggleEmergency,
    required this.l10n,
  });

  Color _lerpAccent() {
    if (emergencyMode) return AppColors.primaryDanger;
    final floor = currentPage.floor().clamp(0, levels.length - 1);
    final ceil = currentPage.ceil().clamp(0, levels.length - 1);
    final t = currentPage - floor;
    return Color.lerp(levels[floor].accent, levels[ceil].accent, t) ??
        levels[floor].accent;
  }

  @override
  Widget build(BuildContext context) {
    final topPad = safePad.top + 12;
    final bottomPad = safePad.bottom + 12;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: 70,
      decoration: BoxDecoration(
        color: emergencyMode
            ? AppColors.primaryDanger.withValues(alpha: 0.12)
            : AppColors.surface.withValues(alpha: 0.62),
        border: Border(
          right: BorderSide(
            color: emergencyMode
                ? AppColors.primaryDanger.withValues(alpha: 0.2)
                : AppColors.stroke,
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: topPad, bottom: bottomPad),
        child: Column(
          children: [
            _buildEmergencyToggle(),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalH = constraints.maxHeight;
                  final indicatorAccent = _lerpAccent();

                  return SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      height: totalH,
                      child: Stack(
                        children: [
                          // Vertical track line
                          Positioned(
                            left: 34,
                            top: (totalH / levels.length) * 0.5,
                            bottom: (totalH / levels.length) * 0.5,
                            child: Container(
                              width: 2,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(1),
                                color: emergencyMode
                                    ? AppColors.primaryDanger.withValues(alpha: 0.15)
                                    : AppColors.stroke,
                              ),
                            ),
                          ),

                          // Sliding glow indicator
                          Positioned(
                            left: 0,
                            right: 0,
                            top: currentPage * (totalH / levels.length),
                            height: totalH / levels.length,
                            child: Center(
                              child: Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: indicatorAccent.withValues(alpha: 0.12),
                                  border: Border.all(
                                    color: indicatorAccent.withValues(alpha: 0.5),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: indicatorAccent.withValues(alpha: 0.3),
                                      blurRadius: 22,
                                      spreadRadius: 2,
                                    ),
                                    BoxShadow(
                                      color: indicatorAccent.withValues(alpha: 0.1),
                                      blurRadius: 44,
                                      spreadRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Track progress fill
                          Positioned(
                            left: 34,
                            top: (totalH / levels.length) * 0.5,
                            width: 2,
                            height: math.max(0, currentPage * (totalH / levels.length)),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(1),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    (emergencyMode ? AppColors.primaryDanger : levels.first.accent).withValues(alpha: 0.4),
                                    indicatorAccent.withValues(alpha: 0.6),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Icon buttons — ring of sizes around the active page
                          ...List.generate(levels.length, (i) {
                            final level = levels[i];
                            final dist = (currentPage - i).abs();
                            // Continuous ramp: 0→28, 1→23, 2→19, 3+→15
                            final size =
                                (28.0 - dist * 4.5).clamp(14.0, 28.0).toDouble();
                            final opacity =
                                (1.0 - dist * 0.22).clamp(0.4, 1.0).toDouble();
                            final isActive = dist < 0.5;
                            final perItemH = totalH / levels.length;

                            return Positioned(
                              left: 0,
                              right: 0,
                              top: i * perItemH,
                              height: perItemH,
                              child: Semantics(
                                button: true,
                                selected: i == activePage,
                                label: l10n.aiAssistRailSemantics(i + 1, level.title),
                                child: GestureDetector(
                                  onTap: () => onTap(i),
                                  behavior: HitTestBehavior.opaque,
                                  child: Center(
                                    child: Opacity(
                                      opacity: opacity,
                                      child: Icon(
                                        level.icon,
                                        size: size,
                                        semanticLabel: level.title,
                                        color: isActive
                                            ? (emergencyMode
                                                ? AppColors.primaryDanger
                                                : level.accent)
                                            : AppColors.textSecondary
                                                .withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${activePage + 1}/${levels.length}',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyToggle() {
    return Semantics(
      button: true,
      toggled: emergencyMode,
      label: emergencyMode ? l10n.aiAssistEmergencyToggleOn : l10n.aiAssistEmergencyToggleOff,
      child: Tooltip(
        message: emergencyMode ? l10n.aiAssistEmergencyToggleOn : l10n.aiAssistEmergencyToggleOff,
        child: GestureDetector(
          onTap: onToggleEmergency,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            width: 46,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: emergencyMode
                  ? AppColors.primaryDanger
                  : AppColors.surfaceHighlight,
              border: Border.all(
                color: emergencyMode
                    ? AppColors.primaryDanger
                    : AppColors.stroke,
                width: 1,
              ),
              boxShadow: emergencyMode
                  ? [
                      BoxShadow(
                        color: AppColors.primaryDanger.withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              emergencyMode ? 'LIVE' : 'SOS',
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: emergencyMode
                    ? Colors.white
                    : AppColors.textSecondary,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

