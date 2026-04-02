import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:helios_gcs/core/mavlink/transports/transport.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';

/// A simulated ArduPilot flight controller for testing.
///
/// Connects via a [LoopbackTransport] and generates realistic MAVLink telemetry:
/// heartbeats, attitude, position, GPS, battery, sensors, and responds to
/// commands (arm/disarm, mode changes, takeoff).
///
/// Usage:
/// ```dart
/// final fc = MockFlightController();
/// final transport = fc.transport;
/// // Wire transport into MavlinkService or ConnectionController
/// fc.start();
/// // ... run tests ...
/// fc.stop();
/// ```
class MockFlightController {
  MockFlightController({
    this.vehicleType = MavType.quadrotor,
    this.autopilot = MavAutopilot.ardupilotmega,
    this.systemId = 1,
    this.componentId = 1,
    this.latitude = -35.363261,
    this.longitude = 149.165230,
    this.altitudeMsl = 584.0,
  });

  final int vehicleType;
  final int autopilot;
  final int systemId;
  final int componentId;

  // Simulated state
  double latitude;
  double longitude;
  double altitudeMsl;
  double altitudeRel = 0;
  double roll = 0;
  double pitch = 0;
  double yaw = 0;
  double heading = 0;
  double groundspeed = 0;
  double airspeed = 0;
  double climbRate = 0;
  double batteryVoltage = 12.6;
  double batteryCurrent = 5.0;
  int batteryRemaining = 100;
  int satellites = 12;
  int gpsFix = 3; // 3D fix
  double hdop = 0.9;
  bool armed = false;
  int customMode = 0; // STABILIZE
  int baseMode = 0;
  int sensorPresent = 0x1FFFFFF;
  int sensorEnabled = 0x1FFFFFF;
  int sensorHealth = 0x1FFFFFF;

  // Parameter store
  final Map<String, double> params = {
    'ARMING_CHECK': 1,
    'FS_BATT_ENABLE': 1,
    'FS_BATT_VOLTAGE': 10.5,
    'FS_BATT_MAH': 0,
    'FS_THR_ENABLE': 1,
    'FS_THR_VALUE': 975,
    'FS_GCS_ENABLE': 1,
    'FENCE_ENABLE': 0,
    'FENCE_ACTION': 1,
    'FENCE_ALT_MAX': 100,
    'FENCE_RADIUS': 300,
    'FRAME_CLASS': 1,
    'FRAME_TYPE': 1,
  };

  late final LoopbackTransport transport = LoopbackTransport();
  final MavlinkParser _parser = MavlinkParser();

  Timer? _heartbeatTimer;
  Timer? _attitudeTimer;
  Timer? _positionTimer;
  Timer? _sysStatusTimer;
  Timer? _gpsTimer;
  Timer? _vfrTimer;
  StreamSubscription<Uint8List>? _incomingSub;

  int _sequence = 0;

