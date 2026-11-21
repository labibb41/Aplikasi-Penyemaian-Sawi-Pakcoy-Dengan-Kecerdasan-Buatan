import 'package:flutter/material.dart';

class SplashBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.10);
    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }

    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final center = Offset(size.width / 2, size.height * 0.42);
    canvas.drawCircle(center, 110, ringPaint);
    canvas.drawCircle(center, 155, ringPaint);

    final glowPaint = Paint()
      ..color = const Color(0xFF6EE7B7).withValues(alpha: 0.12);
    canvas.drawCircle(
      Offset(size.width * 0.9, size.height * 0.08),
      110,
      glowPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.85),
      130,
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================================
// SCREEN 2: LOGIN SCREEN
// ============================================================================

