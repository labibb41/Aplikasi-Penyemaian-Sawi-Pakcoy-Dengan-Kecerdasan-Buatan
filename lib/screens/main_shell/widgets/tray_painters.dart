import 'package:flutter/material.dart';

class TopViewTrayPainter extends CustomPainter {
  final List<int> etiolatedIndices;

  TopViewTrayPainter({required this.etiolatedIndices});

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF1E293B);
    canvas.drawRect(Offset.zero & size, bg);

    const cols = 6;
    const rows = 4;
    const padX = 16.0;
    const padY = 14.0;
    final cellW = (size.width - padX * 2) / cols;
    final cellH = (size.height - padY * 2) / rows;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final isEtio = etiolatedIndices.contains(idx);
        final rect = Rect.fromLTWH(
          padX + c * cellW + 4,
          padY + r * cellH + 4,
          cellW - 8,
          cellH - 8,
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()
            ..color = isEtio ? const Color(0xFFEF4444) : const Color(0xFF22C55E)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );

        canvas.drawCircle(
          rect.center,
          isEtio ? 5.5 : 7.5,
          Paint()
            ..color = isEtio
                ? const Color(0xFFBEF264)
                : const Color(0xFF22C55E),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant TopViewTrayPainter oldDelegate) =>
      oldDelegate.etiolatedIndices != etiolatedIndices;
}

class SideViewStemPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1E293B),
    );

    // Threshold line
    final limitY = size.height * 0.44;
    canvas.drawLine(
      Offset(0, limitY),
      Offset(size.width, limitY),
      Paint()
        ..color = const Color(0xFFF87171)
        ..strokeWidth = 1.4,
    );

    // Tray base
    final trayY = size.height * 0.78;
    canvas.drawRect(
      Rect.fromLTWH(16, trayY, size.width - 32, 24),
      Paint()..color = const Color(0xFF334155),
    );

    final stems = [
      (0.16, 0.20, false),
      (0.35, 0.52, true),
      (0.54, 0.18, false),
      (0.71, 0.46, true),
      (0.86, 0.21, false),
    ];

    for (final (xFactor, hFactor, isEtio) in stems) {
      final x = size.width * xFactor;
      final topY = trayY - size.height * hFactor;

      canvas.drawLine(
        Offset(x, trayY),
        Offset(x, topY),
        Paint()
          ..color = isEtio ? const Color(0xFFD9F99D) : const Color(0xFF22C55E)
          ..strokeWidth = isEtio ? 2.2 : 3.2,
      );

      canvas.drawCircle(
        Offset(x, topY),
        isEtio ? 6 : 8,
        Paint()
          ..color = isEtio ? const Color(0xFFBEF264) : const Color(0xFF4ADE80),
      );

      canvas.drawRect(
        Rect.fromLTRB(x - 16, topY - 10, x + 16, trayY),
        Paint()
          ..color = isEtio ? const Color(0xFFEF4444) : const Color(0xFF22C55E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

