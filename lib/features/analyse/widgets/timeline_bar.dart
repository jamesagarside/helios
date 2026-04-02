import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';
import 'synced_line_chart.dart';

enum _DragTarget { none, leftHandle, rightHandle, pan, crosshair }

/// A scrub-able timeline bar that shows the full flight duration, a miniature
/// altitude profile, the currently visible zoom range, event markers, and a
/// draggable playhead synced to the shared [crosshairX].
///
/// Interaction model:
/// - Drag left/right handles → resize the zoom window
/// - Drag inside zoom window → pan the window left/right
/// - Tap outside zoom window → move crosshair
/// - Scroll anywhere → zoom in/out centred on cursor
class TimelineBar extends StatefulWidget {
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
  State<TimelineBar> createState() => _TimelineBarState();
}

class _TimelineBarState extends State<TimelineBar> {
  _DragTarget _dragTarget = _DragTarget.none;
  double _panStartViewMin = 0;
  double _panStartViewMax = 0;
  double _panStartX = 0;

  static const _handleHitZone = 10.0; // px around handle that triggers resize

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barWidth = constraints.maxWidth;

          return Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && widget.onZoom != null) {
                final fraction =
                    (event.localPosition.dx / barWidth).clamp(0.0, 1.0);
                final atX = widget.totalDuration * fraction;
                widget.onZoom!(event.scrollDelta.dy, atX);
              }
            },
            child: GestureDetector(
              onHorizontalDragStart: (d) =>
                  _onDragStart(d, barWidth),
              onHorizontalDragUpdate: (d) =>
                  _onDragUpdate(d, barWidth),
              onHorizontalDragEnd: (_) =>
                  _dragTarget = _DragTarget.none,
              onTapDown: (d) => _onTap(d, barWidth),
              child: ListenableBuilder(
                listenable: Listenable.merge(
                    [widget.crosshairX, widget.viewMinX, widget.viewMaxX]),
                builder: (context, _) {
                  final hc = context.hc;
                  return MouseRegion(
                    cursor: _cursorForPosition(barWidth),
                    child: CustomPaint(
                      size: Size(barWidth, widget.height),
                      painter: _TimelinePainter(
                        crosshairX: widget.crosshairX.value,
                        viewMinX: widget.viewMinX.value,
                        viewMaxX: widget.viewMaxX.value,
                        totalDuration: widget.totalDuration,
                        referenceSeries: widget.referenceSeries,
                        events: widget.events,
                        surfaceDimColor: hc.surfaceDim,
                        backgroundDimColor: hc.background,
                        accentColor: hc.accent,
                        textTertiaryColor: hc.textTertiary,
                      ),
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

  /// Determine which zone was tapped/dragged at [localX].
  _DragTarget _hitTest(double localX, double barWidth) {
    if (widget.totalDuration <= 0 || barWidth <= 0) return _DragTarget.none;
    final leftPx = (widget.viewMinX.value / widget.totalDuration) * barWidth;
    final rightPx = (widget.viewMaxX.value / widget.totalDuration) * barWidth;
    if ((localX - leftPx).abs() <= _handleHitZone) return _DragTarget.leftHandle;
    if ((localX - rightPx).abs() <= _handleHitZone) return _DragTarget.rightHandle;
    if (localX > leftPx && localX < rightPx) return _DragTarget.pan;
    return _DragTarget.crosshair;
  }

  MouseCursor _cursorForPosition(double barWidth) {
    // Always returns system mouse cursor based on drag state or current position.
    // We can't read mouse position here without a StatefulWidget hover tracker,
    // so use the active drag target to change cursor during drag.
    return switch (_dragTarget) {
      _DragTarget.leftHandle || _DragTarget.rightHandle =>
        SystemMouseCursors.resizeLeftRight,
      _DragTarget.pan => SystemMouseCursors.grabbing,
      _ => SystemMouseCursors.basic,
    };
  }

  void _onDragStart(DragStartDetails details, double barWidth) {
    _dragTarget = _hitTest(details.localPosition.dx, barWidth);
    if (_dragTarget == _DragTarget.pan) {
      _panStartViewMin = widget.viewMinX.value;
      _panStartViewMax = widget.viewMaxX.value;
      _panStartX = details.localPosition.dx;
    }
  }

  void _onDragUpdate(DragUpdateDetails details, double barWidth) {
    if (widget.totalDuration <= 0 || barWidth <= 0) return;
    final dx = details.localPosition.dx;

    switch (_dragTarget) {
      case _DragTarget.leftHandle:
        final newMin = ((dx / barWidth) * widget.totalDuration)
            .clamp(0.0, widget.viewMaxX.value - 1.0);
        widget.viewMinX.value = newMin;

      case _DragTarget.rightHandle:
        final newMax = ((dx / barWidth) * widget.totalDuration)
            .clamp(widget.viewMinX.value + 1.0, widget.totalDuration);
        widget.viewMaxX.value = newMax;

      case _DragTarget.pan:
        final dSeconds = ((dx - _panStartX) / barWidth) * widget.totalDuration;
        final range = _panStartViewMax - _panStartViewMin;
        final newMin = (_panStartViewMin + dSeconds)
            .clamp(0.0, widget.totalDuration - range);
        widget.viewMinX.value = newMin;
        widget.viewMaxX.value = newMin + range;

      case _DragTarget.crosshair:
        final fraction = (dx / barWidth).clamp(0.0, 1.0);
        widget.crosshairX.value = widget.totalDuration * fraction;

      case _DragTarget.none:
        break;
    }
  }

  void _onTap(TapDownDetails details, double barWidth) {
    if (widget.totalDuration <= 0 || barWidth <= 0) return;
    final target = _hitTest(details.localPosition.dx, barWidth);
    if (target == _DragTarget.crosshair || target == _DragTarget.none) {
      final fraction =
          (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
      widget.crosshairX.value = widget.totalDuration * fraction;
    }
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
