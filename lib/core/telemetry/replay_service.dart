import 'dart:async';
import 'package:path/path.dart' as p;

import '../../shared/models/vehicle_state.dart';
import '../database/database.dart';
import 'columns.dart';

/// A single telemetry snapshot at a point in time, used for flight replay.
class ReplaySnapshot {
  const ReplaySnapshot({
    required this.timeSeconds,
    required this.state,
  });

  /// Time offset from flight start in seconds.
  final double timeSeconds;

  /// Vehicle state at this moment.
  final VehicleState state;
}

/// Playback speed multipliers.
enum ReplaySpeed {
  half(0.5, '0.5x'),
  normal(1.0, '1x'),
  double_(2.0, '2x'),
  quad(4.0, '4x'),
  octo(8.0, '8x');

  const ReplaySpeed(this.multiplier, this.label);
  final double multiplier;
  final String label;
}

/// Current replay state.
enum ReplayState { idle, loading, playing, paused }

/// Service that reads a flight file and produces time-synchronised
/// [VehicleState] snapshots for playback through the Fly View.
///
/// The replay engine pre-loads all telemetry into memory (flights are typically
/// <50MB), then uses an ASOF-style merge to produce a unified VehicleState at
/// each GPS timestamp. A [Timer] drives playback at the selected speed.
class ReplayService {
  ReplayService();

  // Internal state
  final List<ReplaySnapshot> _snapshots = [];
  Timer? _playbackTimer;
  final Stopwatch _playbackClock = Stopwatch();
  double _playbackStartTime = 0;
  ReplaySpeed _speed = ReplaySpeed.normal;
  ReplayState _state = ReplayState.idle;
  int _currentIndex = 0;
  double _totalDuration = 0;
  String? loadedFilePath;

  // Flight metadata
  String _flightName = '';
  DateTime? _flightStartUtc;

  // Callbacks
  void Function(VehicleState state)? onStateUpdate;
  void Function(ReplayState state)? onReplayStateChanged;
  void Function(double timeSeconds, double totalDuration)? onTimeUpdate;

  // Public getters
  ReplayState get state => _state;
  ReplaySpeed get speed => _speed;
  double get totalDuration => _totalDuration;
  double get currentTime {
    if (_snapshots.isEmpty) return 0;
    if (_state == ReplayState.playing) {
      final elapsed = _playbackClock.elapsedMilliseconds / 1000.0;
      return (_playbackStartTime + elapsed * _speed.multiplier)
          .clamp(0, _totalDuration);
    }
    if (_currentIndex < _snapshots.length) {
      return _snapshots[_currentIndex].timeSeconds;
    }
    return 0;
  }
  int get snapshotCount => _snapshots.length;
  String get flightName => _flightName;
  DateTime? get flightStartUtc => _flightStartUtc;
  bool get isActive => _state != ReplayState.idle;

