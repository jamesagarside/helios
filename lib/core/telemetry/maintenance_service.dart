import 'forensics_service.dart';
import 'telemetry_store.dart';

/// Severity of a maintenance alert.
enum MaintenanceSeverity {
  info,
  warning,
  critical;

  /// Human-readable label.
  String get label => switch (this) {
        MaintenanceSeverity.info => 'Info',
        MaintenanceSeverity.warning => 'Warning',
        MaintenanceSeverity.critical => 'Critical',
      };
}

/// A single maintenance recommendation derived from cross-flight statistics.
class MaintenanceAlert {
  const MaintenanceAlert({
    required this.severity,
    required this.category,
    required this.title,
    required this.detail,
  });

  final MaintenanceSeverity severity;
  final String category;
  final String title;
  final String detail;
}

/// Analyses historical flight statistics to detect maintenance concerns.
///
/// Uses the same DuckDB ATTACH approach as [ForensicsService] to build a
/// `flight_stats` summary table, then applies simple statistical rules:
///
/// - **Battery voltage trend**: linear regression slope over the last 20
///   flights. A negative slope > 0.01 V/flight flags degradation.
/// - **Battery minimum capacity**: if min_bat_pct < 20% in any recent flight,
///   emit a critical alert.
/// - **Vibration z-score**: if the latest flight's avg_vibe_z is more than
///   2 standard deviations above the historical mean, warn about motor wear.
/// - **Clip events**: any clip events in the last flight suggest motor or
///   prop imbalance.
class MaintenanceService {
  final _forensics = ForensicsService();

  /// Run predictive maintenance analysis across [flights].
  ///
  /// Returns an empty list if fewer than 3 flights are available (not enough
  /// history for meaningful trends).
  Future<List<MaintenanceAlert>> analyze(List<FlightSummary> flights) async {
    if (flights.length < 3) return [];

    final recent = flights.take(20).toList();
    final alerts = <MaintenanceAlert>[];

    try {
      final result = await _forensics.query(
        recent,
        sql: '''
SELECT
  flight_id,
  start_time,
  ROUND(min_voltage, 3)     AS min_voltage,
  min_bat_pct,
  ROUND(avg_vibe_z, 4)      AS avg_vibe_z,
  ROUND(max_vibe_z, 4)      AS max_vibe_z,
  total_clips,
  ROW_NUMBER() OVER (ORDER BY start_time) AS flight_num
FROM flight_stats
ORDER BY start_time
''',
      );

      if (result.rowCount < 3) return [];

      final rows = result.rows;

      // ── Battery voltage trend (linear regression) ──────────────────────
      final voltageAlerts = _checkBatteryVoltageTrend(rows);
      alerts.addAll(voltageAlerts);

      // ── Low battery capacity ────────────────────────────────────────────
      alerts.addAll(_checkLowBatteryCapacity(rows));

      // ── Vibration z-score ───────────────────────────────────────────────
      alerts.addAll(_checkVibrationAnomaly(rows));

      // ── Clip events ─────────────────────────────────────────────────────
      alerts.addAll(_checkClipEvents(rows));
    } catch (_) {
      // Analysis is best-effort; never crash the app over it.
    }

    return alerts;
  }

  List<MaintenanceAlert> _checkBatteryVoltageTrend(
      List<Map<String, dynamic>> rows) {
    final voltages = rows
        .map((r) => _toDouble(r['min_voltage']))
        .whereType<double>()
        .toList();
    if (voltages.length < 3) return [];

    final slope = _linearRegressionSlope(voltages);
    if (slope < -0.02) {
      return [
        MaintenanceAlert(
          severity: MaintenanceSeverity.critical,
          category: 'Battery',
          title: 'Rapid battery voltage decline',
          detail:
              'Average minimum voltage is dropping ~${(-slope).toStringAsFixed(3)} V/flight '
              'over the last ${voltages.length} flights. '
              'Check battery health and consider replacement.',
        ),
      ];
    }
    if (slope < -0.005) {
      return [
        MaintenanceAlert(
          severity: MaintenanceSeverity.warning,
          category: 'Battery',
          title: 'Battery voltage declining',
          detail:
              'Minimum voltage shows a downward trend (~${(-slope).toStringAsFixed(3)} V/flight). '
              'Monitor closely over the next few flights.',
        ),
      ];
    }
    return [];
  }

