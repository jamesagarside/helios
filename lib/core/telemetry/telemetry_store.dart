import 'dart:async';
import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../shared/models/flight_metadata.dart';
import '../../shared/models/mission_item.dart';
import '../database/database.dart';
import '../platform/file_system.dart';
import 'schema.dart';

/// Query result from the database.
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

/// Embedded flight data store.
///
/// Uses the platform database abstraction — DuckDB on native, sql.js on web.
/// Connection constructor opens DB. execute() for DDL/DML. fetch() for queries.
class TelemetryStore {
  HeliosDatabase? _conn;
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

  // MSP buffered messages for batch insert
  final List<_MspBufferedAttitude> _mspAttitudeBuf = [];
  final List<_MspBufferedGps> _mspGpsBuf = [];
  final List<_MspBufferedAnalog> _mspAnalogBuf = [];
  final List<_MspBufferedStatus> _mspStatusBuf = [];
  final List<_MspBufferedAltitude> _mspAltitudeBuf = [];

  Timer? _flushTimer;

  bool get isRecording => _isRecording;
  String? get currentFilePath => _currentFilePath;
  int get rowsWritten => _rowsWritten;

  /// Create a new flight database and start recording.
  Future<String> createFlight({
    int vehicleSysId = 0,
    String vehicleType = 'unknown',
    String autopilot = 'unknown',
    String protocol = 'mavlink',
  }) async {
    await closeFlight();

    final dir = await heliosFileSystem.flightsDirectory;
    final now = DateTime.now();
    final fileName = 'helios_${_formatDate(now)}_$vehicleSysId.duckdb';
    final filePath = p.join(dir, fileName);

    databaseFactory.ensureInitialised();
    _conn = databaseFactory.open(filePath);
    _currentFilePath = filePath;

    // Create schema
    for (final sql in HeliosSchema.allTables) {
      _conn!.execute(sql);
    }
    for (final sql in HeliosMspSchema.allTables) {
      _conn!.execute(sql);
    }

    // Insert flight metadata
    final flightId = const Uuid().v4();
    _conn!.execute("INSERT INTO flight_meta VALUES ('schema_version', '${HeliosSchema.version}')");
    _conn!.execute("INSERT INTO flight_meta VALUES ('flight_id', '$flightId')");
    _conn!.execute("INSERT INTO flight_meta VALUES ('vehicle_sysid', '$vehicleSysId')");
    final safeVehicleType = vehicleType.replaceAll("'", "''");
    final safeAutopilot = autopilot.replaceAll("'", "''");
    final safeProtocol = protocol.replaceAll("'", "''");
    _conn!.execute("INSERT INTO flight_meta VALUES ('vehicle_type', '$safeVehicleType')");
    _conn!.execute("INSERT INTO flight_meta VALUES ('autopilot', '$safeAutopilot')");
    _conn!.execute("INSERT INTO flight_meta VALUES ('start_time_utc', '${now.toUtc().toIso8601String()}')");
    _conn!.execute("INSERT INTO flight_meta VALUES ('helios_version', '0.1.0')");
    _conn!.execute("INSERT INTO flight_meta VALUES ('protocol', '$safeProtocol')");

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

  /// Buffer an MSP ATTITUDE message.
  void bufferMspAttitude({
    required double rollDeg,
    required double pitchDeg,
    required int headingDeg,
  }) {
    if (!_isRecording) return;
    _mspAttitudeBuf.add(_MspBufferedAttitude(DateTime.now().toUtc(), rollDeg, pitchDeg, headingDeg));
  }

  /// Buffer an MSP GPS message.
  void bufferMspGps({
    required int fixType,
    required int numSat,
    required double lat,
    required double lon,
    required double altitudeM,
    required double speedMs,
    required double courseDeg,
  }) {
    if (!_isRecording) return;
    _mspGpsBuf.add(_MspBufferedGps(DateTime.now().toUtc(), fixType, numSat, lat, lon, altitudeM, speedMs, courseDeg));
  }

  /// Buffer an MSP ANALOG message.
  void bufferMspAnalog({
    required double voltageV,
    required double currentA,
    required double consumedMah,
    required int remainingPct,
    required int rssi,
  }) {
    if (!_isRecording) return;
    _mspAnalogBuf.add(_MspBufferedAnalog(DateTime.now().toUtc(), voltageV, currentA, consumedMah, remainingPct, rssi));
  }

  /// Buffer an MSP ALTITUDE message.
  void bufferMspAltitude({
    required double altitudeRelM,
    required double climbMs,
  }) {
    if (!_isRecording) return;
    _mspAltitudeBuf.add(_MspBufferedAltitude(DateTime.now().toUtc(), altitudeRelM, climbMs));
  }

  /// Buffer an MSP STATUS message.
  void bufferMspStatus({
    required bool armed,
    required int flightModeFlags,
    required String flightModeName,
    required bool sensorsOk,
    required int cycleTimeUs,
  }) {
    if (!_isRecording) return;
    _mspStatusBuf.add(_MspBufferedStatus(DateTime.now().toUtc(), armed, flightModeFlags, flightModeName, sensorsOk, cycleTimeUs));
  }

  /// Flush all buffered data to the database.
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
          final type = e.type.replaceAll("'", "''");
          final detail = e.detail.replaceAll("'", "''");
          return "('${_ts(e.ts)}', '$type', '$detail', ${e.severity})";
        }).join(', ');
        _conn!.execute('INSERT INTO events VALUES $values');
        count += _eventBuf.length;
        _eventBuf.clear();
      }

      if (_mspAttitudeBuf.isNotEmpty) {
        final values = _mspAttitudeBuf.map((a) =>
          "('${_ts(a.ts)}', ${a.roll}, ${a.pitch}, ${a.heading})"
        ).join(', ');
        _conn!.execute('INSERT INTO msp_attitude VALUES $values');
        count += _mspAttitudeBuf.length;
        _mspAttitudeBuf.clear();
      }

      if (_mspGpsBuf.isNotEmpty) {
        final values = _mspGpsBuf.map((g) =>
          "('${_ts(g.ts)}', ${g.fixType}, ${g.numSat}, ${g.lat}, ${g.lon}, "
          '${g.altitudeM}, ${g.speedMs}, ${g.courseDeg})'
        ).join(', ');
        _conn!.execute('INSERT INTO msp_gps VALUES $values');
        count += _mspGpsBuf.length;
        _mspGpsBuf.clear();
      }

      if (_mspAnalogBuf.isNotEmpty) {
        final values = _mspAnalogBuf.map((a) =>
          "('${_ts(a.ts)}', ${a.voltageV}, ${a.currentA}, ${a.consumedMah}, "
          '${a.remainingPct}, ${a.rssi})'
        ).join(', ');
        _conn!.execute('INSERT INTO msp_analog VALUES $values');
        count += _mspAnalogBuf.length;
        _mspAnalogBuf.clear();
      }

      if (_mspStatusBuf.isNotEmpty) {
        final values = _mspStatusBuf.map((s) {
          final modeName = s.flightModeName.replaceAll("'", "''");
          return "('${_ts(s.ts)}', ${s.armed}, ${s.flightModeFlags}, "
                 "'$modeName', ${s.sensorsOk}, ${s.cycleTimeUs})";
        }).join(', ');
        _conn!.execute('INSERT INTO msp_status VALUES $values');
        count += _mspStatusBuf.length;
        _mspStatusBuf.clear();
      }

      if (_mspAltitudeBuf.isNotEmpty) {
        final values = _mspAltitudeBuf.map((a) =>
          "('${_ts(a.ts)}', ${a.altitudeRelM}, ${a.climbMs})"
        ).join(', ');
        _conn!.execute('INSERT INTO msp_altitude VALUES $values');
        count += _mspAltitudeBuf.length;
        _mspAltitudeBuf.clear();
      }
    } catch (_) {
      // Don't let database errors crash the real-time path
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
    final normalized = p.normalize(filePath);
    if (normalized.contains('..')) {
      throw ArgumentError('Path traversal detected: $filePath');
    }
    await closeFlight();
    databaseFactory.ensureInitialised();
    _conn = databaseFactory.open(normalized);
    _currentFilePath = normalized;
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

  String _sanitizePath(String outputPath) {
    final normalized = p.normalize(outputPath);
    if (normalized.contains('..')) {
      throw ArgumentError('Path traversal detected: $outputPath');
    }
    return normalized.replaceAll("'", "''");
  }

  String _sanitizeIdentifier(String name) {
    final safe = name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
    if (safe.isEmpty) throw ArgumentError('Invalid identifier: $name');
    return safe;
  }

  /// Export a table to Parquet (native only — uses COPY TO).
  Future<String> exportParquet(String tableName, String outputPath) async {
    if (_conn == null) throw StateError('No database open');
    if (!databaseFactory.capabilities.supportsCopyExport) {
      throw UnsupportedError('Parquet export not supported on this platform');
    }
    final safePath = _sanitizePath(outputPath);
    final safeTable = _sanitizeIdentifier(tableName);
    await heliosFileSystem.ensureDirectory(p.dirname(outputPath));
    _conn!.execute("COPY $safeTable TO '$safePath' (FORMAT PARQUET)");
    return outputPath;
  }

  /// Export a table (or arbitrary SQL result) to CSV.
  Future<String> exportCsv(String tableOrQuery, String outputPath) async {
    if (_conn == null) throw StateError('No database open');
    if (!databaseFactory.capabilities.supportsCopyExport) {
      throw UnsupportedError('CSV export via COPY not supported on this platform');
    }
    final safePath = _sanitizePath(outputPath);
    await heliosFileSystem.ensureDirectory(p.dirname(outputPath));
    final src = tableOrQuery.trimLeft().toUpperCase().startsWith('SELECT')
        ? '($tableOrQuery)'
        : _sanitizeIdentifier(tableOrQuery);
    _conn!.execute("COPY $src TO '$safePath' (FORMAT CSV, HEADER)");
    return outputPath;
  }

  /// Export a table (or arbitrary SQL result) to newline-delimited JSON.
  Future<String> exportJson(String tableOrQuery, String outputPath) async {
    if (_conn == null) throw StateError('No database open');
    if (!databaseFactory.capabilities.supportsCopyExport) {
      throw UnsupportedError('JSON export via COPY not supported on this platform');
    }
    final safePath = _sanitizePath(outputPath);
    await heliosFileSystem.ensureDirectory(p.dirname(outputPath));
    final src = tableOrQuery.trimLeft().toUpperCase().startsWith('SELECT')
        ? '($tableOrQuery)'
        : _sanitizeIdentifier(tableOrQuery);
    _conn!.execute("COPY $src TO '$safePath' (FORMAT JSON)");
    return outputPath;
  }

  /// List all recorded flights.
  Future<List<FlightSummary>> listFlights() async {
    final files = await heliosFileSystem.listFlightFiles();

    return files.map((f) {
      DateTime? startTime;
      try {
        final parts = f.name.split('_');
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
        fileName: f.name,
        startTime: startTime,
        fileSizeBytes: f.sizeBytes,
      );
    }).toList();
  }

  /// Read user-editable metadata from a flight database.
  Future<FlightMetadata> getFlightMetadata(String filePath) async {
    databaseFactory.ensureInitialised();
    HeliosDatabase? conn;
    try {
      conn = databaseFactory.open(filePath);
      final result = conn.fetch(
        "SELECT key, value FROM flight_meta WHERE key LIKE 'user_%'",
      );
      final keys = result['key'];
      final values = result['value'];
      if (keys == null || values == null || keys.isEmpty) {
        return const FlightMetadata();
      }
      final map = <String, String>{};
      for (var i = 0; i < keys.length; i++) {
        map[keys[i].toString()] = values[i].toString();
      }
      return FlightMetadata(
        name: map['user_name'],
        notes: map['user_notes'],
        tags: map['user_tags']?.isNotEmpty == true
            ? map['user_tags']!.split(',')
            : const [],
        rating: map['user_rating'] != null
            ? int.tryParse(map['user_rating']!)
            : null,
      );
    } catch (_) {
      return const FlightMetadata();
    } finally {
      conn?.close();
    }
  }

  /// Write user-editable metadata to a flight database.
  Future<void> setFlightMetadata(
      String filePath, FlightMetadata metadata) async {
    final useExisting = _currentFilePath == filePath && _conn != null;
    databaseFactory.ensureInitialised();
    HeliosDatabase? conn;
    try {
      conn = useExisting ? _conn : databaseFactory.open(filePath);
      void upsert(String key, String? value) {
        if (value == null || value.isEmpty) {
          conn!.execute(
            "DELETE FROM flight_meta WHERE key = '$key'",
          );
        } else {
          final escaped = value.replaceAll("'", "''");
          conn!.execute(
            "INSERT OR REPLACE INTO flight_meta VALUES ('$key', '$escaped')",
          );
        }
      }

      upsert('user_name', metadata.name);
      upsert('user_notes', metadata.notes);
      upsert('user_tags', metadata.tags.isNotEmpty ? metadata.tags.join(',') : null);
      upsert('user_rating', metadata.rating?.toString());
    } finally {
      if (!useExisting) conn?.close();
    }
  }

  /// Execute a SQL query against an arbitrary flight file.
  Future<QueryResult> queryFile(String filePath, String sql) async {
    databaseFactory.ensureInitialised();
    HeliosDatabase? conn;
    try {
      conn = databaseFactory.open(filePath);
      final sw = Stopwatch()..start();
      final result = conn.fetch(sql);
      sw.stop();
      final columnNames = result.keys.toList();
      final rowCount =
          columnNames.isEmpty ? 0 : result[columnNames.first]!.length;
      final rows = <List<dynamic>>[];
      for (var i = 0; i < rowCount; i++) {
        rows.add(columnNames.map((col) => result[col]![i]).toList());
      }
      return QueryResult(
        columnNames: columnNames,
        rows: rows,
        executionTime: sw.elapsed,
      );
    } finally {
      conn?.close();
    }
  }

  /// Delete a recorded flight database file.
  Future<void> deleteFlight(String filePath) async {
    final normalized = p.normalize(filePath);
    if (normalized.contains('..')) {
      throw ArgumentError('Path traversal detected: $filePath');
    }
    if (_currentFilePath == normalized) {
      await closeFlight();
    }
    await heliosFileSystem.deleteFlightFile(normalized);
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

// MSP buffered message wrappers
class _MspBufferedAttitude {
  _MspBufferedAttitude(this.ts, this.roll, this.pitch, this.heading);
  final DateTime ts;
  final double roll;
  final double pitch;
  final int heading;
}

class _MspBufferedGps {
  _MspBufferedGps(this.ts, this.fixType, this.numSat, this.lat, this.lon,
      this.altitudeM, this.speedMs, this.courseDeg);
  final DateTime ts;
  final int fixType;
  final int numSat;
  final double lat;
  final double lon;
  final double altitudeM;
  final double speedMs;
  final double courseDeg;
}

class _MspBufferedAnalog {
  _MspBufferedAnalog(this.ts, this.voltageV, this.currentA, this.consumedMah,
      this.remainingPct, this.rssi);
  final DateTime ts;
  final double voltageV;
  final double currentA;
  final double consumedMah;
  final int remainingPct;
  final int rssi;
}

class _MspBufferedStatus {
  _MspBufferedStatus(this.ts, this.armed, this.flightModeFlags,
      this.flightModeName, this.sensorsOk, this.cycleTimeUs);
  final DateTime ts;
  final bool armed;
  final int flightModeFlags;
  final String flightModeName;
  final bool sensorsOk;
  final int cycleTimeUs;
}

class _MspBufferedAltitude {
  _MspBufferedAltitude(this.ts, this.altitudeRelM, this.climbMs);
  final DateTime ts;
  final double altitudeRelM;
  final double climbMs;
}
