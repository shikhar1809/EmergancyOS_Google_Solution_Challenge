import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Bundled Lifeline hero graphics (`assets/images/lifeline/N.png` by level id, with overrides).
const int kLifelineBundledGraphicCount = 31;

/// Bundled PNG path for [levelId].
///
/// Default is `assets/images/lifeline/<id>.png`. Overrides:
/// - [12] drowning → `27.png`
/// - [2] basic first aid → `46.png`
/// - [16] hypothermia & heat stroke → `45.png`
/// - [28] heavy smoke / toxic gas → `48.png`
/// - [30] electrocute rescue → `47.png`
/// - [31] BASIC trauma response → `233.png`
String lifelineBundledPngPath(int levelId) {
  switch (levelId) {
    case 12:
      return 'assets/images/lifeline/27.png';
    case 2:
      return 'assets/images/lifeline/46.png';
    case 16:
      return 'assets/images/lifeline/45.png';
    case 28:
      return 'assets/images/lifeline/48.png';
    case 30:
      return 'assets/images/lifeline/47.png';
    case 31:
      return 'assets/images/lifeline/233.png';
    default:
      return 'assets/images/lifeline/$levelId.png';
  }
}

/// Returns the appropriate visual for a Lifeline / technique ID.
/// Bundled levels use PNG heroes; other IDs fall back to legacy vector art.
Widget techniqueVisualFor(int techniqueId, Color accent) {
  if (techniqueId >= 1 && techniqueId <= kLifelineBundledGraphicCount) {
    return _lifelineBundledPng(techniqueId, accent);
  }
  return CustomPaint(
    painter: switch (techniqueId) {
      1 => _CprBasicsPainter(accent),
      2 => _HandsOnlyCprPainter(accent),
      3 => _AedPainter(accent),
      4 => _AirwayPainter(accent),
      5 => _ChokingPainter(accent),
      6 => _BleedingPainter(accent),
      7 => _StrokeFastPainter(accent),
      8 => _BurnsPainter(accent),
      9 => _ShockPainter(accent),
      10 => _SceneCommandPainter(accent),
      _ => _CprBasicsPainter(accent),
    },
    size: const Size(double.infinity, 220),
  );
}

CustomPainter _legacyPainterFallback(int techniqueId, Color accent) {
  return switch (techniqueId) {
    1 => _CprBasicsPainter(accent),
    2 => _HandsOnlyCprPainter(accent),
    3 => _AedPainter(accent),
    4 => _AirwayPainter(accent),
    5 => _ChokingPainter(accent),
    6 => _BleedingPainter(accent),
    7 => _StrokeFastPainter(accent),
    8 => _BurnsPainter(accent),
    9 => _ShockPainter(accent),
    10 => _SceneCommandPainter(accent),
    _ => _CprBasicsPainter(accent),
  };
}

Widget _lifelineBundledPng(int levelId, Color accent) {
  final path = lifelineBundledPngPath(levelId);
  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.asset(
      path,
      fit: BoxFit.contain,
      width: double.infinity,
      alignment: Alignment.center,
      errorBuilder: (_, err, st) => CustomPaint(
        key: ValueKey<int>(Object.hash(err.hashCode, st.hashCode)),
        painter: _legacyPainterFallback(levelId, accent),
        size: const Size(double.infinity, 220),
      ),
    ),
  );
}

// ─── helpers ───

void _drawPersonLying(Canvas canvas, Offset center, double scale, Paint p) {
  final headR = 12.0 * scale;
  final headC = Offset(center.dx - 50 * scale, center.dy);
  canvas.drawCircle(headC, headR, p);

  final bodyStart = Offset(headC.dx + headR + 2, center.dy);
  final bodyEnd = Offset(center.dx + 40 * scale, center.dy);
  canvas.drawLine(bodyStart, bodyEnd, p);

  // legs
  canvas.drawLine(bodyEnd, Offset(bodyEnd.dx + 30 * scale, center.dy + 20 * scale), p);
  canvas.drawLine(bodyEnd, Offset(bodyEnd.dx + 30 * scale, center.dy - 5 * scale), p);

  // arm
  canvas.drawLine(
    Offset(bodyStart.dx + 20 * scale, center.dy),
    Offset(bodyStart.dx + 15 * scale, center.dy + 22 * scale),
    p,
  );
}

