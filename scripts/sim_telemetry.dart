/// Lightweight MAVLink telemetry simulator.
///
/// Sends realistic ArduPlane telemetry over UDP to localhost:14550.
/// Run with: dart run scripts/sim_telemetry.dart
///
/// Simulates a fixed-wing aircraft flying a circular pattern with:
/// - HEARTBEAT at 1 Hz
/// - ATTITUDE at 20 Hz
/// - GLOBAL_POSITION_INT at 5 Hz
/// - GPS_RAW_INT at 5 Hz
/// - SYS_STATUS at 1 Hz
/// - VFR_HUD at 5 Hz
/// - VIBRATION at 1 Hz

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

// Add the packages path
import '../packages/dart_mavlink/lib/src/crc.dart';
import '../packages/dart_mavlink/lib/src/mavlink_types.dart';

late RawDatagramSocket _socket;
InternetAddress? _gcsAddress;
int? _gcsPort;
int _sequence = 0;

const int _sysId = 1;
const int _compId = 1;

// Simulated aircraft state
double _roll = 0;
double _pitch = 0.05; // slight nose up
double _yaw = 0;
double _heading = 0;
double _lat = -35.3632621; // Canberra Model Aircraft Club
double _lon = 149.1652374;
double _altMsl = 600; // metres
double _altRel = 100;
double _airspeed = 22.0; // m/s
double _groundspeed = 24.0;
double _climbRate = 0.0;
int _throttle = 55;
double _voltage = 12.6;
double _current = 15.2;
int _batteryPct = 85;
int _customMode = 10; // AUTO
bool _armed = true;
int _bootMs = 0;

void main() async {
  _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  print('MAVLink Telemetry Simulator');
  print('Sending to localhost:14550');
  print('Simulating ArduPlane in AUTO mode, circular flight pattern');
  print('Press Ctrl+C to stop\n');

  // Listen for incoming packets (GCS heartbeats) to discover the GCS address
  _socket.listen((event) {
    if (event == RawSocketEvent.read) {
      final dg = _socket.receive();
      if (dg != null && _gcsAddress == null) {
        // Auto-discover GCS from incoming heartbeat
        // But for simplicity, we just send to localhost:14550
      }
    }
  });

  // Default target
  _gcsAddress = InternetAddress('127.0.0.1');
  _gcsPort = 14550;

  // HEARTBEAT at 1 Hz
  Timer.periodic(const Duration(seconds: 1), (_) {
    _sendHeartbeat();
    _sendSysStatus();
    _sendVibration();
    _simulateBattery();
    _bootMs += 1000;
    print(
      'HDG: ${_heading.toStringAsFixed(0).padLeft(3)}\u00B0 '
      'ALT: ${_altRel.toStringAsFixed(0).padLeft(4)}m '
      'IAS: ${_airspeed.toStringAsFixed(1)} '
      'BAT: ${_voltage.toStringAsFixed(1)}V ${_batteryPct}% '
      'MODE: AUTO'
    );
  });

  // ATTITUDE at 20 Hz
  Timer.periodic(const Duration(milliseconds: 50), (_) {
    _simulateAttitude();
    _sendAttitude();
    _bootMs += 50;
  });

  // GPS + VFR_HUD at 5 Hz
  Timer.periodic(const Duration(milliseconds: 200), (_) {
    _simulatePosition();
    _sendGlobalPositionInt();
    _sendGpsRawInt();
    _sendVfrHud();
  });
}

void _simulateAttitude() {
  // Circular flight: gentle 15-degree bank, constant heading change
  final t = _bootMs / 1000.0;
  _roll = 0.26; // ~15 degrees bank (radians)
  _pitch = 0.05 + 0.02 * sin(t * 0.5); // slight oscillation
  _heading = (t * 5) % 360; // 5 degrees/second turn rate
  _yaw = _heading * pi / 180;
}

void _simulatePosition() {
  // Circular path, radius ~200m
  final t = _bootMs / 1000.0;
  final radius = 0.002; // ~200m in degrees
  _lat = -35.3632621 + radius * cos(t * 0.087); // 0.087 rad/s ≈ 5°/s heading
  _lon = 149.1652374 + radius * sin(t * 0.087);
  _altRel = 100 + 5 * sin(t * 0.3); // gentle altitude oscillation
  _altMsl = 584 + _altRel;
  _climbRate = 5 * 0.3 * cos(t * 0.3);
  _groundspeed = _airspeed + 2 * sin(t * 0.2); // wind effect
}

void _simulateBattery() {
  // Slow discharge
  _voltage = max(10.0, _voltage - 0.001);
  _batteryPct = max(0, (_batteryPct - 0.02).round());
  _current = 15.0 + 2 * Random().nextDouble();
}