  /// Start generating telemetry.
  void start() {
    // Listen for incoming commands from the GCS
    _incomingSub = transport.gcsToFc.listen(_handleIncoming);

    // Heartbeat at 1 Hz
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sendHeartbeat();
    });

    // Attitude at 10 Hz
    _attitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _sendAttitude();
    });

    // Position at 5 Hz
    _positionTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _sendGlobalPositionInt();
    });

    // SYS_STATUS at 1 Hz
    _sysStatusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sendSysStatus();
    });

    // GPS_RAW_INT at 2 Hz
    _gpsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _sendGpsRawInt();
    });

    // VFR_HUD at 5 Hz
    _vfrTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _sendVfrHud();
    });

    // Initial heartbeat immediately
    _sendHeartbeat();
  }

  /// Stop all telemetry generation.
  void stop() {
    _heartbeatTimer?.cancel();
    _attitudeTimer?.cancel();
    _positionTimer?.cancel();
    _sysStatusTimer?.cancel();
    _gpsTimer?.cancel();
    _vfrTimer?.cancel();
    _incomingSub?.cancel();
  }

  /// Simulate flight: slowly climb, drift, and drain battery.
  void simulateFlight({Duration duration = const Duration(seconds: 10)}) {
    armed = true;
    baseMode = MavModeFlag.safetyArmed | MavModeFlag.guidedEnabled;
    customMode = 4; // GUIDED
    altitudeRel = 0;

    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (timer.tick * 100 > duration.inMilliseconds) {
        timer.cancel();
        return;
      }
      // Climb for first 3 seconds
      if (altitudeRel < 20) {
        altitudeRel += 0.5;
        climbRate = 5.0;
      } else {
        climbRate = 0;
      }
      // Drift slightly
      latitude += 0.000001;
      longitude += 0.0000005;
      heading = (heading + 0.5) % 360;
      groundspeed = 2.0;
      // Drain battery
      batteryRemaining = (batteryRemaining - 0.01).round().clamp(0, 100);
      batteryVoltage = 10.5 + (batteryRemaining / 100.0) * 2.1;
      // Gentle attitude oscillation
      roll = 0.05 * math.sin(timer.tick * 0.1);
      pitch = 0.03 * math.cos(timer.tick * 0.08);
    });
  }

  // ─── Command handling ────────────────────────────────────────────────────

  void _handleIncoming(Uint8List data) {
    _parser.parse(data);
    final messages = _parser.takeMessages();
    for (final msg in messages) {
      switch (msg) {
        case HeartbeatMessage():
          break; // GCS heartbeat — ignore
        case ParamRequestListMessage():
          _sendAllParams();
        case ParamSetMessage():
          _handleParamSet(msg);
        case MissionRequestListMessage():
          _sendMissionCount(0);
        case UnknownMessage() when msg.messageId == 76: // COMMAND_LONG
          _handleCommandLong(msg.payload);
        default:
          break;
      }
    }
  }

  /// Parse COMMAND_LONG (msg_id=76) from raw payload and respond.
  void _handleCommandLong(Uint8List payload) {
    if (payload.length < 33) return;
    final data = ByteData.sublistView(payload);
    final param1 = data.getFloat32(0, Endian.little);
    final param2 = data.getFloat32(4, Endian.little);
    final param7 = data.getFloat32(24, Endian.little);
    final command = data.getUint16(28, Endian.little);

    switch (command) {
      case MavCmd.componentArmDisarm:
        armed = param1 > 0;
        baseMode = armed
            ? baseMode | MavModeFlag.safetyArmed
            : baseMode & ~MavModeFlag.safetyArmed;
        _sendCommandAck(command, 0);
      case MavCmd.doSetMode:
        customMode = param2.toInt();
        _sendCommandAck(command, 0);
      case MavCmd.navTakeoff:
        altitudeRel = param7;
        climbRate = 3.0;
        _sendCommandAck(command, 0);
      case MavCmd.requestMessage:
        final msgId = param1.toInt();
        if (msgId == 148) _sendAutopilotVersion();
        _sendCommandAck(command, 0);
      case MavCmd.preflightCalibration:
        _sendCommandAck(command, 0);
        _sendStatusText('Calibration started', MavSeverity.info);
      case MavCmd.preflightRebootShutdown:
        _sendCommandAck(command, 0);
      default:
        _sendCommandAck(command, 0);
    }
  }

  void _handleParamSet(ParamSetMessage msg) {
    params[msg.paramId] = msg.paramValue;
    _sendParamValue(msg.paramId, msg.paramValue, params.keys.toList().indexOf(msg.paramId));
  }

  // ─── Message senders ─────────────────────────────────────────────────────

  void _sendHeartbeat() {
    final payload = Uint8List(9);
    final data = ByteData.sublistView(payload);
    data.setUint32(0, customMode, Endian.little);
    payload[4] = vehicleType;
    payload[5] = autopilot;
    payload[6] = baseMode;
    payload[7] = MavState.active;
    payload[8] = 3;
    _sendFrame(0, payload);
  }

  void _sendAttitude() {
    final payload = Uint8List(28);
    final data = ByteData.sublistView(payload);
    data.setUint32(0, DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF, Endian.little);
    data.setFloat32(4, roll, Endian.little);
    data.setFloat32(8, pitch, Endian.little);
    data.setFloat32(12, yaw, Endian.little);
    data.setFloat32(16, 0, Endian.little); // rollspeed
    data.setFloat32(20, 0, Endian.little); // pitchspeed
    data.setFloat32(24, 0, Endian.little); // yawspeed
    _sendFrame(30, payload);
  }

  void _sendGlobalPositionInt() {
    final payload = Uint8List(28);
    final data = ByteData.sublistView(payload);
    data.setUint32(0, DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF, Endian.little);
    data.setInt32(4, (latitude * 1e7).round(), Endian.little);
    data.setInt32(8, (longitude * 1e7).round(), Endian.little);
    data.setInt32(12, (altitudeMsl * 1000).round(), Endian.little);
    data.setInt32(16, (altitudeRel * 1000).round(), Endian.little);
    data.setInt16(20, 0, Endian.little); // vx
    data.setInt16(22, 0, Endian.little); // vy
    data.setInt16(24, 0, Endian.little); // vz
    data.setUint16(26, (heading * 100).round(), Endian.little);
    _sendFrame(33, payload);
  }

  void _sendSysStatus() {
    final payload = Uint8List(31);
    final data = ByteData.sublistView(payload);
    data.setUint32(0, sensorPresent, Endian.little);
    data.setUint32(4, sensorEnabled, Endian.little);
    data.setUint32(8, sensorHealth, Endian.little);
    data.setUint16(12, 0, Endian.little); // load
    data.setUint16(14, (batteryVoltage * 1000).round(), Endian.little);
    data.setInt16(16, (batteryCurrent * 100).round(), Endian.little);
    payload[30] = batteryRemaining.clamp(-1, 100);
    _sendFrame(1, payload);
  }

  void _sendGpsRawInt() {
    final payload = Uint8List(30);
    final data = ByteData.sublistView(payload);
    data.setUint64(0, DateTime.now().microsecondsSinceEpoch, Endian.little);
    data.setInt32(8, (latitude * 1e7).round(), Endian.little);
    data.setInt32(12, (longitude * 1e7).round(), Endian.little);
    data.setInt32(16, (altitudeMsl * 1000).round(), Endian.little);
    data.setUint16(20, (hdop * 100).round(), Endian.little);
    data.setUint16(22, 0xFFFF, Endian.little); // vdop
    data.setUint16(24, (groundspeed * 100).round(), Endian.little);
    data.setUint16(26, (heading * 100).round(), Endian.little);
    payload[28] = gpsFix;
    payload[29] = satellites;
    _sendFrame(24, payload);
  }

  void _sendVfrHud() {
    final payload = Uint8List(20);
    final data = ByteData.sublistView(payload);
    data.setFloat32(0, airspeed, Endian.little);
    data.setFloat32(4, groundspeed, Endian.little);
    data.setFloat32(8, climbRate, Endian.little);
    data.setInt16(12, heading.round(), Endian.little);
    data.setUint16(14, 0, Endian.little); // throttle
    data.setFloat32(16, altitudeMsl, Endian.little);
    _sendFrame(74, payload);
  }

  void _sendCommandAck(int command, int result) {
    final payload = Uint8List(10);
    final data = ByteData.sublistView(payload);
    data.setUint16(0, command, Endian.little);
    payload[2] = result;
    payload[3] = 0xFF; // progress
    data.setInt32(4, 0, Endian.little); // result_param2
    payload[8] = systemId;
    payload[9] = componentId;
    _sendFrame(77, payload);
  }

  void _sendAutopilotVersion() {
    final payload = Uint8List(60);
    final data = ByteData.sublistView(payload);
    data.setUint64(0, 0, Endian.little); // capabilities
    data.setUint32(8, (4 << 24) | (5 << 16) | (7 << 8), Endian.little); // fw version 4.5.7
    data.setUint32(12, 0, Endian.little); // middleware
    data.setUint32(16, 0, Endian.little); // os
    data.setUint32(20, 0, Endian.little); // board version
    _sendFrame(148, payload);
  }

  void _sendAllParams() {
    final keys = params.keys.toList();
    for (var i = 0; i < keys.length; i++) {
      _sendParamValue(keys[i], params[keys[i]]!, i, total: keys.length);
    }
  }

  void _sendParamValue(String paramId, double value, int index, {int? total}) {
    final payload = Uint8List(25);
    final data = ByteData.sublistView(payload);
    data.setFloat32(0, value, Endian.little);
    data.setUint16(4, total ?? params.length, Endian.little);
    data.setUint16(6, index, Endian.little);
    // param_id at offset 8, 16 chars
    final idBytes = paramId.codeUnits;
    for (var i = 0; i < 16 && i < idBytes.length; i++) {
      payload[8 + i] = idBytes[i];
    }
    payload[24] = 9; // MAV_PARAM_TYPE_REAL32
    _sendFrame(22, payload);
  }

  void _sendMissionCount(int count) {
    final payload = Uint8List(5);
    final data = ByteData.sublistView(payload);
    data.setUint16(0, count, Endian.little);
    payload[2] = 255; // target_system (GCS)
    payload[3] = 190; // target_component
    payload[4] = 0;   // mission_type
    _sendFrame(44, payload);
  }

  void _sendStatusText(String text, int severity) {
    final payload = Uint8List(54);
    payload[0] = severity;
    final bytes = text.codeUnits;
    for (var i = 0; i < 50 && i < bytes.length; i++) {
      payload[1 + i] = bytes[i];
    }
    _sendFrame(253, payload);
  }

  void _sendFrame(int messageId, Uint8List payload) {
    final frameSize = 10 + payload.length + 2;
    final frame = Uint8List(frameSize);
    frame[0] = 0xFD; // MAVLink v2 magic
    frame[1] = payload.length;
    frame[2] = 0;
    frame[3] = 0;
    frame[4] = _sequence++ & 0xFF;
    frame[5] = systemId;
    frame[6] = componentId;
    frame[7] = messageId & 0xFF;
    frame[8] = (messageId >> 8) & 0xFF;
    frame[9] = (messageId >> 16) & 0xFF;
    frame.setRange(10, 10 + payload.length, payload);

    // CRC
    final crcExtra = mavlinkCrcExtras[messageId] ?? 0;
    final header = Uint8List.sublistView(frame, 0, 10);
    final crc = MavlinkCrc.computeFrameCrc(
      header: header,
      payload: payload,
      crcExtra: crcExtra,
    );
    frame[frameSize - 2] = crc & 0xFF;
    frame[frameSize - 1] = (crc >> 8) & 0xFF;

    transport.fcToGcs(frame);
  }
}

