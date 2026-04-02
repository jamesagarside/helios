/// Full-featured MAVLink simulator for Helios GCS development.
///
/// Simulates everything needed to test all Sprint 1-2 features without hardware:
/// - 1-2 vehicles (quadrotor + fixed-wing) with realistic flight patterns
/// - AUTOPILOT_VERSION responses (firmware detection)
/// - MOUNT_STATUS (gimbal feedback, tracks commanded position)
/// - COMMAND_ACK for all incoming commands
/// - EKF_STATUS_REPORT
/// - Mode changes and status text events
/// - Mission current waypoint progression
///
/// Run with: dart run scripts/sim_full.dart [--multi]
///   --multi    Simulate 2 vehicles (quad sysid=1, plane sysid=2)
///
/// Connect Helios via UDP 127.0.0.1:14550

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../packages/dart_mavlink/lib/src/crc.dart';
import '../packages/dart_mavlink/lib/src/mavlink_types.dart';

late RawDatagramSocket _socket;
final _rng = Random();

// --------------------------------------------------------------------------
// Vehicle state
// --------------------------------------------------------------------------

class SimVehicle {
  SimVehicle({
    required this.sysId,
    required this.type,
    required this.label,
    required this.lat0,
    required this.lon0,
    this.isQuad = false,
  });

  final int sysId;
  final int type; // MAV_TYPE
  final String label;
  final double lat0;
  final double lon0;
  final bool isQuad;

  int compId = 1;
  int sequence = 0;
  int bootMs = 0;

  // Attitude
  double roll = 0, pitch = 0, yaw = 0;
  double heading = 0;

  // Position
  double lat = 0, lon = 0;
  double altMsl = 0, altRel = 0;
  double climbRate = 0;

  // Speed
  double airspeed = 0, groundspeed = 0;
  int throttle = 50;

  // Battery
  double voltage = 12.6;
  double current = 15.0;
  int batteryPct = 92;

  // Status
  int customMode = 10; // AUTO
  bool armed = true;
  int currentWaypoint = 1;

  // Gimbal (simulated feedback)
  double gimbalPitch = 0;
  double gimbalYaw = 0;
  double gimbalRoll = 0;

  // EKF
  double ekfVelVar = 0.15;
  double ekfPosHVar = 0.12;
  double ekfPosVVar = 0.18;
  double ekfCompVar = 0.08;
  double ekfTerrVar = 0.05;

  void init() {
    lat = lat0;
    lon = lon0;
    altRel = isQuad ? 50 : 100;
    altMsl = 584 + altRel;
    airspeed = isQuad ? 5.0 : 22.0;
    groundspeed = isQuad ? 3.0 : 24.0;
  }
}

late List<SimVehicle> _vehicles;
bool _multiVehicle = false;

// --------------------------------------------------------------------------
// Main
// --------------------------------------------------------------------------

