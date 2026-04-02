import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';

void main() {
  group('VehicleState sensor helpers', () {
    const state = VehicleState(
      sensorPresent: MavSensorBit.gyro3d | MavSensorBit.accel3d | MavSensorBit.gps,
      sensorEnabled: MavSensorBit.gyro3d | MavSensorBit.accel3d,
      sensorHealth: MavSensorBit.gyro3d | MavSensorBit.gps,
    );

    test('isSensorPresent', () {
      expect(state.isSensorPresent(MavSensorBit.gyro3d), true);
      expect(state.isSensorPresent(MavSensorBit.terrain), false);
    });

    test('isSensorHealthy', () {
      expect(state.isSensorHealthy(MavSensorBit.gyro3d), true);
      expect(state.isSensorHealthy(MavSensorBit.accel3d), false);
    });

    test('ekfOk true when variances low', () {
      const ok = VehicleState(ekfVelocityVar: 0.1, ekfPosHorizVar: 0.2, ekfPosVertVar: 0.3, ekfCompassVar: 0.1);
      expect(ok.ekfOk, true);
    });

    test('ekfOk false when variances high', () {
      const bad = VehicleState(ekfVelocityVar: 0.9);
      expect(bad.ekfOk, false);
    });
  });

  group('VehicleState vibration', () {
    test('vibration fields copyWith', () {
      const original = VehicleState(vibrationX: 15.5, vibrationY: 20.3, vibrationZ: 10.1, clipping0: 5);
      final copy = original.copyWith(vibrationZ: 99.9);
      expect(copy.vibrationX, 15.5);
      expect(copy.vibrationZ, 99.9);
      expect(copy.clipping0, 5);
    });

    test('defaults are zero', () {
      const state = VehicleState();
      expect(state.vibrationX, 0.0);
      expect(state.clipping0, 0);
    });
  });

  group('MavSensorBit', () {
    test('labels for primary sensors', () {
      for (final bit in MavSensorBit.primarySensors) {
        expect(MavSensorBit.label(bit), isNot(startsWith('Sensor 0x')));
      }
    });
  });
}