  /// Load a flight database file for replay.
  Future<void> loadFlight(String filePath) async {
    _setState(ReplayState.loading);
    _snapshots.clear();
    _currentIndex = 0;
    loadedFilePath = filePath;
    _flightName = p.basenameWithoutExtension(filePath);

    databaseFactory.ensureInitialised();
    HeliosDatabase? conn;
    try {
      conn = databaseFactory.open(filePath);

      // Read flight metadata
      try {
        final meta = conn.fetch(
          'SELECT ${FlightMetaColumns.key}, ${FlightMetaColumns.value} '
          'FROM ${FlightMetaColumns.table} '
          'WHERE ${FlightMetaColumns.key} IN '
          "('start_time_utc', 'user_name', 'vehicle_type', 'autopilot')",
        );
        final keys = meta[FlightMetaColumns.key] ?? [];
        final vals = meta[FlightMetaColumns.value] ?? [];
        final metaMap = <String, String>{};
        for (var i = 0; i < keys.length; i++) {
          metaMap[keys[i].toString()] = vals[i].toString();
        }
        if (metaMap.containsKey('start_time_utc')) {
          _flightStartUtc = DateTime.tryParse(metaMap['start_time_utc']!);
        }
        if (metaMap.containsKey('user_name')) {
          _flightName = metaMap['user_name']!;
        }
      } catch (_) {}

      // Load GPS track (primary timeline)
      final gps = conn.fetch(
        'SELECT ${GpsColumns.ts}, ${GpsColumns.lat}, ${GpsColumns.lon}, '
        '${GpsColumns.altMsl}, ${GpsColumns.altRel}, ${GpsColumns.fixType}, '
        '${GpsColumns.satellites}, ${GpsColumns.hdop} '
        'FROM ${GpsColumns.table} ORDER BY ${GpsColumns.ts}',
      );
      final gpsTs = gps[GpsColumns.ts] ?? [];
      if (gpsTs.isEmpty) {
        conn.close();
        _setState(ReplayState.idle);
        return;
      }

      final gpsLat = gps[GpsColumns.lat] ?? [];
      final gpsLon = gps[GpsColumns.lon] ?? [];
      final gpsAltMsl = gps[GpsColumns.altMsl] ?? [];
      final gpsAltRel = gps[GpsColumns.altRel] ?? [];
      final gpsFixType = gps[GpsColumns.fixType] ?? [];
      final gpsSats = gps[GpsColumns.satellites] ?? [];
      final gpsHdop = gps[GpsColumns.hdop] ?? [];

      final startTime = _parseTs(gpsTs.first);

      // Load attitude data
      final att = conn.fetch(
        'SELECT ${AttitudeColumns.ts}, ${AttitudeColumns.roll}, '
        '${AttitudeColumns.pitch}, ${AttitudeColumns.yaw}, '
        '${AttitudeColumns.rollSpd}, ${AttitudeColumns.pitchSpd}, '
        '${AttitudeColumns.yawSpd} '
        'FROM ${AttitudeColumns.table} ORDER BY ${AttitudeColumns.ts}',
      );
      final attTs = (att[AttitudeColumns.ts] ?? []).map(_parseTs).toList();
      final attRoll = att[AttitudeColumns.roll] ?? [];
      final attPitch = att[AttitudeColumns.pitch] ?? [];
      final attYaw = att[AttitudeColumns.yaw] ?? [];
      final attRollSpd = att[AttitudeColumns.rollSpd] ?? [];
      final attPitchSpd = att[AttitudeColumns.pitchSpd] ?? [];
      final attYawSpd = att[AttitudeColumns.yawSpd] ?? [];

      // Load VFR HUD
      final vfr = conn.fetch(
        'SELECT ${VfrHudColumns.ts}, ${VfrHudColumns.airspeed}, '
        '${VfrHudColumns.groundspeed}, ${VfrHudColumns.heading}, '
        '${VfrHudColumns.throttle}, ${VfrHudColumns.climb} '
        'FROM ${VfrHudColumns.table} ORDER BY ${VfrHudColumns.ts}',
      );
      final vfrTs = (vfr[VfrHudColumns.ts] ?? []).map(_parseTs).toList();
      final vfrAirspeed = vfr[VfrHudColumns.airspeed] ?? [];
      final vfrGs = vfr[VfrHudColumns.groundspeed] ?? [];
      final vfrHeading = vfr[VfrHudColumns.heading] ?? [];
      final vfrThrottle = vfr[VfrHudColumns.throttle] ?? [];
      final vfrClimb = vfr[VfrHudColumns.climb] ?? [];

      // Load battery
      final bat = conn.fetch(
        'SELECT ${BatteryColumns.ts}, ${BatteryColumns.voltage}, '
        '${BatteryColumns.currentA}, ${BatteryColumns.remainingPct} '
        'FROM ${BatteryColumns.table} ORDER BY ${BatteryColumns.ts}',
      );
      final batTs = (bat[BatteryColumns.ts] ?? []).map(_parseTs).toList();
      final batVoltage = bat[BatteryColumns.voltage] ?? [];
      final batCurrent = bat[BatteryColumns.currentA] ?? [];
      final batRemaining = bat[BatteryColumns.remainingPct] ?? [];

      // Load vibration
      final vib = conn.fetch(
        'SELECT ${VibrationColumns.ts}, ${VibrationColumns.vibeX}, '
        '${VibrationColumns.vibeY}, ${VibrationColumns.vibeZ} '
        'FROM ${VibrationColumns.table} ORDER BY ${VibrationColumns.ts}',
      );
      final vibTs = (vib[VibrationColumns.ts] ?? []).map(_parseTs).toList();

      conn.close();
      conn = null;

      // ASOF merge: for each GPS sample, find the latest attitude/vfr/battery
      // sample at or before that time.
      int attIdx = 0;
      int vfrIdx = 0;
      int batIdx = 0;
      int vibIdx = 0;

      for (var i = 0; i < gpsTs.length; i++) {
        final ts = _parseTs(gpsTs[i]);
        final timeSec = ts.difference(startTime).inMilliseconds / 1000.0;

        while (attIdx < attTs.length - 1 && attTs[attIdx + 1].compareTo(ts) <= 0) {
          attIdx++;
        }
        while (vfrIdx < vfrTs.length - 1 && vfrTs[vfrIdx + 1].compareTo(ts) <= 0) {
          vfrIdx++;
        }
        while (batIdx < batTs.length - 1 && batTs[batIdx + 1].compareTo(ts) <= 0) {
          batIdx++;
        }
        while (vibIdx < vibTs.length - 1 && vibTs[vibIdx + 1].compareTo(ts) <= 0) {
          vibIdx++;
        }

        final state = VehicleState(
          latitude: _toDouble(gpsLat, i),
          longitude: _toDouble(gpsLon, i),
          altitudeMsl: _toDouble(gpsAltMsl, i),
          altitudeRel: _toDouble(gpsAltRel, i),
          gpsFix: _toGpsFix(_toInt(gpsFixType, i)),
          satellites: _toInt(gpsSats, i),
          hdop: _toDouble(gpsHdop, i),
          roll: attTs.isNotEmpty ? _toDouble(attRoll, attIdx) : 0,
          pitch: attTs.isNotEmpty ? _toDouble(attPitch, attIdx) : 0,
          yaw: attTs.isNotEmpty ? _toDouble(attYaw, attIdx) : 0,
          rollSpeed: attTs.isNotEmpty ? _toDouble(attRollSpd, attIdx) : 0,
          pitchSpeed: attTs.isNotEmpty ? _toDouble(attPitchSpd, attIdx) : 0,
          yawSpeed: attTs.isNotEmpty ? _toDouble(attYawSpd, attIdx) : 0,
          airspeed: vfrTs.isNotEmpty ? _toDouble(vfrAirspeed, vfrIdx) : 0,
          groundspeed: vfrTs.isNotEmpty ? _toDouble(vfrGs, vfrIdx) : 0,
          heading: vfrTs.isNotEmpty ? _toInt(vfrHeading, vfrIdx) : 0,
          throttle: vfrTs.isNotEmpty ? _toInt(vfrThrottle, vfrIdx) : 0,
          climbRate: vfrTs.isNotEmpty ? _toDouble(vfrClimb, vfrIdx) : 0,
          batteryVoltage: batTs.isNotEmpty ? _toDouble(batVoltage, batIdx) : 0,
          batteryCurrent: batTs.isNotEmpty ? _toDouble(batCurrent, batIdx) : 0,
          batteryRemaining: batTs.isNotEmpty ? _toInt(batRemaining, batIdx) : -1,
          armed: true,
          lastHeartbeat: ts,
        );

        _snapshots.add(ReplaySnapshot(timeSeconds: timeSec, state: state));
      }

      if (_snapshots.isNotEmpty) {
        _totalDuration = _snapshots.last.timeSeconds;
      }

      _setState(ReplayState.paused);
      _emitCurrentState();
    } catch (e) {
      conn?.close();
      _setState(ReplayState.idle);
      rethrow;
    }
  }

