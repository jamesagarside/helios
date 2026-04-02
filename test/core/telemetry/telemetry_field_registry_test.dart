import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/telemetry/telemetry_field_registry.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';

void main() {
  group('TelemetryFieldRegistry.all', () {
    test('contains at least 20 fields', () {
      expect(TelemetryFieldRegistry.all.length, greaterThanOrEqualTo(20));
    });

    test('all field IDs are unique', () {
      final ids = TelemetryFieldRegistry.all.map((f) => f.id).toList();
      expect(ids.length, ids.toSet().length,
          reason: 'Duplicate field IDs in registry');
    });

    test('all fields have non-empty id, label, and category', () {
      for (final f in TelemetryFieldRegistry.all) {
        expect(f.id, isNotEmpty, reason: 'Empty id in field ${f.label}');
        expect(f.label, isNotEmpty, reason: 'Empty label in field ${f.id}');
        expect(f.category, isNotEmpty,
            reason: 'Empty category in field ${f.id}');
      }
    });

    test('all fields have non-negative formatDecimals', () {
      for (final f in TelemetryFieldRegistry.all) {
        expect(f.formatDecimals, greaterThanOrEqualTo(0),
            reason: 'Negative formatDecimals in field ${f.id}');
      }
    });

    test('getters return doubles from a default VehicleState', () {
      const state = VehicleState();
      for (final f in TelemetryFieldRegistry.all) {
        expect(() => f.getter(state), returnsNormally,
            reason: 'Getter threw for field ${f.id}');
        final value = f.getter(state);
        expect(value, isA<double>(), reason: 'Getter returned non-double for ${f.id}');
      }
    });
  });

  group('TelemetryFieldRegistry.byId', () {
    test('returns null for unknown id', () {
      expect(TelemetryFieldRegistry.byId('nonexistent'), isNull);
    });

    test('returns correct field for bat_v', () {
      final f = TelemetryFieldRegistry.byId('bat_v');
      expect(f, isNotNull);
      expect(f!.id, 'bat_v');
      expect(f.label, 'BATT');
      expect(f.unit, 'V');
      expect(f.category, 'Battery');
    });

    test('returns correct field for gps_sats', () {
      final f = TelemetryFieldRegistry.byId('gps_sats');
      expect(f, isNotNull);
      expect(f!.formatDecimals, 0);
      expect(f.category, 'GPS');
    });

    test('returns correct field for alt_rel', () {
      final f = TelemetryFieldRegistry.byId('alt_rel');
      expect(f, isNotNull);
      expect(f!.unit, 'm');
      expect(f.category, 'Altitude');
    });

    test('returns correct field for rssi', () {
      final f = TelemetryFieldRegistry.byId('rssi');
      expect(f, isNotNull);
      expect(f!.category, 'Link');
    });

    test('all ids in all list are retrievable via byId', () {
      for (final field in TelemetryFieldRegistry.all) {
        final found = TelemetryFieldRegistry.byId(field.id);
        expect(found, isNotNull, reason: 'byId returned null for ${field.id}');
        expect(found!.id, field.id);
      }
    });
  });

  group('TelemetryFieldRegistry.byCategory', () {
    test('contains Battery category', () {
      expect(TelemetryFieldRegistry.byCategory.containsKey('Battery'), true);
    });

    test('Battery category has bat_v, bat_pct, bat_a, bat_mah', () {
      final battery = TelemetryFieldRegistry.byCategory['Battery']!;
      final ids = battery.map((f) => f.id).toSet();
      expect(ids, containsAll(['bat_v', 'bat_pct', 'bat_a', 'bat_mah']));
    });

    test('GPS category contains gps_sats and gps_hdop', () {
      final gps = TelemetryFieldRegistry.byCategory['GPS']!;
      final ids = gps.map((f) => f.id).toSet();
      expect(ids, containsAll(['gps_sats', 'gps_hdop']));
    });

    test('Speed category contains spd_ias, spd_gs, spd_vs', () {
      final speed = TelemetryFieldRegistry.byCategory['Speed']!;
      final ids = speed.map((f) => f.id).toSet();
      expect(ids, containsAll(['spd_ias', 'spd_gs', 'spd_vs']));
    });

    test('total field count across categories matches all list', () {
      final allCount = TelemetryFieldRegistry.all.length;
      final catCount = TelemetryFieldRegistry.byCategory.values
          .fold(0, (sum, list) => sum + list.length);
      expect(catCount, allCount);
    });
  });

  group('TelemetryFieldRegistry.defaultTileIds', () {
    test('has 12 default tiles', () {
      expect(TelemetryFieldRegistry.defaultTileIds.length, 12);
    });

    test('all default tile IDs exist in the registry', () {
      for (final id in TelemetryFieldRegistry.defaultTileIds) {
        expect(TelemetryFieldRegistry.byId(id), isNotNull,
            reason: 'Default tile id "$id" not found in registry');
      }
    });

    test('contains essential fields', () {
      expect(TelemetryFieldRegistry.defaultTileIds,
          containsAll(['bat_v', 'bat_pct', 'gps_sats', 'alt_rel', 'rssi']));
    });

    test('default tile IDs are unique', () {
      final ids = TelemetryFieldRegistry.defaultTileIds;
      expect(ids.length, ids.toSet().length);
    });
  });

  group('TelemetryFieldDef.format', () {
    test('formatDecimals 0 returns integer string', () {
      final f = TelemetryFieldRegistry.byId('gps_sats')!;
      expect(f.format(7.9), '8');
    });

    test('formatDecimals 1 returns one decimal place', () {
      final f = TelemetryFieldRegistry.byId('bat_v')!;
      expect(f.format(11.1), '11.1');
    });

    test('formatDecimals 6 returns 6 decimal places', () {
      final f = TelemetryFieldRegistry.byId('gps_lat')!;
      expect(f.format(51.5074), '51.507400');
    });
  });
}
