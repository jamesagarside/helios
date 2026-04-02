import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/simulate/sitl_injector.dart';

void main() {
  group('SitlInjector', () {
    // ── Instantiation ──────────────────────────────────────────────────────

    test('instantiates without error', () {
      expect(() => const SitlInjector(), returnsNormally);
    });

    test('is const-constructible', () {
      const injector1 = SitlInjector();
      const injector2 = SitlInjector();
      // Both are valid instances; we verify they are the same const value.
      expect(identical(injector1, injector2), isTrue);
    });

    // ── validSpeedMultipliers ──────────────────────────────────────────────

    test('validSpeedMultipliers contains expected values', () {
      expect(
        SitlInjector.validSpeedMultipliers,
        containsAll([1, 2, 4, 8]),
      );
    });

    test('validSpeedMultipliers has exactly four entries', () {
      expect(SitlInjector.validSpeedMultipliers.length, equals(4));
    });

    // ── clampSpeedMultiplier ───────────────────────────────────────────────

    test('clampSpeedMultiplier(1) returns 1', () {
      expect(SitlInjector.clampSpeedMultiplier(1), equals(1));
    });

    test('clampSpeedMultiplier(2) returns 2', () {
      expect(SitlInjector.clampSpeedMultiplier(2), equals(2));
    });

    test('clampSpeedMultiplier(4) returns 4', () {
      expect(SitlInjector.clampSpeedMultiplier(4), equals(4));
    });

    test('clampSpeedMultiplier(8) returns 8', () {
      expect(SitlInjector.clampSpeedMultiplier(8), equals(8));
    });

    test('clampSpeedMultiplier(0) clamps to 1', () {
      expect(SitlInjector.clampSpeedMultiplier(0), equals(1));
    });

    test('clampSpeedMultiplier(-5) clamps to 1', () {
      expect(SitlInjector.clampSpeedMultiplier(-5), equals(1));
    });

    test('clampSpeedMultiplier(3) rounds up to 4', () {
      expect(SitlInjector.clampSpeedMultiplier(3), equals(4));
    });

    test('clampSpeedMultiplier(5) rounds up to 8', () {
      expect(SitlInjector.clampSpeedMultiplier(5), equals(8));
    });

    test('clampSpeedMultiplier(100) clamps to 8', () {
      expect(SitlInjector.clampSpeedMultiplier(100), equals(8));
    });

    test('clampSpeedMultiplier(7) rounds up to 8', () {
      expect(SitlInjector.clampSpeedMultiplier(7), equals(8));
    });
  });
}
