import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/providers/units_provider.dart';

void main() {
  group('Unit Conversions', () {
    test('formatDistance metric shows metres for short distances', () {
      final result = formatDistance(500, UnitSystem.metric);
      expect(result, contains('m'));
      expect(result, isNot(contains('km')));
    });

    test('formatDistance metric shows km for long distances', () {
      final result = formatDistance(1500, UnitSystem.metric);
      expect(result, contains('km'));
    });

    test('formatDistance imperial shows miles', () {
      final result = formatDistance(1609.34, UnitSystem.imperial);
      expect(result, contains('mi'));
    });

    test('formatDistance aviation shows nautical miles', () {
      final result = formatDistance(1852, UnitSystem.aviation);
      expect(result, contains('nm'));
    });

    test('formatAltitude metric shows m', () {
      final result = formatAltitude(100, UnitSystem.metric);
      expect(result, contains('m'));
    });

    test('formatAltitude imperial shows ft', () {
      final result = formatAltitude(100, UnitSystem.imperial);
      expect(result, contains('ft'));
    });

    test('formatSpeed metric', () {
      final result = formatSpeed(10, UnitSystem.metric);
      // May use m/s or km/h depending on implementation
      expect(result, anyOf(contains('m/s'), contains('km/h')));
    });

    test('formatSpeed aviation shows knots', () {
      final result = formatSpeed(10, UnitSystem.aviation);
      expect(result, contains('kts'));
    });

    test('formatTemperature metric shows celsius', () {
      final result = formatTemperature(25, UnitSystem.metric);
      expect(result, contains('C'));
    });

    test('formatTemperature imperial shows fahrenheit', () {
      final result = formatTemperature(0, UnitSystem.imperial);
      expect(result, contains('F'));
    });
  });
}