void main(List<String> args) async {
  _multiVehicle = args.contains('--multi');

  _vehicles = [
    SimVehicle(
      sysId: 1,
      type: MavType.quadrotor,
      label: 'Quad-1',
      lat0: -35.3632621,
      lon0: 149.1652374,
      isQuad: true,
    ),
  ];

  if (_multiVehicle) {
    _vehicles.add(SimVehicle(
      sysId: 2,
      type: MavType.fixedWing,
      label: 'Plane-2',
      lat0: -35.3650,
      lon0: 149.1670,
    ));
  }

  for (final v in _vehicles) {
    v.init();
  }

  _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

  print('Helios Full Simulator');
  print('Vehicles: ${_vehicles.map((v) => '${v.label} (sysId=${v.sysId})').join(', ')}');
  print('Target: UDP 127.0.0.1:14550');
  print('');

  // Listen for incoming GCS messages (heartbeats, commands)
  _socket.listen((event) {
    if (event == RawSocketEvent.read) {
      final dg = _socket.receive();
      if (dg != null) _handleIncoming(dg.data);
    }
  });

  // Heartbeat + low-rate telemetry at 1 Hz
  Timer.periodic(const Duration(seconds: 1), (_) {
    for (final v in _vehicles) {
      v.bootMs += 1000;
      _simulateBattery(v);
      _simulateModeChange(v);
      _sendHeartbeat(v);
      _sendSysStatus(v);
      _sendVibration(v);
      _sendEkfStatus(v);
      _sendMountStatus(v);

      // Advance waypoint every 20 seconds
      if (v.bootMs % 20000 == 0 && v.armed) {
        v.currentWaypoint = (v.currentWaypoint % 8) + 1;
        _sendMissionCurrent(v);
        _sendStatusText(v, 'Reached WP ${v.currentWaypoint}');
      }
    }

    // Console output
    for (final v in _vehicles) {
      stdout.write(
        '[${v.label}] HDG:${v.heading.toStringAsFixed(0).padLeft(3)}\u00B0 '
        'ALT:${v.altRel.toStringAsFixed(0).padLeft(4)}m '
        'BAT:${v.voltage.toStringAsFixed(1)}V '
        'GIM:P${v.gimbalPitch.toStringAsFixed(0)} Y${v.gimbalYaw.toStringAsFixed(0)}  ',
      );
    }
    stdout.writeln();
  });

  // Attitude at 20 Hz
  Timer.periodic(const Duration(milliseconds: 50), (_) {
    for (final v in _vehicles) {
      v.bootMs += 50;
      _simulateAttitude(v);
      _sendAttitude(v);
    }
  });

  // GPS + VFR_HUD at 5 Hz
  Timer.periodic(const Duration(milliseconds: 200), (_) {
    for (final v in _vehicles) {
      _simulatePosition(v);
      _sendGlobalPositionInt(v);
      _sendGpsRawInt(v);
      _sendVfrHud(v);
    }
  });
}

// --------------------------------------------------------------------------
// Simulation logic
// --------------------------------------------------------------------------

void _simulateAttitude(SimVehicle v) {
  final t = v.bootMs / 1000.0;
  if (v.isQuad) {
    // Quad: gentle hovering with small oscillations
    v.roll = 0.05 * sin(t * 1.2);
    v.pitch = 0.03 * sin(t * 0.8);
    v.heading = (t * 15) % 360; // slow yaw rotation
  } else {
    // Plane: banking turn
    v.roll = 0.26; // ~15 deg bank
    v.pitch = 0.05 + 0.02 * sin(t * 0.5);
    v.heading = (t * 5) % 360;
  }
  v.yaw = v.heading * pi / 180;
}

void _simulatePosition(SimVehicle v) {
  final t = v.bootMs / 1000.0;
  final radius = v.isQuad ? 0.001 : 0.002;
  final angularRate = v.isQuad ? 0.262 : 0.087; // rad/s

  v.lat = v.lat0 + radius * cos(t * angularRate);
  v.lon = v.lon0 + radius * sin(t * angularRate);
  v.altRel = (v.isQuad ? 50 : 100) + 5 * sin(t * 0.3);
  v.altMsl = 584 + v.altRel;
  v.climbRate = 5 * 0.3 * cos(t * 0.3);
  v.groundspeed = v.airspeed + 2 * sin(t * 0.2);
}

void _simulateBattery(SimVehicle v) {
  v.voltage = max(10.0, v.voltage - 0.001);
  v.batteryPct = max(0, (v.batteryPct - 0.02).round());
  v.current = 15.0 + 2 * _rng.nextDouble();
}

void _simulateModeChange(SimVehicle v) {
  // Simulate occasional mode changes
  if (v.bootMs == 5000) {
    v.armed = true;
    _sendStatusText(v, 'Arming motors');
  }
  if (v.bootMs == 8000) {
    _sendStatusText(v, 'Mode change to AUTO');
  }
}

