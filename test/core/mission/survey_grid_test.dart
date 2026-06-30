import 'dart:math' as math;

import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/mission/survey_grid.dart';
import 'package:helios_gcs/shared/models/mission_item.dart';

void main() {
  final gen = SurveyGridGenerator();

  // 100 m x 100 m box near Canberra YFBT (ArduPilot default SITL location).
  const metersPerDegLat = 111319.0;
  const baseLat = -35.3600;
  const baseLon = 149.1600;
  final metersPerDegLon = 111319.0 * math.cos(baseLat * math.pi / 180.0);
  final deltaLat = 100.0 / metersPerDegLat;
  final deltaLon = 100.0 / metersPerDegLon;

  final corner1 = (lat: baseLat, lon: baseLon);
  final corner2 = (lat: baseLat + deltaLat, lon: baseLon + deltaLon);

  const altM = 50.0;
  const laneSpacingM = 20.0;

  group('generateSurveyGrid — 0 degree grid, empty mission', () {
    late List<MissionItem> items;

    setUp(() {
      items = gen.generateSurveyGrid(
        corner1: corner1,
        corner2: corner2,
        params: const SurveyGridParams(
          laneSpacingM: laneSpacingM,
          altitudeM: altM,
          angleDeg: 0,
        ),
      );
    });

    test('result is non-empty', () {
      expect(items, isNotEmpty);
    });

    test('all items have the requested altitude', () {
      for (final item in items) {
        expect(item.altitude, closeTo(altM, 0.01));
      }
    });

    test('first item is TAKEOFF (cmd 22) when mission is empty', () {
      expect(items.first.command, MavCmd.navTakeoff);
      expect(MavCmd.navTakeoff, 22);
    });

    test('subsequent items are WAYPOINT (cmd 16)', () {
      final waypoints = items.skip(1).toList();
      expect(waypoints, isNotEmpty);
      for (final item in waypoints) {
        expect(item.command, MavCmd.navWaypoint);
      }
    });

    test('sequence numbers start at 0 and increment', () {
      for (var i = 0; i < items.length; i++) {
        expect(items[i].seq, i);
      }
    });

    test('waypoints alternate sides (lawnmower)', () {
      final waypoints = items.skip(1).toList();
      expect(waypoints.length, greaterThanOrEqualTo(4));
      expect(waypoints[0].longitude, lessThan(waypoints[1].longitude));
      expect(waypoints[2].longitude, greaterThan(waypoints[3].longitude));
    });

    test('waypoints fall within or near the bounding box', () {
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

  group('generateSurveyGrid — rotated grid', () {
    test('45 degree rotation produces a valid, non-empty mission', () {
      final items = gen.generateSurveyGrid(
        corner1: corner1,
        corner2: corner2,
        params: const SurveyGridParams(
          laneSpacingM: laneSpacingM,
          altitudeM: altM,
          angleDeg: 45,
        ),
      );
      expect(items, isNotEmpty);
      expect(items.first.command, MavCmd.navTakeoff);
      for (final item in items.skip(1)) {
        expect(item.command, MavCmd.navWaypoint);
      }
    });

    test('rotation changes the generated geometry vs 0 degrees', () {
      final straight = gen.generateSurveyGrid(
        corner1: corner1,
        corner2: corner2,
        params: const SurveyGridParams(
          laneSpacingM: laneSpacingM,
          altitudeM: altM,
          angleDeg: 0,
        ),
      );
      final rotated = gen.generateSurveyGrid(
        corner1: corner1,
        corner2: corner2,
        params: const SurveyGridParams(
          laneSpacingM: laneSpacingM,
          altitudeM: altM,
          angleDeg: 30,
        ),
      );
      // At least one waypoint position must differ once the grid is rotated.
      final differs = straight.length != rotated.length ||
          List.generate(math.min(straight.length, rotated.length), (i) => i)
              .any((i) =>
                  (straight[i].latitude - rotated[i].latitude).abs() > 1e-9 ||
                  (straight[i].longitude - rotated[i].longitude).abs() > 1e-9);
      expect(differs, isTrue);
    });
  });

  group('generateSurveyGrid — non-empty existing mission', () {
    test('no TAKEOFF prepended when mission already has items', () {
      final items = gen.generateSurveyGrid(
        corner1: corner1,
        corner2: corner2,
        params: const SurveyGridParams(
          laneSpacingM: laneSpacingM,
          altitudeM: altM,
          angleDeg: 0,
        ),
        existingItemCount: 3,
      );
      expect(items, isNotEmpty);
      expect(items.any((i) => i.command == MavCmd.navTakeoff), isFalse);
      for (final item in items) {
        expect(item.command, MavCmd.navWaypoint);
      }
    });

    test('sequence numbers continue from existing mission size', () {
      const existing = 5;
      final items = gen.generateSurveyGrid(
        corner1: corner1,
        corner2: corner2,
        params: const SurveyGridParams(
          laneSpacingM: laneSpacingM,
          altitudeM: altM,
          angleDeg: 0,
        ),
        existingItemCount: existing,
      );
      expect(items, isNotEmpty);
      expect(items.first.seq, existing);
      for (var i = 0; i < items.length; i++) {
        expect(items[i].seq, existing + i);
      }
    });
  });

  group('generatePolygonSurvey — clipped lawnmower', () {
    // Triangle: bottom edge ~100 m wide, apex ~100 m north of the base centre.
    final triangle = <GeoPoint>[
      (lat: baseLat, lon: baseLon),
      (lat: baseLat, lon: baseLon + deltaLon),
      (lat: baseLat + deltaLat, lon: baseLon + deltaLon / 2.0),
    ];

    test('produces a non-empty clipped mission for a triangle', () {
      final items = gen.generatePolygonSurvey(
        polygon: triangle,
        spacingM: laneSpacingM,
        altM: altM,
      );
      expect(items, isNotEmpty);
      expect(items.first.command, MavCmd.navTakeoff);
    });

    test('returns empty for fewer than 3 vertices', () {
      final items = gen.generatePolygonSurvey(
        polygon: [
          (lat: baseLat, lon: baseLon),
          (lat: baseLat + deltaLat, lon: baseLon),
        ],
        spacingM: laneSpacingM,
        altM: altM,
      );
      expect(items, isEmpty);
    });

    test('sequence numbers are contiguous from 0', () {
      final items = gen.generatePolygonSurvey(
        polygon: triangle,
        spacingM: laneSpacingM,
        altM: altM,
      );
      for (var i = 0; i < items.length; i++) {
        expect(items[i].seq, i);
      }
    });

    test('clipped width per row narrows toward the apex', () {
      // For a triangle narrowing upward, scan rows higher up should span a
      // smaller longitude range than rows lower down.
      final items = gen
          .generatePolygonSurvey(
            polygon: triangle,
            spacingM: laneSpacingM,
            altM: altM,
          )
          .where((i) => i.command == MavCmd.navWaypoint)
          .toList();
      expect(items.length, greaterThanOrEqualTo(4));
      double rowSpan(MissionItem a, MissionItem b) =>
          (a.longitude - b.longitude).abs();
      final firstRowSpan = rowSpan(items[0], items[1]);
      final lastRowSpan = rowSpan(items[items.length - 2], items.last);
      expect(lastRowSpan, lessThan(firstRowSpan));
    });

    test('existing mission count offsets sequence and omits TAKEOFF', () {
      final items = gen.generatePolygonSurvey(
        polygon: triangle,
        spacingM: laneSpacingM,
        altM: altM,
        existingItemCount: 4,
      );
      expect(items, isNotEmpty);
      expect(items.any((i) => i.command == MavCmd.navTakeoff), isFalse);
      expect(items.first.seq, 4);
    });
  });

  group('generateOrbitWaypoints', () {
    final centre = (lat: baseLat, lon: baseLon);
    const radiusM = 50.0;

    test('emits TAKEOFF + laps * 12 waypoints', () {
      final items = gen.generateOrbitWaypoints(
        centre: centre,
        params: const OrbitParams(radiusM: radiusM, altitudeM: altM, laps: 2),
      );
      expect(items.length, 1 + 2 * 12);
      expect(items.first.command, MavCmd.navTakeoff);
      for (final item in items.skip(1)) {
        expect(item.command, MavCmd.navWaypoint);
      }
    });

    test('sequence numbers are contiguous from 0', () {
      final items = gen.generateOrbitWaypoints(
        centre: centre,
        params: const OrbitParams(radiusM: radiusM, altitudeM: altM, laps: 1),
      );
      for (var i = 0; i < items.length; i++) {
        expect(items[i].seq, i);
      }
    });

    test('all orbit points sit ~radius from the centre', () {
      const earthRadius = 6371000.0;
      final items = gen.generateOrbitWaypoints(
        centre: centre,
        params: const OrbitParams(radiusM: radiusM, altitudeM: altM, laps: 1),
      );
      for (final item in items) {
        final dLat = (item.latitude - centre.lat) * math.pi / 180.0;
        final dLon = (item.longitude - centre.lon) * math.pi / 180.0;
        final dy = dLat * earthRadius;
        final dx =
            dLon * earthRadius * math.cos(centre.lat * math.pi / 180.0);
        final dist = math.sqrt(dx * dx + dy * dy);
        expect(dist, closeTo(radiusM, 1.0));
      }
    });
  });

  group('characterisation — generated missions are stable', () {
    test('grid waypoints match recorded coordinates', () {
      final items = gen.generateSurveyGrid(
        corner1: corner1,
        corner2: corner2,
        params: const SurveyGridParams(
          laneSpacingM: laneSpacingM,
          altitudeM: altM,
          angleDeg: 0,
        ),
      );
      // Snapshot: count and the first/last coordinate are pinned so any change
      // to the algorithm is caught.
      expect(items.length, 11); // TAKEOFF + 5 rows x 2 endpoints.
      expect(items.first.latitude, closeTo(-35.35991016807553, 1e-9));
      expect(items.first.longitude, closeTo(149.16, 1e-9));
      expect(items.last.latitude, closeTo(-35.35919151267978, 1e-9));
      expect(items.last.longitude, closeTo(149.16110151316184, 1e-9));
    });

    test('orbit first waypoint is at 0 radians (due north of centre)', () {
      final items = gen.generateOrbitWaypoints(
        centre: (lat: baseLat, lon: baseLon),
        params: const OrbitParams(radiusM: 50.0, altitudeM: altM, laps: 1),
      );
      // angle 0 => offset purely in latitude, longitude == centre longitude.
      expect(items.first.longitude, closeTo(baseLon, 1e-9));
      expect(items.first.latitude, greaterThan(baseLat));
    });
  });
}
