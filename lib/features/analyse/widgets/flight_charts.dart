import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/telemetry/telemetry_store.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Pre-built visual analytics dashboard — no SQL required.
///
/// When [liveMode] is true, refreshes every 2 seconds for real-time updates.
class FlightCharts extends StatefulWidget {
  const FlightCharts({
    super.key,
    required this.store,
    this.liveMode = false,
  });

  final TelemetryStore store;
  final bool liveMode;

  @override
  State<FlightCharts> createState() => _FlightChartsState();
}

class _FlightChartsState extends State<FlightCharts> {
  Timer? _refreshTimer;
  bool _loading = true;
  String? _error;

  // Chart data
  List<FlSpot> _altitudeRel = [];
  List<FlSpot> _altitudeMsl = [];
  List<FlSpot> _airspeed = [];
  List<FlSpot> _groundspeed = [];
  List<FlSpot> _climbRate = [];
  List<FlSpot> _voltage = [];
  List<FlSpot> _batteryPct = [];
  List<FlSpot> _satellites = [];
  List<FlSpot> _hdop = [];
  List<FlSpot> _vibeX = [];
  List<FlSpot> _vibeY = [];
  List<FlSpot> _vibeZ = [];
  List<FlSpot> _roll = [];
  List<FlSpot> _pitch = [];

  // Summary stats
  double _maxAlt = 0;
  double _maxSpeed = 0;
  double _minVoltage = 0;
  double _avgGroundspeed = 0;
  int _totalRows = 0;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadData();

