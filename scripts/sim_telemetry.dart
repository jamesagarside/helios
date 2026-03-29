/// Helios MAVLink Telemetry Simulator — UK Edition
///
/// ArduPlane survey flight over Hampshire, UK (Popham Airfield — EGHP).
/// Sends MAVLink v2 telemetry to a Helios GCS over UDP.
///
/// Run:  dart run scripts/sim_telemetry.dart
/// Env:  HELIOS_GCS_HOST  HELIOS_GCS_PORT  (defaults: 127.0.0.1:14550)
///
/// Flight lifecycle (repeating):
///   DISARMED (preflight) → ARMED (engine running) → TAKEOFF (climb-out)
///   → CRUISE (4-leg Hampshire survey) → RTL (at 25% battery)
///   → LANDING → DISARMED (battery swap) → …

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../packages/dart_mavlink/lib/src/crc.dart';
import '../packages/dart_mavlink/lib/src/mavlink_types.dart';

// ─── Configuration ─────────────────────────────────────────────────────────

typedef _Pos = ({double lat, double lon});

const _home = (lat: 51.1971, lon: -1.1482); // Popham Airfield (EGHP), Hampshire
const double _homeElev = 168.0; // m AMSL

const double _cruiseAlt = 350.0; // m AGL
const double _cruiseIas = 22.0; // m/s (~43 kts)
const double _rotateIas = 15.0; // m/s — liftoff speed
const double _battCap = 10000.0; // mAh (6S survey pack)

// Hampshire survey rectangle: Dummer → Oakley → North Waltham → Axford
const List<_Pos> _wps = [
  (lat: 51.2120, lon: -1.1000),
  (lat: 51.2120, lon: -1.1900),
  (lat: 51.1830, lon: -1.1900),
  (lat: 51.1830, lon: -1.1000),
];

// Prevailing SW wind at 7 m/s — pre-computed NE vector (from 225°)
const double _wN = 4.95; // m/s northward
const double _wE = 4.95; // m/s eastward

// ─── Flight phases ─────────────────────────────────────────────────────────

enum _Phase { disarmed, armed, takeoff, cruise, rtl, landing }

// MAVLink mode numbers for each phase
const _modeFor = {
  _Phase.disarmed: 0,  // MANUAL
  _Phase.armed:    0,  // MANUAL (armed, engine idling)
  _Phase.takeoff:  13, // TAKEOFF
  _Phase.cruise:   10, // AUTO
  _Phase.rtl:      11, // RTL
  _Phase.landing:  9,  // LAND
};

// ─── State ─────────────────────────────────────────────────────────────────

late RawDatagramSocket _socket;
InternetAddress? _gcsAddr;
int? _gcsPort;
int _seq = 0;
final _rng = Random();

const int _sysId = 1;
const int _compId = 1;

double _lat = _home.lat, _lon = _home.lon;
double _altRel = 0.0, _altMsl = _homeElev;
double _roll = 0.0, _pitch = 0.0, _heading = 45.0;
double _ias = 0.0, _gs = 0.0, _cr = 0.0;
int _thr = 0;
double _volt = 25.2, _amps = 0.0, _gust = 0.0;
int _batPct = 100;
double _mAh = 0.0;
int _bootMs = 0;
bool _armed = false;
_Phase _phase = _Phase.disarmed;
int _wpIdx = 0;

// ─── Entry point ──────────────────────────────────────────────────────────

