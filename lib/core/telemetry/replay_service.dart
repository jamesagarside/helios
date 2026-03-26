import 'dart:async';
import 'package:duckdb_dart/duckdb_dart.dart';
import '../../shared/models/vehicle_state.dart';
import 'package:path/path.dart' as p;

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

/// Service that reads a DuckDB flight file and produces time-synchronised
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
  double _playbackStartTime = 0; // where in the flight we started playing
  ReplaySpeed _speed = ReplaySpeed.normal;
  ReplayState _state = ReplayState.idle;
  int _currentIndex = 0;
  double _totalDuration = 0;
  // Retained so callers can query which file is loaded
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

  /// Load a flight DuckDB file for replay.
  ///
  /// Reads all telemetry tables and merges them into chronological
  /// [ReplaySnapshot]s, one per GPS sample (typically 5-10 Hz).
  Future<void> loadFlight(String filePath) async {
    _setState(ReplayState.loading);
    _snapshots.clear();
    _currentIndex = 0;
    loadedFilePath = filePath;
    _flightName = p.basenameWithoutExtension(filePath);

    Connection? conn;
    try {
      conn = Connection(filePath);

      // Read flight metadata
      try {
        final meta = conn.fetch(
          'SELECT key, value FROM flight_meta WHERE key IN '
          "('start_time_utc', 'user_name', 'vehicle_type', 'autopilot')",
        );
        final keys = meta['key'] as List? ?? [];
        final vals = meta['value'] as List? ?? [];
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
        'SELECT ts, lat, lon, alt_msl, alt_rel, fix_type, satellites, hdop '
        'FROM gps ORDER BY ts',
      );
      final gpsTs = gps['ts'] as List? ?? [];
      if (gpsTs.isEmpty) {
        conn.close();
        _setState(ReplayState.idle);
        return;
      }

      final gpsLat = gps['lat'] as List? ?? [];
      final gpsLon = gps['lon'] as List? ?? [];
      final gpsAltMsl = gps['alt_msl'] as List? ?? [];
      final gpsAltRel = gps['alt_rel'] as List? ?? [];
      final gpsFixType = gps['fix_type'] as List? ?? [];
      final gpsSats = gps['satellites'] as List? ?? [];
      final gpsHdop = gps['hdop'] as List? ?? [];

      final startTime = _parseTs(gpsTs.first);

      // Load attitude data
      final att = conn.fetch(
        'SELECT ts, roll, pitch, yaw, roll_spd, pitch_spd, yaw_spd '
        'FROM attitude ORDER BY ts',
      );
      final attTs = (att['ts'] as List? ?? []).map(_parseTs).toList();
      final attRoll = att['roll'] as List? ?? [];
      final attPitch = att['pitch'] as List? ?? [];
      final attYaw = att['yaw'] as List? ?? [];
      final attRollSpd = att['roll_spd'] as List? ?? [];
      final attPitchSpd = att['pitch_spd'] as List? ?? [];
      final attYawSpd = att['yaw_spd'] as List? ?? [];

      // Load VFR HUD
      final vfr = conn.fetch(
        'SELECT ts, airspeed, groundspeed, heading, throttle, climb '
        'FROM vfr_hud ORDER BY ts',
      );
      final vfrTs = (vfr['ts'] as List? ?? []).map(_parseTs).toList();
      final vfrAirspeed = vfr['airspeed'] as List? ?? [];
      final vfrGs = vfr['groundspeed'] as List? ?? [];
      final vfrHeading = vfr['heading'] as List? ?? [];
      final vfrThrottle = vfr['throttle'] as List? ?? [];
      final vfrClimb = vfr['climb'] as List? ?? [];

      // Load battery
      final bat = conn.fetch(
        'SELECT ts, voltage, current_a, remaining_pct FROM battery ORDER BY ts',
      );
      final batTs = (bat['ts'] as List? ?? []).map(_parseTs).toList();
      final batVoltage = bat['voltage'] as List? ?? [];
      final batCurrent = bat['current_a'] as List? ?? [];
      final batRemaining = bat['remaining_pct'] as List? ?? [];

      // Load vibration
      final vib = conn.fetch(
        'SELECT ts, vibe_x, vibe_y, vibe_z FROM vibration ORDER BY ts',
      );
      final vibTs = (vib['ts'] as List? ?? []).map(_parseTs).toList();

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

        // Advance attitude index
        while (attIdx < attTs.length - 1 && attTs[attIdx + 1].compareTo(ts) <= 0) {
          attIdx++;
        }
        // Advance VFR index
        while (vfrIdx < vfrTs.length - 1 && vfrTs[vfrIdx + 1].compareTo(ts) <= 0) {
          vfrIdx++;
        }
        // Advance battery index
        while (batIdx < batTs.length - 1 && batTs[batIdx + 1].compareTo(ts) <= 0) {
          batIdx++;
        }
        // Advance vibration index
        while (vibIdx < vibTs.length - 1 && vibTs[vibIdx + 1].compareTo(ts) <= 0) {
          vibIdx++;
        }

        final state = VehicleState(
          // Position
          latitude: _toDouble(gpsLat, i),
          longitude: _toDouble(gpsLon, i),
          altitudeMsl: _toDouble(gpsAltMsl, i),
          altitudeRel: _toDouble(gpsAltRel, i),
          gpsFix: _toGpsFix(_toInt(gpsFixType, i)),
          satellites: _toInt(gpsSats, i),
          hdop: _toDouble(gpsHdop, i),
          // Attitude
          roll: attTs.isNotEmpty ? _toDouble(attRoll, attIdx) : 0,
          pitch: attTs.isNotEmpty ? _toDouble(attPitch, attIdx) : 0,
          yaw: attTs.isNotEmpty ? _toDouble(attYaw, attIdx) : 0,
          rollSpeed: attTs.isNotEmpty ? _toDouble(attRollSpd, attIdx) : 0,
          pitchSpeed: attTs.isNotEmpty ? _toDouble(attPitchSpd, attIdx) : 0,
          yawSpeed: attTs.isNotEmpty ? _toDouble(attYawSpd, attIdx) : 0,
          // Speed
          airspeed: vfrTs.isNotEmpty ? _toDouble(vfrAirspeed, vfrIdx) : 0,
          groundspeed: vfrTs.isNotEmpty ? _toDouble(vfrGs, vfrIdx) : 0,
          heading: vfrTs.isNotEmpty ? _toInt(vfrHeading, vfrIdx) : 0,
          throttle: vfrTs.isNotEmpty ? _toInt(vfrThrottle, vfrIdx) : 0,
          climbRate: vfrTs.isNotEmpty ? _toDouble(vfrClimb, vfrIdx) : 0,
          // Battery
          batteryVoltage: batTs.isNotEmpty ? _toDouble(batVoltage, batIdx) : 0,
          batteryCurrent: batTs.isNotEmpty ? _toDouble(batCurrent, batIdx) : 0,
          batteryRemaining: batTs.isNotEmpty ? _toInt(batRemaining, batIdx) : -1,
          // Mark as connected for PFD rendering
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

  /// Start or resume playback.
  void play() {
    if (_snapshots.isEmpty) return;
    if (_state == ReplayState.playing) return;

    _playbackStartTime = currentTime;
    _playbackClock.reset();
    _playbackClock.start();

    // Tick at ~30Hz for smooth PFD animation
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => _tick(),
    );

    _setState(ReplayState.playing);
  }

  /// Pause playback.
  void pause() {
    if (_state != ReplayState.playing) return;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _playbackClock.stop();
    _playbackStartTime = currentTime;
    _setState(ReplayState.paused);
  }

  /// Toggle play/pause.
  void togglePlayPause() {
    if (_state == ReplayState.playing) {
      pause();
    } else if (_state == ReplayState.paused) {
      play();
    }
  }

  /// Seek to a specific time in seconds.
  void seekTo(double timeSeconds) {
    if (_snapshots.isEmpty) return;
    final clamped = timeSeconds.clamp(0.0, _totalDuration);

    // Binary search for nearest snapshot
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

  /// Set playback speed.
  void setSpeed(ReplaySpeed newSpeed) {
    if (_state == ReplayState.playing) {
      // Preserve current position when changing speed
      _playbackStartTime = currentTime;
      _playbackClock.reset();
      _playbackClock.start();
    }
    _speed = newSpeed;
  }

  /// Step forward one snapshot (when paused).
  void stepForward() {
    if (_state != ReplayState.paused) return;
    if (_currentIndex < _snapshots.length - 1) {
      _currentIndex++;
      _playbackStartTime = _snapshots[_currentIndex].timeSeconds;
      _emitCurrentState();
    }
  }

  /// Step backward one snapshot (when paused).
  void stepBackward() {
    if (_state != ReplayState.paused) return;
    if (_currentIndex > 0) {
      _currentIndex--;
      _playbackStartTime = _snapshots[_currentIndex].timeSeconds;
      _emitCurrentState();
    }
  }

  /// Stop replay and return to idle.
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
      // Reached end of flight
      _currentIndex = _snapshots.length - 1;
      pause();
      _emitCurrentState();
      return;
    }

    // Advance _currentIndex to match time
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
