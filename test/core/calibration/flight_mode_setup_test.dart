import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/calibration/flight_mode_setup.dart';

void main() {
  group('slotForPwm — PWM band → slot mapping', () {
    test('maps each band centre to its 1-based slot', () {
      expect(slotForPwm(1000), 1);
      expect(slotForPwm(1300), 2);
      expect(slotForPwm(1400), 3);
      expect(slotForPwm(1550), 4);
      expect(slotForPwm(1680), 5);
      expect(slotForPwm(1900), 6);
    });

    test('inclusive lower and upper band boundaries select the right slot', () {
      // Slot 1 spans 0..1230
      expect(slotForPwm(0), 1);
      expect(slotForPwm(1230), 1);
      // Slot 2 starts at 1231
      expect(slotForPwm(1231), 2);
      expect(slotForPwm(1360), 2);
      // Slot 3
      expect(slotForPwm(1361), 3);
      expect(slotForPwm(1490), 3);
      // Slot 4
      expect(slotForPwm(1491), 4);
      expect(slotForPwm(1620), 4);
      // Slot 5
      expect(slotForPwm(1621), 5);
      expect(slotForPwm(1749), 5);
      // Slot 6 spans 1750..2200
      expect(slotForPwm(1750), 6);
      expect(slotForPwm(2200), 6);
    });

    test('returns null above the last band (e.g. failsafe high)', () {
      expect(slotForPwm(2201), isNull);
      expect(slotForPwm(3000), isNull);
    });

    test('bands are contiguous and cover the full 0..2200 envelope', () {
      // Every PWM value across the envelope must land in exactly one slot.
      for (var pwm = 0; pwm <= 2200; pwm++) {
        final matches =
            kFlightModeBands.where((b) => b.contains(pwm)).toList();
        expect(matches, hasLength(1),
            reason: 'pwm=$pwm should match exactly one band');
        expect(slotForPwm(pwm), matches.single.slot);
      }
    });

    test('there are exactly six slots', () {
      expect(kFlightModeSlotCount, 6);
      expect(kFlightModeBands, hasLength(6));
      expect(
        kFlightModeBands.map((b) => b.slot).toList(),
        [1, 2, 3, 4, 5, 6],
      );
    });
  });

  group('bandForSlot', () {
    test('returns the band for valid slots', () {
      expect(bandForSlot(1)!.slot, 1);
      expect(bandForSlot(6)!.slot, 6);
    });

    test('returns null for out-of-range slots', () {
      expect(bandForSlot(0), isNull);
      expect(bandForSlot(7), isNull);
    });
  });

  group('flightModeSlotParam', () {
    test('builds FLTMODE{slot} names', () {
      expect(flightModeSlotParam(1), 'FLTMODE1');
      expect(flightModeSlotParam(6), 'FLTMODE6');
    });
  });

  group('buildFlightModeWrites', () {
    test('writes FLTMODE_CH plus only the assigned slots', () {
      const assignment = FlightModeAssignment(
        channel: 5,
        slotModes: {1: 0, 3: 2, 6: 6},
      );

      final writes = buildFlightModeWrites(assignment);

      expect(writes[kFlightModeChannelParam], 5.0);
      expect(writes['FLTMODE1'], 0.0);
      expect(writes['FLTMODE3'], 2.0);
      expect(writes['FLTMODE6'], 6.0);
      // Unassigned slots are not written so existing FC values are preserved.
      expect(writes.containsKey('FLTMODE2'), isFalse);
      expect(writes.containsKey('FLTMODE4'), isFalse);
      expect(writes.containsKey('FLTMODE5'), isFalse);
    });

    test('always includes the channel even with no slots assigned', () {
      const assignment = FlightModeAssignment(channel: 8, slotModes: {});
      final writes = buildFlightModeWrites(assignment);
      expect(writes, {kFlightModeChannelParam: 8.0});
    });
  });

  group('readFlightModeAssignment', () {
    test('round-trips a full assignment through build → read', () {
      const original = FlightModeAssignment(
        channel: 6,
        slotModes: {1: 0, 2: 2, 3: 5, 4: 6, 5: 16, 6: 9},
      );

      final params = buildFlightModeWrites(original);
      final readBack = readFlightModeAssignment(params);

      expect(readBack, original);
    });

    test('defaults the channel when FLTMODE_CH is absent', () {
      final readBack = readFlightModeAssignment({'FLTMODE1': 0.0});
      expect(readBack.channel, kDefaultFlightModeChannel);
      expect(readBack.modeForSlot(1), 0);
    });

    test('omits slots that are not present in the params', () {
      final readBack = readFlightModeAssignment({
        kFlightModeChannelParam: 5.0,
        'FLTMODE2': 3.0,
      });
      expect(readBack.modeForSlot(1), isNull);
      expect(readBack.modeForSlot(2), 3);
      expect(readBack.slotModes, {2: 3});
    });

    test('rounds non-integer param values', () {
      final readBack = readFlightModeAssignment({
        kFlightModeChannelParam: 5.0,
        'FLTMODE1': 2.999,
      });
      expect(readBack.modeForSlot(1), 3);
    });
  });

  group('FlightModeAssignment', () {
    test('withSlotMode assigns and clears slots immutably', () {
      const a = FlightModeAssignment(channel: 5, slotModes: {1: 0});
      final b = a.withSlotMode(2, 6);
      final c = b.withSlotMode(1, null);

      expect(a.slotModes, {1: 0}); // unchanged
      expect(b.slotModes, {1: 0, 2: 6});
      expect(c.slotModes, {2: 6});
    });

    test('equality is value-based and order-independent for slots', () {
      const a = FlightModeAssignment(channel: 5, slotModes: {1: 0, 2: 6});
      const b = FlightModeAssignment(channel: 5, slotModes: {2: 6, 1: 0});
      const different =
          FlightModeAssignment(channel: 5, slotModes: {1: 0, 2: 7});

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == different, isFalse);
    });
  });
}