// --------------------------------------------------------------------------
// Incoming message handling (GCS → vehicle)
// --------------------------------------------------------------------------

void _handleIncoming(Uint8List data) {
  // Basic MAVLink v2 parse to handle COMMAND_LONG
  if (data.length < 12 || data[0] != 0xFD) return;

  final payloadLen = data[1];
  final msgId = data[7] | (data[8] << 8) | (data[9] << 16);

  if (data.length < 12 + payloadLen) return;
  final payload = Uint8List.sublistView(data, 10, 10 + payloadLen);

  if (msgId == 76) {
    // COMMAND_LONG
    _handleCommandLong(payload);
  }
}

void _handleCommandLong(Uint8List payload) {
  if (payload.length < 33) return;
  final d = ByteData.sublistView(payload);

  final targetSys = d.getUint8(30);
  final command = d.getUint16(28, Endian.little);
  final param1 = d.getFloat32(0, Endian.little);
  final param2 = d.getFloat32(4, Endian.little);
  final param3 = d.getFloat32(8, Endian.little);

  final vehicle = _vehicles.where((v) => v.sysId == targetSys).firstOrNull;
  if (vehicle == null && _vehicles.isNotEmpty) {
    // Target any vehicle
    _handleCommand(_vehicles.first, command, param1, param2, param3);
  } else if (vehicle != null) {
    _handleCommand(vehicle, command, param1, param2, param3);
  }
}

void _handleCommand(
    SimVehicle v, int command, double p1, double p2, double p3) {
  switch (command) {
    case 512: // MAV_CMD_REQUEST_MESSAGE
      final msgId = p1.toInt();
      if (msgId == 148) {
        // Request for AUTOPILOT_VERSION
        _sendAutopilotVersion(v);
      }
      _sendCommandAck(v, command, 0); // MAV_RESULT_ACCEPTED

    case 511: // MAV_CMD_SET_MESSAGE_INTERVAL
      _sendCommandAck(v, command, 0);

    case 400: // COMPONENT_ARM_DISARM
      v.armed = p1 == 1.0;
      _sendCommandAck(v, command, 0);
      _sendStatusText(v, v.armed ? 'Arming motors' : 'Disarming motors');

    case 176: // DO_SET_MODE
      v.customMode = p2.toInt();
      _sendCommandAck(v, command, 0);
      _sendStatusText(v, 'Mode change to MODE_${v.customMode}');

    case 205: // DO_MOUNT_CONTROL
      v.gimbalPitch = p1;
      v.gimbalRoll = p2;
      v.gimbalYaw = p3;
      _sendCommandAck(v, command, 0);

    case 203: // DO_DIGICAM_CONTROL
      _sendCommandAck(v, command, 0);
      _sendStatusText(v, 'Camera: capture triggered');

    default:
      _sendCommandAck(v, command, 0);
  }
}

// --------------------------------------------------------------------------
// Message senders
// --------------------------------------------------------------------------

void _send(SimVehicle v, int msgId, Uint8List payload) {
  final frameSize = 10 + payload.length + 2;
  final frame = Uint8List(frameSize);

  frame[0] = 0xFD;
  frame[1] = payload.length;
  frame[2] = 0;
  frame[3] = 0;
  frame[4] = v.sequence++ & 0xFF;
  frame[5] = v.sysId;
  frame[6] = v.compId;
  frame[7] = msgId & 0xFF;
  frame[8] = (msgId >> 8) & 0xFF;
  frame[9] = (msgId >> 16) & 0xFF;

  frame.setRange(10, 10 + payload.length, payload);

  final header = Uint8List.sublistView(frame, 0, 10);
  final crcExtra = mavlinkCrcExtras[msgId] ?? 0;
  final crc = MavlinkCrc.computeFrameCrc(
    header: header,
    payload: payload,
    crcExtra: crcExtra,
  );
  frame[frameSize - 2] = crc & 0xFF;
  frame[frameSize - 1] = (crc >> 8) & 0xFF;

  _socket.send(frame, InternetAddress('127.0.0.1'), 14550);
}

