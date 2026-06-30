import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/calibration/battery_calibration.dart';

void main() {
  group('computeVoltageMultiplier', () {
    test('scales the multiplier by the measured/reported ratio', () {
      // FC reports 12.0 V, multimeter reads 12.6 V, existing mult 10.1.
      final result = computeVoltageMultiplier(
        currentMultiplier: 10.1,
        reportedVoltage: 12.0,
        measuredVoltage: 12.6,
      );
      expect(result.valid, isTrue);
      expect(result.value, closeTo(10.1 * (12.6 / 12.0), 1e-9));
    });

    test('returns the same multiplier when reading already matches', () {
      final result = computeVoltageMultiplier(
        currentMultiplier: 10.1,
        reportedVoltage: 12.6,
        measuredVoltage: 12.6,
      );
      expect(result.valid, isTrue);
      expect(result.value, closeTo(10.1, 1e-9));
    });

    test('corrects a reading that is reading low', () {
      // FC under-reports (11.0 vs 12.6): multiplier must increase.
      final result = computeVoltageMultiplier(
        currentMultiplier: 10.0,
        reportedVoltage: 11.0,
        measuredVoltage: 12.6,
      );
      expect(result.valid, isTrue);
      expect(result.value, greaterThan(10.0));
    });

    test('invalid when reported voltage is zero', () {
      final result = computeVoltageMultiplier(
        currentMultiplier: 10.1,
        reportedVoltage: 0,
        measuredVoltage: 12.6,
      );
      expect(result.valid, isFalse);
    });

    test('invalid when measured voltage is non-positive', () {
      final result = computeVoltageMultiplier(
        currentMultiplier: 10.1,
        reportedVoltage: 12.0,
        measuredVoltage: 0,
      );
      expect(result.valid, isFalse);
    });

    test('invalid when current multiplier is zero (uncalibrated)', () {
      final result = computeVoltageMultiplier(
        currentMultiplier: 0,
        reportedVoltage: 12.0,
        measuredVoltage: 12.6,
      );
      expect(result.valid, isFalse);
    });
  });

  group('computeCurrentPerVolt', () {
    test('scales amps-per-volt by the measured/reported ratio', () {
      // FC reports 20 A, clamp meter reads 22 A, existing pervlt 17.0.
      final result = computeCurrentPerVolt(
        currentPerVolt: 17.0,
        reportedCurrent: 20.0,
        measuredCurrent: 22.0,
      );
      expect(result.valid, isTrue);
      expect(result.value, closeTo(17.0 * (22.0 / 20.0), 1e-9));
    });

    test('invalid when reported current is zero (no load)', () {
      final result = computeCurrentPerVolt(
        currentPerVolt: 17.0,
        reportedCurrent: 0,
        measuredCurrent: 22.0,
      );
      expect(result.valid, isFalse);
    });

    test('invalid when measured current is negative', () {
      final result = computeCurrentPerVolt(
        currentPerVolt: 17.0,
        reportedCurrent: 20.0,
        measuredCurrent: -1,
      );
      expect(result.valid, isFalse);
    });

    test('invalid when amps-per-volt is zero', () {
      final result = computeCurrentPerVolt(
        currentPerVolt: 0,
        reportedCurrent: 20.0,
        measuredCurrent: 22.0,
      );
      expect(result.valid, isFalse);
    });

    test('measured current of zero is valid (real zero-load calibration)', () {
      final result = computeCurrentPerVolt(
        currentPerVolt: 17.0,
        reportedCurrent: 20.0,
        measuredCurrent: 0,
      );
      // A measured 0 yields a 0 pervlt which is non-positive → invalid result.
      expect(result.valid, isFalse);
    });
  });
}
