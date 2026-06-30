import '../database/database.dart';
import 'columns.dart';

/// Per-flight summary statistics shared across the cross-flight analytics
/// modules (forensics, predictive maintenance).
///
/// Before this type existed, the `flight_stats` table shape and the per-flight
/// aggregation SQL were re-stated in three places (the DuckDB ATTACH path and
/// the web aggregation path in `ForensicsService`, plus implicitly in
/// `MaintenanceService`). They are now defined once here: [columns] is the
/// single CREATE-TABLE / INSERT column order, [createTable] builds the table,
/// and [fromDatabase] derives the stats for one open flight database — so the
/// per-table column names come from `columns.dart` and never drift.
class FlightStats {
  const FlightStats({
    required this.flightId,
    required this.startTime,
    required this.durationMin,
    required this.maxAltM,
    required this.maxIasMs,
    required this.avgGsMs,
    required this.minVoltage,
    required this.minBatPct,
    required this.avgVibeX,
    required this.avgVibeY,
    required this.avgVibeZ,
    required this.maxVibeZ,
    required this.totalClips,
  });

  /// Display id — the user-supplied name, else the flight_id, else file name.
  final String flightId;

  /// `start_time_utc` from flight_meta, or null when absent.
  final String? startTime;

  final double durationMin;
  final double? maxAltM;
  final double? maxIasMs;
  final double? avgGsMs;
  final double? minVoltage;
  final int? minBatPct;
  final double? avgVibeX;
  final double? avgVibeY;
  final double? avgVibeZ;
  final double? maxVibeZ;
  final int totalClips;

  /// Ordered `flight_stats` column tuple — used for both CREATE TABLE and the
  /// positional `INSERT INTO flight_stats VALUES (...)`.
  static const columns = <String, String>{
    'flight_id': 'VARCHAR',
    'start_time': 'VARCHAR',
    'duration_min': 'DOUBLE',
    'max_alt_m': 'DOUBLE',
    'max_ias_ms': 'DOUBLE',
    'avg_gs_ms': 'DOUBLE',
    'min_voltage': 'DOUBLE',
    'min_bat_pct': 'INTEGER',
    'avg_vibe_x': 'DOUBLE',
    'avg_vibe_y': 'DOUBLE',
    'avg_vibe_z': 'DOUBLE',
    'max_vibe_z': 'DOUBLE',
    'total_clips': 'INTEGER',
  };

  static const tableName = 'flight_stats';

  /// `CREATE TABLE flight_stats (...)`. [temp] toggles the `TEMP` keyword used
  /// by the DuckDB ATTACH path.
  static String createTable({bool temp = false}) {
    final cols =
        columns.entries.map((e) => '  ${e.key} ${e.value}').join(',\n');
    return 'CREATE ${temp ? 'TEMP ' : ''}TABLE $tableName (\n$cols\n)';
  }

  /// SQL-escape a string literal for embedding in a VALUES tuple.
  static String _sqlStr(String s) => "'${s.replaceAll("'", "''")}'";

  static String _num(num? v) => v == null ? 'NULL' : '$v';

  /// Render this row as a positional `VALUES (...)` tuple matching [columns].
  String toValuesTuple() {
    final startSql = startTime == null || startTime!.isEmpty
        ? 'NULL'
        : _sqlStr(startTime!);
    return '('
        '${_sqlStr(flightId)}, '
        '$startSql, '
        '$durationMin, '
        '${_num(maxAltM)}, '
        '${_num(maxIasMs)}, '
        '${_num(avgGsMs)}, '
        '${_num(minVoltage)}, '
        '${_num(minBatPct)}, '
        '${_num(avgVibeX)}, '
        '${_num(avgVibeY)}, '
        '${_num(avgVibeZ)}, '
        '${_num(maxVibeZ)}, '
        '$totalClips'
        ')';
  }

  /// `INSERT INTO flight_stats VALUES (...)` for this row.
  String toInsert() => 'INSERT INTO $tableName VALUES ${toValuesTuple()}';

