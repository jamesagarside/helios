import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/telemetry/telemetry_field_registry.dart';

/// Unit tests for the telemetry field registry's custom format support,
/// which is critical to consistent GPS data display across the app.
void main() {
  group('TelemetryFieldRegistry customFormat', () {
    test('all fields have non-null getters', () {
      for (final field in TelemetryFieldRegistry.all) {
        expect(field.getter, isNotNull, reason: '${field.id} has null getter');
        expect(field.id, isNotEmpty, reason: 'field has empty id');
        expect(field.label, isNotEmpty, reason: '${field.id} has empty label');
      }
    });

    test('byId returns correct field', () {
      expect(TelemetryFieldRegistry.byId('bat_v'), isNotNull);
      expect(TelemetryFieldRegistry.byId('gps_hdop'), isNotNull);
      expect(TelemetryFieldRegistry.byId('nonexistent'), isNull);
    });

    test('defaultTileIds are all valid field IDs', () {
      for (final id in TelemetryFieldRegistry.defaultTileIds) {
        expect(TelemetryFieldRegistry.byId(id), isNotNull,
            reason: 'Default tile "$id" not found in registry');
      }
    });

    test('fields with customFormat use it over default', () {
      final hdop = TelemetryFieldRegistry.byId('gps_hdop')!;
      // customFormat should be set
      expect(hdop.customFormat, isNotNull);
      // Default format would give "99.99" but custom gives "--"
      expect(hdop.format(99.99), '--');
      expect(hdop.format(1.5), '1.5');
    });

    test('fields without customFormat use decimal formatting', () {
      final battV = TelemetryFieldRegistry.byId('bat_v')!;
      expect(battV.customFormat, isNull);
      expect(battV.format(12.6), '12.6');
    });

    test('byCategory groups all fields', () {
      final categories = TelemetryFieldRegistry.byCategory;
      expect(categories, isNotEmpty);

      int total = 0;
      for (final group in categories.values) {
        total += group.length;
      }
      expect(total, TelemetryFieldRegistry.all.length);
    });
  });
}
