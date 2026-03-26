import 'package:duckdb_dart/duckdb_dart.dart';
import 'telemetry_store.dart';

/// A cross-flight comparison result row.
class ForensicsRow {
  const ForensicsRow(this.values);
  final Map<String, dynamic> values;
}

/// Result of a cross-flight forensics query.
class ForensicsResult {
  ForensicsResult({
    required this.columnNames,
    required this.rows,
    required this.executionTime,
  });

  final List<String> columnNames;
  final List<Map<String, dynamic>> rows;
  final Duration executionTime;

  int get rowCount => rows.length;
}

/// Pre-built cross-flight comparison templates.
enum ForensicsTemplate {
  flightComparison(
    name: 'Flight Comparison',
    description: 'Side-by-side statistics for all selected flights',
    sql: '''
SELECT
  flight_id,
  start_time,
  duration_min,
  ROUND(max_alt_m, 1) AS max_alt_m,
  ROUND(max_ias_ms, 1) AS max_ias_ms,
  ROUND(avg_gs_ms, 1) AS avg_gs_ms,
  ROUND(min_voltage, 2) AS min_voltage_v,
  min_bat_pct
FROM flight_stats
ORDER BY start_time DESC
''',
  ),

  batteryDegradation(
    name: 'Battery Degradation',
    description: 'Minimum voltage and capacity trend across flights',
    sql: '''
SELECT
  flight_id,
  start_time,
  ROUND(min_voltage, 2) AS min_voltage_v,
  min_bat_pct,
  ROUND(
    min_voltage - LAG(min_voltage) OVER (ORDER BY start_time),
    3
  ) AS voltage_delta
FROM flight_stats
ORDER BY start_time
''',
  ),

  vibrationTrend(
    name: 'Vibration Trend',
    description: 'Average vibration levels across flights (motor wear indicator)',
    sql: '''
SELECT
  flight_id,
  start_time,
  ROUND(avg_vibe_x, 3) AS avg_vibe_x,
  ROUND(avg_vibe_y, 3) AS avg_vibe_y,
  ROUND(avg_vibe_z, 3) AS avg_vibe_z,
  ROUND(max_vibe_z, 3) AS max_vibe_z,
  total_clips
FROM flight_stats
ORDER BY start_time
''',
  ),

  altitudeRecords(
    name: 'Altitude Records',
    description: 'Highest altitude achieved per flight',
    sql: '''
SELECT
  flight_id,
  start_time,
  ROUND(max_alt_m, 1) AS max_alt_m,
  ROUND(max_ias_ms, 1) AS max_ias_ms,
  duration_min
FROM flight_stats
ORDER BY max_alt_m DESC
LIMIT 20
''',
  ),

  flightFrequency(
    name: 'Flight Frequency',
    description: 'Number of flights per week',
    sql: '''
SELECT
  STRFTIME('%Y-%W', start_time) AS week,
  COUNT(*) AS flights,
  ROUND(SUM(duration_min), 1) AS total_minutes
FROM flight_stats
WHERE start_time IS NOT NULL
GROUP BY week
ORDER BY week
''',
  );

  const ForensicsTemplate({
    required this.name,
    required this.description,
    required this.sql,
  });

  final String name;
  final String description;
  final String sql;
}

