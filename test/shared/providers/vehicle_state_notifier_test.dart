import 'dart:typed_data';
import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';
import 'package:helios_gcs/shared/providers/vehicle_state_notifier.dart';

void main() {
  late VehicleStateNotifier notifier;

  setUp(() {
    notifier = VehicleStateNotifier();
  });

  group('VehicleStateNotifier', () {
    test('initial state is default VehicleState', () {
      expect(notifier.state, const VehicleState());
    });

    test('updates attitude from ATTITUDE message', () {
      final payload = Uint8List(28);
      final data = ByteData.sublistView(payload);
      data.setFloat32(4, 0.5, Endian.little);   // roll
      data.setFloat32(8, -0.1, Endian.little);  // pitch
      data.setFloat32(12, 3.14, Endian.little); // yaw
      data.setFloat32(16, 0.01, Endian.little); // rollSpeed
      data.setFloat32(20, 0.0, Endian.little);  // pitchSpeed
      data.setFloat32(24, -0.02, Endian.little); // yawSpeed

      final msg = AttitudeMessage.fromPayload(payload, 1, 1, 0);
      notifier.handleMessage(msg);
      notifier.flush();

      expect(notifier.state.roll, closeTo(0.5, 0.001));
      expect(notifier.state.pitch, closeTo(-0.1, 0.001));
      expect(notifier.state.yaw, closeTo(3.14, 0.001));
      expect(notifier.state.rollSpeed, closeTo(0.01, 0.001));
    });

    test('updates GPS from GLOBAL_POSITION_INT', () {
      final payload = Uint8List(28);
      final data = ByteData.sublistView(payload);
      data.setInt32(4, -353620000, Endian.little);  // lat degE7
      data.setInt32(8, 1491650000, Endian.little);  // lon degE7
      data.setInt32(12, 245000, Endian.little);     // alt mm MSL
      data.setInt32(16, 120000, Endian.little);     // rel_alt mm
      data.setUint16(26, 18200, Endian.little);     // hdg cdeg

      final msg = GlobalPositionIntMessage.fromPayload(payload, 1, 1, 0);
      notifier.handleMessage(msg);
      notifier.flush();

      expect(notifier.state.latitude, closeTo(-35.362, 0.001));
      expect(notifier.state.longitude, closeTo(149.165, 0.001));
      expect(notifier.state.altitudeMsl, closeTo(245.0, 0.001));
      expect(notifier.state.altitudeRel, closeTo(120.0, 0.001));
      expect(notifier.state.heading, 182);
      expect(notifier.state.hasPosition, true);
    });

    test('updates GPS fix from GPS_RAW_INT', () {
      final payload = Uint8List(30);
      payload[28] = 3;  // fix_type = 3D
      payload[29] = 14; // satellites

      final data = ByteData.sublistView(payload);
      data.setUint16(20, 90, Endian.little); // eph = 0.9 HDOP

      final msg = GpsRawIntMessage.fromPayload(payload, 1, 1, 0);
      notifier.handleMessage(msg);
      notifier.flush();

      expect(notifier.state.gpsFix, GpsFix.fix3d);
      expect(notifier.state.satellites, 14);
      expect(notifier.state.hdop, closeTo(0.9, 0.01));
    });

    test('updates battery from SYS_STATUS', () {
      final payload = Uint8List(31);
      final data = ByteData.sublistView(payload);
      data.setUint16(14, 12420, Endian.little); // voltage mV
      data.setInt16(16, 1500, Endian.little);    // current cA
      payload[30] = 78; // remaining %

      final msg = SysStatusMessage.fromPayload(payload, 1, 1, 0);
      notifier.handleMessage(msg);
      notifier.flush();

      expect(notifier.state.batteryVoltage, closeTo(12.42, 0.01));
      expect(notifier.state.batteryCurrent, closeTo(15.0, 0.01));
      expect(notifier.state.batteryRemaining, 78);
    });

    test('updates VFR HUD data', () {
      final payload = Uint8List(20);
      final data = ByteData.sublistView(payload);
      data.setFloat32(0, 22.5, Endian.little);  // airspeed
      data.setFloat32(4, 25.1, Endian.little);  // groundspeed
      data.setFloat32(12, 2.1, Endian.little);  // climb
      data.setInt16(16, 182, Endian.little);     // heading
      data.setUint16(18, 65, Endian.little);     // throttle

      final msg = VfrHudMessage.fromPayload(payload, 1, 1, 0);
      notifier.handleMessage(msg);
      notifier.flush();

      expect(notifier.state.airspeed, closeTo(22.5, 0.01));
      expect(notifier.state.groundspeed, closeTo(25.1, 0.01));
      expect(notifier.state.heading, 182);
      expect(notifier.state.throttle, 65);
      expect(notifier.state.climbRate, closeTo(2.1, 0.01));
    });

    test('detects armed state from HEARTBEAT', () {
      final payload = Uint8List(9);
      payload[4] = MavType.fixedWing;
      payload[5] = MavAutopilot.ardupilotmega;
      payload[6] = MavModeFlag.safetyArmed;
      payload[7] = MavState.active;
      payload[8] = 3;

      final msg = HeartbeatMessage.fromPayload(payload, 1, 1, 0);
      notifier.handleMessage(msg);
      notifier.flush();

      expect(notifier.state.armed, true);
      expect(notifier.state.vehicleType, VehicleType.fixedWing);
      expect(notifier.state.autopilotType, AutopilotType.ardupilot);
    });

    test('detects disarmed state from HEARTBEAT', () {
      final payload = Uint8List(9);
      payload[4] = MavType.quadrotor;
      payload[5] = MavAutopilot.px4;
      payload[6] = 0; // disarmed
      payload[7] = MavState.standby;
      payload[8] = 3;

      final msg = HeartbeatMessage.fromPayload(payload, 1, 1, 0);
      notifier.handleMessage(msg);
      notifier.flush();

      expect(notifier.state.armed, false);
      expect(notifier.state.vehicleType, VehicleType.quadrotor);
      expect(notifier.state.autopilotType, AutopilotType.px4);
    });

    test('updates RSSI from RC_CHANNELS', () {
      final payload = Uint8List(42);
      payload[41] = 189; // rssi

      final msg = RcChannelsMessage.fromPayload(payload, 1, 1, 0);
      notifier.handleMessage(msg);
      notifier.flush();

      expect(notifier.state.rssi, 189);
    });

    test('reset clears all state', () {
      // Set some state
      final payload = Uint8List(9);
      payload[4] = MavType.fixedWing;
      payload[6] = MavModeFlag.safetyArmed;
      payload[8] = 3;
      notifier.handleMessage(HeartbeatMessage.fromPayload(payload, 1, 1, 0));
      notifier.flush();

      expect(notifier.state.armed, true);

      notifier.reset();

      expect(notifier.state.armed, false);
      expect(notifier.state.vehicleType, VehicleType.unknown);
      expect(notifier.state.systemId, 0);
    });

    test('handles unknown message types gracefully', () {
      final msg = UnknownMessage(
        messageId: 9999,
        systemId: 1,
        componentId: 1,
        sequence: 0,
        payload: Uint8List(0),
      );
      // Should not throw
      notifier.handleMessage(msg);
      expect(notifier.state, const VehicleState());
    });

    test('GPS fix enum mapping covers all types', () {
      for (var fixType = 0; fixType <= 6; fixType++) {
        final payload = Uint8List(30);
        payload[28] = fixType;
        final msg = GpsRawIntMessage.fromPayload(payload, 1, 1, 0);
        notifier.handleMessage(msg);
        notifier.flush();
        // Should not throw
        expect(notifier.state.gpsFix, isNotNull);
      }
    });
  });
}
