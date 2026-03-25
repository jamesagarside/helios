import 'dart:async';
import 'dart:io';
import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:duckdb_dart/duckdb_dart.dart';
import '../../shared/models/mission_item.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'schema.dart';

/// Query result from DuckDB.
class QueryResult {
  QueryResult({
    required this.columnNames,
    required this.rows,
    required this.executionTime,
  });

  final List<String> columnNames;
  final List<List<dynamic>> rows;
  final Duration executionTime;

  int get rowCount => rows.length;
}

/// Summary of a recorded flight.
class FlightSummary {
  FlightSummary({
    required this.filePath,
    required this.fileName,
    this.flightId,
    this.startTime,
    this.duration,
    required this.fileSizeBytes,
  });

  final String filePath;
  final String fileName;
  final String? flightId;
  final DateTime? startTime;
  final Duration? duration;
  final int fileSizeBytes;
}

/// Embedded DuckDB flight data store.
///
/// Uses duckdb_dart (synchronous FFI-based API).
/// Connection constructor opens DB. execute() for DDL/DML. fetch() for queries.
class TelemetryStore {
  Connection? _conn;
  String? _currentFilePath;
  bool _isRecording = false;
  int _rowsWritten = 0;

  // Buffered messages for batch insert
  final List<_BufferedAttitude> _attitudeBuf = [];
  final List<_BufferedGps> _gpsBuf = [];
  final List<_BufferedBattery> _batteryBuf = [];
  final List<_BufferedVfrHud> _vfrHudBuf = [];
  final List<_BufferedVibration> _vibrationBuf = [];
  final List<_BufferedEvent> _eventBuf = [];

  Timer? _flushTimer;

  bool get isRecording => _isRecording;
  String? get currentFilePath => _currentFilePath;
  int get rowsWritten => _rowsWritten;

