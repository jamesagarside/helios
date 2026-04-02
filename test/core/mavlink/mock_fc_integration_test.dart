import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/mavlink/mavlink_service.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';
import 'package:helios_gcs/shared/providers/vehicle_state_notifier.dart';
import 'package:dart_mavlink/dart_mavlink.dart';
import '../../helpers/mock_fc.dart';

void main() {
  late MockFlightController fc;
  late MavlinkService service;
  late VehicleStateNotifier notifier;

  setUp(() {
    fc = MockFlightController();
    service = MavlinkService(fc.transport);
    notifier = VehicleStateNotifier();
  });

  tearDown(() {
    fc.stop();
    service.dispose();
    notifier.dispose();
  });

  group('MockFlightController integration', () {
    test('receives heartbeat and populates vehicle type', () async {
      await service.connect();
      fc.start();

      // Wire messages to notifier
      final sub = service.messageStream.listen(notifier.handleMessage);

      // Wait for heartbeat processing + 30Hz flush
      await Future<void>.delayed(const Duration(milliseconds: 150));
      notifier.flush();

      expect(notifier.state.vehicleType, VehicleType.quadrotor);
      expect(notifier.state.autopilotType, AutopilotType.ardupilot);
      expect(notifier.state.systemId, 1);

      await sub.cancel();
    });

    test('receives attitude data', () async {
      await service.connect();
      fc.start();
      fc.roll = 0.15;
      fc.pitch = -0.05;

      final sub = service.messageStream.listen(notifier.handleMessage);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      notifier.flush();

      expect(notifier.state.roll, closeTo(0.15, 0.01));
      expect(notifier.state.pitch, closeTo(-0.05, 0.01));

      await sub.cancel();
    });

    test('receives GPS position', () async {
      await service.connect();
      fc.start();

      final sub = service.messageStream.listen(notifier.handleMessage);
      // GPS_RAW_INT at 2 Hz — need >500ms for at least one cycle
      await Future<void>.delayed(const Duration(milliseconds: 700));
      notifier.flush();

      expect(notifier.state.latitude, closeTo(-35.363261, 0.001));
      expect(notifier.state.longitude, closeTo(149.165230, 0.001));
      expect(notifier.state.satellites, 12);
      expect(notifier.state.gpsFix, GpsFix.fix3d);

      await sub.cancel();
    });

    test('receives battery data', () async {
      await service.connect();
      fc.start();
      fc.batteryVoltage = 11.8;
      fc.batteryRemaining = 42;

      final sub = service.messageStream.listen(notifier.handleMessage);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      notifier.flush();

      expect(notifier.state.batteryVoltage, closeTo(11.8, 0.1));
      expect(notifier.state.batteryRemaining, 42);

      await sub.cancel();
    });

    test('receives sensor health bitmask', () async {
      await service.connect();
      fc.start();
      fc.sensorHealth = MavSensorBit.gyro3d | MavSensorBit.accel3d;

      final sub = service.messageStream.listen(notifier.handleMessage);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      notifier.flush();

      expect(notifier.state.isSensorHealthy(MavSensorBit.gyro3d), true);
      expect(notifier.state.isSensorHealthy(MavSensorBit.accel3d), true);
      expect(notifier.state.isSensorHealthy(MavSensorBit.mag3d), false);

      await sub.cancel();
    });

    test('arm command changes FC state', () async {
      await service.connect();
      fc.start();
      expect(fc.armed, false);

      // Send arm command
      await service.sendCommand(
        targetSystem: 1,
        targetComponent: 1,
        command: MavCmd.componentArmDisarm,
        param1: 1.0,
      );

      // Wait for command + response
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(fc.armed, true);
    });

    test('mode change command updates FC', () async {
      await service.connect();
      fc.start();

      await service.sendCommand(
        targetSystem: 1,
        targetComponent: 1,
        command: MavCmd.doSetMode,
        param1: 1.0,
        param2: 4.0, // GUIDED
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(fc.customMode, 4);
    });

    test('param fetch returns all params', () async {
      await service.connect();
      fc.start();

      // Request param list
      final frame = service.frameBuilder.buildParamRequestList(
        targetSystem: 1,
        targetComponent: 1,
      );
      await service.sendRaw(frame);

      // Collect PARAM_VALUE messages
      final params = <String, double>{};
      final sub = service.messagesOf<ParamValueMessage>().listen((msg) {
        params[msg.paramId] = msg.paramValue;
      });

      await Future<void>.delayed(const Duration(milliseconds: 500));
      await sub.cancel();

      expect(params.isNotEmpty, true);
      expect(params['ARMING_CHECK'], 1.0);
      expect(params['FS_BATT_ENABLE'], 1.0);
      expect(params['FRAME_CLASS'], 1.0);
    });

    test('param set changes value and echoes back', () async {
      await service.connect();
      fc.start();

      final frame = service.frameBuilder.buildParamSet(
        targetSystem: 1,
        targetComponent: 1,
        paramId: 'FS_BATT_VOLTAGE',
        paramValue: 11.0,
      );
      await service.sendRaw(frame);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(fc.params['FS_BATT_VOLTAGE'], 11.0);
    });

    test('command ACK is received', () async {
      await service.connect();
      fc.start();

      final ackFuture = service.messagesOf<CommandAckMessage>()
          .where((msg) => msg.command == MavCmd.componentArmDisarm)
          .first
          .timeout(const Duration(seconds: 2));

      await service.sendCommand(
        targetSystem: 1,
        targetComponent: 1,
        command: MavCmd.componentArmDisarm,
        param1: 1.0,
      );

      final ack = await ackFuture;
      expect(ack.accepted, true);
    });

    test('message rate increases with connection duration', () async {
      await service.connect();
      fc.start();

      int count = 0;
      final sub = service.messageStream.listen((_) => count++);
      await Future<void>.delayed(const Duration(seconds: 1));
      await sub.cancel();

      // At minimum: 1Hz heartbeat + 10Hz attitude + 5Hz position = 16+ messages/sec
      expect(count, greaterThan(10));
    });
  });
}