void _drawPersonStanding(Canvas canvas, Offset base, double scale, Paint p) {
  final headC = Offset(base.dx, base.dy - 70 * scale);
  canvas.drawCircle(headC, 11 * scale, p);

  // torso
  canvas.drawLine(
    Offset(base.dx, headC.dy + 11 * scale),
    Offset(base.dx, base.dy - 25 * scale),
    p,
  );

  // legs
  canvas.drawLine(Offset(base.dx, base.dy - 25 * scale), Offset(base.dx - 14 * scale, base.dy), p);
  canvas.drawLine(Offset(base.dx, base.dy - 25 * scale), Offset(base.dx + 14 * scale, base.dy), p);

  // arms
  canvas.drawLine(
    Offset(base.dx, headC.dy + 20 * scale),
    Offset(base.dx - 22 * scale, base.dy - 35 * scale),
    p,
  );
  canvas.drawLine(
    Offset(base.dx, headC.dy + 20 * scale),
    Offset(base.dx + 22 * scale, base.dy - 35 * scale),
    p,
  );
}

void _drawArrow(Canvas canvas, Offset from, Offset to, Paint p) {
  canvas.drawLine(from, to, p);
  final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
  const arrowLen = 8.0;
  canvas.drawLine(
    to,
    Offset(to.dx - arrowLen * math.cos(angle - 0.5), to.dy - arrowLen * math.sin(angle - 0.5)),
    p,
  );
  canvas.drawLine(
    to,
    Offset(to.dx - arrowLen * math.cos(angle + 0.5), to.dy - arrowLen * math.sin(angle + 0.5)),
    p,
  );
}

void _drawLabel(Canvas canvas, String text, Offset pos, Color color, {double fontSize = 11, bool bold = false}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        shadows: [
          Shadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
}

void _drawDashedCircle(Canvas canvas, Offset center, double radius, Paint p) {
  const segments = 24;
  for (var i = 0; i < segments; i += 2) {
    final startAngle = (i / segments) * 2 * math.pi;
    final sweepAngle = (1.0 / segments) * 2 * math.pi;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, p);
  }
}

void _drawBackdrop(Canvas canvas, Size size, Color accent) {
  final rect = Offset.zero & size;
  final background = Paint()
    ..shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF102445),
        const Color(0xFF0C1B35),
      ],
    ).createShader(rect);

  final panel = RRect.fromRectAndRadius(rect.deflate(4), const Radius.circular(16));
  canvas.drawRRect(panel, background);

  final topGlow = Paint()
    ..shader = RadialGradient(
      colors: [
        accent.withValues(alpha: 0.2),
        accent.withValues(alpha: 0.0),
      ],
    ).createShader(Rect.fromCircle(center: Offset(size.width * 0.5, size.height * 0.28), radius: 120));
  canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.28), 120, topGlow);

  canvas.drawRRect(
    panel,
    Paint()
      ..color = accent.withValues(alpha: 0.18)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke,
  );
}

// ─── 1. CPR BASICS ───

class _CprBasicsPainter extends CustomPainter {
  final Color accent;
  _CprBasicsPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackdrop(canvas, size, accent);

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final accentPaint = Paint()
      ..color = accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final cx = size.width / 2;
    final cy = size.height / 2;

    _drawPersonLying(canvas, Offset(cx, cy + 10), 1.2, linePaint);

    // chest target zone
    final chestCenter = Offset(cx - 5, cy + 2);
    canvas.drawCircle(chestCenter, 18, Paint()..color = accent.withValues(alpha: 0.12));
    _drawDashedCircle(canvas, chestCenter, 18, accentPaint);