void _sendHeartbeat(SimVehicle v) {
  final p = Uint8List(9);
  final d = ByteData.sublistView(p);
  d.setUint32(0, v.customMode, Endian.little);
  p[4] = v.type;
  p[5] = MavAutopilot.ardupilotmega;
  p[6] = v.armed ? 0xC1 : 0x41;
  p[7] = 4; // MAV_STATE_ACTIVE
  p[8] = 3;
  _send(v, 0, p);
}

void _sendAttitude(SimVehicle v) {
  final p = Uint8List(28);
  final d = ByteData.sublistView(p);
  d.setUint32(0, v.bootMs, Endian.little);
  d.setFloat32(4, v.roll, Endian.little);
  d.setFloat32(8, v.pitch, Endian.little);
  d.setFloat32(12, v.yaw, Endian.little);
  d.setFloat32(16, 0.01, Endian.little);
  d.setFloat32(20, 0.005, Endian.little);
  d.setFloat32(24, 0.087, Endian.little);
  _send(v, 30, p);
}

void _sendGlobalPositionInt(SimVehicle v) {
  final p = Uint8List(28);
  final d = ByteData.sublistView(p);
  d.setUint32(0, v.bootMs, Endian.little);
  d.setInt32(4, (v.lat * 1e7).round(), Endian.little);
  d.setInt32(8, (v.lon * 1e7).round(), Endian.little);
  d.setInt32(12, (v.altMsl * 1000).round(), Endian.little);
  d.setInt32(16, (v.altRel * 1000).round(), Endian.little);
  d.setInt16(20, (v.groundspeed * 100).round(), Endian.little);
  d.setInt16(22, 0, Endian.little);
  d.setInt16(24, (v.climbRate * -100).round(), Endian.little);
  d.setUint16(26, (v.heading * 100).round(), Endian.little);
  _send(v, 33, p);
}

void _sendGpsRawInt(SimVehicle v) {
  final p = Uint8List(30);
  final d = ByteData.sublistView(p);
  d.setUint64(0, v.bootMs * 1000, Endian.little);
  d.setInt32(8, (v.lat * 1e7).round(), Endian.little);
  d.setInt32(12, (v.lon * 1e7).round(), Endian.little);
  d.setInt32(16, (v.altMsl * 1000).round(), Endian.little);
  d.setUint16(20, 85, Endian.little); // HDOP 0.85
  d.setUint16(22, 120, Endian.little);
  d.setUint16(24, (v.groundspeed * 100).round(), Endian.little);
  d.setUint16(26, (v.heading * 100).round(), Endian.little);
  p[28] = 3; // 3D fix
  p[29] = 14; // 14 sats
  _send(v, 24, p);
}

void _sendSysStatus(SimVehicle v) {
  final p = Uint8List(31);
  final d = ByteData.sublistView(p);
  d.setUint16(14, (v.voltage * 1000).round(), Endian.little);
  d.setInt16(16, (v.current * 100).round(), Endian.little);
  p[30] = v.batteryPct;
  _send(v, 1, p);
}

void _sendVfrHud(SimVehicle v) {
  final p = Uint8List(20);
  final d = ByteData.sublistView(p);
  d.setFloat32(0, v.airspeed, Endian.little);
  d.setFloat32(4, v.groundspeed, Endian.little);
  d.setFloat32(8, v.altMsl, Endian.little);
  d.setFloat32(12, v.climbRate, Endian.little);
  d.setInt16(16, v.heading.round(), Endian.little);
  d.setUint16(18, v.throttle, Endian.little);
  _send(v, 74, p);
}

