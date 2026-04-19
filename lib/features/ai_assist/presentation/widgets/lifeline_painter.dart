import 'dart:math' as math;
import 'package:flutter/material.dart';

class LifelineWidget extends StatefulWidget {
  final Color color;
  final bool isActive;
  final double voiceState; // 0.0: idle, 1.0: listening, 1.5: hearing, 2.0: processing, 3.0: speaking

  const LifelineWidget({
    super.key,
    required this.color,
    required this.isActive,
    required this.voiceState,
  });

  @override
  State<LifelineWidget> createState() => _LifelineWidgetState();
}

class _LifelineWidgetState extends State<LifelineWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(double.infinity, 200),
          painter: _LifelinePainter(
            animationValue: _controller.value,
            color: widget.color,
            voiceState: widget.voiceState,
          ),
        );
      },
    );
  }
}

class _LifelinePainter extends CustomPainter {
  final double animationValue;
  final Color color;
  final double voiceState;

  _LifelinePainter({
    required this.animationValue,
    required this.color,
    required this.voiceState,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 8.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final path = Path();
    final centerY = size.height / 2;
    final width = size.width;

    path.moveTo(0, centerY);

    // Number of points to draw for the wave
    const int segments = 100;
    for (int i = 0; i <= segments; i++) {
      double x = (i / segments) * width;

      // Base heartbeat logic
      // We want a "pulse" peak moving from left to right
      double pulsePos = (animationValue * width * 1.2) - (width * 0.1);
      double dist = (x - pulsePos).abs();
      
      double waveHeight = 0;
      
      if (voiceState == 1.0 || voiceState == 1.5) { // Listening or Hearing - Jittery
        waveHeight = (math.Random().nextDouble() - 0.5) * 40;
      } else if (voiceState == 2.0) { // Processing - Fast smooth waves
        waveHeight = math.sin((x / 20) + (animationValue * 20)) * 15;
      } else if (voiceState == 3.0) { // Speaking - Rhythmic large pulses
        waveHeight = math.sin((x / 40) + (animationValue * 15)) * 30;
      } else { // Idle - Low heartbeat
        if (dist < 40) {
          // Classic EKG pulse shape: P-Q-RS-T
          double normalizedDist = (pulsePos - x) / 40; // -1 to 1
          if (normalizedDist > -0.8 && normalizedDist < -0.6) waveHeight = -5; // P
          else if (normalizedDist > -0.4 && normalizedDist < -0.2) waveHeight = 5; // Q
          else if (normalizedDist > -0.1 && normalizedDist < 0.1) waveHeight = -60; // R
          else if (normalizedDist > 0.1 && normalizedDist < 0.3) waveHeight = 20; // S
          else if (normalizedDist > 0.6 && normalizedDist < 0.8) waveHeight = -10; // T
        }
      }

      path.lineTo(x, centerY + waveHeight);
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _LifelinePainter oldDelegate) => true;
}