    // hands on chest
    final handPaint = Paint()
      ..color = accent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(chestCenter.dx - 8, chestCenter.dy - 28),
      Offset(chestCenter.dx, chestCenter.dy - 8),
      handPaint,
    );
    canvas.drawLine(
      Offset(chestCenter.dx + 8, chestCenter.dy - 28),
      Offset(chestCenter.dx, chestCenter.dy - 8),
      handPaint,
    );

    // push arrows
    final arrowPaint = Paint()
      ..color = accent.withValues(alpha: 0.9)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    _drawArrow(canvas, Offset(chestCenter.dx, chestCenter.dy - 38), Offset(chestCenter.dx, chestCenter.dy - 16), arrowPaint);
    _drawArrow(canvas, Offset(chestCenter.dx - 8, chestCenter.dy - 30), Offset(chestCenter.dx - 8, chestCenter.dy - 14), arrowPaint);
    _drawArrow(canvas, Offset(chestCenter.dx + 8, chestCenter.dy - 30), Offset(chestCenter.dx + 8, chestCenter.dy - 14), arrowPaint);

    // labels
    _drawLabel(canvas, '5-6 cm', Offset(chestCenter.dx + 35, chestCenter.dy - 25), accent, fontSize: 12, bold: true);
    _drawLabel(canvas, '100-120/min', Offset(cx, cy + 55), accent, fontSize: 13, bold: true);
    _drawLabel(canvas, 'Push hard, push fast', Offset(cx, cy + 72), Colors.white.withValues(alpha: 0.5), fontSize: 11);

    // phone icon area
    _drawLabel(canvas, 'CALL', Offset(cx + 80, cy - 35), Colors.white.withValues(alpha: 0.6), fontSize: 10, bold: true);
    canvas.drawCircle(Offset(cx + 80, cy - 20), 13, Paint()..color = accent.withValues(alpha: 0.25));
    _drawLabel(canvas, '112', Offset(cx + 80, cy - 20), accent, fontSize: 10, bold: true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── 2. HANDS-ONLY CPR ───

class _HandsOnlyCprPainter extends CustomPainter {
  final Color accent;
  _HandsOnlyCprPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackdrop(canvas, size, accent);

    final cx = size.width / 2;
    final cy = size.height / 2;

    final accentPaint = Paint()
      ..color = accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // draw two hands interlocked
    final handCenter = Offset(cx, cy - 5);
    // palm base
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: handCenter, width: 50, height: 30),
        const Radius.circular(8),
      ),
      accentPaint,
    );
    // fingers interlocked
    for (var i = -2; i <= 2; i++) {
      canvas.drawLine(
        Offset(handCenter.dx + i * 10, handCenter.dy - 15),
        Offset(handCenter.dx + i * 10, handCenter.dy - 7),
        Paint()..color = accent.withValues(alpha: 0.6)..strokeWidth = 3..strokeCap = StrokeCap.round,
      );
    }

    // push arrows below
    final arrowP = Paint()
      ..color = accent.withValues(alpha: 0.8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    _drawArrow(canvas, Offset(cx - 15, handCenter.dy + 20), Offset(cx - 15, handCenter.dy + 40), arrowP);
    _drawArrow(canvas, Offset(cx + 15, handCenter.dy + 20), Offset(cx + 15, handCenter.dy + 40), arrowP);

    // chest target + line
    canvas.drawCircle(Offset(cx, handCenter.dy + 45), 15, Paint()..color = accent.withValues(alpha: 0.08));
    _drawDashedCircle(
      canvas,
      Offset(cx, handCenter.dy + 45),
      15,
      Paint()
        ..color = accent.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
    canvas.drawLine(
      Offset(cx - 40, handCenter.dy + 45),
      Offset(cx + 40, handCenter.dy + 45),
      Paint()..color = Colors.white.withValues(alpha: 0.3)..strokeWidth = 1.5..strokeCap = StrokeCap.round,
    );

    // rhythm indicator
    _drawLabel(canvas, 'CENTER OF CHEST', Offset(cx, handCenter.dy + 58), Colors.white.withValues(alpha: 0.5), fontSize: 10, bold: true);

    // beat visual - sine wave
    final wavePaint = Paint()
      ..color = accent.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final wavePath = Path();
    for (var x = -60.0; x <= 60.0; x += 1) {
      final y = math.sin(x * 0.15) * 8;
      if (x == -60) {
        wavePath.moveTo(cx + x, cy - 55 + y);
      } else {
        wavePath.lineTo(cx + x, cy - 55 + y);
      }
    }
    canvas.drawPath(wavePath, wavePaint);

    _drawLabel(canvas, '♪ Stayin\' Alive tempo', Offset(cx, cy - 70), accent, fontSize: 12, bold: true);
    _drawLabel(canvas, '100-120 BPM', Offset(cx, cy + 78), accent, fontSize: 13, bold: true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── 3. AED ───

class _AedPainter extends CustomPainter {
  final Color accent;
  _AedPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackdrop(canvas, size, accent);

    final cx = size.width / 2;
    final cy = size.height / 2;

    final accentPaint = Paint()
      ..color = accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // AED box
    final boxRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy - 10), width: 80, height: 60),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      boxRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.2),
            accent.withValues(alpha: 0.05),
          ],
        ).createShader(Rect.fromCenter(center: Offset(cx, cy - 10), width: 80, height: 60)),
    );
    canvas.drawRRect(boxRect, accentPaint);

    // heart + bolt inside
    _drawLabel(canvas, '♥', Offset(cx - 10, cy - 14), accent, fontSize: 20);
    _drawLabel(canvas, '⚡', Offset(cx + 10, cy - 14), Colors.white.withValues(alpha: 0.8), fontSize: 16);

    // pad wires
    final wirePaint = Paint()
      ..color = accent.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // right pad
    final rightWire = Path()
      ..moveTo(cx + 40, cy - 10)
      ..quadraticBezierTo(cx + 58, cy + 0, cx + 70, cy + 20);
    canvas.drawPath(rightWire, wirePaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + 75, cy + 30), width: 28, height: 20),
        const Radius.circular(5),
      ),
      Paint()..color = accent.withValues(alpha: 0.2),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + 75, cy + 30), width: 28, height: 20),
        const Radius.circular(5),
      ),
      accentPaint,
    );
    _drawLabel(canvas, 'PAD', Offset(cx + 75, cy + 30), accent, fontSize: 8, bold: true);

    // left pad
    final leftWire = Path()
      ..moveTo(cx - 40, cy - 10)
      ..quadraticBezierTo(cx - 55, cy + 2, cx - 70, cy + 25);
    canvas.drawPath(leftWire, wirePaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx - 75, cy + 35), width: 28, height: 20),
        const Radius.circular(5),
      ),
      Paint()..color = accent.withValues(alpha: 0.2),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx - 75, cy + 35), width: 28, height: 20),
        const Radius.circular(5),
      ),
      accentPaint,
    );
    _drawLabel(canvas, 'PAD', Offset(cx - 75, cy + 35), accent, fontSize: 8, bold: true);

    // labels
    _drawLabel(canvas, 'POWER ON → FOLLOW PROMPTS', Offset(cx, cy + 65), Colors.white.withValues(alpha: 0.5), fontSize: 10, bold: true);
    _drawLabel(canvas, '"CLEAR!" — No one touching', Offset(cx, cy + 80), accent, fontSize: 12, bold: true);

    // warning zone
    _drawDashedCircle(canvas, Offset(cx, cy + 30), 55, Paint()
      ..color = accent.withValues(alpha: 0.2)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── 4. AIRWAY ───

class _AirwayPainter extends CustomPainter {
  final Color accent;
  _AirwayPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackdrop(canvas, size, accent);

    final cx = size.width / 2;
    final cy = size.height / 2;

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // head profile (circle for head)
    final headC = Offset(cx - 20, cy - 10);
    canvas.drawCircle(headC, 28, linePaint);
    canvas.drawCircle(headC, 28, Paint()..color = accent.withValues(alpha: 0.06));

    // chin
    canvas.drawLine(
      Offset(headC.dx + 20, headC.dy + 15),
      Offset(headC.dx + 28, headC.dy + 5),
      linePaint,
    );

    // airway line (throat)
    final airwayPaint = Paint()
      ..color = accent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final airwayPath = Path();
    airwayPath.moveTo(headC.dx + 15, headC.dy + 20);
    airwayPath.quadraticBezierTo(headC.dx + 20, headC.dy + 35, headC.dx + 10, headC.dy + 50);
    canvas.drawPath(airwayPath, airwayPaint);

    // head tilt arrow
    final arrowP = Paint()
      ..color = accent.withValues(alpha: 0.8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    _drawArrow(canvas, Offset(headC.dx - 10, headC.dy - 30), Offset(headC.dx - 25, headC.dy - 40), arrowP);
    _drawLabel(canvas, 'HEAD TILT', Offset(headC.dx - 25, headC.dy - 50), accent, fontSize: 10, bold: true);

    // chin lift arrow
    _drawArrow(canvas, Offset(headC.dx + 32, headC.dy + 10), Offset(headC.dx + 40, headC.dy - 5), arrowP);
    _drawLabel(canvas, 'CHIN LIFT', Offset(headC.dx + 55, headC.dy - 10), accent, fontSize: 10, bold: true);

    // look listen feel
    final rightX = cx + 60;
    _drawLabel(canvas, '👁  LOOK', Offset(rightX, cy - 30), Colors.white.withValues(alpha: 0.7), fontSize: 11);
    _drawLabel(canvas, '👂  LISTEN', Offset(rightX, cy - 10), Colors.white.withValues(alpha: 0.7), fontSize: 11);
    _drawLabel(canvas, '✋  FEEL', Offset(rightX, cy + 10), Colors.white.withValues(alpha: 0.7), fontSize: 11);

    _drawLabel(canvas, '< 10 seconds', Offset(rightX, cy + 30), accent, fontSize: 12, bold: true);
    _drawLabel(canvas, 'If breathing → Recovery position', Offset(cx, cy + 70), Colors.white.withValues(alpha: 0.5), fontSize: 10);
    _drawLabel(canvas, 'If NOT → Start CPR', Offset(cx, cy + 85), accent, fontSize: 12, bold: true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── 5. CHOKING ───

class _ChokingPainter extends CustomPainter {
  final Color accent;
  _ChokingPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackdrop(canvas, size, accent);

    final cx = size.width / 2;
    final cy = size.height / 2;
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // victim standing
    _drawPersonStanding(canvas, Offset(cx - 15, cy + 55), 1.1, linePaint);

    // rescuer behind (simplified)
    final rescuerPaint = Paint()
      ..color = accent.withValues(alpha: 0.7)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rx = cx + 20;
    canvas.drawCircle(Offset(rx, cy - 25), 10, rescuerPaint);
    canvas.drawLine(Offset(rx, cy - 15), Offset(rx, cy + 15), rescuerPaint);

    // arms wrapping around
    canvas.drawLine(Offset(rx, cy - 5), Offset(cx - 15, cy + 5), rescuerPaint);
    canvas.drawLine(Offset(rx, cy - 5), Offset(cx - 12, cy + 10), rescuerPaint);

    // fist position above navel
    final fistPos = Offset(cx - 15, cy + 8);
    canvas.drawCircle(fistPos, 8, Paint()..color = accent.withValues(alpha: 0.25)..style = PaintingStyle.fill);
    canvas.drawCircle(
      fistPos,
      6,
      Paint()
        ..color = accent
        ..style = PaintingStyle.fill,
    );

    // thrust arrow
    final arrowP = Paint()
      ..color = accent
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    _drawArrow(canvas, Offset(fistPos.dx, fistPos.dy + 5), Offset(fistPos.dx, fistPos.dy - 15), arrowP);

    // labels
    _drawLabel(canvas, 'ABOVE NAVEL', Offset(cx - 55, cy + 8), accent, fontSize: 9, bold: true);
    _drawLabel(canvas, 'INWARD + UPWARD', Offset(cx, cy + 70), accent, fontSize: 13, bold: true);

    // back blows reference
    _drawLabel(canvas, '5 BACK BLOWS', Offset(cx - 50, cy - 50), Colors.white.withValues(alpha: 0.6), fontSize: 10, bold: true);
    _drawLabel(canvas, 'then', Offset(cx, cy - 50), Colors.white.withValues(alpha: 0.4), fontSize: 10);
    _drawLabel(canvas, '5 THRUSTS', Offset(cx + 45, cy - 50), accent, fontSize: 10, bold: true);
    _drawLabel(canvas, 'Alternate until clear', Offset(cx, cy + 85), Colors.white.withValues(alpha: 0.5), fontSize: 10);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── 6. SEVERE BLEEDING ───

class _BleedingPainter extends CustomPainter {
  final Color accent;
  _BleedingPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackdrop(canvas, size, accent);

    final cx = size.width / 2;
    final cy = size.height / 2;

    final limbPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    // arm/limb
    canvas.drawLine(Offset(cx - 60, cy), Offset(cx + 60, cy), limbPaint);
    canvas.drawLine(
      Offset(cx - 58, cy + 2),
      Offset(cx + 58, cy + 2),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    // wound
    canvas.drawCircle(Offset(cx + 20, cy), 10, Paint()..color = accent.withValues(alpha: 0.4));
    canvas.drawCircle(Offset(cx + 20, cy), 10, Paint()
      ..color = accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke);

    // pressure hands
    final handPaint = Paint()
      ..color = accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    _drawArrow(canvas, Offset(cx + 20, cy - 35), Offset(cx + 20, cy - 15), handPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + 20, cy - 40), width: 30, height: 12),
        const Radius.circular(4),
      ),
      handPaint,
    );

    // tourniquet band
    final tqPaint = Paint()
      ..color = accent.withValues(alpha: 0.8)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(cx - 20, cy - 8), Offset(cx - 20, cy + 8), tqPaint);
    canvas.drawLine(Offset(cx - 24, cy - 8), Offset(cx - 16, cy - 8), tqPaint);

    _drawLabel(canvas, 'TOURNIQUET', Offset(cx - 20, cy - 22), accent, fontSize: 9, bold: true);
    _drawLabel(canvas, 'DIRECT PRESSURE', Offset(cx + 20, cy - 55), accent, fontSize: 10, bold: true);

    // instructions
    _drawLabel(canvas, 'WOUND', Offset(cx + 20, cy + 22), Colors.white.withValues(alpha: 0.5), fontSize: 9);
    _drawLabel(canvas, 'Do NOT remove soaked dressing — add layers', Offset(cx, cy + 50), Colors.white.withValues(alpha: 0.5), fontSize: 10);
    _drawLabel(canvas, 'NOTE TIME of tourniquet', Offset(cx, cy + 65), accent, fontSize: 12, bold: true);
    _drawLabel(canvas, 'Limbs ONLY — never neck/chest/abdomen', Offset(cx, cy + 80), Colors.white.withValues(alpha: 0.5), fontSize: 10);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── 7. STROKE FAST ───

class _StrokeFastPainter extends CustomPainter {
  final Color accent;
  _StrokeFastPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackdrop(canvas, size, accent);

    final cx = size.width / 2;
    final cy = size.height / 2;

    final accentPaint = Paint()
      ..color = accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // F - Face
    final fX = cx - 70;
    canvas.drawCircle(Offset(fX, cy - 20), 18, accentPaint);
    canvas.drawCircle(Offset(fX, cy - 20), 18, Paint()..color = accent.withValues(alpha: 0.06));
    // drooping mouth line
    final mouthPath = Path();
    mouthPath.moveTo(fX - 8, cy - 18);
    mouthPath.quadraticBezierTo(fX, cy - 12, fX + 8, cy - 20);
    canvas.drawPath(mouthPath, Paint()..color = accent..strokeWidth = 2..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);
    // eyes
    canvas.drawCircle(Offset(fX - 5, cy - 25), 2, Paint()..color = accent);
    canvas.drawCircle(Offset(fX + 5, cy - 25), 2, Paint()..color = accent);
    _drawLabel(canvas, 'F', Offset(fX, cy - 48), accent, fontSize: 18, bold: true);
    _drawLabel(canvas, 'FACE', Offset(fX, cy + 8), Colors.white.withValues(alpha: 0.6), fontSize: 10, bold: true);
    _drawLabel(canvas, 'droop?', Offset(fX, cy + 20), Colors.white.withValues(alpha: 0.4), fontSize: 9);

    // A - Arms
    final aX = cx - 20;
    // two arms, one drifting
    canvas.drawLine(Offset(aX, cy - 15), Offset(aX - 15, cy - 35), Paint()..color = Colors.white.withValues(alpha: 0.6)..strokeWidth = 2.5..strokeCap = StrokeCap.round);
    canvas.drawLine(Offset(aX, cy - 15), Offset(aX + 15, cy - 25), Paint()..color = accent..strokeWidth = 2.5..strokeCap = StrokeCap.round);
    _drawArrow(canvas, Offset(aX + 15, cy - 25), Offset(aX + 18, cy - 15), Paint()..color = accent..strokeWidth = 1.5..strokeCap = StrokeCap.round);
    _drawLabel(canvas, 'A', Offset(aX, cy - 48), accent, fontSize: 18, bold: true);
    _drawLabel(canvas, 'ARMS', Offset(aX, cy + 8), Colors.white.withValues(alpha: 0.6), fontSize: 10, bold: true);
    _drawLabel(canvas, 'drift?', Offset(aX, cy + 20), Colors.white.withValues(alpha: 0.4), fontSize: 9);

    // S - Speech
    final sX = cx + 30;
    // speech bubble
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(sX, cy - 25), width: 30, height: 20),
        const Radius.circular(8),
      ),
      accentPaint,
    );
    _drawLabel(canvas, '?!', Offset(sX, cy - 25), accent, fontSize: 11, bold: true);
    _drawLabel(canvas, 'S', Offset(sX, cy - 48), accent, fontSize: 18, bold: true);
    _drawLabel(canvas, 'SPEECH', Offset(sX, cy + 8), Colors.white.withValues(alpha: 0.6), fontSize: 10, bold: true);
    _drawLabel(canvas, 'slurred?', Offset(sX, cy + 20), Colors.white.withValues(alpha: 0.4), fontSize: 9);

    // T - Time
    final tX = cx + 80;
    // clock
    canvas.drawCircle(Offset(tX, cy - 25), 15, accentPaint);
    canvas.drawLine(Offset(tX, cy - 25), Offset(tX, cy - 35), Paint()..color = accent..strokeWidth = 2..strokeCap = StrokeCap.round);
    canvas.drawLine(Offset(tX, cy - 25), Offset(tX + 8, cy - 22), Paint()..color = accent..strokeWidth = 2..strokeCap = StrokeCap.round);
    _drawLabel(canvas, 'T', Offset(tX, cy - 48), accent, fontSize: 18, bold: true);
    _drawLabel(canvas, 'TIME', Offset(tX, cy + 8), Colors.white.withValues(alpha: 0.6), fontSize: 10, bold: true);
    _drawLabel(canvas, 'CALL NOW', Offset(tX, cy + 20), accent, fontSize: 9, bold: true);

    _drawLabel(canvas, 'Every minute counts — note onset time', Offset(cx, cy + 55), accent, fontSize: 13, bold: true);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── 8. BURNS ───

class _BurnsPainter extends CustomPainter {
  final Color accent;
  _BurnsPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackdrop(canvas, size, accent);

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Three-step visual: COOL → COVER → CALL

    // Step 1: COOL - water drops
    final s1x = cx - 70;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(s1x, cy - 10), width: 55, height: 70),
        const Radius.circular(12),
      ),
      Paint()..color = accent.withValues(alpha: 0.1),
    );
    // water drops
    for (var i = 0; i < 3; i++) {
      final dropY = cy - 25.0 + i * 15;
      final dropPath = Path();
      dropPath.moveTo(s1x, dropY - 8);
      dropPath.quadraticBezierTo(s1x + 6, dropY, s1x, dropY + 4);
      dropPath.quadraticBezierTo(s1x - 6, dropY, s1x, dropY - 8);
      canvas.drawPath(dropPath, Paint()..color = accent.withValues(alpha: 0.5 + i * 0.15));
    }
    _drawLabel(canvas, '1', Offset(s1x, cy - 48), accent, fontSize: 16, bold: true);
    _drawLabel(canvas, 'COOL', Offset(s1x, cy + 35), accent, fontSize: 11, bold: true);
    _drawLabel(canvas, '20 min', Offset(s1x, cy + 48), Colors.white.withValues(alpha: 0.5), fontSize: 10);

    // Arrow
    _drawLabel(canvas, '→', Offset(cx - 32, cy - 10), Colors.white.withValues(alpha: 0.3), fontSize: 18);

    // Step 2: COVER - bandage
    final s2x = cx;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(s2x, cy - 10), width: 55, height: 70),
        const Radius.circular(12),
      ),
      Paint()..color = accent.withValues(alpha: 0.1),
    );
    // bandage roll
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(s2x, cy - 10), width: 30, height: 24),
        const Radius.circular(6),
      ),
      Paint()..color = accent.withValues(alpha: 0.4)..strokeWidth = 2..style = PaintingStyle.stroke,
    );
    canvas.drawLine(Offset(s2x - 10, cy - 10), Offset(s2x + 10, cy - 10), Paint()..color = accent.withValues(alpha: 0.3)..strokeWidth = 1.5);
    canvas.drawLine(Offset(s2x, cy - 22), Offset(s2x, cy + 2), Paint()..color = accent.withValues(alpha: 0.3)..strokeWidth = 1.5);
    _drawLabel(canvas, '2', Offset(s2x, cy - 48), accent, fontSize: 16, bold: true);
    _drawLabel(canvas, 'COVER', Offset(s2x, cy + 35), accent, fontSize: 11, bold: true);
    _drawLabel(canvas, 'sterile', Offset(s2x, cy + 48), Colors.white.withValues(alpha: 0.5), fontSize: 10);

    // Arrow
    _drawLabel(canvas, '→', Offset(cx + 38, cy - 10), Colors.white.withValues(alpha: 0.3), fontSize: 18);

    // Step 3: CALL
    final s3x = cx + 70;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(s3x, cy - 10), width: 55, height: 70),
        const Radius.circular(12),
      ),
      Paint()..color = accent.withValues(alpha: 0.1),
    );
    // phone
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(s3x, cy - 10), width: 18, height: 28),
        const Radius.circular(4),
      ),
      Paint()..color = accent.withValues(alpha: 0.6)..strokeWidth = 2..style = PaintingStyle.stroke,
    );
    _drawLabel(canvas, '3', Offset(s3x, cy - 48), accent, fontSize: 16, bold: true);
    _drawLabel(canvas, 'CALL', Offset(s3x, cy + 35), accent, fontSize: 11, bold: true);
    _drawLabel(canvas, 'if severe', Offset(s3x, cy + 48), Colors.white.withValues(alpha: 0.5), fontSize: 10);

    // warning
    _drawLabel(canvas, 'NO ice • NO butter • NO toothpaste', Offset(cx, cy + 72), accent, fontSize: 12, bold: true);
    _drawLabel(canvas, 'Cool running water only', Offset(cx, cy + 87), Colors.white.withValues(alpha: 0.5), fontSize: 10);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── 9. SHOCK ───

