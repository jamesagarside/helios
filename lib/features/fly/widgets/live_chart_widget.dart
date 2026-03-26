import 'dart:async';
import 'dart:collection';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';
import 'chart_toolbar.dart';

/// Series definition — describes what to extract from VehicleState.
class SeriesDef {
  const SeriesDef(this.name, this.color, this.extract);
  final String name;
  final Color color;
  final double Function(VehicleState v) extract;
}

/// Accumulated data for one series.
class _SeriesData {
  _SeriesData(this.def);
  final SeriesDef def;
  final Queue<FlSpot> points = Queue();
  double latest = 0;

  void addPoint(double timeSec, VehicleState vehicle) {
    latest = def.extract(vehicle);
    points.addLast(FlSpot(timeSec, latest));
    while (points.length > 1 && points.first.x < timeSec - 60) {
      points.removeFirst();
    }
  }
}

/// Static chart definitions per ChartType.
const _chartDefs = <ChartType, _ChartDef>{
  ChartType.altitude: _ChartDef('Altitude', Icons.height, 'm', [
    SeriesDef('REL', HeliosColors.accent, _getAltRel),
  ]),
  ChartType.speed: _ChartDef('Speed', Icons.speed, 'm/s', [
    SeriesDef('IAS', HeliosColors.accent, _getAirspeed),
    SeriesDef('GS', HeliosColors.success, _getGroundspeed),
  ]),
  ChartType.battery: _ChartDef('Battery', Icons.battery_full, 'V', [
    SeriesDef('V', HeliosColors.warning, _getVoltage),
  ]),
  ChartType.attitude: _ChartDef('Attitude', Icons.rotate_right, '\u00B0', [
    SeriesDef('Roll', HeliosColors.accent, _getRollDeg),
    SeriesDef('Pitch', HeliosColors.warning, _getPitchDeg),
  ]),
  ChartType.climbRate: _ChartDef('Climb Rate', Icons.trending_up, 'm/s', [
    SeriesDef('VS', HeliosColors.success, _getClimbRate),
  ]),
  ChartType.vibration: _ChartDef('Vibration', Icons.vibration, '', [
    SeriesDef('Accel', HeliosColors.danger, _getVibeProxy),
  ]),
};

// Extraction functions (top-level for const)
double _getAltRel(VehicleState v) => v.altitudeRel;
double _getAirspeed(VehicleState v) => v.airspeed;
double _getGroundspeed(VehicleState v) => v.groundspeed;
double _getVoltage(VehicleState v) => v.batteryVoltage;
double _getRollDeg(VehicleState v) => v.roll * 57.2958;
double _getPitchDeg(VehicleState v) => v.pitch * 57.2958;
double _getClimbRate(VehicleState v) => v.climbRate;
double _getVibeProxy(VehicleState v) => v.climbRate.abs() * 5;

class _ChartDef {
  const _ChartDef(this.title, this.icon, this.unit, this.seriesDefs);
  final String title;
  final IconData icon;
  final String unit;
  final List<SeriesDef> seriesDefs;
}

/// Draggable, semi-transparent live chart widget.
/// Reads vehicle state directly from Riverpod — no external data push needed.
class LiveChartWidget extends ConsumerStatefulWidget {
  const LiveChartWidget({
    super.key,
    required this.chartType,
    required this.initialPosition,
    this.initialWidth = 280,
    this.initialHeight = 150,
    this.onClose,
    this.onPositionChanged,
    this.onSizeChanged,
  });

  final ChartType chartType;
  final Offset initialPosition;
  final double initialWidth;
  final double initialHeight;
  final VoidCallback? onClose;
  final ValueChanged<Offset>? onPositionChanged;
  final void Function(double width, double height)? onSizeChanged;

  @override
  ConsumerState<LiveChartWidget> createState() => _LiveChartWidgetState();
}