  /// Get the flights directory.
  Future<String> get _flightsDir async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'flights'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir.path;
  }

  /// Create a new flight database and start recording.
  Future<String> createFlight({
    int vehicleSysId = 0,
    String vehicleType = 'unknown',
    String autopilot = 'unknown',
  }) async {
    await closeFlight();

    final dir = await _flightsDir;
    final now = DateTime.now();
    final fileName = 'helios_${_formatDate(now)}_$vehicleSysId.duckdb';
    final filePath = p.join(dir, fileName);

    _conn = Connection(filePath);
    _currentFilePath = filePath;

    // Create schema
    for (final sql in HeliosSchema.allTables) {
      _conn!.execute(sql);
    }

    // Insert flight metadata
    final flightId = const Uuid().v4();
    _conn!.execute("INSERT INTO flight_meta VALUES ('schema_version', '${HeliosSchema.version}')");
    _conn!.execute("INSERT INTO flight_meta VALUES ('flight_id', '$flightId')");
    _conn!.execute("INSERT INTO flight_meta VALUES ('vehicle_sysid', '$vehicleSysId')");
    _conn!.execute("INSERT INTO flight_meta VALUES ('vehicle_type', '$vehicleType')");
    _conn!.execute("INSERT INTO flight_meta VALUES ('autopilot', '$autopilot')");
    _conn!.execute("INSERT INTO flight_meta VALUES ('start_time_utc', '${now.toUtc().toIso8601String()}')");
    _conn!.execute("INSERT INTO flight_meta VALUES ('helios_version', '0.1.0')");

    _isRecording = true;
    _rowsWritten = 0;

    // Start periodic flush (every 1 second)
    _flushTimer = Timer.periodic(const Duration(seconds: 1), (_) => flush());

    return filePath;
  }

  /// Buffer a MAVLink message for batch insert.
  void buffer(MavlinkMessage msg) {
    if (!_isRecording) return;

    final now = DateTime.now().toUtc();

    switch (msg) {
      case AttitudeMessage():
        _attitudeBuf.add(_BufferedAttitude(now, msg));
      case GlobalPositionIntMessage():
        _gpsBuf.add(_BufferedGps(now, msg));
      case SysStatusMessage():
        _batteryBuf.add(_BufferedBattery(now, msg));
      case VfrHudMessage():
        _vfrHudBuf.add(_BufferedVfrHud(now, msg));
      case VibrationMessage():
        _vibrationBuf.add(_BufferedVibration(now, msg));
      case StatusTextMessage():
        _eventBuf.add(_BufferedEvent(now, 'statustext', msg.text, msg.severity));
      default:
        break;
    }
  }

  /// Log a discrete event.
  void logEvent(String type, String detail, {int severity = 6}) {
    if (!_isRecording) return;
    _eventBuf.add(_BufferedEvent(DateTime.now().toUtc(), type, detail, severity));
  }

  /// Flush all buffered data to DuckDB.
  int flush() {
    if (_conn == null) return 0;
    var count = 0;

    try {
      if (_attitudeBuf.isNotEmpty) {
        final values = _attitudeBuf.map((a) =>
          "('${_ts(a.ts)}', ${a.msg.roll}, ${a.msg.pitch}, ${a.msg.yaw}, "
          '${a.msg.rollSpeed}, ${a.msg.pitchSpeed}, ${a.msg.yawSpeed})'
        ).join(', ');
        _conn!.execute('INSERT INTO attitude VALUES $values');
        count += _attitudeBuf.length;
        _attitudeBuf.clear();
      }

      if (_gpsBuf.isNotEmpty) {
        final values = _gpsBuf.map((g) =>
          "('${_ts(g.ts)}', ${g.msg.latDeg}, ${g.msg.lonDeg}, "
          '${g.msg.altMetres}, ${g.msg.relAltMetres}, 3, 14, 0.85, 1.2, 0, 0)'
        ).join(', ');
        _conn!.execute('INSERT INTO gps VALUES $values');
        count += _gpsBuf.length;
        _gpsBuf.clear();
      }

      if (_batteryBuf.isNotEmpty) {
        final values = _batteryBuf.map((b) =>
          "('${_ts(b.ts)}', ${b.msg.voltageVolts}, ${b.msg.currentAmps}, "
          '${b.msg.batteryRemaining}, 0)'
        ).join(', ');
        _conn!.execute('INSERT INTO battery VALUES $values');
        count += _batteryBuf.length;
        _batteryBuf.clear();
      }

      if (_vfrHudBuf.isNotEmpty) {
        final values = _vfrHudBuf.map((v) =>
          "('${_ts(v.ts)}', ${v.msg.airspeed}, ${v.msg.groundspeed}, "
          '${v.msg.heading}, ${v.msg.throttle}, ${v.msg.climb})'
        ).join(', ');
        _conn!.execute('INSERT INTO vfr_hud VALUES $values');
        count += _vfrHudBuf.length;
        _vfrHudBuf.clear();
      }

      if (_vibrationBuf.isNotEmpty) {
        final values = _vibrationBuf.map((v) =>
          "('${_ts(v.ts)}', ${v.msg.vibrationX}, ${v.msg.vibrationY}, "
          '${v.msg.vibrationZ}, ${v.msg.clipping0}, ${v.msg.clipping1}, ${v.msg.clipping2})'
        ).join(', ');
        _conn!.execute('INSERT INTO vibration VALUES $values');
        count += _vibrationBuf.length;
        _vibrationBuf.clear();
      }

      if (_eventBuf.isNotEmpty) {
        final values = _eventBuf.map((e) {
          final detail = e.detail.replaceAll("'", "''");
          return "('${_ts(e.ts)}', '${e.type}', '$detail', ${e.severity})";
        }).join(', ');
        _conn!.execute('INSERT INTO events VALUES $values');
        count += _eventBuf.length;
        _eventBuf.clear();
      }
    } catch (_) {
      // Don't let DuckDB errors crash the real-time path
    }

    _rowsWritten += count;
    return count;
  }

  /// Close the current flight database.
  Future<void> closeFlight() async {
    if (_conn == null) return;

    _flushTimer?.cancel();
    _flushTimer = null;

    flush();

    if (_isRecording) {
      try {
        _conn!.execute(
          "INSERT INTO flight_meta VALUES ('end_time_utc', "
          "'${DateTime.now().toUtc().toIso8601String()}')"
        );
      } catch (_) {}
    }

    _conn!.close();
    _conn = null;
    _isRecording = false;
    _currentFilePath = null;
  }

  /// Save a mission snapshot to the database.
  /// Called on upload/download to record the mission at that point in time.
  void saveMission(List<MissionItem> items, {required String direction}) {
    if (_conn == null || items.isEmpty) return;

    try {
      final now = DateTime.now().toUtc();
      final ts = _ts(now);
      final values = items.map((item) =>
        "('$ts', '$direction', ${item.seq}, ${item.frame}, ${item.command}, "
        '${item.param1}, ${item.param2}, ${item.param3}, ${item.param4}, '
        '${item.latitude}, ${item.longitude}, ${item.altitude}, ${item.autocontinue})'
      ).join(', ');
      _conn!.execute('INSERT INTO missions VALUES $values');
    } catch (_) {
      // Don't let persistence errors affect operations
    }
  }

  /// Open an existing flight database for analysis.
  Future<void> openFlight(String filePath) async {
    await closeFlight();
    _conn = Connection(filePath);
    _currentFilePath = filePath;
    _isRecording = false;
  }

  /// Execute a SQL query and return results.
  Future<QueryResult> query(String sql) async {
    if (_conn == null) throw StateError('No database open');

    final sw = Stopwatch()..start();
    final result = _conn!.fetch(sql);
    sw.stop();

    final columnNames = result.keys.toList();
    final rowCount = columnNames.isEmpty ? 0 : result[columnNames.first]!.length;

    final rows = <List<dynamic>>[];
    for (var i = 0; i < rowCount; i++) {
      rows.add(columnNames.map((col) => result[col]![i]).toList());
    }

    return QueryResult(
      columnNames: columnNames,
      rows: rows,
      executionTime: sw.elapsed,
    );
  }

  /// Export a table to Parquet.
  Future<String> exportParquet(String tableName, String outputPath) async {
    if (_conn == null) throw StateError('No database open');
    final dir = Directory(p.dirname(outputPath));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _conn!.execute("COPY $tableName TO '$outputPath' (FORMAT PARQUET)");
    return outputPath;
  }

  /// List all recorded flights.
  Future<List<FlightSummary>> listFlights() async {
    final dir = await _flightsDir;
    final flightsDir = Directory(dir);
    if (!flightsDir.existsSync()) return [];

    final files = flightsDir.listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.duckdb'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    return files.map((f) {
      final name = p.basename(f.path);
      DateTime? startTime;
      try {
        final parts = name.split('_');
        if (parts.length >= 3) {
          final date = parts[1];
          final time = parts[2];
          startTime = DateTime.parse(
            '${date.substring(0, 4)}-${date.substring(4, 6)}-${date.substring(6, 8)} '
            '${time.substring(0, 2)}:${time.substring(2, 4)}:${time.substring(4, 6)}'
          );
        }
      } catch (_) {}

      return FlightSummary(
        filePath: f.path,
        fileName: name,
        startTime: startTime,
        fileSizeBytes: f.lengthSync(),
      );
    }).toList();
  }

  /// Dispose all resources.
  void dispose() {
    _flushTimer?.cancel();
    _conn?.close();
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}_'
           '${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}${dt.second.toString().padLeft(2, '0')}';
  }

  String _ts(DateTime dt) => dt.toIso8601String().replaceFirst('T', ' ');
}

// Buffered message wrappers
class _BufferedAttitude {
  _BufferedAttitude(this.ts, this.msg);
  final DateTime ts;
  final AttitudeMessage msg;
}

class _BufferedGps {
  _BufferedGps(this.ts, this.msg);
  final DateTime ts;
  final GlobalPositionIntMessage msg;
}

class _BufferedBattery {
  _BufferedBattery(this.ts, this.msg);
  final DateTime ts;
  final SysStatusMessage msg;
}

class _BufferedVfrHud {
  _BufferedVfrHud(this.ts, this.msg);
  final DateTime ts;
  final VfrHudMessage msg;
}

class _BufferedVibration {
  _BufferedVibration(this.ts, this.msg);
  final DateTime ts;
  final VibrationMessage msg;
}

class _BufferedEvent {
  _BufferedEvent(this.ts, this.type, this.detail, this.severity);
  final DateTime ts;
  final String type;
  final String detail;
  final int severity;
}
