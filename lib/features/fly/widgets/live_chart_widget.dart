import 'dart:async';
import 'dart:collection';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// A single data series for the live chart.
class LiveSeries {
  LiveSeries({
    required this.name,
    required this.color,
    required this.getValue,
    this.unit = '',
  });

  final String name;
  final Color color;
  final double Function() getValue;
  final String unit;

  final Queue<FlSpot> _points = Queue();

  void addPoint(double timeSec) {
    _points.addLast(FlSpot(timeSec, getValue()));
    // Keep last 60 seconds of data
    while (_points.length > 1 && _points.first.x < timeSec - 60) {
      _points.removeFirst();
    }
  }

  List<FlSpot> get points => _points.toList();
  double get latest => _points.isEmpty ? 0 : _points.last.y;
}

/// Configuration for a live chart widget type.
class LiveChartConfig {
  const LiveChartConfig({
    required this.title,
    required this.icon,
    required this.series,
    this.unit = '',
    this.minY,
    this.maxY,
  });

  final String title;
  final IconData icon;
  final List<LiveSeries> series;
  final String unit;
  final double? minY;
  final double? maxY;
}

/// Draggable, semi-transparent live chart that overlays on the Fly View map.
class LiveChartWidget extends StatefulWidget {
  const LiveChartWidget({
    super.key,
    required this.config,
    required this.initialPosition,
    this.width = 280,
    this.height = 150,
    this.onClose,
    this.onPositionChanged,
  });

  final LiveChartConfig config;
  final Offset initialPosition;
  final double width;
  final double height;
  final VoidCallback? onClose;
  final ValueChanged<Offset>? onPositionChanged;

  @override
  State<LiveChartWidget> createState() => _LiveChartWidgetState();
}

class _LiveChartWidgetState extends State<LiveChartWidget> {
  late Offset _position;
  Timer? _updateTimer;
  final _stopwatch = Stopwatch();
  bool _minimised = false;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _stopwatch.start();

    // Update at 4 Hz
    _updateTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final t = _stopwatch.elapsedMilliseconds / 1000.0;
      for (final series in widget.config.series) {
        series.addPoint(t);
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
          widget.onPositionChanged?.call(_position);
        },
        child: Container(
          width: widget.width,
          height: _minimised ? 32 : widget.height,
          decoration: BoxDecoration(
            color: HeliosColors.surfaceDim.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: HeliosColors.border.withValues(alpha: 0.6)),
          ),
          child: Column(
            children: [
              // Title bar (always visible, draggable)
              _TitleBar(
                title: widget.config.title,
                icon: widget.config.icon,
                minimised: _minimised,
                latestValues: widget.config.series
                    .map((s) => '${s.latest.toStringAsFixed(1)}${widget.config.unit}')
                    .join(' / '),
                onMinimise: () => setState(() => _minimised = !_minimised),
                onClose: widget.onClose,
              ),
              // Chart (hidden when minimised)
              if (!_minimised)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 8, 4),
                    child: _buildChart(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChart() {
    final allSpots = widget.config.series.expand((s) => s.points).toList();
    if (allSpots.isEmpty) {
      return const Center(
        child: Text('Waiting...', style: TextStyle(color: HeliosColors.textTertiary, fontSize: 10)),
      );
    }

    final maxX = allSpots.map((s) => s.x).reduce((a, b) => a > b ? a : b);
    final minX = (maxX - 60).clamp(0.0, double.infinity);

    return LineChart(
      LineChartData(
        clipData: const FlClipData.all(),
        minX: minX,
        maxX: maxX,
        minY: widget.config.minY,
        maxY: widget.config.maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: null,
          getDrawingHorizontalLine: (_) => FlLine(
            color: HeliosColors.border.withValues(alpha: 0.3),
            strokeWidth: 0.5,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) {
                if (meta.min == value || meta.max == value) return const SizedBox();
                return Text(
                  value.toStringAsFixed(value.abs() < 10 ? 1 : 0),
                  style: const TextStyle(fontSize: 8, color: HeliosColors.textTertiary),
                );
              },
            ),
          ),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: widget.config.series.map((s) {
          return LineChartBarData(
            spots: s.points,
            isCurved: true,
            curveSmoothness: 0.15,
            color: s.color,
            barWidth: 1.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: widget.config.series.length == 1
                ? BarAreaData(show: true, color: s.color.withValues(alpha: 0.08))
                : BarAreaData(show: false),
          );
        }).toList(),
        lineTouchData: const LineTouchData(enabled: false),
      ),
      duration: Duration.zero, // No animation for real-time
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.title,
    required this.icon,
    required this.minimised,
    required this.latestValues,
    required this.onMinimise,
    required this.onClose,
  });

  final String title;
  final IconData icon;
  final bool minimised;
  final String latestValues;
  final VoidCallback onMinimise;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: HeliosColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.vertical(
          top: const Radius.circular(6),
          bottom: minimised ? const Radius.circular(6) : Radius.zero,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 12, color: HeliosColors.accent),
          const SizedBox(width: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: HeliosColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              latestValues,
              style: HeliosTypography.telemetrySmall.copyWith(fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onMinimise,
            child: Icon(
              minimised ? Icons.expand_more : Icons.expand_less,
              size: 14,
              color: HeliosColors.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          if (onClose != null)
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close, size: 12, color: HeliosColors.textSecondary),
            ),
        ],
      ),
    );
  }
}
