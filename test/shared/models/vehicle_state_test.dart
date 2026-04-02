import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';

void main() {
  group('VehicleState', () {
    test('default state has sensible initial values', () {
      const state = VehicleState();

      expect(state.systemId, 0);
      expect(state.vehicleType, VehicleType.unknown);
      expect(state.autopilotType, AutopilotType.unknown);
      expect(state.roll, 0.0);
      expect(state.pitch, 0.0);
      expect(state.yaw, 0.0);
      expect(state.latitude, 0.0);
      expect(state.longitude, 0.0);
      expect(state.gpsFix, GpsFix.none);
      expect(state.satellites, 0);
      expect(state.hdop, 99.99);
      expect(state.batteryVoltage, 0.0);
      expect(state.batteryRemaining, -1);
      expect(state.flightMode, FlightMode.unknown);
      expect(state.armed, false);
      expect(state.hasPosition, false);
    });

    test('copyWith creates correct copy with updated fields', () {
      const state = VehicleState();

      final updated = state.copyWith(
        roll: 0.5,
        pitch: -0.1,
        yaw: 3.14,
        latitude: -35.362,
        longitude: 149.165,
        armed: true,
      );

      expect(updated.roll, 0.5);
      expect(updated.pitch, -0.1);
      expect(updated.yaw, 3.14);
      expect(updated.latitude, -35.362);
      expect(updated.longitude, 149.165);
      expect(updated.armed, true);
      // Unchanged fields
      expect(updated.systemId, 0);
      expect(updated.batteryVoltage, 0.0);
      expect(updated.gpsFix, GpsFix.none);
    });

    test('hasPosition returns true when lat/lon are non-zero', () {
      const noPos = VehicleState();
      expect(noPos.hasPosition, false);

      final withPos = noPos.copyWith(latitude: -35.362, longitude: 149.165);
      expect(withPos.hasPosition, true);

      final onlyLat = noPos.copyWith(latitude: -35.362);
      expect(onlyLat.hasPosition, true);
    });

    test('equality works correctly', () {
      const a = VehicleState(roll: 0.5, pitch: -0.1);
      final b = const VehicleState().copyWith(roll: 0.5, pitch: -0.1);
      const c = VehicleState(roll: 0.5, pitch: 0.1);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('FlightMode', () {
    test('equality by name and number', () {
      const a = FlightMode('AUTO', 10);
      const b = FlightMode('AUTO', 10);
      const c = FlightMode('MANUAL', 0);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('unknown mode is static const', () {
      expect(FlightMode.unknown.name, 'UNKNOWN');
      expect(FlightMode.unknown.number, -1);
    });
  });

  group('GpsFix', () {
    test('enum values exist', () {
      expect(GpsFix.values.length, 7);
      expect(GpsFix.none.index, 0);
      expect(GpsFix.rtkFixed.index, 6);
    });
  });

  group('LinkState', () {
    test('enum values exist', () {
      expect(LinkState.values.length, 4);
      expect(LinkState.disconnected.index, 0);
      expect(LinkState.lost.index, 3);
    });
  });
}
