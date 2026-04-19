import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/lifeline_progress_repository.dart';
import '../../domain/lifeline_training_levels.dart';
import 'technique_visuals.dart';

/// Full-screen level: embedded video, infographic, quiz gate.
class LifelineLevelPlayPage extends StatefulWidget {
  const LifelineLevelPlayPage({
    super.key,
    required this.level,
    required this.isUnlocked,
    required this.isCleared,
  });

  final LifelineTrainingLevel level;
  final bool isUnlocked;
  final bool isCleared;

  @override
  State<LifelineLevelPlayPage> createState() => _LifelineLevelPlayPageState();
}

class _LifelineLevelPlayPageState extends State<LifelineLevelPlayPage> {
  late final YoutubePlayerController _yt;
  int? _selectedChoice;
  bool _submitted = false;
  bool _saving = false;

  LifelineTrainingLevel get level => widget.level;

  @override
  void initState() {
    super.initState();
    _yt = YoutubePlayerController.fromVideoId(
      videoId: level.youtubeVideoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
      ),
    );
  }

  @override
  void dispose() {
    _yt.close();
    super.dispose();
  }

  Future<void> _submitQuiz() async {
    if (!widget.isUnlocked || widget.isCleared) return;
    if (_selectedChoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an answer to continue.')),
      );
      return;
    }
    setState(() => _submitted = true);
    final ok = _selectedChoice == level.quiz.correctIndex;
    if (!ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Not quite — review the video and infographic, then try again.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final stageIndex =
          kLifelineTrainingLevels.indexWhere((l) => l.id == level.id) + 1;
      await LifelineProgressRepository.instance
          .recordLevelPassed(stageIndex, level.xpReward);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Level $stageIndex cleared — +${level.xpReward} volunteer XP',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save progress. Check connection.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (context.mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = level.quiz;
    final canInteract = widget.isUnlocked && !widget.isCleared;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Level ${level.id} · ${level.title}'),
        backgroundColor: level.accent.withValues(alpha: 0.25),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (!widget.isUnlocked)
            _banner(Icons.lock_rounded, 'Complete the previous level to unlock this one.', Colors.orange),
          if (widget.isCleared)
            _banner(Icons.verified_rounded, 'You already cleared this level. Replay anytime.', Colors.green),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: YoutubePlayer(controller: _yt),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            level.subtitle,
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 15),
          ),
          if (level.id >= 1 && level.id <= kLifelineBundledGraphicCount) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: level.accent.withValues(alpha: 0.35)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: techniqueVisualFor(level.id, level.accent),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Quick infographic',
            style: TextStyle(color: level.accent, fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 12),
          ...level.infographic.map((step) => _infographicRow(step, level.accent)),
          const SizedBox(height: 24),
          Text(
            'Checkpoint quiz',
            style: TextStyle(color: level.accent, fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(q.question, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16, height: 1.35)),
          const SizedBox(height: 12),
          ...List.generate(q.choices.length, (i) {
            final selected = _selectedChoice == i;
            final showResult = _submitted && _selectedChoice != null;
            final correct = i == q.correctIndex;
            Color? tileColor;
            if (showResult) {
              if (correct) tileColor = Colors.green.withValues(alpha: 0.2);
              if (selected && !correct) tileColor = Colors.red.withValues(alpha: 0.2);
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: tileColor ?? AppColors.surfaceHighlight,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: canInteract && !_saving
                      ? () => setState(() {
                            _selectedChoice = i;
                            _submitted = false;
                          })
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                          color: selected ? level.accent : Colors.white38,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            q.choices[i],
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          if (canInteract)
            FilledButton.icon(
              onPressed: _saving ? null : _submitQuiz,
              style: FilledButton.styleFrom(
                backgroundColor: level.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.arrow_forward_rounded),
              label: Text(_saving ? 'Saving…' : 'Submit answer & unlock next level'),
            ),
        ],
      ),
    );
  }

  Widget _banner(IconData icon, String text, Color c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Icon(icon, color: c),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.95), fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }

  Widget _infographicRow(LifelineInfographicStep step, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            ),
            child: Icon(step.icon, color: accent, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.headline, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 4),
                Text(step.detail, style: const TextStyle(color: Colors.white70, height: 1.4, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
