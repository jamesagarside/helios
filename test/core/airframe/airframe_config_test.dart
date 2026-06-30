import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/airframe/airframe_config.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';

void main() {
  group('AirframeConfig.resolve from FRAME_CLASS/FRAME_TYPE', () {
    test('quad X → 4-motor multirotor, X layout, fromParams', () {
      final c = AirframeConfig.resolve(
        vehicleType: VehicleType.quadrotor,
        frameClass: 1,
        frameType: 1,
      );
      expect(c.archetype, AirframeArchetype.multirotor);
      expect(c.motorCount, 4);
      expect(c.armLayout, ArmLayout.x);
      expect(c.fromParams, isTrue);
    });

    test('hexa → 6 motors', () {
      final c = AirframeConfig.resolve(
        vehicleType: VehicleType.quadrotor,
        frameClass: 2,
        frameType: 1,
      );
      expect(c.motorCount, 6);
    });

    test('octo → 8 motors', () {
      final c = AirframeConfig.resolve(
        vehicleType: VehicleType.quadrotor,
        frameClass: 3,
      );
      expect(c.motorCount, 8);
    });

    test('tricopter (class 7) → 3 motors', () {
      final c = AirframeConfig.resolve(
        vehicleType: VehicleType.quadrotor,
        frameClass: 7,
        frameType: 1,
      );
      expect(c.motorCount, 3);
      expect(c.archetype, AirframeArchetype.multirotor);
    });

    test('Y6 (class 5) → 6 motors', () {
      final c = AirframeConfig.resolve(
        vehicleType: VehicleType.quadrotor,
        frameClass: 5,
      );
      expect(c.motorCount, 6);
    });

    test('Plus frame type → plus layout', () {
      final c = AirframeConfig.resolve(
        vehicleType: VehicleType.quadrotor,
        frameClass: 1,
        frameType: 0,
      );
      expect(c.armLayout, ArmLayout.plus);
    });

    test('VTOL with FRAME_CLASS → quadplane archetype', () {
      final c = AirframeConfig.resolve(
        vehicleType: VehicleType.vtol,
        frameClass: 1,
        frameType: 1,
      );
      expect(c.archetype, AirframeArchetype.quadplane);
      expect(c.motorCount, 4);
      expect(c.fromParams, isTrue);
    });
  });

  group('AirframeConfig.resolve fallback from MAV_TYPE (no params)', () {
    test('fixed-wing → fixedWing archetype, not fromParams', () {
      final c = AirframeConfig.resolve(vehicleType: VehicleType.fixedWing);
      expect(c.archetype, AirframeArchetype.fixedWing);
      expect(c.fromParams, isFalse);
    });

    test('quadrotor → 4-motor multirotor', () {
      final c = AirframeConfig.resolve(vehicleType: VehicleType.quadrotor);
      expect(c.archetype, AirframeArchetype.multirotor);
      expect(c.motorCount, 4);
      expect(c.fromParams, isFalse);
    });

    test('VTOL → quadplane', () {
      final c = AirframeConfig.resolve(vehicleType: VehicleType.vtol);
      expect(c.archetype, AirframeArchetype.quadplane);
    });

    test('unknown → generic multirotor', () {
      final c = AirframeConfig.resolve(vehicleType: VehicleType.unknown);
      expect(c.archetype, AirframeArchetype.multirotor);
    });
  });

  test('equatable: same inputs produce equal configs', () {
    final a = AirframeConfig.resolve(
        vehicleType: VehicleType.quadrotor, frameClass: 1, frameType: 1);
    final b = AirframeConfig.resolve(
        vehicleType: VehicleType.quadrotor, frameClass: 1, frameType: 1);
    expect(a, equals(b));
  });
}