void main() async {
  _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final host = Platform.environment['HELIOS_GCS_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(Platform.environment['HELIOS_GCS_PORT'] ?? '') ?? 14550;
  final resolved = await InternetAddress.lookup(host);
  _gcsAddr = resolved.first;
  _gcsPort = port;

  print('╔════════════════════════════════════════════╗');
  print('║   Helios MAVLink Simulator — UK Edition    ║');
  print('╠════════════════════════════════════════════╣');
  print('║  Base  : Popham Airfield (EGHP) Hampshire  ║');
  print('║  Route : 4-leg survey, Hampshire downs     ║');
  print('║  Wind  : SW 7 m/s (prevailing UK)          ║');
  print('║  GCS   : $host:$port');
  print('╚════════════════════════════════════════════╝\n');

  _scheduleArm(const Duration(seconds: 3));

  Timer.periodic(const Duration(milliseconds: 50), (_) => _step(0.05));
  Timer.periodic(const Duration(milliseconds: 200), (_) {
    _sendGlobalPositionInt();
    _sendGpsRawInt();
    _sendVfrHud();
  });
  Timer.periodic(const Duration(seconds: 1), (_) {
    _sendHeartbeat();
    _sendSysStatus();
    _sendVibration();
    _gust = (_gust + (_rng.nextDouble() * 2 - 1) * 0.6).clamp(-3.5, 3.5);
    _log();
  });
}

// ─── Phase transitions ─────────────────────────────────────────────────────

void _scheduleArm(Duration delay) {
  Future.delayed(delay, () {
    _transition(_Phase.armed);
    print('[SIM] Armed — engine running, pre-takeoff checks…');
    Future.delayed(const Duration(seconds: 4), () {
      if (_phase == _Phase.armed) _transition(_Phase.takeoff);
      print('[SIM] Takeoff roll — departing Popham on 045°');
    });
  });
}

void _transition(_Phase next) {
  _phase = next;
  _armed = next != _Phase.disarmed;
}

// ─── Physics step (dt = 0.05 s at 20 Hz) ─────────────────────────────────

void _step(double dt) {
  _bootMs += (dt * 1000).round();

  switch (_phase) {
    case _Phase.disarmed:
      break; // on ground, no movement

    case _Phase.armed:
      _thr = 15; // engine idling
      _ias = 0; _gs = 0; _cr = 0;

    case _Phase.takeoff:
      _thr = 85;
      _ias = min(_cruiseIas, _ias + 0.5); // takeoff roll acceleration
      _steer(_wps[0]); // track toward WP1 during climb-out
      if (_ias >= _rotateIas) {
        // Airborne — climb at 4 m/s until cruise altitude
        _cr += (4.0 - _cr) * 0.1;
        _altRel = max(0.0, _altRel + _cr * dt);
        _altMsl = _homeElev + _altRel;
        _pitch = 0.2; // climb attitude
        _moveAcrossGround(dt);
      }
      if (_altRel > 50) {
        _transition(_Phase.cruise);
        _thr = 55;
        print('[SIM] 50m AGL — survey commencing');
      }

    case _Phase.cruise:
      _thr = _altRel < _cruiseAlt - 10 ? 70 : 55;
      _ias = _cruiseIas;
      final wp = _wps[_wpIdx % _wps.length];
      if (_dist(wp.lat, wp.lon) < 80) {
        _wpIdx = (_wpIdx + 1) % _wps.length;
        print('[SIM] → WP${_wpIdx + 1}/${_wps.length}: ${_wps[_wpIdx]}');
      }
      _steer(wp);
      _holdAlt(_cruiseAlt, dt);
      _moveAcrossGround(dt);
      _dischargeBattery(dt);
      if (_batPct <= 25) {
        _transition(_Phase.rtl);
        print('[SIM] Battery ${_batPct}% — RTL to Popham');
      }

    case _Phase.rtl:
      _ias = _cruiseIas; _thr = 55;
      _steer(_home);
      _holdAlt(_cruiseAlt, dt);
      _moveAcrossGround(dt);
      _dischargeBattery(dt);
      if (_dist(_home.lat, _home.lon) < 400) {
        _transition(_Phase.landing);
        print('[SIM] Overhead Popham — final approach');
      }

    case _Phase.landing:
      _thr = max(0, _thr - 1);
      _ias = max(14.0, _ias - 0.04);
      _steer(_home);
      _holdAlt(0, dt);
      _moveAcrossGround(dt);
      _dischargeBattery(dt);
      if (_altRel <= 1.5 && _gs < 6) {
        _ias = 0; _gs = 0; _cr = 0; _thr = 0; _roll = 0; _pitch = 0;
        _transition(_Phase.disarmed);
        print('[SIM] Touchdown at Popham — battery swap, next flight in 15s');
        _wpIdx = 0;
        _volt = 25.2; _mAh = 0; _batPct = 100; _amps = 0;
        _scheduleArm(const Duration(seconds: 15));
      }
  }

  _sendAttitude();
}

// ─── Reusable flight helpers ───────────────────────────────────────────────

// Turn toward target, updating _heading and _roll
void _steer(_Pos tgt) {
  final err = _normAngle(_bearing(tgt.lat, tgt.lon) - _heading);
  _heading = (_heading + err.clamp(-3.0, 3.0) + 360) % 360;
  _roll = (err.clamp(-15.0, 15.0) * pi / 180 * 3.5).clamp(-pi / 4, pi / 4);
}

// Proportional altitude hold with pitch feedback
void _holdAlt(double target, double dt) {
  final targetCr = ((target - _altRel) * 0.3).clamp(-4.0, 5.0);
  _cr += (targetCr - _cr) * 0.1;
  _altRel = max(0.0, _altRel + _cr * dt);
  _altMsl = _homeElev + _altRel;
  _pitch = (targetCr * 0.04).clamp(-0.35, 0.35);
}

// Move lat/lon based on heading, airspeed, and wind
void _moveAcrossGround(double dt) {
  final hdg = _heading * pi / 180;
  final vgN = _ias * cos(hdg) + _wN + _gust * 0.5;
  final vgE = _ias * sin(hdg) + _wE + _gust * 0.3;
  _gs = sqrt(vgN * vgN + vgE * vgE);
  _lat += vgN * dt / 111320.0;
  _lon += vgE * dt / (111320.0 * cos(_lat * pi / 180));
}

// Battery discharge model (6S LiPo)
void _dischargeBattery(double dt) {
  _amps = (2.0 + _thr / 100 * 45 + max(0, _cr) * 3 + (_rng.nextDouble() - 0.5) * 1.5)
      .clamp(0.0, 60.0);
  _mAh += _amps * dt / 3.6;
  final soc = (1.0 - _mAh / _battCap).clamp(0.0, 1.0);
  _batPct = (soc * 100).round();
  _volt = 18.0 + soc * 7.2;
}

// ─── Console log ──────────────────────────────────────────────────────────

void _log() => print(
    '${_phase.name.toUpperCase().padRight(8)} '
    'WP${_wpIdx % _wps.length + 1}/${_wps.length} '
    'HDG:${_heading.toStringAsFixed(0).padLeft(3)}° '
    'ALT:${_altRel.toStringAsFixed(0).padLeft(4)}m '
    'IAS:${_ias.toStringAsFixed(1).padLeft(5)} '
    'BAT:${_batPct}% ${_volt.toStringAsFixed(1)}V',
  );

// ─── Geometry ─────────────────────────────────────────────────────────────

double _bearing(double toLat, double toLon) {
  final lat1 = _lat * pi / 180;
  final lat2 = toLat * pi / 180;
  final dLon = (toLon - _lon) * pi / 180;
  final y = sin(dLon) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
  return (atan2(y, x) * 180 / pi + 360) % 360;
}

double _dist(double toLat, double toLon) {
  final dLat = (toLat - _lat) * pi / 180;
  final dLon = (toLon - _lon) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_lat * pi / 180) * cos(toLat * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
  return 6371000 * 2 * atan2(sqrt(a), sqrt(1 - a));
}

double _normAngle(double d) {
  while (d > 180) d -= 360;
  while (d < -180) d += 360;
  return d;
}

// ─── MAVLink frame builder ─────────────────────────────────────────────────

Uint8List _frame(int id, Uint8List p) {
  final f = Uint8List(10 + p.length + 2);
  f[0] = 0xFD; f[1] = p.length; f[4] = _seq++ & 0xFF;
  f[5] = _sysId; f[6] = _compId;
  f[7] = id & 0xFF; f[8] = (id >> 8) & 0xFF; f[9] = (id >> 16) & 0xFF;
  f.setRange(10, 10 + p.length, p);
  final crc = MavlinkCrc.computeFrameCrc(
    header: Uint8List.sublistView(f, 0, 10),
    payload: p,
    crcExtra: mavlinkCrcExtras[id] ?? 0,
  );
  f[f.length - 2] = crc & 0xFF;
  f[f.length - 1] = (crc >> 8) & 0xFF;
  return f;
}

void _send(Uint8List f) {
  if (_gcsAddr != null) _socket.send(f, _gcsAddr!, _gcsPort!);
}

// ─── MAVLink message senders ───────────────────────────────────────────────

void _sendHeartbeat() {
  final p = Uint8List(9);
  ByteData.sublistView(p).setUint32(0, _modeFor[_phase]!, Endian.little);
  p[4] = 1; p[5] = 3; p[6] = _armed ? 0xC1 : 0x41; p[7] = _armed ? 4 : 3; p[8] = 3;
  _send(_frame(0, p));
}

void _sendAttitude() {
  final p = Uint8List(28); final d = ByteData.sublistView(p);
  d.setUint32(0, _bootMs, Endian.little);
  d.setFloat32(4, _roll, Endian.little);
  d.setFloat32(8, _pitch, Endian.little);
  d.setFloat32(12, _heading * pi / 180, Endian.little);
  d.setFloat32(16, _roll * 0.1, Endian.little);
  d.setFloat32(20, _pitch * 0.05, Endian.little);
  d.setFloat32(24, _roll * 9.81 / (_cruiseIas + 1) * 0.5, Endian.little);
  _send(_frame(30, p));
}

void _sendGlobalPositionInt() {
  final p = Uint8List(28); final d = ByteData.sublistView(p);
  d.setUint32(0, _bootMs, Endian.little);
  d.setInt32(4, (_lat * 1e7).round(), Endian.little);
  d.setInt32(8, (_lon * 1e7).round(), Endian.little);
  d.setInt32(12, (_altMsl * 1000).round(), Endian.little);
  d.setInt32(16, (_altRel * 1000).round(), Endian.little);
  d.setInt16(20, (_gs * 100).round(), Endian.little);
  d.setInt16(24, (_cr * -100).round(), Endian.little);
  d.setUint16(26, (_heading * 100).round(), Endian.little);
  _send(_frame(33, p));
}

void _sendGpsRawInt() {
  final p = Uint8List(30); final d = ByteData.sublistView(p);
  d.setUint64(0, _bootMs * 1000, Endian.little);
  d.setInt32(8, (_lat * 1e7).round(), Endian.little);
  d.setInt32(12, (_lon * 1e7).round(), Endian.little);
  d.setInt32(16, (_altMsl * 1000).round(), Endian.little);
  d.setUint16(20, 75 + _rng.nextInt(15), Endian.little);
  d.setUint16(22, 130, Endian.little);
  d.setUint16(24, (_gs * 100).round(), Endian.little);
  d.setUint16(26, (_heading * 100).round(), Endian.little);
  p[28] = 3; p[29] = 12 + _rng.nextInt(3);
  _send(_frame(24, p));
}

void _sendSysStatus() {
  final p = Uint8List(31); final d = ByteData.sublistView(p);
  d.setUint16(14, (_volt * 1000).round(), Endian.little);
  d.setInt16(16, (_amps * 100).round(), Endian.little);
  p[30] = _batPct.clamp(0, 100);
  _send(_frame(1, p));
}

void _sendVfrHud() {
  final p = Uint8List(20); final d = ByteData.sublistView(p);
  d.setFloat32(0, _ias, Endian.little);
  d.setFloat32(4, _gs, Endian.little);
  d.setFloat32(8, _altMsl, Endian.little);
  d.setFloat32(12, _cr, Endian.little);
  d.setInt16(16, _heading.round(), Endian.little);
  d.setUint16(18, _thr, Endian.little);
  _send(_frame(74, p));
}

void _sendVibration() {
  final p = Uint8List(32); final d = ByteData.sublistView(p);
  d.setUint64(0, _bootMs * 1000, Endian.little);
  d.setFloat32(8, _ias * 0.6 + _rng.nextDouble() * 4, Endian.little);
  d.setFloat32(12, _ias * 0.6 + _rng.nextDouble() * 3, Endian.little);
  d.setFloat32(16, _ias * 0.6 + _rng.nextDouble() * 5, Endian.little);
  _send(_frame(241, p));
}
