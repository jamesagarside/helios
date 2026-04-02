import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/mavlink/flight_modes.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';

void main() {
  group('FlightModeRegistry.lookup', () {
    test('returns correct info for ArduCopter modes', () {
      final info = FlightModeRegistry.lookup(VehicleType.quadrotor, 6);
      expect(info, isNotNull);
      expect(info!.name, 'RTL');
      expect(info.category, 'auto');
    });

    test('returns LOITER for copter mode 5', () {
      final info = FlightModeRegistry.lookup(VehicleType.quadrotor, 5);
      expect(info!.name, 'LOITER');
      expect(info.category, 'assisted');
    });

    test('returns null for unknown mode number', () {
      expect(FlightModeRegistry.lookup(VehicleType.quadrotor, 999), isNull);
    });

    test('returns correct info for ArduPlane modes', () {
      final info = FlightModeRegistry.lookup(VehicleType.fixedWing, 10);
      expect(info!.name, 'AUTO');
      expect(info.category, 'auto');
    });

    test('returns correct info for ArduRover modes', () {
      final info = FlightModeRegistry.lookup(VehicleType.rover, 4);
      expect(info!.name, 'HOLD');
    });

    test('vtol uses plane mode table', () {
      final info = FlightModeRegistry.lookup(VehicleType.vtol, 11);
      expect(info!.name, 'RTL');
    });

    test('boat uses rover mode table', () {
      final info = FlightModeRegistry.lookup(VehicleType.boat, 10);
      expect(info!.name, 'AUTO');
    });

    test('unknown vehicle type falls back to copter table', () {
      final info = FlightModeRegistry.lookup(VehicleType.unknown, 3);
      expect(info!.name, 'AUTO');
    });

    test('helicopter uses copter mode table', () {
      final info = FlightModeRegistry.lookup(VehicleType.helicopter, 9);
      expect(info!.name, 'LAND');
    });
  });

  group('FlightModeRegistry.name', () {
    test('returns mode name for known mode', () {
      expect(
        FlightModeRegistry.name(VehicleType.quadrotor, 3),
        'AUTO',
      );
    });

    test('returns MODE_N fallback for unknown mode', () {
      expect(
        FlightModeRegistry.name(VehicleType.quadrotor, 99),
        'MODE_99',
      );
    });
  });

  group('FlightModeRegistry.modesFor', () {
    test('copter modes include STABILIZE, LOITER, RTL, AUTO, GUIDED', () {
      final modes = FlightModeRegistry.modesFor(VehicleType.quadrotor);
      final names = modes.map((m) => m.name).toList();
      expect(names, containsAll(['STABILIZE', 'LOITER', 'RTL', 'AUTO', 'GUIDED']));
    });

    test('plane modes include MANUAL, FLY_BY_WIRE_A, AUTO, RTL', () {
      final modes = FlightModeRegistry.modesFor(VehicleType.fixedWing);
      final names = modes.map((m) => m.name).toList();
      expect(names, containsAll(['MANUAL', 'FLY_BY_WIRE_A', 'AUTO', 'RTL']));
    });

    test('rover modes include MANUAL, AUTO, RTL, GUIDED', () {
      final modes = FlightModeRegistry.modesFor(VehicleType.rover);
      final names = modes.map((m) => m.name).toList();
      expect(names, containsAll(['MANUAL', 'AUTO', 'RTL', 'GUIDED']));
    });

    test('all modes have unique numbers within a vehicle type', () {
      for (final vt in VehicleType.values) {
        final modes = FlightModeRegistry.modesFor(vt);
        final numbers = modes.map((m) => m.number).toList();
        expect(numbers.length, numbers.toSet().length,
            reason: 'Duplicate mode number in $vt modes');
      }
    });

    test('all modes have a non-empty name and valid category', () {
      const validCategories = {'manual', 'assisted', 'auto'};
      for (final vt in VehicleType.values) {
        for (final m in FlightModeRegistry.modesFor(vt)) {
          expect(m.name, isNotEmpty, reason: 'Empty name in $vt mode ${m.number}');
          expect(validCategories, contains(m.category),
              reason: 'Invalid category "${m.category}" for $vt mode ${m.name}');
        }
      }
    });
  });

  group('FlightModeRegistry shortcut modes', () {
    test('RTL mode is 6 for copter', () {
      expect(FlightModeRegistry.rtlMode(VehicleType.quadrotor), 6);
    });

    test('RTL mode is 11 for plane', () {
      expect(FlightModeRegistry.rtlMode(VehicleType.fixedWing), 11);
    });

    test('LAND mode is 9 for copter', () {
      expect(FlightModeRegistry.landMode(VehicleType.quadrotor), 9);
    });

    test('LOITER mode is 5 for copter', () {
      expect(FlightModeRegistry.loiterMode(VehicleType.quadrotor), 5);
    });

    test('LOITER mode is 12 for plane', () {
      expect(FlightModeRegistry.loiterMode(VehicleType.fixedWing), 12);
    });

    test('AUTO mode is 3 for copter', () {
      expect(FlightModeRegistry.autoMode(VehicleType.quadrotor), 3);
    });

    test('AUTO mode is 10 for plane and rover', () {
      expect(FlightModeRegistry.autoMode(VehicleType.fixedWing), 10);
      expect(FlightModeRegistry.autoMode(VehicleType.rover), 10);
    });

    test('BRAKE mode is 17 for copter', () {
      expect(FlightModeRegistry.brakeMode(VehicleType.quadrotor), 17);
    });

    test('GUIDED mode is 4 for copter', () {
      expect(FlightModeRegistry.guidedMode(VehicleType.quadrotor), 4);
    });

    test('GUIDED mode is 15 for plane and rover', () {
      expect(FlightModeRegistry.guidedMode(VehicleType.fixedWing), 15);
      expect(FlightModeRegistry.guidedMode(VehicleType.rover), 15);
    });

    test('shortcut modes all exist in the mode table', () {
      for (final vt in VehicleType.values) {
        final rtl = FlightModeRegistry.lookup(vt, FlightModeRegistry.rtlMode(vt));
        expect(rtl, isNotNull, reason: 'RTL mode not found for $vt');

        final loiter = FlightModeRegistry.lookup(vt, FlightModeRegistry.loiterMode(vt));
        expect(loiter, isNotNull, reason: 'LOITER mode not found for $vt');

        final auto = FlightModeRegistry.lookup(vt, FlightModeRegistry.autoMode(vt));
        expect(auto, isNotNull, reason: 'AUTO mode not found for $vt');
      }
    });
  });
}
