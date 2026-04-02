import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';

void main() {
  group('VehicleState — servo output and RC input', () {
    test('servoOutputs defaults to empty list', () {
      const state = VehicleState();
      expect(state.servoOutputs, isEmpty);
    });

    test('rcChannels defaults to empty list', () {
      const state = VehicleState();
      expect(state.rcChannels, isEmpty);
    });

    test('rcRssi defaults to 255 (invalid)', () {
      const state = VehicleState();
      expect(state.rcRssi, 255);
    });

    test('rcFailsafe defaults to false', () {
      const state = VehicleState();
      expect(state.rcFailsafe, isFalse);
    });

    test('copyWith updates servoOutputs correctly', () {
      const state = VehicleState();
      final servos = List<int>.filled(16, 1500);
      final updated = state.copyWith(servoOutputs: servos);

      expect(updated.servoOutputs, equals(servos));
      expect(updated.servoOutputs.length, 16);
      expect(updated.servoOutputs.first, 1500);
    });

    test('copyWith updates rcChannels correctly', () {
      const state = VehicleState();
      final channels = List<int>.generate(18, (i) => 1000 + i * 50);
      final updated = state.copyWith(rcChannels: channels);

      expect(updated.rcChannels, equals(channels));
      expect(updated.rcChannels.length, 18);
    });

    test('copyWith updates rcRssi correctly', () {
      const state = VehicleState();
      final updated = state.copyWith(rcRssi: 200);

      expect(updated.rcRssi, 200);
    });

    test('copyWith updates rcFailsafe correctly', () {
      const state = VehicleState();
      final updated = state.copyWith(rcFailsafe: true);

      expect(updated.rcFailsafe, isTrue);
    });

    test('copyWith preserves other fields when only servoOutputs changes', () {
      final state = const VehicleState().copyWith(
        roll: 0.5,
        pitch: -0.1,
        batteryVoltage: 12.6,
        armed: true,
      );
      final servos = List<int>.filled(16, 1600);
      final updated = state.copyWith(servoOutputs: servos);

      // Updated field
      expect(updated.servoOutputs, equals(servos));
      // Unchanged fields
      expect(updated.roll, 0.5);
      expect(updated.pitch, -0.1);
      expect(updated.batteryVoltage, 12.6);
      expect(updated.armed, isTrue);
    });

    test('Equatable props includes servoOutputs — states with different values are not equal', () {
      const stateA = VehicleState();
      final stateB = stateA.copyWith(servoOutputs: [1500, 1500, 1000, 2000]);

      expect(stateA, isNot(equals(stateB)));
    });

    test('Equatable props includes rcChannels — states with different values are not equal', () {
      const stateA = VehicleState();
      final stateB = stateA.copyWith(rcChannels: [1500, 1500, 1000, 2000]);

      expect(stateA, isNot(equals(stateB)));
    });

    test('Equatable props includes rcRssi', () {
      const stateA = VehicleState();
      final stateB = stateA.copyWith(rcRssi: 180);

      expect(stateA, isNot(equals(stateB)));
    });

    test('Equatable props includes rcFailsafe', () {
      const stateA = VehicleState();
      final stateB = stateA.copyWith(rcFailsafe: true);

      expect(stateA, isNot(equals(stateB)));
    });

    test('identical servo states are equal', () {
      final servos = List<int>.filled(16, 1500);
      final stateA = const VehicleState().copyWith(servoOutputs: servos);
      final stateB = const VehicleState().copyWith(servoOutputs: servos);

      expect(stateA, equals(stateB));
    });
  });
}
