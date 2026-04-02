import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/models/telemetry_tile_config.dart';

void main() {
  group('TelemetryTileConfig', () {
    test('minimal round-trip JSON (no warn thresholds)', () {
      const config = TelemetryTileConfig(fieldId: 'bat_v');
      final json = config.toJson();
      final restored = TelemetryTileConfig.fromJson(json);

      expect(restored.fieldId, 'bat_v');
      expect(restored.warnLow, isNull);
      expect(restored.warnHigh, isNull);
    });

    test('round-trip JSON with warn thresholds', () {
      const config = TelemetryTileConfig(
        fieldId: 'gps_sats',
        warnLow: 5.0,
        warnHigh: 100.0,
      );
      final json = config.toJson();
      final restored = TelemetryTileConfig.fromJson(json);

      expect(restored.fieldId, 'gps_sats');
      expect(restored.warnLow, 5.0);
      expect(restored.warnHigh, 100.0);
    });

    test('toJson omits null warn thresholds', () {
      const config = TelemetryTileConfig(fieldId: 'rssi');
      final json = config.toJson();

      expect(json.containsKey('warnLow'), false);
      expect(json.containsKey('warnHigh'), false);
    });

    test('toJson includes warn thresholds when set', () {
      const config =
          TelemetryTileConfig(fieldId: 'rssi', warnLow: 50.0, warnHigh: 200.0);
      final json = config.toJson();

      expect(json['warnLow'], 50.0);
      expect(json['warnHigh'], 200.0);
    });

    test('fromJson handles integer warn values (num→double)', () {
      final config = TelemetryTileConfig.fromJson({
        'fieldId': 'alt_rel',
        'warnLow': 10,
        'warnHigh': 120,
      });

      expect(config.warnLow, 10.0);
      expect(config.warnHigh, 120.0);
    });

    test('equality: same values are equal', () {
      const a = TelemetryTileConfig(fieldId: 'bat_pct', warnLow: 15.0);
      const b = TelemetryTileConfig(fieldId: 'bat_pct', warnLow: 15.0);

      expect(a, equals(b));
    });

    test('equality: different fieldId are not equal', () {
      const a = TelemetryTileConfig(fieldId: 'bat_v');
      const b = TelemetryTileConfig(fieldId: 'bat_pct');

      expect(a, isNot(equals(b)));
    });

    test('equality: different warnLow are not equal', () {
      const a = TelemetryTileConfig(fieldId: 'bat_v', warnLow: 10.0);
      const b = TelemetryTileConfig(fieldId: 'bat_v', warnLow: 11.0);

      expect(a, isNot(equals(b)));
    });

    test('copyWith changes fieldId', () {
      const original = TelemetryTileConfig(fieldId: 'bat_v', warnLow: 10.0);
      final updated = original.copyWith(fieldId: 'bat_pct');

      expect(updated.fieldId, 'bat_pct');
      expect(updated.warnLow, 10.0); // unchanged
    });

    test('copyWith changes warnLow', () {
      const original =
          TelemetryTileConfig(fieldId: 'bat_v', warnLow: 10.0, warnHigh: 20.0);
      final updated = original.copyWith(warnLow: 9.0);

      expect(updated.warnLow, 9.0);
      expect(updated.warnHigh, 20.0); // unchanged
      expect(updated.fieldId, 'bat_v'); // unchanged
    });

    test('hashCode is consistent with equality', () {
      const a = TelemetryTileConfig(fieldId: 'bat_v', warnLow: 10.5);
      const b = TelemetryTileConfig(fieldId: 'bat_v', warnLow: 10.5);

      expect(a.hashCode, b.hashCode);
    });
  });
}
