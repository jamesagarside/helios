import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/airframe/board_orientation.dart';

void main() {
  group('BoardOrientations catalogue', () {
    test('includes the common everyday rotations with stable values', () {
      expect(BoardOrientations.byValue(0)?.label, 'None (forward, level)');
      expect(BoardOrientations.byValue(2)?.label, 'Yaw 90°');
      expect(BoardOrientations.byValue(4)?.label, 'Yaw 180°');
      expect(BoardOrientations.byValue(6)?.label, 'Yaw 270°');
      expect(BoardOrientations.byValue(8)?.label, 'Roll 180°');
    });

    test('none constant is value 0', () {
      expect(BoardOrientations.none.value, 0);
    });

    test('every catalogue value is unique', () {
      final values = BoardOrientations.all.map((o) => o.value).toList();
      expect(values.toSet().length, values.length);
    });

    test('byValue returns null for an unknown rotation', () {
      expect(BoardOrientations.byValue(999), isNull);
    });
  });

  group('labelFor', () {
    test('returns the catalogue label for a known value', () {
      expect(BoardOrientations.labelFor(2), 'Yaw 90°');
    });

    test('falls back to a Custom label for unknown values', () {
      expect(BoardOrientations.labelFor(123), 'Custom (123)');
    });
  });

  group('resolveValue (param read mapping)', () {
    test('prefers AHRS_ORIENTATION when present', () {
      final v = BoardOrientations.resolveValue(
        ahrsOrientation: 4,
        compassOrient: 2,
      );
      expect(v, 4);
    });

    test('falls back to COMPASS_ORIENT when AHRS absent', () {
      final v = BoardOrientations.resolveValue(compassOrient: 6);
      expect(v, 6);
    });

    test('returns null when neither parameter is present', () {
      expect(BoardOrientations.resolveValue(), isNull);
    });

    test('rounds the MAVLink float value to the nearest rotation code', () {
      expect(
        BoardOrientations.resolveValue(ahrsOrientation: 8.0),
        8,
      );
      expect(
        BoardOrientations.resolveValue(ahrsOrientation: 1.999999),
        2,
      );
    });
  });

  group('BoardOrientation equality', () {
    test('same value and label are equal', () {
      expect(
        const BoardOrientation(2, 'Yaw 90°'),
        const BoardOrientation(2, 'Yaw 90°'),
      );
    });

    test('different value is not equal', () {
      expect(
        const BoardOrientation(2, 'Yaw 90°') ==
            const BoardOrientation(3, 'Yaw 90°'),
        isFalse,
      );
    });
  });
}
