import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/telemetry/telemetry_store.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';
import 'replay_map.dart';
import 'synced_line_chart.dart';
import 'timeline_bar.dart';

/// Pre-built visual analytics dashboard with synchronised crosshair, timeline
/// scrub bar, and scroll-to-zoom.
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

  // Synchronised crosshair & zoom state
  final _crosshairX = ValueNotifier<double?>(null);
  final _viewMinX = ValueNotifier<double>(0);
  final _viewMaxX = ValueNotifier<double>(1);
  double _totalDuration = 1;

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

  // Events detected from flight data
  List<ChartEvent> _events = [];

  // Whether the loaded flight used MSP (vs MAVLink)
  bool _isMspFlight = false;

  // Summary stats
  double _maxAlt = 0;
  double _maxSpeed = 0;
  double _minVoltage = 0;
  double _avgGroundspeed = 0;
  int _totalRows = 0;
  Duration _duration = Duration.zero;

  // Map visibility
  bool _showMap = true;

  // Chart manager panel visibility
  bool _showChartManager = false;

  // Chart visibility & order
  late List<_ChartDef> _chartDefs;

  // Hidden chart IDs (user can toggle)
  final Set<String> _hiddenCharts = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    if (widget.liveMode) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) _loadData();
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _crosshairX.dispose();
    _viewMinX.dispose();
    _viewMaxX.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Future.wait([
        _loadAltitudeSpeed(),
        _loadBattery(),
        _loadGps(),
        _loadVibration(),
        _loadAttitude(),
        _loadSummary(),
        _loadEvents(),
      ]);

      // Set total duration and initial zoom to full extent
      if (_duration.inSeconds > 0) {
        _totalDuration = _duration.inSeconds.toDouble();
        _viewMinX.value = 0;
        _viewMaxX.value = _totalDuration;
      }

      _buildChartDefs();
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadAltitudeSpeed() async {
    // Try MAVLink first, fall back to MSP tables
    final mavResult = await widget.store
        .query('SELECT ts, airspeed, groundspeed, climb FROM vfr_hud ORDER BY ts');
    if (mavResult.rowCount > 0) {
      final startTime = _parseTimestamp(mavResult.rows.first[0]);
      _airspeed = _toSpots(mavResult.rows, 0, 1, startTime);
      _groundspeed = _toSpots(mavResult.rows, 0, 2, startTime);
      _climbRate = _toSpots(mavResult.rows, 0, 3, startTime);

      final altResult = await widget.store
          .query('SELECT ts, alt_rel, alt_msl FROM gps ORDER BY ts');
      if (altResult.rowCount > 0) {
        _altitudeRel = _toSpots(altResult.rows, 0, 1, startTime);
        _altitudeMsl = _toSpots(altResult.rows, 0, 2, startTime);
      }
      return;
    }

    // MSP fallback
    final mspGps = await widget.store
        .query('SELECT ts, speed_ms, altitude_m FROM msp_gps ORDER BY ts');
    final mspAlt = await widget.store
        .query('SELECT ts, altitude_rel_m, climb_ms FROM msp_altitude ORDER BY ts');
    if (mspGps.rowCount == 0 && mspAlt.rowCount == 0) return;

    final startTime = mspGps.rowCount > 0
        ? _parseTimestamp(mspGps.rows.first[0])
        : _parseTimestamp(mspAlt.rows.first[0]);
    if (mspGps.rowCount > 0) {
      _groundspeed = _toSpots(mspGps.rows, 0, 1, startTime);
      _altitudeMsl = _toSpots(mspGps.rows, 0, 2, startTime);
    }
    if (mspAlt.rowCount > 0) {
      _altitudeRel = _toSpots(mspAlt.rows, 0, 1, startTime);
      _climbRate = _toSpots(mspAlt.rows, 0, 2, startTime);
    }
  }

  Future<void> _loadBattery() async {
    // Try MAVLink first, fall back to MSP tables
    final result = await widget.store
        .query('SELECT ts, voltage, remaining_pct FROM battery ORDER BY ts');
    if (result.rowCount > 0) {
      final startTime = _parseTimestamp(result.rows.first[0]);
      _voltage = _toSpots(result.rows, 0, 1, startTime);
      _batteryPct = _toSpots(result.rows, 0, 2, startTime);
      return;
    }

    // MSP fallback
    final mspResult = await widget.store
        .query('SELECT ts, voltage_v, remaining_pct FROM msp_analog ORDER BY ts');
    if (mspResult.rowCount == 0) return;
    final startTime = _parseTimestamp(mspResult.rows.first[0]);
    _voltage = _toSpots(mspResult.rows, 0, 1, startTime);
    _batteryPct = _toSpots(mspResult.rows, 0, 2, startTime);
  }

  Future<void> _loadGps() async {
    // Try MAVLink first, fall back to MSP tables
    final result = await widget.store
        .query('SELECT ts, satellites, hdop FROM gps ORDER BY ts');
    if (result.rowCount > 0) {
      final startTime = _parseTimestamp(result.rows.first[0]);
      _satellites = _toSpots(result.rows, 0, 1, startTime);
      _hdop = _toSpots(result.rows, 0, 2, startTime);
      return;
    }

    // MSP fallback (no hdop available from MSP)
    final mspResult = await widget.store
        .query('SELECT ts, num_sat FROM msp_gps ORDER BY ts');
    if (mspResult.rowCount == 0) return;
    final startTime = _parseTimestamp(mspResult.rows.first[0]);
    _satellites = _toSpots(mspResult.rows, 0, 1, startTime);
  }

  Future<void> _loadVibration() async {
    // Vibration data is MAVLink-only; MSP has no equivalent
    final result = await widget.store
        .query('SELECT ts, vibe_x, vibe_y, vibe_z FROM vibration ORDER BY ts');
    if (result.rowCount == 0) return;
    final startTime = _parseTimestamp(result.rows.first[0]);
    _vibeX = _toSpots(result.rows, 0, 1, startTime);
    _vibeY = _toSpots(result.rows, 0, 2, startTime);
    _vibeZ = _toSpots(result.rows, 0, 3, startTime);
  }

  Future<void> _loadAttitude() async {
    // Try MAVLink first (radians → degrees), fall back to MSP (already degrees)
    final result = await widget.store.query(
      'SELECT ts, roll * 57.2958 AS roll_deg, pitch * 57.2958 AS pitch_deg '
      'FROM attitude WHERE rowid % 10 = 0 ORDER BY ts',
    );
    if (result.rowCount > 0) {
      final startTime = _parseTimestamp(result.rows.first[0]);
      _roll = _toSpots(result.rows, 0, 1, startTime);
      _pitch = _toSpots(result.rows, 0, 2, startTime);
      return;
    }

    // MSP fallback (already in degrees)
    final mspResult = await widget.store.query(
      'SELECT ts, roll, pitch FROM msp_attitude WHERE rowid % 10 = 0 ORDER BY ts',
    );
    if (mspResult.rowCount == 0) return;
    final startTime = _parseTimestamp(mspResult.rows.first[0]);
    _roll = _toSpots(mspResult.rows, 0, 1, startTime);
    _pitch = _toSpots(mspResult.rows, 0, 2, startTime);
  }

  Future<void> _loadSummary() async {
    try {
      // Read the protocol recorded at flight creation — definitive, not inferred.
      final metaResult = await widget.store.query(
        "SELECT value FROM flight_meta WHERE key = 'protocol'",
      );
      final protocol = metaResult.rowCount > 0
          ? metaResult.rows.first[0].toString()
          : 'mavlink';
      _isMspFlight = protocol == 'msp';

      if (!_isMspFlight) {
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

        final timeResult =
            await widget.store.query('SELECT MIN(ts), MAX(ts) FROM gps');
        if (timeResult.rowCount > 0 && timeResult.rows.first[0] != null) {
          final start = _parseTimestamp(timeResult.rows.first[0]);
          final end = _parseTimestamp(timeResult.rows.first[1]);
          _duration = end.difference(start);
        }
      } else {
        // MSP: stats from MSP tables.
        final result = await widget.store.query('''
          SELECT
            (SELECT COUNT(*) FROM msp_gps) AS gps_rows,
            (SELECT MAX(altitude_rel_m) FROM msp_altitude) AS max_alt,
            (SELECT MAX(speed_ms) FROM msp_gps) AS max_gs,
            (SELECT AVG(speed_ms) FROM msp_gps) AS avg_gs,
            (SELECT MIN(voltage_v) FROM msp_analog) AS min_v
        ''');
        if (result.rowCount > 0) {
          final row = result.rows.first;
          _totalRows = (row[0] as num?)?.toInt() ?? 0;
          _maxAlt = (row[1] as num?)?.toDouble() ?? 0;
          _maxSpeed = (row[2] as num?)?.toDouble() ?? 0;
          _avgGroundspeed = (row[3] as num?)?.toDouble() ?? 0;
          _minVoltage = (row[4] as num?)?.toDouble() ?? 0;
        }

        // Duration: prefer msp_gps timestamps; fall back to msp_attitude
        // so duration is correct even when GPS has no fix.
        for (final table in ['msp_gps', 'msp_altitude', 'msp_attitude']) {
          final tr = await widget.store
              .query('SELECT MIN(ts), MAX(ts) FROM $table');
          if (tr.rowCount > 0 && tr.rows.first[0] != null) {
            final start = _parseTimestamp(tr.rows.first[0]);
            final end = _parseTimestamp(tr.rows.first[1]);
            _duration = end.difference(start);
            break;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadEvents() async {
    final detected = <ChartEvent>[];
    try {
      // Use the authoritative protocol from flight_meta (same as _loadSummary).
      final metaResult = await widget.store.query(
        "SELECT value FROM flight_meta WHERE key = 'protocol'",
      );
      final isMsp = metaResult.rowCount > 0 &&
          metaResult.rows.first[0].toString() == 'msp';

      // Auto-detect takeoff and set start reference
      DateTime? flightStart;
      DateTime start;

      if (!isMsp) {
        final takeoff = await widget.store.query(
          'SELECT ts FROM gps WHERE alt_rel > 2 ORDER BY ts LIMIT 1',
        );
        if (takeoff.rowCount > 0) {
          flightStart = _parseTimestamp(takeoff.rows.first[0]);
        }
        final startResult = await widget.store.query('SELECT MIN(ts) FROM gps');
        if (startResult.rowCount == 0 || startResult.rows.first[0] == null) {
          _events = [];
          return;
        }
        start = _parseTimestamp(startResult.rows.first[0]);
      } else {
        // MSP: use msp_altitude for takeoff detection
        final takeoff = await widget.store.query(
          'SELECT ts FROM msp_altitude WHERE altitude_rel_m > 2 ORDER BY ts LIMIT 1',
        );
        if (takeoff.rowCount > 0) {
          flightStart = _parseTimestamp(takeoff.rows.first[0]);
        }
        final startResult =
            await widget.store.query('SELECT MIN(ts) FROM msp_gps');
        if (startResult.rowCount == 0 || startResult.rows.first[0] == null) {
          _events = [];
          return;
        }
        start = _parseTimestamp(startResult.rows.first[0]);
      }

      if (flightStart != null) {
        detected.add(ChartEvent(
          timeSeconds:
              flightStart.difference(start).inMilliseconds / 1000.0,
          label: 'Takeoff',
          color: HeliosColors.dark.accent,
        ));
      }

      // Auto-detect landing: last point where alt_rel drops below 2m after takeoff
      if (flightStart != null) {
        final landingQuery = !isMsp
            ? "SELECT ts FROM gps WHERE alt_rel < 2 AND ts > '${_ts(flightStart)}' ORDER BY ts DESC LIMIT 1"
            : "SELECT ts FROM msp_altitude WHERE altitude_rel_m < 2 AND ts > '${_ts(flightStart)}' ORDER BY ts DESC LIMIT 1";
        final landing = await widget.store.query(landingQuery);
        if (landing.rowCount > 0) {
          final landTime = _parseTimestamp(landing.rows.first[0]);
          detected.add(ChartEvent(
            timeSeconds:
                landTime.difference(start).inMilliseconds / 1000.0,
            label: 'Landing',
            color: HeliosColors.dark.warning,
          ));
        }
      }

      // Mode changes from events table
      final modeEvents = await widget.store.query(
        "SELECT ts, detail FROM events WHERE type = 'statustext' "
        "AND (detail LIKE '%mode%' OR detail LIKE '%Mode%' "
        "OR detail LIKE '%ARM%' OR detail LIKE '%DISARM%') "
        'ORDER BY ts',
      );
      for (final row in modeEvents.rows) {
        final ts = _parseTimestamp(row[0]);
        final detail = row[1].toString();
        final isArm = detail.toUpperCase().contains('ARM');
        detected.add(ChartEvent(
          timeSeconds: ts.difference(start).inMilliseconds / 1000.0,
          label: detail.length > 12 ? detail.substring(0, 12) : detail,
          color: isArm ? HeliosColors.dark.success : HeliosColors.dark.textSecondary,
        ));
      }

      // ── Z-score anomaly detection ──────────────────────────────────────────
      // For each key channel, find timestamps where the value is more than
      // 2.5 standard deviations from the flight mean. Cluster results so that
      // at most one event fires per 30-second window per channel.
      if (!isMsp) {
        final anomalyQueries = <(String, String, String)>[
          // (channel label, short label, SQL)
          (
            'vibration',
            'Vib',
            '''
            SELECT (epoch_ms(ts) - epoch_ms(MIN(ts) OVER ())) / 1000.0 AS t
            FROM (
              SELECT ts,
                (vibe_x + vibe_y + vibe_z) / 3.0 AS v,
                AVG((vibe_x + vibe_y + vibe_z) / 3.0) OVER () AS mu,
                STDDEV_SAMP((vibe_x + vibe_y + vibe_z) / 3.0) OVER () AS sd
              FROM vibration
            )
            WHERE sd > 0 AND (v - mu) / sd > 2.5
            ORDER BY t
            ''',
          ),
          (
            'voltage_drop',
            'Volt↓',
            '''
            SELECT (epoch_ms(ts) - epoch_ms(MIN(ts) OVER ())) / 1000.0 AS t
            FROM (
              SELECT ts,
                voltage AS v,
                AVG(voltage) OVER () AS mu,
                STDDEV_SAMP(voltage) OVER () AS sd
              FROM battery
            )
            WHERE sd > 0 AND (mu - v) / sd > 2.5
            ORDER BY t
            ''',
          ),
          (
            'climb_rate',
            'Climb',
            '''
            SELECT (epoch_ms(ts) - epoch_ms(MIN(ts) OVER ())) / 1000.0 AS t
            FROM (
              SELECT ts,
                ABS(climb) AS v,
                AVG(ABS(climb)) OVER () AS mu,
                STDDEV_SAMP(ABS(climb)) OVER () AS sd
              FROM vfr_hud
            )
            WHERE sd > 0 AND (v - mu) / sd > 2.5
            ORDER BY t
            ''',
          ),
          (
            'altitude_spike',
            'Alt',
            '''
            SELECT (epoch_ms(ts) - epoch_ms(MIN(ts) OVER ())) / 1000.0 AS t
            FROM (
              SELECT ts,
                alt_rel AS v,
                AVG(alt_rel) OVER () AS mu,
                STDDEV_SAMP(alt_rel) OVER () AS sd
              FROM gps
            )
            WHERE sd > 0 AND ABS((v - mu) / sd) > 2.5
            ORDER BY t
            ''',
          ),
        ];

        for (final (_, label, sql) in anomalyQueries) {
          try {
            final result = await widget.store.query(sql);
            final times = result.rows
                .map((r) => (r[0] as num).toDouble())
                .toList();
            // Cluster: emit at most one event per 30-second window
            double? lastEmitted;
            for (final t in times) {
              if (t < 0) continue;
              if (lastEmitted == null || t - lastEmitted >= 30) {
                detected.add(ChartEvent(
                  timeSeconds: t,
                  label: label,
                  color: HeliosColors.dark.warning,
                ));
                lastEmitted = t;
              }
            }
          } catch (_) {
            // Skip channels that don't exist in this flight
          }
        }
      }
    } catch (_) {
      // Events are optional — don't fail the whole load
    }

    _events = detected;
  }

  // ---------------------------------------------------------------------------
  // Zoom handler
  // ---------------------------------------------------------------------------

  void _handleZoom(double scrollDelta, double centerX) {
    final currentMin = _viewMinX.value;
    final currentMax = _viewMaxX.value;
    final currentRange = currentMax - currentMin;

    // Scroll up (negative delta) = zoom in, scroll down = zoom out
    final factor = scrollDelta > 0 ? 1.15 : 0.87;
    final newRange =
        (currentRange * factor).clamp(2.0, _totalDuration);

    // Keep centerX at the same relative position
    final centerFrac = currentRange > 0
        ? (centerX - currentMin) / currentRange
        : 0.5;
    var newMin = centerX - centerFrac * newRange;
    var newMax = newMin + newRange;

    // Clamp to total range
    if (newMin < 0) {
      newMin = 0;
      newMax = newRange.clamp(0.0, _totalDuration);
    }
    if (newMax > _totalDuration) {
      newMax = _totalDuration;
      newMin = (_totalDuration - newRange).clamp(0.0, _totalDuration);
    }

    _viewMinX.value = newMin;
    _viewMaxX.value = newMax;
  }

  // ---------------------------------------------------------------------------
  // Chart definitions
  // ---------------------------------------------------------------------------

  void _buildChartDefs() {
    _chartDefs = [
      if (_altitudeRel.isNotEmpty)
        _ChartDef(
          id: 'altitude',
          title: 'Altitude (Relative)',
          series: [
            ChartSeries('Relative', _altitudeRel, HeliosColors.dark.accent),
          ],
          yLabel: 'm',
          minY: 0,
        ),
      if (_altitudeMsl.isNotEmpty)
        _ChartDef(
          id: 'altitude_msl',
          title: 'Altitude (MSL)',
          series: [
            ChartSeries('MSL', _altitudeMsl, HeliosColors.dark.textTertiary),
          ],
          yLabel: 'm',
        ),
      // Speed: show both if MAVLink, groundspeed-only if MSP
      if (_groundspeed.isNotEmpty || _airspeed.isNotEmpty)
        _ChartDef(
          id: 'speed',
          title: 'Speed',
          series: [
            if (_airspeed.isNotEmpty)
              ChartSeries('Airspeed', _airspeed, HeliosColors.dark.accent),
            if (_groundspeed.isNotEmpty)
              ChartSeries('Groundspeed', _groundspeed, HeliosColors.dark.success),
          ],
          yLabel: 'm/s',
        ),
      // Airspeed unavailable for MSP
      if (_isMspFlight)
        _ChartDef(
          id: 'airspeed',
          title: 'Airspeed',
          series: const [],
          yLabel: '',
          unavailableReason:
              'Airspeed not available via MSP — Betaflight/iNav do not '
              'expose airspeed sensor data over MSP. Use an external '
              'pitot sensor with MAVLink for airspeed telemetry.',
        ),
      if (_climbRate.isNotEmpty)
        _ChartDef(
          id: 'climb',
          title: 'Climb Rate',
          series: [ChartSeries('VS', _climbRate, HeliosColors.dark.warning)],
          yLabel: 'm/s',
        ),
      if (_roll.isNotEmpty)
        _ChartDef(
          id: 'attitude',
          title: 'Attitude',
          series: [
            ChartSeries('Roll', _roll, HeliosColors.dark.accent),
            ChartSeries('Pitch', _pitch, HeliosColors.dark.warning),
          ],
          yLabel: 'deg',
        ),
      if (_voltage.isNotEmpty)
        _ChartDef(
          id: 'battery',
          title: 'Battery',
          series: [ChartSeries('Voltage', _voltage, HeliosColors.dark.warning)],
          yLabel: 'V',
          minY: 0,
          referenceLines: _batteryReferenceLines(),
        ),
      if (_batteryPct.isNotEmpty)
        _ChartDef(
          id: 'battery_pct',
          title: 'Battery %',
          series: [ChartSeries('%', _batteryPct, HeliosColors.dark.success)],
          yLabel: '%',
          minY: 0,
          maxY: 100,
        ),
      if (_satellites.isNotEmpty)
        _ChartDef(
          id: 'gps_sats',
          title: 'GPS Satellites',
          series: [ChartSeries('Sats', _satellites, HeliosColors.dark.success)],
          yLabel: '',
          minY: 0,
        ),
      if (_hdop.isNotEmpty)
        _ChartDef(
          id: 'hdop',
          title: 'HDOP',
          series: [ChartSeries('HDOP', _hdop, HeliosColors.dark.accent)],
          yLabel: '',
          minY: 0,
        ),
      // HDOP unavailable for MSP
      if (_isMspFlight)
        _ChartDef(
          id: 'hdop',
          title: 'HDOP',
          series: const [],
          yLabel: '',
          unavailableReason:
              'HDOP not available via MSP — MSP_RAW_GPS does not include '
              'dilution of precision fields. Switch to MAVLink for '
              'full GPS quality reporting.',
        ),
      if (_vibeX.isNotEmpty)
        _ChartDef(
          id: 'vibration',
          title: 'Vibration',
          series: [
            ChartSeries('X', _vibeX, HeliosColors.dark.danger),
            ChartSeries('Y', _vibeY, HeliosColors.dark.warning),
            ChartSeries('Z', _vibeZ, HeliosColors.dark.accent),
          ],
          yLabel: 'm/s\u00B2',
        ),
      // Vibration unavailable for MSP
      if (_isMspFlight)
        _ChartDef(
          id: 'vibration',
          title: 'Vibration',
          series: const [],
          yLabel: '',
          unavailableReason:
              'Vibration data not available via MSP — Betaflight/iNav do not '
              'stream IMU vibration metrics over MSP. Use Blackbox logging '
              'for gyro/accelerometer noise analysis.',
        ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  DateTime _parseTimestamp(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString()) ?? DateTime.now();
  }

  String _ts(DateTime dt) => dt.toIso8601String().replaceFirst('T', ' ');

  /// Auto-detect cell count from peak voltage and return labelled reference
  /// lines at standard LiPo per-cell thresholds.
  List<ChartReferenceLine> _batteryReferenceLines() {
    if (_voltage.isEmpty) return [];
    final peakV = _voltage.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    // Detect cell count: 4.2 V per cell fully charged
    final cells = (peakV / 4.2).ceil().clamp(1, 14);

    return [
      ChartReferenceLine(
        y: 4.20 * cells,
        label: 'Full (${cells}S)',
        color: HeliosColors.dark.success,
      ),
      ChartReferenceLine(
        y: 3.70 * cells,
        label: 'Nominal',
        color: HeliosColors.dark.accent,
      ),
      ChartReferenceLine(
        y: 3.50 * cells,
        label: 'Low',
        color: HeliosColors.dark.warning,
      ),
      ChartReferenceLine(
        y: 3.30 * cells,
        label: 'Critical',
        color: HeliosColors.dark.danger,
      ),
    ];
  }

  List<FlSpot> _toSpots(
      List<List<dynamic>> rows, int tsCol, int valCol, DateTime startTime) {
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text('Error: $_error',
            style: TextStyle(color: hc.danger)),
      );
    }
    // Gate: show placeholder only when truly no series has any data.
    // _totalRows counts GPS rows (MAVLink) or msp_gps rows.
    // For MSP, _airspeed is always empty and GPS may be absent (no fix),
    // so check all series rather than only GPS/airspeed.
    final hasAnyData = _totalRows > 0 ||
        _altitudeRel.isNotEmpty ||
        _altitudeMsl.isNotEmpty ||
        _airspeed.isNotEmpty ||
        _groundspeed.isNotEmpty ||
        _climbRate.isNotEmpty ||
        _roll.isNotEmpty ||
        _voltage.isNotEmpty ||
        _satellites.isNotEmpty;
    if (!hasAnyData) {
      return Center(
        child: Text('No telemetry data in this flight',
            style: TextStyle(color: hc.textTertiary)),
      );
    }

    return Column(
      children: [
        // Map replay + collapse toggle
        Container(
          height: 28,
          color: hc.surface,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _showMap = !_showMap),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showMap
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 16,
                      color: hc.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Flight Map',
                      style: HeliosTypography.caption.copyWith(
                        color: hc.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_showMap)
          ReplayMap(
            store: widget.store,
            crosshairX: _crosshairX,
          ),

        // Timeline scrub bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TimelineBar(
            crosshairX: _crosshairX,
            viewMinX: _viewMinX,
            viewMaxX: _viewMaxX,
            totalDuration: _totalDuration,
            referenceSeries: _altitudeRel.isNotEmpty
                ? _altitudeRel
                : _airspeed,
            events: _events,
            onZoom: _handleZoom,
          ),
        ),

        // Zoom reset hint
        ValueListenableBuilder(
          valueListenable: _viewMinX,
          builder: (context, minX, _) {
            final isZoomed =
                minX > 0.5 || _viewMaxX.value < _totalDuration - 0.5;
            if (!isZoomed) return const SizedBox.shrink();
            final hc = context.hc;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.zoom_in,
                      size: 12, color: hc.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    'Scroll to zoom \u2022 ',
                    style: HeliosTypography.caption
                        .copyWith(color: hc.textTertiary),
                  ),
                  GestureDetector(
                    onTap: () {
                      _viewMinX.value = 0;
                      _viewMaxX.value = _totalDuration;
                    },
                    child: Text(
                      'Reset zoom',
                      style: HeliosTypography.caption.copyWith(
                        color: hc.accent,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 4),

        // Summary cards
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _SummaryRow(
            duration: _duration,
            maxAlt: _maxAlt,
            maxSpeed: _maxSpeed,
            avgSpeed: _avgGroundspeed,
            minVoltage: _minVoltage,
            isMsp: _isMspFlight,
          ),
        ),
        const SizedBox(height: 4),

        // Chart toolbar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Text(
                '${_visibleDefs.length} of ${_chartDefs.length} charts',
                style: HeliosTypography.caption
                    .copyWith(color: hc.textTertiary),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () =>
                    setState(() => _showChartManager = !_showChartManager),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showChartManager ? Icons.close : Icons.tune,
                      size: 14,
                      color: _showChartManager
                          ? hc.accent
                          : hc.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _showChartManager ? 'Done' : 'Customise',
                      style: TextStyle(
                        fontSize: 12,
                        color: _showChartManager
                            ? hc.accent
                            : hc.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // Chart manager panel (when open)
        if (_showChartManager)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: hc.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Text('Toggle & reorder charts',
                          style: HeliosTypography.caption.copyWith(
                              color: hc.textSecondary)),
                      const Spacer(),
                      if (_hiddenCharts.isNotEmpty)
                        GestureDetector(
                          onTap: () =>
                              setState(() => _hiddenCharts.clear()),
                          child: Text('Show all',
                              style: HeliosTypography.caption.copyWith(
                                  color: hc.accent)),
                        ),
                    ],
                  ),
                ),
                Divider(
                    height: 1, color: hc.border),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    itemCount: _chartDefs.length,
                    onReorder: _onReorderChart,
                    itemBuilder: (context, index) {
                      final def = _chartDefs[index];
                      final visible =
                          !_hiddenCharts.contains(def.id);
                      return ListTile(
                        key: ValueKey(def.id),
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: Checkbox(
                          value: visible,
                          onChanged: (_) => setState(() {
                            if (visible) {
                              _hiddenCharts.add(def.id);
                            } else {
                              _hiddenCharts.remove(def.id);
                            }
                          }),
                          activeColor: hc.accent,
                          side: BorderSide(
                              color: hc.textTertiary),
                        ),
                        title: Text(def.title,
                            style: TextStyle(
                              fontSize: 13,
                              color: visible
                                  ? hc.textPrimary
                                  : hc.textTertiary,
                            )),
                        trailing: ReorderableDragStartListener(
                          index: index,
                          child: Icon(Icons.drag_handle,
                              size: 18,
                              color: hc.textTertiary),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

        // Synchronised chart cards (filtered by visibility)
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _visibleDefs.length,
            itemBuilder: (context, index) {
              final def = _visibleDefs[index];
              if (def.unavailableReason != null) {
                return _ChartCard(
                  title: def.title,
                  chart: _UnavailablePlaceholder(reason: def.unavailableReason!),
                );
              }
              return _ChartCard(
                title: def.title,
                chart: SyncedLineChart(
                  series: def.series,
                  yLabel: def.yLabel,
                  crosshairX: _crosshairX,
                  viewMinX: _viewMinX,
                  viewMaxX: _viewMaxX,
                  events: _events,
                  onZoom: _handleZoom,
                  minY: def.minY,
                  maxY: def.maxY,
                  referenceLines: def.referenceLines,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<_ChartDef> get _visibleDefs =>
      _chartDefs.where((d) => !_hiddenCharts.contains(d.id)).toList();

  void _onReorderChart(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _chartDefs.removeAt(oldIndex);
      _chartDefs.insert(newIndex, item);
    });
  }
}

// -----------------------------------------------------------------------------
// Chart definition (Phase 4 prep)
// -----------------------------------------------------------------------------

class _ChartDef {
  const _ChartDef({
    required this.id,
    required this.title,
    required this.series,
    required this.yLabel,
    this.minY,
    this.maxY,
    this.referenceLines = const [],
    this.unavailableReason,
  });

  final String id;
  final String title;
  final List<ChartSeries> series;
  final String yLabel;
  final double? minY;
  final double? maxY;
  final List<ChartReferenceLine> referenceLines;
  /// If non-null, renders a "not available" placeholder instead of a chart.
  final String? unavailableReason;
}

// -----------------------------------------------------------------------------
// Summary widgets
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Unavailable-feature placeholder
// -----------------------------------------------------------------------------

class _UnavailablePlaceholder extends StatelessWidget {
  const _UnavailablePlaceholder({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: hc.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 15, color: hc.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reason,
              style: HeliosTypography.caption.copyWith(color: hc.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.duration,
    required this.maxAlt,
    required this.maxSpeed,
    required this.avgSpeed,
    required this.minVoltage,
    this.isMsp = false,
  });

  final Duration duration;
  final double maxAlt;
  final double maxSpeed;
  final double avgSpeed;
  final double minVoltage;
  final bool isMsp;

  @override
  Widget build(BuildContext context) {
    final mins = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    // MAVLink reports airspeed from VFR_HUD; MSP only has groundspeed.
    final speedLabel = isMsp ? 'Max GS' : 'Max IAS';
    return Row(
      children: [
        _SummaryCard(
            label: 'Duration',
            value: '$mins:${secs.toString().padLeft(2, '0')}',
            unit: 'min'),
        _SummaryCard(
            label: 'Max Alt',
            value: maxAlt.toStringAsFixed(0),
            unit: 'm'),
        _SummaryCard(
            label: speedLabel,
            value: maxSpeed.toStringAsFixed(1),
            unit: 'm/s'),
        _SummaryCard(
            label: 'Avg GS',
            value: avgSpeed.toStringAsFixed(1),
            unit: 'm/s'),
        _SummaryCard(
            label: 'Min Batt',
            value: minVoltage.toStringAsFixed(1),
            unit: 'V'),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Column(
            children: [
              Text(label, style: HeliosTypography.caption),
              const SizedBox(height: 2),
              Text(value, style: HeliosTypography.telemetryMedium),
              Text(unit,
                  style: TextStyle(
                      fontSize: 12, color: hc.textTertiary)),
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
            Text(title,
                style: HeliosTypography.heading2.copyWith(fontSize: 14)),
            const SizedBox(height: 8),
            chart,
          ],
        ),
      ),
    );
  }
}