  /// Derive stats for a single open flight [db].
  ///
  /// Each per-table aggregate is wrapped so a corrupt or missing table leaves
  /// the corresponding field null rather than aborting the whole flight.
  /// [flightId] and [startTime] are read from `flight_meta` by the caller and
  /// passed in, since name resolution (user_name vs flight_id) is shared logic.
  static FlightStats fromDatabase(
    HeliosDatabase db, {
    required String flightId,
    required String startTime,
  }) {
    double? maxAlt, maxIas, avgGs, minV, avgVx, avgVy, avgVz, maxVz;
    int? minBat;
    var totalClips = 0;
    var durationMin = 0.0;

    _guard(() {
      final r = db.fetch(
        'SELECT MAX(${GpsColumns.altRel}) AS v, '
        'MIN(${GpsColumns.ts}) AS t0, MAX(${GpsColumns.ts}) AS t1 '
        'FROM ${GpsColumns.table}',
      );
      maxAlt = _double(_first(r, 'v'));
      final t0 = _first(r, 't0');
      final t1 = _first(r, 't1');
      if (t0 != null && t1 != null) {
        final d0 = _parseTs(t0);
        final d1 = _parseTs(t1);
        if (d0 != null && d1 != null) {
          durationMin = d1.difference(d0).inSeconds / 60.0;
        }
      }
    });

    _guard(() {
      final r = db.fetch(
        'SELECT MAX(${VfrHudColumns.airspeed}) AS mi, '
        'AVG(${VfrHudColumns.groundspeed}) AS ag '
        'FROM ${VfrHudColumns.table}',
      );
      maxIas = _double(_first(r, 'mi'));
      avgGs = _double(_first(r, 'ag'));
    });

    _guard(() {
      final r = db.fetch(
        'SELECT MIN(${BatteryColumns.voltage}) AS mv, '
        'MIN(${BatteryColumns.remainingPct}) AS mb '
        'FROM ${BatteryColumns.table}',
      );
      minV = _double(_first(r, 'mv'));
      minBat = _int(_first(r, 'mb'));
    });

    _guard(() {
      final r = db.fetch(
        'SELECT AVG(${VibrationColumns.vibeX}) AS ax, '
        'AVG(${VibrationColumns.vibeY}) AS ay, '
        'AVG(${VibrationColumns.vibeZ}) AS az, '
        'MAX(${VibrationColumns.vibeZ}) AS mz, '
        'SUM(${VibrationColumns.clip0}+${VibrationColumns.clip1}+'
        '${VibrationColumns.clip2}) AS tc FROM ${VibrationColumns.table}',
      );
      avgVx = _double(_first(r, 'ax'));
      avgVy = _double(_first(r, 'ay'));
      avgVz = _double(_first(r, 'az'));
      maxVz = _double(_first(r, 'mz'));
      totalClips = _int(_first(r, 'tc')) ?? 0;
    });

    return FlightStats(
      flightId: flightId,
      startTime: startTime.isEmpty ? null : startTime,
      durationMin: durationMin,
      maxAltM: maxAlt,
      maxIasMs: maxIas,
      avgGsMs: avgGs,
      minVoltage: minV,
      minBatPct: minBat,
      avgVibeX: avgVx,
      avgVibeY: avgVy,
      avgVibeZ: avgVz,
      maxVibeZ: maxVz,
      totalClips: totalClips,
    );
  }

  static void _guard(void Function() fn) {
    try {
      fn();
    } catch (_) {
      // Best-effort: a missing/corrupt table leaves the field null.
    }
  }

  static dynamic _first(Map<String, List<dynamic>> r, String col) =>
      r[col]?.isNotEmpty == true ? r[col]!.first : null;

  static double? _double(dynamic v) => v is num ? v.toDouble() : null;

  static int? _int(dynamic v) => v is num ? v.toInt() : null;

  static DateTime? _parseTs(dynamic v) {
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }
}
