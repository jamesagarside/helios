import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';
import 'synced_line_chart.dart';

/// A scrub-able timeline bar that shows the full flight duration, a miniature
/// altitude profile, the currently visible zoom range, event markers, and a
/// draggable playhead synced to the shared [crosshairX].
class TimelineBar extends StatelessWidget {
  const TimelineBar({
    super.key,
    required this.crosshairX,
    required this.viewMinX,
    required this.viewMaxX,
    required this.totalDuration,
    this.referenceSeries = const [],
    this.events = const [],
    this.onZoom,
    this.height = 56,
  });

  final ValueNotifier<double?> crosshairX;
  final ValueNotifier<double> viewMinX;
  final ValueNotifier<double> viewMaxX;
  final double totalDuration;

  /// A reference data series (e.g. altitude) shown as a miniature area chart.
  final List<FlSpot> referenceSeries;
  final List<ChartEvent> events;
  final void Function(double delta, double atX)? onZoom;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barWidth = constraints.maxWidth;

          return Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && onZoom != null) {
                final fraction =
                    (event.localPosition.dx / barWidth).clamp(0.0, 1.0);
                final atX = totalDuration * fraction;
                onZoom!(event.scrollDelta.dy, atX);
              }
            },
            child: GestureDetector(
              onHorizontalDragUpdate: (details) => _onScrub(details, barWidth),
              onTapDown: (details) => _onTap(details, barWidth),
              child: ListenableBuilder(
                listenable:
                    Listenable.merge([crosshairX, viewMinX, viewMaxX]),
                builder: (context, _) {
                  final hc = context.hc;
                  return CustomPaint(
                    size: Size(barWidth, height),
                    painter: _TimelinePainter(
                      crosshairX: crosshairX.value,
                      viewMinX: viewMinX.value,
                      viewMaxX: viewMaxX.value,
                      totalDuration: totalDuration,
                      referenceSeries: referenceSeries,
                      events: events,
                      surfaceDimColor: hc.surfaceDim,
                      backgroundDimColor: hc.background,
                      accentColor: hc.accent,
                      textTertiaryColor: hc.textTertiary,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _onScrub(DragUpdateDetails details, double barWidth) {
    if (totalDuration <= 0 || barWidth <= 0) return;
    final fraction = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
    crosshairX.value = totalDuration * fraction;
  }

  void _onTap(TapDownDetails details, double barWidth) {
    if (totalDuration <= 0 || barWidth <= 0) return;
    final fraction = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
    crosshairX.value = totalDuration * fraction;
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.crosshairX,
    required this.viewMinX,
    required this.viewMaxX,
    required this.totalDuration,
    required this.referenceSeries,
    required this.events,
    required this.surfaceDimColor,
    required this.backgroundDimColor,
    required this.accentColor,
    required this.textTertiaryColor,
  });

  final double? crosshairX;
  final double viewMinX;
  final double viewMaxX;
  final double totalDuration;
  final List<FlSpot> referenceSeries;
  final List<ChartEvent> events;
  final Color surfaceDimColor;
  final Color backgroundDimColor;
  final Color accentColor;
  final Color textTertiaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (totalDuration <= 0) return;

    final w = size.width;
    final h = size.height;
    const topPad = 4.0;
    const bottomPad = 14.0; // room for time labels
    final chartH = h - topPad - bottomPad;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = surfaceDimColor,
    );

    // Mini altitude profile
    if (referenceSeries.length >= 2) {
      _drawMiniProfile(canvas, w, chartH, topPad);
    }

    // Dim out-of-view regions
    final leftFrac = viewMinX / totalDuration;
    final rightFrac = viewMaxX / totalDuration;
    final dimPaint = Paint()
      ..color = backgroundDimColor.withValues(alpha: 0.55);

    if (leftFrac > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, leftFrac * w, h), dimPaint);
    }
    if (rightFrac < 1) {
      canvas.drawRect(
        Rect.fromLTWH(rightFrac * w, 0, (1 - rightFrac) * w, h),
        dimPaint,
      );
    }

    // Visible range border
    final rangeRect = Rect.fromLTRB(leftFrac * w, 0, rightFrac * w, h);
    canvas.drawRect(
      rangeRect,
      Paint()
        ..color = accentColor.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Range handles (small rectangles at left/right edges)
    final handlePaint = Paint()..color = accentColor;
    const handleW = 3.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(leftFrac * w - 1, 0, handleW, h),
        const Radius.circular(1),
      ),
      handlePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rightFrac * w - handleW + 1, 0, handleW, h),
        const Radius.circular(1),
      ),
      handlePaint,
    );

    // Event markers
    for (final event in events) {
      final x = (event.timeSeconds / totalDuration) * w;
      canvas.drawCircle(
        Offset(x, h - bottomPad + 4),
        3,
        Paint()..color = event.color,
      );
    }

    // Crosshair / playhead
    if (crosshairX != null) {
      final cx = (crosshairX! / totalDuration).clamp(0.0, 1.0) * w;
      canvas.drawLine(
        Offset(cx, 0),
        Offset(cx, h - bottomPad),
        Paint()
          ..color = accentColor
          ..strokeWidth = 1.5,
      );

      // Scrub time label
      final timeStr = _formatTime(crosshairX!);
      final tp = TextPainter(
        text: TextSpan(
          text: timeStr,
          style: HeliosTypography.caption.copyWith(
            color: accentColor,
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelX = (cx - tp.width / 2).clamp(0.0, w - tp.width);
      tp.paint(canvas, Offset(labelX, h - bottomPad + 1));
    }

    // Start / end time labels
    _paintTimeLabel(canvas, 0, h, _formatTime(0), TextAlign.left);
    _paintTimeLabel(canvas, w, h, _formatTime(totalDuration), TextAlign.right);
  }

  void _drawMiniProfile(Canvas canvas, double w, double chartH, double topPad) {
    // Find Y range
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (final spot in referenceSeries) {
      if (spot.y < minY) minY = spot.y;
      if (spot.y > maxY) maxY = spot.y;
    }
    if (maxY <= minY) maxY = minY + 1;

    final path = Path();
    final fillPath = Path();

    for (var i = 0; i < referenceSeries.length; i++) {
      final spot = referenceSeries[i];
      final x = (spot.x / totalDuration) * w;
      final y = topPad + chartH - ((spot.y - minY) / (maxY - minY)) * chartH;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, topPad + chartH);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Close fill path
    final lastX =
        (referenceSeries.last.x / totalDuration) * w;
    fillPath.lineTo(lastX, topPad + chartH);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()..color = accentColor.withValues(alpha: 0.08),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = accentColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  void _paintTimeLabel(
      Canvas canvas, double x, double h, String text, TextAlign align) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            fontSize: 10, color: textTertiaryColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = align == TextAlign.left ? 4.0 : x - tp.width - 4;
    tp.paint(canvas, Offset(dx, h - 12));
  }

  String _formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      crosshairX != old.crosshairX ||
      viewMinX != old.viewMinX ||
      viewMaxX != old.viewMaxX ||
      totalDuration != old.totalDuration ||
      accentColor != old.accentColor ||
      surfaceDimColor != old.surfaceDimColor ||
      backgroundDimColor != old.backgroundDimColor ||
      textTertiaryColor != old.textTertiaryColor;
}