  void play() {
    if (_snapshots.isEmpty) return;
    if (_state == ReplayState.playing) return;

    _playbackStartTime = currentTime;
    _playbackClock.reset();
    _playbackClock.start();

    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => _tick(),
    );

    _setState(ReplayState.playing);
  }

  void pause() {
    if (_state != ReplayState.playing) return;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _playbackClock.stop();
    _playbackStartTime = currentTime;
    _setState(ReplayState.paused);
  }

  void togglePlayPause() {
    if (_state == ReplayState.playing) {
      pause();
    } else if (_state == ReplayState.paused) {
      play();
    }
  }

  void seekTo(double timeSeconds) {
    if (_snapshots.isEmpty) return;
    final clamped = timeSeconds.clamp(0.0, _totalDuration);

    var lo = 0;
    var hi = _snapshots.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_snapshots[mid].timeSeconds < clamped) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    _currentIndex = lo;
    _playbackStartTime = clamped;

    if (_state == ReplayState.playing) {
      _playbackClock.reset();
      _playbackClock.start();
    }

    _emitCurrentState();
  }

  void setSpeed(ReplaySpeed newSpeed) {
    if (_state == ReplayState.playing) {
      _playbackStartTime = currentTime;
      _playbackClock.reset();
      _playbackClock.start();
    }
    _speed = newSpeed;
  }

  void stepForward() {
    if (_state != ReplayState.paused) return;
    if (_currentIndex < _snapshots.length - 1) {
      _currentIndex++;
      _playbackStartTime = _snapshots[_currentIndex].timeSeconds;
      _emitCurrentState();
    }
  }

  void stepBackward() {
    if (_state != ReplayState.paused) return;
    if (_currentIndex > 0) {
      _currentIndex--;
      _playbackStartTime = _snapshots[_currentIndex].timeSeconds;
      _emitCurrentState();
    }
  }

  void stop() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _playbackClock.stop();
    _playbackClock.reset();
    _snapshots.clear();
    _currentIndex = 0;
    _totalDuration = 0;
    _playbackStartTime = 0;
    loadedFilePath = null;
    _flightName = '';
    _flightStartUtc = null;
    _setState(ReplayState.idle);
  }

  void dispose() {
    _playbackTimer?.cancel();
    _playbackClock.stop();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _tick() {
    final time = currentTime;
    if (time >= _totalDuration) {
      _currentIndex = _snapshots.length - 1;
      pause();
      _emitCurrentState();
      return;
    }

    while (_currentIndex < _snapshots.length - 1 &&
        _snapshots[_currentIndex + 1].timeSeconds <= time) {
      _currentIndex++;
    }

    _emitCurrentState();
  }

  void _emitCurrentState() {
    if (_currentIndex < _snapshots.length) {
      final snapshot = _snapshots[_currentIndex];
      onStateUpdate?.call(snapshot.state);
      onTimeUpdate?.call(snapshot.timeSeconds, _totalDuration);
    }
  }

  void _setState(ReplayState newState) {
    _state = newState;
    onReplayStateChanged?.call(newState);
  }

  DateTime _parseTs(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString()) ?? DateTime.now();
  }

  double _toDouble(List<dynamic> list, int index) {
    if (index >= list.length) return 0;
    final v = list[index];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  int _toInt(List<dynamic> list, int index) {
    if (index >= list.length) return 0;
    final v = list[index];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  GpsFix _toGpsFix(int fixType) {
    return switch (fixType) {
      0 => GpsFix.none,
      1 => GpsFix.noFix,
      2 => GpsFix.fix2d,
      3 => GpsFix.fix3d,
      4 => GpsFix.dgps,
      5 => GpsFix.rtkFloat,
      6 => GpsFix.rtkFixed,
      _ => GpsFix.none,
    };
  }
}