  List<MaintenanceAlert> _checkLowBatteryCapacity(
      List<Map<String, dynamic>> rows) {
    // Check the most recent 3 flights for critically low min capacity
    final recent = rows.reversed.take(3).toList();
    final lowFlights = recent.where((r) {
      final pct = _toDouble(r['min_bat_pct']);
      return pct != null && pct < 20;
    }).length;

    if (lowFlights >= 2) {
      return [
        MaintenanceAlert(
          severity: MaintenanceSeverity.critical,
          category: 'Battery',
          title: 'Battery deeply discharged in recent flights',
          detail:
              '$lowFlights of the last 3 flights reached below 20% battery capacity. '
              'Deep discharge damages cells. Land earlier and check battery health.',
        ),
      ];
    }
    if (lowFlights == 1) {
      return [
        MaintenanceAlert(
          severity: MaintenanceSeverity.warning,
          category: 'Battery',
          title: 'Battery reached low capacity',
          detail:
              'A recent flight reached below 20% battery capacity. '
              'Consider increasing your land-now threshold.',
        ),
      ];
    }
    return [];
  }

  List<MaintenanceAlert> _checkVibrationAnomaly(
      List<Map<String, dynamic>> rows) {
    final vibes = rows
        .map((r) => _toDouble(r['avg_vibe_z']))
        .whereType<double>()
        .toList();
    if (vibes.length < 3) return [];

    final mean = vibes.reduce((a, b) => a + b) / vibes.length;
    final variance =
        vibes.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            vibes.length;
    final stdDev = variance > 0 ? _sqrt(variance) : 0.0;

    if (stdDev == 0) return [];

    final latest = vibes.last;
    final zScore = (latest - mean) / stdDev;

    if (zScore > 3.0) {
      return [
        MaintenanceAlert(
          severity: MaintenanceSeverity.critical,
          category: 'Vibration',
          title: 'Severe vibration anomaly detected',
          detail:
              'Latest flight Z-axis vibration is ${zScore.toStringAsFixed(1)}σ above '
              'historical average (${latest.toStringAsFixed(3)} vs avg ${mean.toStringAsFixed(3)}). '
              'Inspect propellers and motor mounts immediately.',
        ),
      ];
    }
    if (zScore > 2.0) {
      return [
        MaintenanceAlert(
          severity: MaintenanceSeverity.warning,
          category: 'Vibration',
          title: 'Elevated Z-axis vibration',
          detail:
              'Latest flight Z-axis vibration is ${zScore.toStringAsFixed(1)}σ above average. '
              'Check for loose propellers or worn motor bearings.',
        ),
      ];
    }

    // Also flag a rising trend even without outlier
    if (vibes.length >= 5) {
      final trend = _linearRegressionSlope(vibes);
      if (trend > 0.001) {
        return [
          MaintenanceAlert(
            severity: MaintenanceSeverity.info,
            category: 'Vibration',
            title: 'Vibration trend increasing',
            detail:
                'Z-axis vibration has been rising gradually over recent flights. '
                'Monitor for motor wear or prop imbalance.',
          ),
        ];
      }
    }
    return [];
  }

  List<MaintenanceAlert> _checkClipEvents(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return [];
    final latestClips = _toDouble(rows.last['total_clips'])?.toInt() ?? 0;
    if (latestClips > 0) {
      return [
        MaintenanceAlert(
          severity: latestClips > 10
              ? MaintenanceSeverity.critical
              : MaintenanceSeverity.warning,
          category: 'Vibration',
          title: 'Accelerometer clip events in last flight',
          detail:
              '$latestClips clip event${latestClips == 1 ? '' : 's'} recorded. '
              'Clips indicate vibration exceeding sensor range — '
              'inspect propellers and motor mounts.',
        ),
      ];
    }
    return [];
  }

  /// Computes the slope of a linear regression on a list of y-values
  /// (x is implicitly 0, 1, 2, ...).
  static double _linearRegressionSlope(List<double> y) {
    final n = y.length;
    if (n < 2) return 0;
    final xMean = (n - 1) / 2.0;
    final yMean = y.reduce((a, b) => a + b) / n;
    double num = 0, den = 0;
    for (var i = 0; i < n; i++) {
      num += (i - xMean) * (y[i] - yMean);
      den += (i - xMean) * (i - xMean);
    }
    return den == 0 ? 0 : num / den;
  }

  /// Newton–Raphson square root (avoids dart:math import).
  static double _sqrt(double x) {
    if (x <= 0) return 0;
    var r = x;
    for (var i = 0; i < 20; i++) {
      r = (r + x / r) / 2;
    }
    return r;
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
