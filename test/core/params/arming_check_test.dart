import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/params/arming_check.dart';

/// Correctness gate for ARMING_CHECK bitmask encode/decode. A wrong rule here
/// silently disables (or fails to enable) pre-arm safety checks, so the toggle,
/// "All" expansion, and round-trip behaviour are pinned with explicit values.
void main() {
  group('ArmingCheckMask decode', () {
    test('fromParam rounds the double parameter value to an int', () {
      expect(ArmingCheckMask.fromParam(0.0).value, 0);
      expect(ArmingCheckMask.fromParam(1.0).value, armingCheckAll);
      // FC stores ints as doubles; tolerate tiny float error.
      expect(ArmingCheckMask.fromParam(8190.0).value, 8190);
      expect(ArmingCheckMask.fromParam(8189.9999).value, 8190);
    });

    test('isAll / isNone sentinels', () {
      expect(const ArmingCheckMask(armingCheckAll).isAll, isTrue);
      expect(const ArmingCheckMask(armingCheckAll).isNone, isFalse);
      expect(const ArmingCheckMask(0).isNone, isTrue);
      expect(const ArmingCheckMask(0).isAll, isFalse);
      // A regular bitmask is neither.
      const mask = ArmingCheckMask(0x06);
      expect(mask.isAll, isFalse);
      expect(mask.isNone, isFalse);
    });

    test('"All" reports every category as enabled', () {
      const mask = ArmingCheckMask(armingCheckAll);
      for (final c in armingCheckBits) {
        expect(mask.isEnabled(c.bit), isTrue, reason: c.label);
      }
      expect(mask.enabledBits, armingCheckBits.map((c) => c.bit).toSet());
    });

    test('individual bits decode correctly', () {
      // Barometer (1<<1) + Compass (1<<2) = 0x06.
      const mask = ArmingCheckMask(0x06);
      expect(mask.isEnabled(1 << 1), isTrue); // Barometer
      expect(mask.isEnabled(1 << 2), isTrue); // Compass
      expect(mask.isEnabled(1 << 3), isFalse); // GPS Lock
      expect(mask.enabledBits, {1 << 1, 1 << 2});
    });

    test('none has no enabled bits', () {
      expect(const ArmingCheckMask(0).enabledBits, isEmpty);
    });
  });

  group('ArmingCheckMask encode / toggle', () {
    test('toggling a bit on sets it without disturbing others', () {
      const start = ArmingCheckMask(1 << 1); // Barometer
      final next = start.toggle(1 << 3, true); // + GPS Lock
      expect(next.value, (1 << 1) | (1 << 3));
      expect(next.isEnabled(1 << 1), isTrue);
      expect(next.isEnabled(1 << 3), isTrue);
    });

    test('toggling a bit off clears only that bit', () {
      const start = ArmingCheckMask((1 << 1) | (1 << 2) | (1 << 3));
      final next = start.toggle(1 << 2, false); // remove Compass
      expect(next.value, (1 << 1) | (1 << 3));
      expect(next.isEnabled(1 << 2), isFalse);
    });

    test('toggling a category off while in "All" mode expands to explicit bits',
        () {
      const all = ArmingCheckMask(armingCheckAll);
      final next = all.toggle(1 << 3, false); // uncheck GPS Lock
      // Should now be the full category set minus the one bit, NOT 0 and NOT 1.
      expect(next.isAll, isFalse);
      expect(next.isEnabled(1 << 3), isFalse);
      expect(next.isEnabled(1 << 1), isTrue);
      expect(next.isEnabled(1 << 2), isTrue);
      final expected = armingCheckBits
          .map((c) => c.bit)
          .where((b) => b != (1 << 3))
          .fold<int>(0, (acc, b) => acc | b);
      expect(next.value, expected);
    });

    test('toggling a bit already in its target state is a no-op value', () {
      const mask = ArmingCheckMask((1 << 1) | (1 << 4));
      expect(mask.toggle(1 << 1, true).value, mask.value);
      expect(mask.toggle(1 << 5, false).value, mask.value);
    });

    test('selectAll / selectNone produce the sentinels', () {
      const mask = ArmingCheckMask(0x06);
      expect(mask.selectAll().value, armingCheckAll);
      expect(mask.selectNone().value, armingCheckNone);
    });
  });

  group('round-trip', () {
    test('value survives decode -> param -> decode', () {
      for (final v in [0, 1, 0x06, 0x1FE, 0xFFFFE]) {
        final mask = ArmingCheckMask(v);
        final round = ArmingCheckMask.fromParam(mask.paramValue);
        expect(round.value, v);
        expect(round, mask);
      }
    });

    test('paramValue is the integer as a double', () {
      expect(const ArmingCheckMask(8190).paramValue, 8190.0);
    });
  });

  group('definitions', () {
    test('category bits are unique and exclude the "All" sentinel', () {
      final bits = armingCheckBits.map((c) => c.bit).toList();
      expect(bits.toSet().length, bits.length, reason: 'bits must be unique');
      expect(bits, isNot(contains(armingCheckAll)));
    });

    test('every category has a label and description', () {
      for (final c in armingCheckBits) {
        expect(c.label, isNotEmpty);
        expect(c.description, isNotEmpty);
      }
    });
  });
}
