import 'dart:math' as math;

import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/mission/survey_grid.dart';
import 'package:helios_gcs/shared/models/mission_item.dart';

// ---------------------------------------------------------------------------
// Characterisation tests for the Plan view survey grid.
//
// The survey grid algorithm used to be a private method on _PlanViewState and
// was duplicated here so it could be tested. It now lives in
// lib/core/mission/survey_grid.dart, so these tests exercise the real core
// generator directly. They are retained to prove the generated missions are
// unchanged after the move.
// ---------------------------------------------------------------------------

void main() {
  final gen = SurveyGridGenerator();

  // 100 m x 100 m box near Canberra YFBT (ArduPilot default SITL location).
  const metersPerDegLat = 111319.0;
  const baseLat = -35.3600;
  const baseLon = 149.1600;
  final deltaLat = 100.0 / metersPerDegLat;
  final metersPerDegLon = 111319.0 * math.cos(baseLat * math.pi / 180.0);
  final deltaLon = 100.0 / metersPerDegLon;

  final corner1 = (lat: baseLat, lon: baseLon);
  final corner2 = (lat: baseLat + deltaLat, lon: baseLon + deltaLon);

  const altM = 50.0;
  const laneSpacingM = 20.0;
  const angleDeg = 0;

  List<MissionItem> grid({int existingCount = 0, double spacing = laneSpacingM}) {
    return gen.generateSurveyGrid(
      corner1: corner1,
      corner2: corner2,
      params: SurveyGridParams(
        laneSpacingM: spacing,
        altitudeM: altM,
        angleDeg: angleDeg,
      ),
      existingItemCount: existingCount,
    );
  }

  group('generateSurveyGrid — 100 m x 100 m, 20 m lanes, 0 deg, empty mission',
      () {
    late List<MissionItem> items;

    setUp(() {
      items = grid();
    });

    test('result is non-empty', () {
      expect(items, isNotEmpty);
    });

    test('all items have the correct altitude', () {
      for (final item in items) {
        expect(item.altitude, closeTo(altM, 0.01));
      }
    });

    test('first item is a TAKEOFF command (cmd 22) when mission is empty', () {
      expect(items.first.command, MavCmd.navTakeoff);
      expect(MavCmd.navTakeoff, 22);
    });

    test('all subsequent items after TAKEOFF are WAYPOINT commands (cmd 16)',
        () {
      final waypoints = items.skip(1).toList();
      expect(waypoints, isNotEmpty);
      for (final item in waypoints) {
        expect(item.command, MavCmd.navWaypoint);
      }
    });

    test('sequence numbers are assigned starting from 0', () {
      for (var i = 0; i < items.length; i++) {
        expect(items[i].seq, i);
      }
    });

    test('waypoints alternate sides (lawnmower pattern)', () {
      final waypoints = items.skip(1).toList();
      expect(waypoints.length, greaterThanOrEqualTo(4));
      final row0Start = waypoints[0].longitude;
      final row0End = waypoints[1].longitude;
      final row1Start = waypoints[2].longitude;
      final row1End = waypoints[3].longitude;
      expect(row0Start, lessThan(row0End));
      expect(row1Start, greaterThan(row1End));
    });

    test('waypoints fall within or very near the bounding box', () {
      final minLat = math.min(corner1.lat, corner2.lat);
      final maxLat = math.max(corner1.lat, corner2.lat);
      final minLon = math.min(corner1.lon, corner2.lon);
      final maxLon = math.max(corner1.lon, corner2.lon);
      final latMargin = laneSpacingM / 2.0 / metersPerDegLat + 1e-6;
      final lonMargin = laneSpacingM / 2.0 / metersPerDegLon + 1e-6;
      for (final item in items) {
        expect(item.latitude, greaterThanOrEqualTo(minLat - latMargin));
        expect(item.latitude, lessThanOrEqualTo(maxLat + latMargin));
        expect(item.longitude, greaterThanOrEqualTo(minLon - lonMargin));
        expect(item.longitude, lessThanOrEqualTo(maxLon + lonMargin));
      }
    });
  });

  group('generateSurveyGrid — non-empty existing mission', () {
    test('first item is NOT a TAKEOFF when mission already has items', () {
      final items = grid(existingCount: 3);
      expect(items, isNotEmpty);
      expect(items.any((i) => i.command == MavCmd.navTakeoff), isFalse);
      for (final item in items) {
        expect(item.command, MavCmd.navWaypoint);
      }
    });

    test('sequence numbers continue from existing mission size', () {
      const existing = 5;
      final items = grid(existingCount: existing);
      expect(items, isNotEmpty);
      expect(items.first.seq, existing);
      for (var i = 0; i < items.length; i++) {
        expect(items[i].seq, existing + i);
      }
    });
  });

  group('generateSurveyGrid — lane spacing larger than area', () {
    test('does not throw when lane spacing exceeds area height', () {
      final tinyDeltaLat = 5.0 / metersPerDegLat;
      final items = gen.generateSurveyGrid(
        corner1: corner1,
        corner2: (lat: baseLat + tinyDeltaLat, lon: baseLon + deltaLon),
        params: const SurveyGridParams(
          laneSpacingM: 100.0,
          altitudeM: altM,
          angleDeg: angleDeg,
        ),
      );
      expect(items, isA<List<MissionItem>>());
    });
  });
}
