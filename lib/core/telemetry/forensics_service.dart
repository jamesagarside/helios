import '../database/database.dart';
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

    databaseFactory.ensureInitialised();

    if (databaseFactory.capabilities.supportsAttach) {
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
    final conn = databaseFactory.openMemory();

    try {
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

      for (var i = 0; i < flights.length; i++) {
        final flight = flights[i];
        final alias = 'f$i';
        final escaped = flight.filePath.replaceAll("'", "''");

        try {
          conn.execute("ATTACH '$escaped' AS $alias (READ_ONLY)");

          String flightId = flight.fileName.replaceAll('.duckdb', '');
          String startTime = '';
          try {
            final meta = conn.fetch(
              'SELECT key, value FROM $alias.flight_meta '
              "WHERE key IN ('flight_id', 'start_time_utc', 'user_name')",
            );
            final keys = meta['key'] ?? [];
            final vals = meta['value'] ?? [];
            final metaMap = <String, String>{};
            for (var j = 0; j < keys.length; j++) {
              metaMap[keys[j].toString()] = vals[j].toString();
            }
            flightId = metaMap['user_name'] ??
                metaMap['flight_id'] ??
                flightId;
            startTime = metaMap['start_time_utc'] ?? '';
          } catch (_) {}

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
            final dr = conn.fetch(
              'SELECT EXTRACT(EPOCH FROM '
              '(SELECT MAX(ts) - MIN(ts) FROM $alias.gps)) AS sec',
            );
            final sec = dr['sec']?.firstOrNull;
            if (sec is num) durationMin = sec.toDouble() / 60.0;
          } catch (_) {}

          final flightIdEsc = flightId.replaceAll("'", "''");
          final startTimeSql = startTime.isEmpty
              ? 'NULL'
              : "'${startTime.replaceAll("'", "''")}'";

          num? n(String col) => _colFirst(stats, col) as num?;
          conn.execute('''
            INSERT INTO flight_stats VALUES (
              '$flightIdEsc',
              $startTimeSql,
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
    final conn = databaseFactory.openMemory();

    try {
      conn.execute('''
        CREATE TABLE flight_stats (
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

      // Open each flight individually and extract stats
      for (final flight in flights) {
        HeliosDatabase? flightConn;
        try {
          flightConn = databaseFactory.open(flight.filePath);

          String flightId = flight.fileName.replaceAll('.duckdb', '');
          String startTime = '';

          try {
            final meta = flightConn.fetch(
              "SELECT key, value FROM flight_meta WHERE key IN "
              "('flight_id', 'start_time_utc', 'user_name')",
            );
            final keys = meta['key'] ?? [];
            final vals = meta['value'] ?? [];
            for (var i = 0; i < keys.length; i++) {
              final k = keys[i].toString();
              final v = vals[i].toString();
              if (k == 'user_name') flightId = v;
              else if (k == 'flight_id' && flightId == flight.fileName.replaceAll('.duckdb', '')) flightId = v;
              if (k == 'start_time_utc') startTime = v;
            }
          } catch (_) {}

          // Gather per-table stats
          double? maxAlt, maxIas, avgGs, minV, avgVx, avgVy, avgVz, maxVz;
          int? minBat, totalClips;
          double durationMin = 0;

          try {
            final gps = flightConn.fetch('SELECT MAX(alt_rel) AS v, MIN(ts) AS t0, MAX(ts) AS t1 FROM gps');
            maxAlt = (_colFirst(gps, 'v') as num?)?.toDouble();
            final t0 = _colFirst(gps, 't0');
            final t1 = _colFirst(gps, 't1');
            if (t0 != null && t1 != null) {
              final d0 = DateTime.tryParse(t0.toString());
              final d1 = DateTime.tryParse(t1.toString());
              if (d0 != null && d1 != null) {
                durationMin = d1.difference(d0).inSeconds / 60.0;
              }
            }
          } catch (_) {}

          try {
            final vfr = flightConn.fetch('SELECT MAX(airspeed) AS mi, AVG(groundspeed) AS ag FROM vfr_hud');
            maxIas = (_colFirst(vfr, 'mi') as num?)?.toDouble();
            avgGs = (_colFirst(vfr, 'ag') as num?)?.toDouble();
          } catch (_) {}

          try {
            final bat = flightConn.fetch('SELECT MIN(voltage) AS mv, MIN(remaining_pct) AS mb FROM battery');
            minV = (_colFirst(bat, 'mv') as num?)?.toDouble();
            minBat = (_colFirst(bat, 'mb') as num?)?.toInt();
          } catch (_) {}

          try {
            final vib = flightConn.fetch(
              'SELECT AVG(vibe_x) AS ax, AVG(vibe_y) AS ay, AVG(vibe_z) AS az, '
              'MAX(vibe_z) AS mz, SUM(clip_0+clip_1+clip_2) AS tc FROM vibration',
            );
            avgVx = (_colFirst(vib, 'ax') as num?)?.toDouble();
            avgVy = (_colFirst(vib, 'ay') as num?)?.toDouble();
            avgVz = (_colFirst(vib, 'az') as num?)?.toDouble();
            maxVz = (_colFirst(vib, 'mz') as num?)?.toDouble();
            totalClips = (_colFirst(vib, 'tc') as num?)?.toInt();
          } catch (_) {}

          flightConn.close();
          flightConn = null;

          final flightIdEsc = flightId.replaceAll("'", "''");
          final startTimeSql = startTime.isEmpty ? 'NULL' : "'${startTime.replaceAll("'", "''")}'";

          conn.execute('''
            INSERT INTO flight_stats VALUES (
              '$flightIdEsc', $startTimeSql, $durationMin,
              ${maxAlt ?? 'NULL'}, ${maxIas ?? 'NULL'}, ${avgGs ?? 'NULL'},
              ${minV ?? 'NULL'}, ${minBat ?? 'NULL'},
              ${avgVx ?? 'NULL'}, ${avgVy ?? 'NULL'}, ${avgVz ?? 'NULL'},
              ${maxVz ?? 'NULL'}, ${totalClips ?? 0}
            )
          ''');
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
}