    // Live mode: refresh every 2 seconds
    if (widget.liveMode) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) _loadData();
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });

    try {
      // Load all data in parallel-ish (sequential but fast since it's local DuckDB)
      await Future.wait([
        _loadAltitudeSpeed(),
        _loadBattery(),
        _loadGps(),
        _loadVibration(),
        _loadAttitude(),
        _loadSummary(),
      ]);
      setState(() => _loading = false);
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _loadAltitudeSpeed() async {
    final result = await widget.store.query(
      'SELECT ts, airspeed, groundspeed, climb FROM vfr_hud ORDER BY ts'
    );
    if (result.rowCount == 0) return;

    final startTime = _parseTimestamp(result.rows.first[0]);
    _airspeed = _toSpots(result.rows, 0, 1, startTime);
    _groundspeed = _toSpots(result.rows, 0, 2, startTime);
    _climbRate = _toSpots(result.rows, 0, 3, startTime);

    final altResult = await widget.store.query(
      'SELECT ts, alt_rel, alt_msl FROM gps ORDER BY ts'
    );
    if (altResult.rowCount == 0) return;
    _altitudeRel = _toSpots(altResult.rows, 0, 1, startTime);
    _altitudeMsl = _toSpots(altResult.rows, 0, 2, startTime);
  }

  Future<void> _loadBattery() async {
    final result = await widget.store.query(
      'SELECT ts, voltage, remaining_pct FROM battery ORDER BY ts'
    );
    if (result.rowCount == 0) return;
    final startTime = _parseTimestamp(result.rows.first[0]);
    _voltage = _toSpots(result.rows, 0, 1, startTime);
    _batteryPct = _toSpots(result.rows, 0, 2, startTime);
  }

  Future<void> _loadGps() async {
    final result = await widget.store.query(
      'SELECT ts, satellites, hdop FROM gps ORDER BY ts'
    );
    if (result.rowCount == 0) return;
    final startTime = _parseTimestamp(result.rows.first[0]);
    _satellites = _toSpots(result.rows, 0, 1, startTime);
    _hdop = _toSpots(result.rows, 0, 2, startTime);
  }

  Future<void> _loadVibration() async {
    final result = await widget.store.query(
      'SELECT ts, vibe_x, vibe_y, vibe_z FROM vibration ORDER BY ts'
    );
    if (result.rowCount == 0) return;
    final startTime = _parseTimestamp(result.rows.first[0]);
    _vibeX = _toSpots(result.rows, 0, 1, startTime);
    _vibeY = _toSpots(result.rows, 0, 2, startTime);
    _vibeZ = _toSpots(result.rows, 0, 3, startTime);
  }

  Future<void> _loadAttitude() async {
    // Downsample attitude (high frequency) — take every 10th row
    final result = await widget.store.query(
      'SELECT ts, roll * 57.2958 AS roll_deg, pitch * 57.2958 AS pitch_deg '
      'FROM attitude WHERE rowid % 10 = 0 ORDER BY ts'
    );
    if (result.rowCount == 0) return;
    final startTime = _parseTimestamp(result.rows.first[0]);
    _roll = _toSpots(result.rows, 0, 1, startTime);
    _pitch = _toSpots(result.rows, 0, 2, startTime);
  }

  Future<void> _loadSummary() async {
    try {
      final result = await widget.store.query('''
        SELECT
          (SELECT COUNT(*) FROM gps) AS gps_rows,
          (SELECT MAX(alt_rel) FROM gps) AS max_alt,
          (SELECT MAX(airspeed) FROM vfr_hud) AS max_ias,
          (SELECT AVG(groundspeed) FROM vfr_hud) AS avg_gs,
          (SELECT MIN(voltage) FROM battery) AS min_v
      ''');
      if (result.rowCount > 0) {
        final row = result.rows.first;
        _totalRows = (row[0] as num?)?.toInt() ?? 0;
        _maxAlt = (row[1] as num?)?.toDouble() ?? 0;
        _maxSpeed = (row[2] as num?)?.toDouble() ?? 0;
        _avgGroundspeed = (row[3] as num?)?.toDouble() ?? 0;
        _minVoltage = (row[4] as num?)?.toDouble() ?? 0;
      }

      final timeResult = await widget.store.query(
        'SELECT MIN(ts), MAX(ts) FROM gps'
      );
      if (timeResult.rowCount > 0 && timeResult.rows.first[0] != null) {
        final start = _parseTimestamp(timeResult.rows.first[0]);
        final end = _parseTimestamp(timeResult.rows.first[1]);
        _duration = end.difference(start);
      }
    } catch (_) {}
  }

  DateTime _parseTimestamp(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString()) ?? DateTime.now();
  }

  List<FlSpot> _toSpots(List<List<dynamic>> rows, int tsCol, int valCol, DateTime startTime) {
    final spots = <FlSpot>[];
    for (final row in rows) {
      try {
        final ts = _parseTimestamp(row[tsCol]);
        final x = ts.difference(startTime).inMilliseconds / 1000.0;
        final y = (row[valCol] as num?)?.toDouble() ?? 0;
        if (!y.isNaN && !y.isInfinite) {
          spots.add(FlSpot(x, y));
        }
      } catch (_) {}
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error', style: const TextStyle(color: HeliosColors.danger)));
    }
    if (_totalRows == 0 && _airspeed.isEmpty) {
      return const Center(
        child: Text('No telemetry data in this flight', style: TextStyle(color: HeliosColors.textTertiary)),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Summary cards
        _SummaryRow(
          duration: _duration,
          maxAlt: _maxAlt,
          maxSpeed: _maxSpeed,
          avgSpeed: _avgGroundspeed,
          minVoltage: _minVoltage,
        ),
        const SizedBox(height: 16),

        // Altitude
        if (_altitudeRel.isNotEmpty)
          _ChartCard(
            title: 'Altitude',
            chart: _buildLineChart(
              series: [
                _Series('Relative', _altitudeRel, HeliosColors.accent),
                _Series('MSL', _altitudeMsl, HeliosColors.textTertiary),
              ],
              yLabel: 'm',
            ),
          ),

        // Speed
        if (_airspeed.isNotEmpty)
          _ChartCard(
            title: 'Speed',
            chart: _buildLineChart(
              series: [
                _Series('Airspeed', _airspeed, HeliosColors.accent),
                _Series('Groundspeed', _groundspeed, HeliosColors.success),
              ],
              yLabel: 'm/s',
            ),
          ),

        // Climb Rate
        if (_climbRate.isNotEmpty)
          _ChartCard(
            title: 'Climb Rate',
            chart: _buildLineChart(
              series: [_Series('VS', _climbRate, HeliosColors.warning)],
              yLabel: 'm/s',
            ),
          ),

        // Attitude
        if (_roll.isNotEmpty)
          _ChartCard(
            title: 'Attitude',
            chart: _buildLineChart(
              series: [
                _Series('Roll', _roll, HeliosColors.accent),
                _Series('Pitch', _pitch, HeliosColors.warning),
              ],
              yLabel: 'deg',
            ),
          ),

        // Battery
        if (_voltage.isNotEmpty)
          _ChartCard(
            title: 'Battery',
            chart: _buildLineChart(
              series: [_Series('Voltage', _voltage, HeliosColors.warning)],
              yLabel: 'V',
            ),
          ),

        if (_batteryPct.isNotEmpty)
          _ChartCard(
            title: 'Battery %',
            chart: _buildLineChart(
              series: [_Series('%', _batteryPct, HeliosColors.success)],
              yLabel: '%',
            ),
          ),

        // GPS
        if (_satellites.isNotEmpty)
          _ChartCard(
            title: 'GPS Satellites',
            chart: _buildLineChart(
              series: [_Series('Sats', _satellites, HeliosColors.success)],
              yLabel: '',
            ),
          ),

        if (_hdop.isNotEmpty)
          _ChartCard(
            title: 'HDOP',
            chart: _buildLineChart(
              series: [_Series('HDOP', _hdop, HeliosColors.accent)],
              yLabel: '',
            ),
          ),

        // Vibration
        if (_vibeX.isNotEmpty)
          _ChartCard(
            title: 'Vibration',
            chart: _buildLineChart(
              series: [
                _Series('X', _vibeX, HeliosColors.danger),
                _Series('Y', _vibeY, HeliosColors.warning),
                _Series('Z', _vibeZ, HeliosColors.accent),
              ],
              yLabel: 'm/s\u00B2',
            ),
          ),
      ],
    );
  }

  Widget _buildLineChart({
    required List<_Series> series,
    required String yLabel,
  }) {
    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: null,
            getDrawingHorizontalLine: (_) => FlLine(
              color: HeliosColors.border,
              strokeWidth: 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (value, meta) {
                  if (meta.min == value || meta.max == value) return const SizedBox();
                  return Text(
                    value.toStringAsFixed(value.abs() < 10 ? 1 : 0),
                    style: const TextStyle(fontSize: 12, color: HeliosColors.textTertiary),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (value, meta) {
                  if (meta.min == value || meta.max == value) return const SizedBox();
                  final mins = (value / 60).floor();
                  final secs = (value % 60).floor();
                  return Text(
                    '$mins:${secs.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 12, color: HeliosColors.textTertiary),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(
            show: true,
            border: const Border(
              left: BorderSide(color: HeliosColors.border, width: 0.5),
              bottom: BorderSide(color: HeliosColors.border, width: 0.5),
            ),
          ),
          lineBarsData: series.map((s) {
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
                      show: true,
                      color: s.color.withValues(alpha: 0.08),
                    )
                  : BarAreaData(show: false),
            );
          }).toList(),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => HeliosColors.surface,
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
      ),
    );
  }
}

