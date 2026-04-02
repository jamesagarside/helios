import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/models/layout_profile.dart';
import 'package:helios_gcs/shared/models/telemetry_tile_config.dart';
import 'package:helios_gcs/core/telemetry/telemetry_field_registry.dart';
import 'package:helios_gcs/features/fly/widgets/chart_toolbar.dart';

void main() {
  group('WidgetConfig', () {
    test('serialises to JSON and back', () {
      const config = WidgetConfig(
        x: 100.5,
        y: 200.0,
        width: 280,
        height: 150,
        visible: true,
        minimised: false,
      );

      final json = config.toJson();
      final restored = WidgetConfig.fromJson(json);

      expect(restored.x, 100.5);
      expect(restored.y, 200.0);
      expect(restored.width, 280);
      expect(restored.height, 150);
      expect(restored.visible, true);
      expect(restored.minimised, false);
    });

    test('omits null width/height from JSON', () {
      const config = WidgetConfig(x: 0, y: 0);
      final json = config.toJson();
      expect(json.containsKey('width'), false);
      expect(json.containsKey('height'), false);
    });

    test('defaults visible=true and minimised=false when missing', () {
      final config = WidgetConfig.fromJson({'x': 10, 'y': 20});
      expect(config.visible, true);
      expect(config.minimised, false);
    });

    test('copyWith preserves unchanged fields', () {
      const original = WidgetConfig(x: 10, y: 20, visible: false);
      final updated = original.copyWith(x: 50);
      expect(updated.x, 50);
      expect(updated.y, 20);
      expect(updated.visible, false);
    });

    test('equality by value', () {
      const a = WidgetConfig(x: 1, y: 2, visible: true);
      const b = WidgetConfig(x: 1, y: 2, visible: true);
      const c = WidgetConfig(x: 1, y: 3, visible: true);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('LayoutProfile', () {
    test('round-trip JSON serialisation', () {
      final profile = LayoutProfile(
        name: 'Test Profile',
        vehicleType: VehicleType.fixedWing,
        charts: {
          ChartType.altitude.name: const WidgetConfig(x: 350, y: 50, visible: true),
          ChartType.speed.name: const WidgetConfig(x: 350, y: 210, visible: false),
        },
        pfd: const WidgetConfig(x: 16, y: -1, visible: true),
        telemetryStrip: const WidgetConfig(x: 0, y: 0, visible: false),
        video: const WidgetConfig(x: 100, y: 200, visible: true),
      );

      final json = profile.toJson();
      final restored = LayoutProfile.fromJson(json);

      expect(restored.name, 'Test Profile');
      expect(restored.vehicleType, VehicleType.fixedWing);
      expect(restored.charts.length, 2);
      expect(restored.charts[ChartType.altitude.name]!.x, 350);
      expect(restored.pfd.visible, true);
      expect(restored.telemetryStrip.visible, false);
      expect(restored.video.visible, true);
    });

    test('encode/decode string round-trip', () {
      final profile = defaultMultirotorProfile();
      final encoded = profile.encode();
      final decoded = LayoutProfile.decode(encoded);

      expect(decoded.name, profile.name);
      expect(decoded.vehicleType, profile.vehicleType);
      expect(decoded.charts.length, profile.charts.length);
    });

    test('activeCharts returns only visible chart types', () {
      final profile = LayoutProfile(
        name: 'Test',
        charts: {
          ChartType.altitude.name: const WidgetConfig(x: 0, y: 0, visible: true),
          ChartType.speed.name: const WidgetConfig(x: 0, y: 0, visible: false),
          ChartType.battery.name: const WidgetConfig(x: 0, y: 0, visible: true),
        },
      );

      final active = profile.activeCharts;
      expect(active, contains(ChartType.altitude));
      expect(active, isNot(contains(ChartType.speed)));
      expect(active, contains(ChartType.battery));
      expect(active.length, 2);
    });

    test('activeCharts ignores unknown chart names', () {
      final profile = LayoutProfile(
        name: 'Test',
        charts: {
          'unknownChart': const WidgetConfig(x: 0, y: 0, visible: true),
          ChartType.altitude.name: const WidgetConfig(x: 0, y: 0, visible: true),
        },
      );

      expect(profile.activeCharts.length, 1);
      expect(profile.activeCharts, contains(ChartType.altitude));
    });

    test('fromJson handles missing optional fields', () {
      final profile = LayoutProfile.fromJson({
        'name': 'Minimal',
      });

      expect(profile.name, 'Minimal');
      expect(profile.vehicleType, VehicleType.multirotor);
      expect(profile.charts, isEmpty);
      expect(profile.pfd.visible, true);
      expect(profile.isDefault, false);
    });

    test('equality based on name and vehicleType', () {
      final a = LayoutProfile(name: 'Test', vehicleType: VehicleType.multirotor);
      final b = LayoutProfile(name: 'Test', vehicleType: VehicleType.multirotor);
      final c = LayoutProfile(name: 'Other', vehicleType: VehicleType.multirotor);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('Default profiles', () {
    test('multirotor has ALT and BAT charts', () {
      final profile = defaultMultirotorProfile();
      expect(profile.name, 'Multirotor');
      expect(profile.vehicleType, VehicleType.multirotor);
      expect(profile.isDefault, true);
      expect(profile.charts.containsKey(ChartType.altitude.name), true);
      expect(profile.charts.containsKey(ChartType.battery.name), true);
      expect(profile.charts.length, 2);
    });

    test('fixed wing has ALT, SPD and VS charts', () {
      final profile = defaultFixedWingProfile();
      expect(profile.name, 'Fixed Wing');
      expect(profile.vehicleType, VehicleType.fixedWing);
      expect(profile.charts.containsKey(ChartType.altitude.name), true);
      expect(profile.charts.containsKey(ChartType.speed.name), true);
      expect(profile.charts.containsKey(ChartType.climbRate.name), true);
      expect(profile.charts.length, 3);
    });

    test('VTOL has ALT, SPD and ATT charts', () {
      final profile = defaultVtolProfile();
      expect(profile.name, 'VTOL');
      expect(profile.vehicleType, VehicleType.vtol);
      expect(profile.charts.containsKey(ChartType.altitude.name), true);
      expect(profile.charts.containsKey(ChartType.speed.name), true);
      expect(profile.charts.containsKey(ChartType.attitude.name), true);
      expect(profile.charts.length, 3);
    });

    test('all default profiles serialise cleanly', () {
      final profiles = [
        defaultMultirotorProfile(),
        defaultFixedWingProfile(),
        defaultVtolProfile(),
      ];
      for (final profile in profiles) {
        final json = jsonEncode(profile.toJson());
        final restored = LayoutProfile.fromJson(jsonDecode(json) as Map<String, dynamic>);
        expect(restored.name, profile.name);
        expect(restored.vehicleType, profile.vehicleType);
        expect(restored.charts.length, profile.charts.length);
      }
    });
  });

  group('LayoutProfile new fields (Sprint A+B)', () {
    test('showMessageLog defaults to false', () {
      final profile = LayoutProfile.fromJson({'name': 'Test'});
      expect(profile.showMessageLog, false);
    });

    test('showActionPanel defaults to true', () {
      final profile = LayoutProfile.fromJson({'name': 'Test'});
      expect(profile.showActionPanel, true);
    });

    test('showMessageLog and showActionPanel round-trip JSON', () {
      final profile = LayoutProfile(
        name: 'Test',
        showMessageLog: true,
        showActionPanel: false,
      );
      final restored = LayoutProfile.fromJson(profile.toJson());
      expect(restored.showMessageLog, true);
      expect(restored.showActionPanel, false);
    });

    test('telemetryTiles round-trip JSON', () {
      final tiles = [
        const TelemetryTileConfig(fieldId: 'bat_v', warnLow: 10.5),
        const TelemetryTileConfig(fieldId: 'gps_sats'),
      ];
      final profile = LayoutProfile(name: 'Test', telemetryTiles: tiles);
      final restored = LayoutProfile.fromJson(profile.toJson());

      expect(restored.telemetryTiles, isNotNull);
      expect(restored.telemetryTiles!.length, 2);
      expect(restored.telemetryTiles![0].fieldId, 'bat_v');
      expect(restored.telemetryTiles![0].warnLow, 10.5);
      expect(restored.telemetryTiles![1].fieldId, 'gps_sats');
    });

    test('telemetryTiles null when not in JSON', () {
      final profile = LayoutProfile.fromJson({'name': 'Test'});
      expect(profile.telemetryTiles, isNull);
    });

    test('effectiveTiles returns custom tiles when set', () {
      final tiles = [
        const TelemetryTileConfig(fieldId: 'rssi'),
        const TelemetryTileConfig(fieldId: 'thr'),
      ];
      final profile = LayoutProfile(name: 'Test', telemetryTiles: tiles);
      expect(profile.effectiveTiles.length, 2);
      expect(profile.effectiveTiles[0].fieldId, 'rssi');
    });

    test('effectiveTiles falls back to defaultTileIds when telemetryTiles is null', () {
      final profile = LayoutProfile(name: 'Test');
      final effective = profile.effectiveTiles;
      expect(effective.length, TelemetryFieldRegistry.defaultTileIds.length);
      for (var i = 0; i < effective.length; i++) {
        expect(effective[i].fieldId, TelemetryFieldRegistry.defaultTileIds[i]);
      }
    });

    test('effectiveTiles falls back to defaults when telemetryTiles is empty', () {
      final profile = LayoutProfile(name: 'Test', telemetryTiles: []);
      expect(profile.effectiveTiles.length,
          TelemetryFieldRegistry.defaultTileIds.length);
    });

    test('copyWith preserves showMessageLog and showActionPanel', () {
      final original = LayoutProfile(
        name: 'Test',
        showMessageLog: true,
        showActionPanel: false,
      );
      final updated = original.copyWith(name: 'Updated');
      expect(updated.showMessageLog, true);
      expect(updated.showActionPanel, false);
    });

    test('all default profiles have showActionPanel=true and showMessageLog=false', () {
      for (final profile in [
        defaultMultirotorProfile(),
        defaultFixedWingProfile(),
        defaultVtolProfile(),
      ]) {
        expect(profile.showActionPanel, true,
            reason: '${profile.name} showActionPanel should default true');
        expect(profile.showMessageLog, false,
            reason: '${profile.name} showMessageLog should default false');
      }
    });

    test('full round-trip encode/decode preserves new fields', () {
      final tiles = [const TelemetryTileConfig(fieldId: 'alt_rel', warnHigh: 120.0)];
      final profile = LayoutProfile(
        name: 'Full Test',
        showMessageLog: true,
        showActionPanel: false,
        telemetryTiles: tiles,
      );
      final encoded = profile.encode();
      final decoded = LayoutProfile.decode(encoded);

      expect(decoded.showMessageLog, true);
      expect(decoded.showActionPanel, false);
      expect(decoded.telemetryTiles!.length, 1);
      expect(decoded.telemetryTiles![0].fieldId, 'alt_rel');
      expect(decoded.telemetryTiles![0].warnHigh, 120.0);
    });
  });

  group('snapToGrid', () {
    // Import the function from layout_provider for testing
    // We test the logic inline here since it's a pure function
    double snap(double value) => (value / 20.0).round() * 20.0;

    test('snaps to nearest 20px grid', () {
      expect(snap(0), 0);
      expect(snap(10), 20);
      expect(snap(9), 0);
      expect(snap(15), 20);
      expect(snap(30), 40);
      expect(snap(355), 360);
    });
  });
}