class _ShockPainter extends CustomPainter {
  final Color accent;
  _ShockPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackdrop(canvas, size, accent);

    final cx = size.width / 2;
    final cy = size.height / 2;

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // person lying flat
    _drawPersonLying(canvas, Offset(cx, cy - 5), 1.2, linePaint);

    // legs elevated - angled line
    final legEnd = Offset(cx + 68, cy - 5);
    final elevEnd = Offset(legEnd.dx + 20, cy - 30);
    canvas.drawLine(legEnd, elevEnd, Paint()..color = accent..strokeWidth = 3..strokeCap = StrokeCap.round);

    // elevation indicator
    final arrowP = Paint()..color = accent.withValues(alpha: 0.7)..strokeWidth = 1.5..strokeCap = StrokeCap.round;
    _drawArrow(canvas, Offset(elevEnd.dx + 5, cy - 5), Offset(elevEnd.dx + 5, cy - 30), arrowP);
    _drawLabel(canvas, '~30 cm', Offset(elevEnd.dx + 20, cy - 18), accent, fontSize: 10, bold: true);

    // support block under legs
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(legEnd.dx + 15, cy + 5), width: 30, height: 15),
        const Radius.circular(3),
      ),
      Paint()..color = accent.withValues(alpha: 0.2),
    );

    // blanket over body
    final blanketPath = Path();
    blanketPath.moveTo(cx - 40, cy + 3);
    blanketPath.quadraticBezierTo(cx, cy - 5, cx + 50, cy + 3);
    blanketPath.lineTo(cx + 50, cy + 10);
    blanketPath.quadraticBezierTo(cx, cy + 2, cx - 40, cy + 10);
    blanketPath.close();
    canvas.drawPath(blanketPath, Paint()..color = accent.withValues(alpha: 0.1));
    canvas.drawPath(blanketPath, Paint()..color = accent.withValues(alpha: 0.3)..strokeWidth = 1..style = PaintingStyle.stroke);

    _drawLabel(canvas, 'KEEP WARM', Offset(cx, cy + 25), accent, fontSize: 10, bold: true);

    // instruction labels
    _drawLabel(canvas, 'Flat on back • Legs elevated if safe', Offset(cx, cy + 55), Colors.white.withValues(alpha: 0.6), fontSize: 11);
    _drawLabel(canvas, 'Nothing to eat or drink', Offset(cx, cy + 70), accent, fontSize: 12, bold: true);
    _drawLabel(canvas, 'Monitor breathing continuously', Offset(cx, cy + 85), Colors.white.withValues(alpha: 0.5), fontSize: 10);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── 10. SCENE COMMAND ───

