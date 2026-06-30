import '../database/database.dart';
import 'columns.dart';
import 'flight_stats.dart';
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
ORDER BY start_time DESC NULLS LAST
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
    min_voltage - LAG(min_voltage) OVER (ORDER BY start_time NULLS LAST),
    3
  ) AS voltage_delta
FROM flight_stats
WHERE start_time IS NOT NULL
ORDER BY start_time NULLS LAST
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
  STRFTIME('%Y-%W', start_time::TIMESTAMP) AS week,
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

/// Service for cross-flight analytics.
///
/// On native (DuckDB): uses ATTACH to open each flight file as a separate
/// database and runs cross-flight queries against a unified view.
///
/// On web: queries each flight individually and aggregates in Dart.
/// This provides the same results without requiring ATTACH support.
class ForensicsService {
  /// Creates a forensics service.
  ///
  /// [factory] defaults to the platform [databaseFactory]; tests inject an
  /// in-memory fake so cross-flight queries run without a live DuckDB.
  ForensicsService({HeliosDatabaseFactory? factory})
      : _factory = factory ?? databaseFactory;

  final HeliosDatabaseFactory _factory;

  /// Run a [ForensicsTemplate] or custom SQL query across [flights].
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

    _factory.ensureInitialised();

    if (_factory.capabilities.supportsAttach) {
      return _queryWithAttach(flights, sql: sql);
    } else {
      return _queryWithAggregation(flights, sql: sql);
    }
  }

  /// DuckDB path: ATTACH each flight file for direct cross-file SQL.
  Future<ForensicsResult> _queryWithAttach(
    List<FlightSummary> flights, {
    required String sql,
  }) async {
    final sw = Stopwatch()..start();
    final conn = _factory.openMemory();

    try {
      conn.execute(FlightStats.createTable(temp: true));

      for (var i = 0; i < flights.length; i++) {
        final flight = flights[i];
        final alias = 'f$i';
        final escaped = flight.filePath.replaceAll("'", "''");

        try {
          conn.execute("ATTACH '$escaped' AS $alias (READ_ONLY)");

          final (flightId, startTime) = _resolveMeta(
            () => conn.fetch(
              'SELECT ${FlightMetaColumns.key}, ${FlightMetaColumns.value} '
              'FROM $alias.${FlightMetaColumns.table} '
              'WHERE ${FlightMetaColumns.key} IN '
              "('flight_id', 'start_time_utc', 'user_name')",
            ),
            flight,
          );

          final stats = conn.fetch('''
            SELECT
              (SELECT MAX(${GpsColumns.altRel}) FROM $alias.${GpsColumns.table})              AS max_alt,
              (SELECT MAX(${VfrHudColumns.airspeed}) FROM $alias.${VfrHudColumns.table})       AS max_ias,
              (SELECT AVG(${VfrHudColumns.groundspeed}) FROM $alias.${VfrHudColumns.table})    AS avg_gs,
              (SELECT MIN(${BatteryColumns.voltage}) FROM $alias.${BatteryColumns.table})      AS min_v,
              (SELECT MIN(${BatteryColumns.remainingPct}) FROM $alias.${BatteryColumns.table}) AS min_bat,
              (SELECT AVG(${VibrationColumns.vibeX}) FROM $alias.${VibrationColumns.table})     AS avg_vx,
              (SELECT AVG(${VibrationColumns.vibeY}) FROM $alias.${VibrationColumns.table})     AS avg_vy,
              (SELECT AVG(${VibrationColumns.vibeZ}) FROM $alias.${VibrationColumns.table})     AS avg_vz,
              (SELECT MAX(${VibrationColumns.vibeZ}) FROM $alias.${VibrationColumns.table})     AS max_vz,
              (SELECT COALESCE(SUM(${VibrationColumns.clip0}+${VibrationColumns.clip1}+${VibrationColumns.clip2}),0)
                 FROM $alias.${VibrationColumns.table})                                         AS clips
          ''');

          double durationMin = 0;
          try {
            final dr = conn.fetch(
              'SELECT EXTRACT(EPOCH FROM '
              '(SELECT MAX(${GpsColumns.ts}) - MIN(${GpsColumns.ts}) '
              'FROM $alias.${GpsColumns.table})) AS sec',
            );
            final sec = dr['sec']?.firstOrNull;
            if (sec is num) durationMin = sec.toDouble() / 60.0;
          } catch (_) {}

          num? n(String col) => _colFirst(stats, col) as num?;
          final row = FlightStats(
            flightId: flightId,
            startTime: startTime,
            durationMin: durationMin,
            maxAltM: n('max_alt')?.toDouble(),
            maxIasMs: n('max_ias')?.toDouble(),
            avgGsMs: n('avg_gs')?.toDouble(),
            minVoltage: n('min_v')?.toDouble(),
            minBatPct: n('min_bat')?.toInt(),
            avgVibeX: n('avg_vx')?.toDouble(),
            avgVibeY: n('avg_vy')?.toDouble(),
            avgVibeZ: n('avg_vz')?.toDouble(),
            maxVibeZ: n('max_vz')?.toDouble(),
            totalClips: n('clips')?.toInt() ?? 0,
          );
          conn.execute(row.toInsert());
        } catch (_) {
          // Skip flights that fail (corrupt / missing tables)
        } finally {
          try {
            conn.execute('DETACH $alias');
          } catch (_) {}
        }
      }

      final result = conn.fetch(sql);
      sw.stop();

      return _toForensicsResult(result, sw.elapsed);
    } catch (e) {
      conn.close();
      rethrow;
    } finally {
      conn.close();
    }
  }

  /// Web fallback: open each flight individually, aggregate stats in Dart,
  /// then create an in-memory table and run the query.
  Future<ForensicsResult> _queryWithAggregation(
    List<FlightSummary> flights, {
    required String sql,
  }) async {
    final sw = Stopwatch()..start();
    final conn = _factory.openMemory();

    try {
      conn.execute(FlightStats.createTable());

      // Open each flight individually and extract stats
      for (final flight in flights) {
        HeliosDatabase? flightConn;
        try {
          flightConn = _factory.open(flight.filePath);

          final (flightId, startTime) = _resolveMeta(
            () => flightConn!.fetch(
              'SELECT ${FlightMetaColumns.key}, ${FlightMetaColumns.value} '
              'FROM ${FlightMetaColumns.table} '
              'WHERE ${FlightMetaColumns.key} IN '
              "('flight_id', 'start_time_utc', 'user_name')",
            ),
            flight,
          );

          final stats = FlightStats.fromDatabase(
            flightConn,
            flightId: flightId,
            startTime: startTime,
          );

          flightConn.close();
          flightConn = null;

          conn.execute(stats.toInsert());
        } catch (_) {
          // Skip corrupt flights
        } finally {
          flightConn?.close();
        }
      }

      final result = conn.fetch(sql);
      sw.stop();

      return _toForensicsResult(result, sw.elapsed);
    } catch (e) {
      conn.close();
      rethrow;
    } finally {
      conn.close();
    }
  }

  /// Run a pre-built template query.
  Future<ForensicsResult> runTemplate(
    List<FlightSummary> flights,
    ForensicsTemplate template,
  ) =>
      query(flights, sql: template.sql.trim());

  ForensicsResult _toForensicsResult(
    Map<String, List<dynamic>> result,
    Duration executionTime,
  ) {
    final columnNames = result.keys.toList();
    final rowCount =
        columnNames.isEmpty ? 0 : result[columnNames.first]?.length ?? 0;

    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < rowCount; i++) {
      final row = <String, dynamic>{};
      for (final col in columnNames) {
        row[col] = result[col]?[i];
      }
      rows.add(row);
    }

    return ForensicsResult(
      columnNames: columnNames,
      rows: rows,
      executionTime: executionTime,
    );
  }

  static dynamic _colFirst(Map<String, List<dynamic>> result, String col) {
    return result[col]?.firstOrNull;
  }

  /// Resolve a flight's display id and start time from its `flight_meta`
  /// key/value rows. Prefers `user_name`, then `flight_id`, falling back to the
  /// file name (sans `.duckdb`). Shared by both the ATTACH and aggregation
  /// paths so the resolution rule lives in one place.
  static (String flightId, String startTime) _resolveMeta(
    Map<String, List<dynamic>> Function() fetchMeta,
    FlightSummary flight,
  ) {
    final fallback = flight.fileName.replaceAll('.duckdb', '');
    var flightId = fallback;
    var startTime = '';
    try {
      final meta = fetchMeta();
      final keys = meta[FlightMetaColumns.key] ?? [];
      final vals = meta[FlightMetaColumns.value] ?? [];
      final metaMap = <String, String>{};
      for (var i = 0; i < keys.length; i++) {
        metaMap[keys[i].toString()] = vals[i].toString();
      }
      flightId = metaMap['user_name'] ?? metaMap['flight_id'] ?? fallback;
      startTime = metaMap['start_time_utc'] ?? '';
    } catch (_) {}
    return (flightId, startTime);
  }
}