/// Service for cross-flight analytics using DuckDB's ATTACH capability.
///
/// Opens each flight file as a separate DuckDB database, extracts per-flight
/// stats into a temporary in-memory table, then runs cross-flight queries
/// against that unified view.
///
/// This is Helios's "Flight Forensics Engine" — the feature that makes it
/// possible to ask "how has my battery degraded over the last 20 flights?"
class ForensicsService {
  /// Run a [ForensicsTemplate] or custom SQL query across [flights].
  ///
  /// Internally creates an in-memory DuckDB database, attaches all flight
  /// files, aggregates per-flight stats into a `flight_stats` view, then
  /// runs the provided SQL.
  Future<ForensicsResult> query(
    List<FlightSummary> flights, {
    required String sql,
  }) async {
    if (flights.isEmpty) {
      return ForensicsResult(
        columnNames: [],
        rows: [],
        executionTime: Duration.zero,
      );
    }

    final sw = Stopwatch()..start();
    // Use an in-memory DuckDB for the combined view
    final conn = Connection(':memory:');

    try {
      // Create the flight_stats staging table
      conn.execute('''
        CREATE TEMP TABLE flight_stats (
          flight_id       VARCHAR,
          start_time      VARCHAR,
          duration_min    DOUBLE,
          max_alt_m       DOUBLE,
          max_ias_ms      DOUBLE,
          avg_gs_ms       DOUBLE,
          min_voltage     DOUBLE,
          min_bat_pct     INTEGER,
          avg_vibe_x      DOUBLE,
          avg_vibe_y      DOUBLE,
          avg_vibe_z      DOUBLE,
          max_vibe_z      DOUBLE,
          total_clips     INTEGER
        )
      ''');

      // Aggregate each flight file into one row
      for (var i = 0; i < flights.length; i++) {
        final flight = flights[i];
        final alias = 'f$i';
        final escaped = flight.filePath.replaceAll("'", "''");

        try {
          conn.execute("ATTACH '$escaped' AS $alias (READ_ONLY)");

          // Extract flight_id and start_time from metadata
          String flightId = flight.fileName.replaceAll('.duckdb', '');
          String startTime = '';
          try {
            final meta = conn.fetch(
              'SELECT key, value FROM $alias.flight_meta '
              "WHERE key IN ('flight_id', 'start_time_utc', 'user_name')",
            );
            final keys = meta['key'] as List<dynamic>? ?? [];
            final vals = meta['value'] as List<dynamic>? ?? [];
            final metaMap = <String, String>{};
            for (var j = 0; j < keys.length; j++) {
              metaMap[keys[j].toString()] = vals[j].toString();
            }
            flightId = metaMap['user_name'] ??
                metaMap['flight_id'] ??
                flightId;
            startTime = metaMap['start_time_utc'] ?? '';
          } catch (_) {}

          // Gather statistics
          final stats = conn.fetch('''
            SELECT
              (SELECT MAX(alt_rel) FROM $alias.gps)                          AS max_alt,
              (SELECT MAX(airspeed) FROM $alias.vfr_hud)                     AS max_ias,
              (SELECT AVG(groundspeed) FROM $alias.vfr_hud)                  AS avg_gs,
              (SELECT MIN(voltage) FROM $alias.battery)                      AS min_v,
              (SELECT MIN(remaining_pct) FROM $alias.battery)                AS min_bat,
              (SELECT AVG(vibe_x) FROM $alias.vibration)                     AS avg_vx,
              (SELECT AVG(vibe_y) FROM $alias.vibration)                     AS avg_vy,
              (SELECT AVG(vibe_z) FROM $alias.vibration)                     AS avg_vz,
              (SELECT MAX(vibe_z) FROM $alias.vibration)                     AS max_vz,
              (SELECT COALESCE(SUM(clip_0+clip_1+clip_2),0) FROM $alias.vibration) AS clips
          ''');

          double durationMin = 0;
          try {
            // Extract duration as seconds
            final dr = conn.fetch(
              'SELECT EXTRACT(EPOCH FROM '
              '(SELECT MAX(ts) - MIN(ts) FROM $alias.gps)) AS sec',
            );
            final sec = (dr['sec'] as List<dynamic>?)?.firstOrNull;
            if (sec is num) durationMin = sec.toDouble() / 60.0;
          } catch (_) {}

          final flightIdEsc = flightId.replaceAll("'", "''");
          final startTimeEsc = startTime.replaceAll("'", "''");

          num? n(String col) => colFirst(stats, col) as num?;
          conn.execute('''
            INSERT INTO flight_stats VALUES (
              '$flightIdEsc',
              '$startTimeEsc',
              $durationMin,
              ${n('max_alt')?.toDouble() ?? 'NULL'},
              ${n('max_ias')?.toDouble() ?? 'NULL'},
              ${n('avg_gs')?.toDouble() ?? 'NULL'},
              ${n('min_v')?.toDouble() ?? 'NULL'},
              ${n('min_bat')?.toInt() ?? 'NULL'},
              ${n('avg_vx')?.toDouble() ?? 'NULL'},
              ${n('avg_vy')?.toDouble() ?? 'NULL'},
              ${n('avg_vz')?.toDouble() ?? 'NULL'},
              ${n('max_vz')?.toDouble() ?? 'NULL'},
              ${n('clips')?.toInt() ?? 0}
            )
          ''');
        } catch (_) {
          // Skip flights that fail (corrupt / missing tables)
        } finally {
          try {
            conn.execute('DETACH $alias');
          } catch (_) {}
        }
      }

      // Run the user query
      final result = conn.fetch(sql);
      sw.stop();

      final columnNames = result.keys.toList();
      final rowCount =
          columnNames.isEmpty ? 0 : (result[columnNames.first] as List?)?.length ?? 0;

      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < rowCount; i++) {
        final row = <String, dynamic>{};
        for (final col in columnNames) {
          row[col] = (result[col] as List?)?[i];
        }
        rows.add(row);
      }

      conn.close();
      return ForensicsResult(
        columnNames: columnNames,
        rows: rows,
        executionTime: sw.elapsed,
      );
    } catch (e) {
      conn.close();
      rethrow;
    }
  }

  /// Run a pre-built template query.
  Future<ForensicsResult> runTemplate(
    List<FlightSummary> flights,
    ForensicsTemplate template,
  ) =>
      query(flights, sql: template.sql.trim());

  /// Helper to get first value from a DuckDB fetch column.
  static dynamic colFirst(Map<String, List<dynamic>> result, String col) {
    return result[col]?.firstOrNull;
  }
}