class _SceneCommandPainter extends CustomPainter {
  final Color accent;
  _SceneCommandPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackdrop(canvas, size, accent);

    final cx = size.width / 2;
    final cy = size.height / 2;

    final accentPaint = Paint()
      ..color = accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Shield in center
    final shieldPath = Path();
    shieldPath.moveTo(cx, cy - 40);
    shieldPath.lineTo(cx + 30, cy - 25);
    shieldPath.quadraticBezierTo(cx + 30, cy + 10, cx, cy + 25);
    shieldPath.quadraticBezierTo(cx - 30, cy + 10, cx - 30, cy - 25);
    shieldPath.close();
    canvas.drawPath(shieldPath, Paint()..color = accent.withValues(alpha: 0.16));
    canvas.drawPath(shieldPath, accentPaint);

    // checkmark inside shield
    canvas.drawLine(Offset(cx - 8, cy - 5), Offset(cx - 2, cy + 3), Paint()..color = accent..strokeWidth = 3..strokeCap = StrokeCap.round);
    canvas.drawLine(Offset(cx - 2, cy + 3), Offset(cx + 10, cy - 12), Paint()..color = accent..strokeWidth = 3..strokeCap = StrokeCap.round);

    _drawLabel(canvas, 'SAFE?', Offset(cx, cy - 52), accent, fontSize: 13, bold: true);

    // hazard icons around
    final hazards = ['⚡', '🔥', '🚗', '⚠'];
    final labels = ['Electric', 'Fire', 'Traffic', 'Violence'];
    for (var i = 0; i < 4; i++) {
      final angle = -math.pi / 2 + (i * math.pi / 2.2) - 0.3;
      final r = 70.0;
      final hx = cx + r * math.cos(angle);
      final hy = cy - 5 + r * math.sin(angle);
      _drawLabel(canvas, hazards[i], Offset(hx, hy), Colors.white, fontSize: 16);
      _drawLabel(canvas, labels[i], Offset(hx, hy + 14), Colors.white.withValues(alpha: 0.4), fontSize: 8);
    }

    // bottom labels
    _drawLabel(canvas, 'PROTECT YOURSELF FIRST', Offset(cx, cy + 55), accent, fontSize: 13, bold: true);
    _drawLabel(canvas, 'Then: Mark hazards → Guide EMS → Handoff', Offset(cx, cy + 72), Colors.white.withValues(alpha: 0.5), fontSize: 10);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
