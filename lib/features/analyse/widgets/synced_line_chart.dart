import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../shared/theme/helios_colors.dart';

/// A single data series for a chart.
class ChartSeries {
  const ChartSeries(this.name, this.spots, this.color);
  final String name;
  final List<FlSpot> spots;
  final Color color;
}

/// An event marker to display on charts and the timeline bar.
class ChartEvent {
  const ChartEvent({
    required this.timeSeconds,
    required this.label,
    required this.color,
  });
  final double timeSeconds;
  final String label;
  final Color color;
}

/// A labelled horizontal reference line drawn across a chart.
class ChartReferenceLine {
  const ChartReferenceLine({
    required this.y,
    required this.label,
    required this.color,
  });
  final double y;
  final String label;
  final Color color;
}

/// A line chart that synchronises its crosshair with sibling charts via shared
/// [ValueNotifier]s.
///
/// When the user hovers any [SyncedLineChart], all siblings show a vertical
/// crosshair line and value tooltips at the same X (time) position.
class SyncedLineChart extends StatelessWidget {
  const SyncedLineChart({
    super.key,
    required this.series,
    required this.yLabel,
    required this.crosshairX,
    required this.viewMinX,
    required this.viewMaxX,
    this.events = const [],
    this.referenceLines = const [],
    this.height = 180,
    this.onZoom,
    this.minY,
    this.maxY,
  });

  final List<ChartSeries> series;
  final String yLabel;
  final ValueNotifier<double?> crosshairX;
  final ValueNotifier<double> viewMinX;
  final ValueNotifier<double> viewMaxX;
  final List<ChartEvent> events;
  final List<ChartReferenceLine> referenceLines;
  final double height;

  /// Fixed Y-axis bounds. When null, fl_chart auto-scales.
  final double? minY;
  final double? maxY;

  /// Called when the user scrolls on this chart. Parameters are scroll delta
  /// and the data-space X at the cursor position.
  final void Function(double delta, double atX)? onZoom;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return SizedBox(
      height: height,
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent && onZoom != null) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final localX = event.localPosition.dx;
            const chartLeft = 44.0; // Y-axis label reserve
            final chartWidth = box.size.width - chartLeft;
            if (chartWidth <= 0) return;
            final fraction =
                ((localX - chartLeft) / chartWidth).clamp(0.0, 1.0);
            final minX = viewMinX.value;
            final maxX = viewMaxX.value;
            final atX = minX + fraction * (maxX - minX);
            onZoom!(event.scrollDelta.dy, atX);
          }
        },
        child: ListenableBuilder(
          listenable: Listenable.merge([crosshairX, viewMinX, viewMaxX]),
          builder: (context, _) => _buildChart(hc),
        ),
      ),
    );
  }

  Widget _buildChart(HeliosColors hc) {
    final cx = crosshairX.value;
    final minX = viewMinX.value;
    final maxX = viewMaxX.value;

    final barDataList = series.map((s) {
      return LineChartBarData(
        spots: s.spots,
        isCurved: true,
        curveSmoothness: 0.2,
        color: s.color,
        barWidth: 1.5,
        isStrokeCapRound: true,
        dotData: const FlDotData(show: false),
        belowBarData: series.length == 1
            ? BarAreaData(
                show: true, color: s.color.withValues(alpha: 0.08))
            : BarAreaData(show: false),
      );
    }).toList();

    // Vertical lines: crosshair + event markers
    final verticalLines = <VerticalLine>[];

    if (cx != null && cx >= minX && cx <= maxX) {
      verticalLines.add(VerticalLine(
        x: cx,
        color: hc.textSecondary.withValues(alpha: 0.4),
        strokeWidth: 1,
        dashArray: [4, 4],
      ));
    }

    for (final event in events) {
      if (event.timeSeconds >= minX && event.timeSeconds <= maxX) {
        verticalLines.add(VerticalLine(
          x: event.timeSeconds,
          color: event.color.withValues(alpha: 0.5),
          strokeWidth: 1,
          dashArray: [3, 3],
          label: VerticalLineLabel(
            show: true,
            alignment: Alignment.topRight,
            style: TextStyle(fontSize: 9, color: event.color),
            labelResolver: (_) => event.label,
          ),
        ));
      }
    }

    // Programmatic tooltip indicators at the crosshair position
    final tooltipIndicators = <ShowingTooltipIndicators>[];
    if (cx != null && cx >= minX && cx <= maxX) {
      final spots = <LineBarSpot>[];
      for (var i = 0; i < series.length; i++) {
        final idx = _nearestSpotIndex(series[i].spots, cx);
        if (idx >= 0) {
          spots.add(LineBarSpot(barDataList[i], i, series[i].spots[idx]));
        }
      }
      if (spots.isNotEmpty) {
        tooltipIndicators.add(ShowingTooltipIndicators(spots));
      }
    }

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: hc.border,
            strokeWidth: 0.5,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) {
                if (meta.min == value || meta.max == value) {
                  return const SizedBox();
                }
                return Text(
                  value.toStringAsFixed(value.abs() < 10 ? 1 : 0),
                  style: TextStyle(
                      fontSize: 12, color: hc.textTertiary),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                if (meta.min == value || meta.max == value) {
                  return const SizedBox();
                }
                final mins = (value / 60).floor();
                final secs = (value % 60).floor();
                return Text(
                  '$mins:${secs.toString().padLeft(2, '0')}',
                  style: TextStyle(
                      fontSize: 12, color: hc.textTertiary),
                );
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            left: BorderSide(color: hc.border, width: 0.5),
            bottom: BorderSide(color: hc.border, width: 0.5),
          ),
        ),
        lineBarsData: barDataList,
        extraLinesData: ExtraLinesData(
          verticalLines: verticalLines,
          horizontalLines: referenceLines.map((ref) {
            return HorizontalLine(
              y: ref.y,
              color: ref.color.withValues(alpha: 0.5),
              strokeWidth: 1,
              dashArray: [6, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                padding: const EdgeInsets.only(right: 4, bottom: 2),
                style: TextStyle(fontSize: 9, color: ref.color),
                labelResolver: (_) => ref.label,
              ),
            );
          }).toList(),
        ),
        showingTooltipIndicators: tooltipIndicators,
        lineTouchData: LineTouchData(
          handleBuiltInTouches: false,
          touchCallback: (event, response) {
            if (event is FlPointerExitEvent) {
              crosshairX.value = null;
            } else if (response?.lineBarSpots?.isNotEmpty == true) {
              crosshairX.value = response!.lineBarSpots!.first.x;
            }
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => hc.surface,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final s = series[spot.barIndex];
                return LineTooltipItem(
                  '${s.name}: ${spot.y.toStringAsFixed(2)} $yLabel',
                  TextStyle(color: s.color, fontSize: 12),
                );
              }).toList();
            },
          ),
        ),
      ),
      duration: Duration.zero,
    );
  }

  /// Binary search for the spot index nearest to [x].
  static int _nearestSpotIndex(List<FlSpot> spots, double x) {
    if (spots.isEmpty) return -1;
    var lo = 0;
    var hi = spots.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (spots[mid].x < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0 &&
        (x - spots[lo - 1].x).abs() < (spots[lo].x - x).abs()) {
      return lo - 1;
    }
    return lo;
  }
}
