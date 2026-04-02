import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/mission/mission_file_service.dart';
import 'package:helios_gcs/shared/models/fence_zone.dart';
import 'package:helios_gcs/shared/models/mission_item.dart';
import 'package:helios_gcs/shared/models/rally_point.dart';

void main() {
  late MissionFileService service;

  setUp(() {
    service = MissionFileService();
  });

  final testItems = [
    const MissionItem(
      seq: 0,
      command: MavCmd.navTakeoff,
      latitude: -35.363261,
      longitude: 149.165230,
      altitude: 50,
    ),
    const MissionItem(
      seq: 1,
      command: MavCmd.navWaypoint,
      latitude: -35.362741,
      longitude: 149.165500,
      altitude: 100,
    ),
    const MissionItem(
      seq: 2,
      command: MavCmd.navWaypoint,
      latitude: -35.361500,
      longitude: 149.166000,
      altitude: 100,
    ),
  ];

  group('Waypoint format (.waypoints)', () {
    test('save produces valid QGC WPL header', () {
      final output = service.save(
        items: testItems,
        format: MissionFileFormat.waypoints,
      );
      expect(output.startsWith('QGC WPL 110'), isTrue);
    });

    test('save and load round-trips waypoints', () {
      final output = service.save(
        items: testItems,
        format: MissionFileFormat.waypoints,
      );
      final result = service.load(output, fileName: 'test.waypoints');
      expect(result.hasError, isFalse);
      expect(result.items.length, equals(3));
      expect(result.items[0].command, equals(MavCmd.navTakeoff));
      expect(result.items[1].latitude, closeTo(-35.362741, 1e-6));
      expect(result.items[2].altitude, closeTo(100, 0.01));
    });

    test('load rejects empty content', () {
      final result = service.load('', fileName: 'test.waypoints');
      expect(result.hasError, isTrue);
    });

    test('load rejects missing header', () {
      final result = service.load('not a waypoint file', fileName: 'test.txt');
      expect(result.hasError, isTrue);
    });

    test('save preserves all fields', () {
      final output = service.save(
        items: testItems,
        format: MissionFileFormat.waypoints,
      );
      final lines = output.split('\n').where((l) => l.trim().isNotEmpty).toList();
      // Header + 3 items = 4 lines
      expect(lines.length, equals(4));
      // First data line: seq 0, takeoff command 22
      expect(lines[1], contains('22'));
    });
  });

  group('Plan format (.plan)', () {
    test('save produces valid JSON with fileType', () {
      final output = service.save(
        items: testItems,
        format: MissionFileFormat.plan,
      );
      expect(output, contains('"fileType": "Plan"'));
      expect(output, contains('"groundStation": "Helios GCS"'));
    });

    test('save and load round-trips mission items', () {
      final output = service.save(
        items: testItems,
        format: MissionFileFormat.plan,
      );
      final result = service.load(output, fileName: 'test.plan');
      expect(result.hasError, isFalse);
      expect(result.items.length, equals(3));
      expect(result.items[0].command, equals(MavCmd.navTakeoff));
      expect(result.items[1].latitude, closeTo(-35.362741, 1e-6));
    });

    test('save and load preserves cruise speed', () {
      final output = service.save(
        items: testItems,
        format: MissionFileFormat.plan,
        cruiseSpeed: 20.0,
      );
      final result = service.load(output, fileName: 'test.plan');
      expect(result.cruiseSpeed, equals(20.0));
    });

    test('save and load round-trips fence zones', () {
      final fences = [
        const FenceZone(
          type: FenceZoneType.inclusion,
          shape: FenceShape.circle,
          centerLat: -35.36,
          centerLon: 149.17,
          radius: 200,
        ),
        const FenceZone(
          type: FenceZoneType.exclusion,
          shape: FenceShape.polygon,
          vertices: [
            (lat: -35.36, lon: 149.16),
            (lat: -35.37, lon: 149.16),
            (lat: -35.37, lon: 149.17),
          ],
        ),
      ];
      final output = service.save(
        items: testItems,
        format: MissionFileFormat.plan,
        fenceZones: fences,
      );
      final result = service.load(output, fileName: 'test.plan');
      expect(result.fenceZones.length, equals(2));
      expect(result.fenceZones[0].shape, equals(FenceShape.circle));
      expect(result.fenceZones[0].radius, equals(200));
      expect(result.fenceZones[1].shape, equals(FenceShape.polygon));
      expect(result.fenceZones[1].vertices.length, equals(3));
    });

    test('save and load round-trips rally points', () {
      final rallies = [
        const RallyPoint(seq: 0, latitude: -35.36, longitude: 149.17, altitude: 50),
        const RallyPoint(seq: 1, latitude: -35.37, longitude: 149.18, altitude: 60),
      ];
      final output = service.save(
        items: testItems,
        format: MissionFileFormat.plan,
        rallyPoints: rallies,
      );
      final result = service.load(output, fileName: 'test.plan');
      expect(result.rallyPoints.length, equals(2));
      expect(result.rallyPoints[0].latitude, closeTo(-35.36, 1e-6));
      expect(result.rallyPoints[1].altitude, closeTo(60, 0.01));
    });

    test('load rejects non-Plan JSON', () {
      final result = service.load('{"fileType": "NotPlan"}', fileName: 'x.plan');
      expect(result.hasError, isTrue);
    });
  });

  group('Auto-detection', () {
    test('detects JSON plan format', () {
      final output = service.save(
        items: testItems,
        format: MissionFileFormat.plan,
      );
      final result = service.load(output); // no filename
      expect(result.hasError, isFalse);
      expect(result.items.length, equals(3));
    });

    test('detects WPL waypoint format', () {
      final output = service.save(
        items: testItems,
        format: MissionFileFormat.waypoints,
      );
      final result = service.load(output); // no filename
      expect(result.hasError, isFalse);
      expect(result.items.length, equals(3));
    });

    test('returns error for unknown format', () {
      final result = service.load('random content');
      expect(result.hasError, isTrue);
    });
  });
}
