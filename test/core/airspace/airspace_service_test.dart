import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/airspace/airspace_service.dart';
import 'package:helios_gcs/shared/models/airspace_zone.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('AirspaceService', () {
    final service = AirspaceService();

    const sampleGeoJson = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "P-123",
      "geometry": {
        "type": "Polygon",
        "coordinates": [
          [
            [149.0, -35.5],
            [149.5, -35.5],
            [149.5, -35.0],
            [149.0, -35.0],
            [149.0, -35.5]
          ]
        ]
      },
      "properties": {
        "name": "Test Prohibited Area",
        "type": "PROHIBITED",
        "lowerLimit": 0,
        "upperLimit": 500
      }
    }
  ]
}
''';

    test('parses valid GeoJSON FeatureCollection', () {
      final zones = service.parseGeoJsonString(sampleGeoJson);
      expect(zones.length, equals(1));
      expect(zones[0].name, equals('Test Prohibited Area'));
      expect(zones[0].type, equals(AirspaceType.prohibited));
      expect(zones[0].lowerLimitFt, equals(0));
      expect(zones[0].upperLimitFt, equals(500));
      expect(zones[0].polygon.length, greaterThanOrEqualTo(3));
    });

    test('returns empty list for invalid JSON', () {
      final zones = service.parseGeoJsonString('not valid json');
      expect(zones, isEmpty);
    });

    test('returns empty list for empty FeatureCollection', () {
      final zones =
          service.parseGeoJsonString('{"type":"FeatureCollection","features":[]}');
      expect(zones, isEmpty);
    });

    test('skips features with non-Polygon geometry', () {
      const pointGeoJson = '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": {"type": "Point", "coordinates": [149.0, -35.0]},
      "properties": {"name": "A point"}
    }
  ]
}
''';
      final zones = service.parseGeoJsonString(pointGeoJson);
      expect(zones, isEmpty);
    });
  });

  group('AirspaceZone.contains', () {
    // Square zone from -35.5 to -35.0 lat, 149.0 to 149.5 lon
    final zone = AirspaceZone(
      id: 'test',
      name: 'Test',
      type: AirspaceType.prohibited,
      polygon: const [
        LatLng(-35.5, 149.0),
        LatLng(-35.5, 149.5),
        LatLng(-35.0, 149.5),
        LatLng(-35.0, 149.0),
      ],
    );

    test('returns true for point inside zone', () {
      expect(zone.contains(const LatLng(-35.2, 149.2)), isTrue);
    });

    test('returns false for point outside zone', () {
      expect(zone.contains(const LatLng(-36.0, 150.0)), isFalse);
    });

    test('returns false for empty polygon', () {
      const emptyZone = AirspaceZone(
        id: 'empty',
        name: 'Empty',
        type: AirspaceType.other,
        polygon: [],
      );
      expect(emptyZone.contains(const LatLng(-35.2, 149.2)), isFalse);
    });
  });
}
