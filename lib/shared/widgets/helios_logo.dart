import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/helios_colors.dart';

/// Helios logo — sun with radiating sight lines and constellation nodes.
///
/// Adapted from the Argus network/constellation logo:
/// - Argus = ground-facing network (horizontal constellation)
/// - Helios = sky-facing sun (radial constellation with rays)
///
/// Renders as CustomPainter for cross-platform compatibility (no SVG dep).
class HeliosLogo extends StatelessWidget {
  const HeliosLogo({super.key, this.size = 32, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HeliosLogoPainter(color: color ?? HeliosColors.accent),
      ),
    );
  }
}

class _HeliosLogoPainter extends CustomPainter {
  _HeliosLogoPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width; // assume square
    final cx = s / 2;
    final cy = s / 2;
    final scale = s / 100; // design is 100x100

    // Ray paint
    final rayPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..strokeWidth = 0.8 * scale
      ..style = PaintingStyle.stroke;

    // Connection paint
    final connPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 0.5 * scale
      ..style = PaintingStyle.stroke;

    final connDimPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 0.5 * scale
      ..style = PaintingStyle.stroke;

    // Node paint
    final nodePaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;

    final rayNodePaint = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;

    final corePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final coreGlow = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    // Helper
    Offset p(double x, double y) => Offset(x * scale, y * scale);

    // === Outer rays (8 directions) ===
    final rays = [
      [50.0, 10.0, 50.0, 25.0], // N
      [50.0, 75.0, 50.0, 90.0], // S
      [10.0, 50.0, 25.0, 50.0], // W
      [75.0, 50.0, 90.0, 50.0], // E
      [21.0, 21.0, 32.0, 32.0], // NW
      [68.0, 68.0, 79.0, 79.0], // SE
      [79.0, 21.0, 68.0, 32.0], // NE
      [32.0, 68.0, 21.0, 79.0], // SW
    ];
    for (final r in rays) {
      canvas.drawLine(p(r[0], r[1]), p(r[2], r[3]), rayPaint);
    }

    // === Corona connections (hexagonal ring) ===
    final conns = [
      [50.0, 28.0, 35.0, 38.0],
      [50.0, 28.0, 65.0, 38.0],
      [35.0, 38.0, 28.0, 50.0],
      [65.0, 38.0, 72.0, 50.0],
      [28.0, 50.0, 35.0, 62.0],
      [72.0, 50.0, 65.0, 62.0],
      [35.0, 62.0, 50.0, 72.0],
      [65.0, 62.0, 50.0, 72.0],
    ];
    for (final c in conns) {
      canvas.drawLine(p(c[0], c[1]), p(c[2], c[3]), connPaint);
    }

    // Cross connections
    canvas.drawLine(p(35, 38), p(65, 38), connDimPaint);
    canvas.drawLine(p(35, 62), p(65, 62), connDimPaint);
    canvas.drawLine(p(28, 50), p(72, 50), connDimPaint);
    canvas.drawLine(p(35, 38), p(65, 62), connDimPaint);
    canvas.drawLine(p(65, 38), p(35, 62), connDimPaint);

    // === Ray tip nodes ===
    final rayNodes = [
      [50.0, 10.0, 2.4], [50.0, 90.0, 2.4],
      [10.0, 50.0, 2.4], [90.0, 50.0, 2.4],
      [21.0, 21.0, 2.0], [79.0, 79.0, 2.0],
      [79.0, 21.0, 2.0], [21.0, 79.0, 2.0],
    ];
    for (final n in rayNodes) {
      canvas.drawCircle(p(n[0], n[1]), n[2] * scale, rayNodePaint);
    }

    // === Corona nodes ===
    final coronaNodes = [
      [50.0, 28.0, 3.2], [50.0, 72.0, 3.2],
      [28.0, 50.0, 3.2], [72.0, 50.0, 3.2],
      [35.0, 38.0, 3.0], [65.0, 38.0, 3.0],
      [35.0, 62.0, 3.0], [65.0, 62.0, 3.0],
    ];
    for (final n in coronaNodes) {
      canvas.drawCircle(p(n[0], n[1]), n[2] * scale, nodePaint);
    }

    // === Centre core ===
    canvas.drawCircle(Offset(cx, cy), 8 * scale, coreGlow);
    canvas.drawCircle(Offset(cx, cy), 5.6 * scale, corePaint);
  }

  @override
  bool shouldRepaint(covariant _HeliosLogoPainter old) => color != old.color;
}