Uint8List _buildFrame(int msgId, Uint8List payload) {
  final frameSize = 10 + payload.length + 2;
  final frame = Uint8List(frameSize);

  frame[0] = 0xFD; // MAVLink v2 magic
  frame[1] = payload.length;
  frame[2] = 0; // incompat flags
  frame[3] = 0; // compat flags
  frame[4] = _sequence++ & 0xFF;
  frame[5] = _sysId;
  frame[6] = _compId;
  frame[7] = msgId & 0xFF;
  frame[8] = (msgId >> 8) & 0xFF;
  frame[9] = (msgId >> 16) & 0xFF;

  frame.setRange(10, 10 + payload.length, payload);

  // CRC
  final header = Uint8List.sublistView(frame, 0, 10);
  final crcExtra = mavlinkCrcExtras[msgId] ?? 0;
  final crc = MavlinkCrc.computeFrameCrc(
    header: header,
    payload: payload,
    crcExtra: crcExtra,
  );
  frame[frameSize - 2] = crc & 0xFF;
  frame[frameSize - 1] = (crc >> 8) & 0xFF;

  return frame;
}

void _send(Uint8List frame) {
  if (_gcsAddress != null && _gcsPort != null) {
    _socket.send(frame, _gcsAddress!, _gcsPort!);
  }
}

void _sendHeartbeat() {
  final payload = Uint8List(9);
  final d = ByteData.sublistView(payload);
  d.setUint32(0, _customMode, Endian.little);
  payload[4] = 1; // MAV_TYPE_FIXED_WING
  payload[5] = 3; // MAV_AUTOPILOT_ARDUPILOTMEGA
  payload[6] = _armed ? 0xC1 : 0x41; // base_mode: armed + guided + auto
  payload[7] = 4; // MAV_STATE_ACTIVE
  payload[8] = 3; // mavlink version
  _send(_buildFrame(0, payload));
}

void _sendAttitude() {
  final payload = Uint8List(28);
  final d = ByteData.sublistView(payload);
  d.setUint32(0, _bootMs, Endian.little);
  d.setFloat32(4, _roll, Endian.little);
  d.setFloat32(8, _pitch, Endian.little);
  d.setFloat32(12, _yaw, Endian.little);
  d.setFloat32(16, 0.01, Endian.little); // rollspeed
  d.setFloat32(20, 0.005, Endian.little); // pitchspeed
  d.setFloat32(24, 0.087, Endian.little); // yawspeed (5 deg/s)
  _send(_buildFrame(30, payload));
}

void _sendGlobalPositionInt() {
  final payload = Uint8List(28);
  final d = ByteData.sublistView(payload);
  d.setUint32(0, _bootMs, Endian.little);
  d.setInt32(4, (_lat * 1e7).round(), Endian.little);
  d.setInt32(8, (_lon * 1e7).round(), Endian.little);
  d.setInt32(12, (_altMsl * 1000).round(), Endian.little);
  d.setInt32(16, (_altRel * 1000).round(), Endian.little);
  d.setInt16(20, (_groundspeed * 100).round(), Endian.little);
  d.setInt16(22, 0, Endian.little);
  d.setInt16(24, (_climbRate * -100).round(), Endian.little);
  d.setUint16(26, (_heading * 100).round(), Endian.little);
  _send(_buildFrame(33, payload));
}

void _sendGpsRawInt() {
  final payload = Uint8List(30);
  final d = ByteData.sublistView(payload);
  d.setUint64(0, _bootMs * 1000, Endian.little); // usec
  d.setInt32(8, (_lat * 1e7).round(), Endian.little);
  d.setInt32(12, (_lon * 1e7).round(), Endian.little);
  d.setInt32(16, (_altMsl * 1000).round(), Endian.little);
  d.setUint16(20, 85, Endian.little); // eph (HDOP 0.85)
  d.setUint16(22, 120, Endian.little); // epv (VDOP 1.2)
  d.setUint16(24, (_groundspeed * 100).round(), Endian.little);
  d.setUint16(26, (_heading * 100).round(), Endian.little);
  payload[28] = 3; // GPS_FIX_TYPE_3D
  payload[29] = 14; // 14 satellites
  _send(_buildFrame(24, payload));
}

void _sendSysStatus() {
  final payload = Uint8List(31);
  final d = ByteData.sublistView(payload);
  d.setUint16(14, (_voltage * 1000).round(), Endian.little);
  d.setInt16(16, (_current * 100).round(), Endian.little);
  payload[30] = _batteryPct;
  _send(_buildFrame(1, payload));
}

void _sendVfrHud() {
  final payload = Uint8List(20);
  final d = ByteData.sublistView(payload);
  d.setFloat32(0, _airspeed, Endian.little);
  d.setFloat32(4, _groundspeed, Endian.little);
  d.setFloat32(8, _altMsl, Endian.little);
  d.setFloat32(12, _climbRate, Endian.little);
  d.setInt16(16, _heading.round(), Endian.little);
  d.setUint16(18, _throttle, Endian.little);
  _send(_buildFrame(74, payload));
}

void _sendVibration() {
  final payload = Uint8List(32);
  final d = ByteData.sublistView(payload);
  d.setUint64(0, _bootMs * 1000, Endian.little);
  d.setFloat32(8, 15.0 + Random().nextDouble() * 5, Endian.little); // vibe_x
  d.setFloat32(12, 12.0 + Random().nextDouble() * 4, Endian.little);
  d.setFloat32(16, 18.0 + Random().nextDouble() * 6, Endian.little);
  d.setUint32(20, 0, Endian.little); // clip counts
  d.setUint32(24, 0, Endian.little);
  d.setUint32(28, 0, Endian.little);
  _send(_buildFrame(241, payload));
}