class _LiveChartWidgetState extends ConsumerState<LiveChartWidget> {
  late Offset _position;
  late double _width;
  late double _height;
  late final List<_SeriesData> _seriesData;
  late final _ChartDef _def;
  Timer? _sampleTimer;
  final _stopwatch = Stopwatch();
  bool _minimised = false;

  static const double _minWidth = 200;
  static const double _maxWidth = 600;
  static const double _minHeight = 100;
  static const double _maxHeight = 400;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _width = widget.initialWidth.clamp(_minWidth, _maxWidth);
    _height = widget.initialHeight.clamp(_minHeight, _maxHeight);
    _def = _chartDefs[widget.chartType]!;
    _seriesData = _def.seriesDefs.map((d) => _SeriesData(d)).toList();
    _stopwatch.start();

    // Sample at 4 Hz
    _sampleTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final vehicle = ref.read(vehicleStateProvider);
      final t = _stopwatch.elapsedMilliseconds / 1000.0;
      for (final s in _seriesData) {
        s.addPoint(t, vehicle);
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sampleTimer?.cancel();
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
          setState(() => _position += details.delta);
          widget.onPositionChanged?.call(_position);
        },
        child: Container(
          width: _width,
          height: _minimised ? 32 : _height,
          decoration: BoxDecoration(
            color: HeliosColors.surfaceDim.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: HeliosColors.border.withValues(alpha: 0.6)),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  _TitleBar(
                    title: _def.title,
                    icon: _def.icon,
                    minimised: _minimised,
                    latestValues: _seriesData
                        .map((s) => '${s.latest.toStringAsFixed(1)}${_def.unit}')
                        .join(' / '),
                    onMinimise: () => setState(() => _minimised = !_minimised),
                    onClose: widget.onClose,
                  ),
                  if (!_minimised)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 8, 4),
                        child: _buildChart(),
                      ),
                    ),
                ],
              ),
              // Resize handle — bottom-right corner
              if (!_minimised)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        _width = (_width + details.delta.dx).clamp(_minWidth, _maxWidth);
                        _height = (_height + details.delta.dy).clamp(_minHeight, _maxHeight);
                      });
                    },
                    onPanEnd: (_) {
                      widget.onSizeChanged?.call(_width, _height);
                    },
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.resizeDownRight,
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CustomPaint(painter: _ResizeHandlePainter()),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChart() {
    final hasData = _seriesData.any((s) => s.points.length >= 2);
    if (!hasData) {
      return const Center(
        child: Text('Sampling...', style: TextStyle(color: HeliosColors.textTertiary, fontSize: 12)),
      );
    }

    final maxX = _stopwatch.elapsedMilliseconds / 1000.0;
    final minX = (maxX - 60).clamp(0.0, double.infinity);

    return LineChart(
      LineChartData(
        clipData: const FlClipData.all(),
        minX: minX,
        maxX: maxX,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
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
        lineBarsData: _seriesData.map((s) {
          return LineChartBarData(
            spots: s.points.toList(),
            isCurved: true,
            curveSmoothness: 0.15,
            color: s.def.color,
            barWidth: 1.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: _seriesData.length == 1
                ? BarAreaData(show: true, color: s.def.color.withValues(alpha: 0.08))
                : BarAreaData(show: false),
          );
        }).toList(),
        lineTouchData: const LineTouchData(enabled: false),
      ),
      duration: Duration.zero,
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
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: HeliosColors.textPrimary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              latestValues,
              style: HeliosTypography.telemetrySmall.copyWith(fontSize: 12),
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

/// Diagonal grip lines for the resize handle.
class _ResizeHandlePainter extends CustomPainter {
  const _ResizeHandlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = HeliosColors.textTertiary
      ..strokeWidth = 1;

    // Three diagonal lines
    for (var i = 0; i < 3; i++) {
      final offset = 4.0 + i * 3.5;
      canvas.drawLine(
        Offset(size.width, offset),
        Offset(offset, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
