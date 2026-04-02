import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/airspace/openair_fetch_service.dart';
import 'package:helios_gcs/shared/models/airspace_zone.dart';

void main() {
  group('OpenAirFetchService — response parsing', () {
    late OpenAirFetchService service;

    setUp(() {
      service = OpenAirFetchService();
    });

    const sampleResponse = '''
{
  "totalCount": 2,
  "items": [
    {
      "_id": "zone-prohibited-001",
      "name": "Restricted Military Area",
      "type": 3,
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
      "lowerLimit": {"value": 0},
      "upperLimit": {"value": 2000}
    },
    {
      "_id": "zone-restricted-002",
      "name": "Restricted Area R123",
      "type": 1,
      "geometry": {
        "type": "Polygon",
        "coordinates": [
          [
            [150.0, -36.0],
            [150.5, -36.0],
            [150.5, -35.5],
            [150.0, -35.5],
            [150.0, -36.0]
          ]
        ]
      },
      "lowerLimit": {"value": 500},
      "upperLimit": {"value": 5000}
    }
  ]
}
''';

    test('parses type 3 (prohibited) correctly', () {
      final zones = service.parseApiResponsePublic(sampleResponse);
      expect(zones.length, 2);
      final prohibited = zones.firstWhere((z) => z.id == 'zone-prohibited-001');
      expect(prohibited.type, AirspaceType.prohibited);
      expect(prohibited.name, 'Restricted Military Area');
      expect(prohibited.lowerLimitFt, 0);
      expect(prohibited.upperLimitFt, 2000);
    });

    test('parses type 1 (restricted) correctly', () {
      final zones = service.parseApiResponsePublic(sampleResponse);
      final restricted = zones.firstWhere((z) => z.id == 'zone-restricted-002');
      expect(restricted.type, AirspaceType.restricted);
      expect(restricted.name, 'Restricted Area R123');
      expect(restricted.lowerLimitFt, 500);
      expect(restricted.upperLimitFt, 5000);
    });

    test('geometry is parsed to correct LatLng — GeoJSON [lon, lat] order', () {
      final zones = service.parseApiResponsePublic(sampleResponse);
      final zone = zones.firstWhere((z) => z.id == 'zone-prohibited-001');
      expect(zone.polygon.length, greaterThanOrEqualTo(3));
      // First coordinate: [149.0, -35.5] => lat=-35.5, lon=149.0
      expect(zone.polygon.first.latitude, closeTo(-35.5, 0.0001));
      expect(zone.polygon.first.longitude, closeTo(149.0, 0.0001));
    });

    test('parses type 2 (danger) correctly', () {
      const dangerResponse = '''
{
  "totalCount": 1,
  "items": [
    {
      "_id": "danger-001",
      "name": "Danger Area D42",
      "type": 2,
      "geometry": {
        "type": "Polygon",
        "coordinates": [
          [[149.0,-35.5],[149.5,-35.5],[149.5,-35.0],[149.0,-35.0],[149.0,-35.5]]
        ]
      },
      "lowerLimit": {"value": 0},
      "upperLimit": {"value": 3000}
    }
  ]
}
''';
      final zones = service.parseApiResponsePublic(dangerResponse);
      expect(zones.length, 1);
      expect(zones.first.type, AirspaceType.danger);
    });

    test('parses type 4 (CTR) correctly', () {
      const ctrResponse = '''
{
  "totalCount": 1,
  "items": [
    {
      "_id": "ctr-001",
      "name": "Sydney CTR",
      "type": 4,
      "geometry": {
        "type": "Polygon",
        "coordinates": [
          [[151.0,-34.0],[151.5,-34.0],[151.5,-33.5],[151.0,-33.5],[151.0,-34.0]]
        ]
      },
      "lowerLimit": {"value": 0},
      "upperLimit": {"value": 2500}
    }
  ]
}
''';
      final zones = service.parseApiResponsePublic(ctrResponse);
      expect(zones.length, 1);
      expect(zones.first.type, AirspaceType.ctr);
    });

    test('returns empty list for empty items array', () {
      const emptyResponse = '{"totalCount": 0, "items": []}';
      final zones = service.parseApiResponsePublic(emptyResponse);
      expect(zones, isEmpty);
    });

    test('returns empty list for malformed JSON', () {
      final zones = service.parseApiResponsePublic('not valid json {{{');
      expect(zones, isEmpty);
    });

    test('returns empty list for JSON without items key', () {
      final zones = service.parseApiResponsePublic('{"totalCount": 0}');
      expect(zones, isEmpty);
    });

    test('skips items with non-Polygon geometry type', () {
      const pointResponse = '''
{
  "totalCount": 1,
  "items": [
    {
      "_id": "point-001",
      "name": "Point Zone",
      "type": 3,
      "geometry": {"type": "Point", "coordinates": [149.0, -35.0]},
      "lowerLimit": {"value": 0},
      "upperLimit": {"value": 1000}
    }
  ]
}
''';
      final zones = service.parseApiResponsePublic(pointResponse);
      expect(zones, isEmpty);
    });

    test('skips items whose polygon has fewer than 3 vertices', () {
      const shortPolyResponse = '''
{
  "totalCount": 1,
  "items": [
    {
      "_id": "short-001",
      "name": "Short Zone",
      "type": 3,
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[149.0,-35.0],[149.5,-35.0]]]
      },
      "lowerLimit": {"value": 0},
      "upperLimit": {"value": 1000}
    }
  ]
}
''';
      final zones = service.parseApiResponsePublic(shortPolyResponse);
      expect(zones, isEmpty);
    });

    test('prohibited zone reports isProhibited true', () {
      final zones = service.parseApiResponsePublic(sampleResponse);
      final prohibited = zones.firstWhere((z) => z.id == 'zone-prohibited-001');
      expect(prohibited.isProhibited, isTrue);
    });

    test('restricted zone reports isProhibited true', () {
      final zones = service.parseApiResponsePublic(sampleResponse);
      final restricted = zones.firstWhere((z) => z.id == 'zone-restricted-002');
      expect(restricted.isProhibited, isTrue);
    });
  });
}
