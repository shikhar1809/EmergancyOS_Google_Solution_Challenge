import 'dart:async';

import 'package:flutter/material.dart';

/// Horizontal swipe-to-confirm (drag handle past ~85% of track), matching the volunteer
/// incoming-emergency overlay pattern.
class SlideToConfirmAction extends StatefulWidget {
  const SlideToConfirmAction({
    super.key,
    required this.label,
    required this.idleBadge,
    required this.accentColor,
    required this.onConfirm,
    this.enabled = true,
  });

  final String label;
  final String idleBadge;
  final Color accentColor;
  final Future<void> Function() onConfirm;
  final bool enabled;

  @override
  State<SlideToConfirmAction> createState() => _SlideToConfirmActionState();
}

class _SlideToConfirmActionState extends State<SlideToConfirmAction> {
  double _dragX = 0.0;
  bool _confirmed = false;
  bool _busy = false;

  static const double _handleSize = 60.0;

  Future<void> _fireConfirm() async {
    if (_confirmed || _busy || !widget.enabled) return;
    setState(() => _busy = true);
    try {
      await widget.onConfirm();
      if (mounted) setState(() => _confirmed = true);
    } catch (_) {
      if (mounted) setState(() => _dragX = 0.0);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _confirmed) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth.clamp(320.0, 560.0);
        final maxDrag = (trackWidth - _handleSize).clamp(1.0, 10000.0);
        final accent = widget.accentColor;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1),
            ),
            const SizedBox(height: 10),
            Center(
              child: SizedBox(
                width: trackWidth,
                height: 64,
                child: Stack(
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
                      child: Center(
                        child: Text(
                          widget.idleBadge,
                          style: const TextStyle(
                            color: Colors.white24,
                            letterSpacing: 4,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: (_dragX + _handleSize).clamp(_handleSize, trackWidth),
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
                        onHorizontalDragUpdate: _busy
                            ? null
                            : (details) {
                                setState(() {
                                  _dragX = (_dragX + details.delta.dx).clamp(0.0, maxDrag);
                                });
                                if (_dragX >= maxDrag * 0.85) unawaited(_fireConfirm());
                              },
                        onHorizontalDragEnd: _busy
                            ? null
                            : (_) {
                                if (!_confirmed) setState(() => _dragX = 0.0);
                              },
                        child: Container(
                          width: _handleSize,
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
                          child: _busy
                              ? const Padding(
                                  padding: EdgeInsets.all(18),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