/// A loopback transport that connects MockFlightController to MavlinkService.
///
/// Data sent by the GCS (via [send]) goes to [gcsToFc] stream (read by the FC).
/// Data sent by the FC (via [fcToGcs]) goes to [dataStream] (read by the GCS).
class LoopbackTransport implements MavlinkTransport {
  final _fcToGcsController = StreamController<Uint8List>.broadcast();
  final _gcsToFcController = StreamController<Uint8List>.broadcast();
  TransportState _state = TransportState.disconnected;
  final _stateController = StreamController<TransportState>.broadcast();

  /// Stream of data from FC to GCS (consumed by MavlinkService).
  @override
  Stream<Uint8List> get dataStream => _fcToGcsController.stream;

  /// Stream of data from GCS to FC (consumed by MockFlightController).
  Stream<Uint8List> get gcsToFc => _gcsToFcController.stream;

  /// Send data from FC to GCS.
  void fcToGcs(Uint8List data) {
    if (!_fcToGcsController.isClosed) {
      _fcToGcsController.add(data);
    }
  }

  @override
  TransportState get state => _state;

  @override
  Stream<TransportState> get stateStream => _stateController.stream;

  @override
  Future<void> connect() async {
    _state = TransportState.connected;
    _stateController.add(_state);
  }

  @override
  Future<void> send(Uint8List data) async {
    if (!_gcsToFcController.isClosed) {
      _gcsToFcController.add(data);
    }
  }

  @override
  Future<void> disconnect() async {
    _state = TransportState.disconnected;
    _stateController.add(_state);
  }

  @override
  void dispose() {
    _fcToGcsController.close();
    _gcsToFcController.close();
    _stateController.close();
  }
}