class _Series {
  _Series(this.name, this.spots, this.color);
  final String name;
  final List<FlSpot> spots;
  final Color color;
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.duration,
    required this.maxAlt,
    required this.maxSpeed,
    required this.avgSpeed,
    required this.minVoltage,
  });

  final Duration duration;
  final double maxAlt;
  final double maxSpeed;
  final double avgSpeed;
  final double minVoltage;

  @override
  Widget build(BuildContext context) {
    final mins = duration.inMinutes;
    final secs = duration.inSeconds % 60;

    return Row(
      children: [
        _SummaryCard(label: 'Duration', value: '$mins:${secs.toString().padLeft(2, '0')}', unit: 'min'),
        _SummaryCard(label: 'Max Alt', value: maxAlt.toStringAsFixed(0), unit: 'm'),
        _SummaryCard(label: 'Max IAS', value: maxSpeed.toStringAsFixed(1), unit: 'm/s'),
        _SummaryCard(label: 'Avg GS', value: avgSpeed.toStringAsFixed(1), unit: 'm/s'),
        _SummaryCard(label: 'Min Batt', value: minVoltage.toStringAsFixed(1), unit: 'V'),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            children: [
              Text(label, style: HeliosTypography.caption),
              const SizedBox(height: 2),
              Text(value, style: HeliosTypography.telemetryMedium),
              Text(unit, style: const TextStyle(fontSize: 12, color: HeliosColors.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.chart});

  final String title;
  final Widget chart;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: HeliosTypography.heading2.copyWith(fontSize: 14)),
            const SizedBox(height: 8),
            chart,
          ],
        ),
      ),
    );
  }
}