void _sendVibration(SimVehicle v) {
  final p = Uint8List(32);
  final d = ByteData.sublistView(p);
  d.setUint64(0, v.bootMs * 1000, Endian.little);
  d.setFloat32(8, 15 + _rng.nextDouble() * 5, Endian.little);
  d.setFloat32(12, 12 + _rng.nextDouble() * 4, Endian.little);
  d.setFloat32(16, 18 + _rng.nextDouble() * 6, Endian.little);
  _send(v, 241, p);
}

void _sendEkfStatus(SimVehicle v) {
  final p = Uint8List(22);
  final d = ByteData.sublistView(p);
  d.setFloat32(0, v.ekfVelVar + _rng.nextDouble() * 0.05, Endian.little);
  d.setFloat32(4, v.ekfPosHVar + _rng.nextDouble() * 0.03, Endian.little);
  d.setFloat32(8, v.ekfPosVVar + _rng.nextDouble() * 0.04, Endian.little);
  d.setFloat32(12, v.ekfCompVar + _rng.nextDouble() * 0.02, Endian.little);
  d.setFloat32(16, v.ekfTerrVar + _rng.nextDouble() * 0.01, Endian.little);
  d.setUint16(20, 0, Endian.little); // flags
  _send(v, 193, p);
}

void _sendCommandAck(SimVehicle v, int command, int result) {
  final p = Uint8List(3);
  final d = ByteData.sublistView(p);
  d.setUint16(0, command, Endian.little);
  p[2] = result; // MAV_RESULT
  _send(v, 77, p);
}

void _sendAutopilotVersion(SimVehicle v) {
  final p = Uint8List(60);
  final d = ByteData.sublistView(p);

  // capabilities (mission, fence, rally, terrain, etc.)
  d.setUint64(0, 0x000000000001FFFF, Endian.little);

  // flight_sw_version: 4.5.1 release (packed: major<<24 | minor<<16 | patch<<8 | type)
  d.setUint32(8, (4 << 24) | (5 << 16) | (1 << 8) | 255, Endian.little);

  // middleware_sw_version
  d.setUint32(12, 0, Endian.little);

  // os_sw_version
  d.setUint32(16, (5 << 24) | (15 << 16), Endian.little);

  // board_version
  d.setUint32(20, 140, Endian.little);

  // flight_custom_version (8 bytes) — git hash
  for (var i = 24; i < 32; i++) {
    p[i] = _rng.nextInt(256);
  }
  // middleware_custom_version (8 bytes)
  // os_custom_version (8 bytes)
  // Skip to vendor/product/uid

  // vendor_id
  d.setUint16(48, 0x1209, Endian.little); // Example: ArduPilot

  // product_id
  d.setUint16(50, 0x5740, Endian.little);

  // uid (unique hardware ID)
  d.setUint64(52, 0xDEADBEEF12345678, Endian.little);

  _send(v, 148, p);
}

void _sendMountStatus(SimVehicle v) {
  // MOUNT_STATUS (msg_id=158)
  final p = Uint8List(14);
  final d = ByteData.sublistView(p);
  d.setInt32(0, (v.gimbalPitch * 100).round(), Endian.little); // pointing_a (pitch)
  d.setInt32(4, (v.gimbalRoll * 100).round(), Endian.little); // pointing_b (roll)
  d.setInt32(8, (v.gimbalYaw * 100).round(), Endian.little); // pointing_c (yaw)
  p[12] = 0; // target_system
  p[13] = 0; // target_component
  _send(v, 158, p);
}

void _sendMissionCurrent(SimVehicle v) {
  final p = Uint8List(2);
  final d = ByteData.sublistView(p);
  d.setUint16(0, v.currentWaypoint, Endian.little);
  _send(v, 42, p);
}

void _sendStatusText(SimVehicle v, String text) {
  final bytes = text.codeUnits;
  final p = Uint8List(51);
  p[0] = MavSeverity.info; // severity
  final len = min(bytes.length, 50);
  for (var i = 0; i < len; i++) {
    p[1 + i] = bytes[i];
  }
  _send(v, 253, p);
}
