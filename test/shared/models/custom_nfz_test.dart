import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/models/custom_nfz.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('CustomNfz', () {
    final polygon = [
      const LatLng(-35.3, 149.1),
      const LatLng(-35.3, 149.2),
      const LatLng(-35.2, 149.2),
      const LatLng(-35.2, 149.1),
    ];

    final zone = CustomNfz(
      id: 'abc-123',
      name: 'Test Zone',
      polygon: polygon,
      colour: 'orange',
    );

    // ─── JSON round-trip ──────────────────────────────────────────────────

    test('toJson produces expected keys', () {
      final json = zone.toJson();
      expect(json['id'], 'abc-123');
      expect(json['name'], 'Test Zone');
      expect(json['colour'], 'orange');
      expect(json['polygon'], isA<List<dynamic>>());
      expect((json['polygon'] as List<dynamic>).length, 4);
    });

    test('fromJson round-trips all fields correctly', () {
      final json = zone.toJson();
      final restored = CustomNfz.fromJson(json);

      expect(restored.id, zone.id);
      expect(restored.name, zone.name);
      expect(restored.colour, zone.colour);
      expect(restored.polygon.length, zone.polygon.length);
      for (var i = 0; i < zone.polygon.length; i++) {
        expect(restored.polygon[i].latitude,
            closeTo(zone.polygon[i].latitude, 1e-9));
        expect(restored.polygon[i].longitude,
            closeTo(zone.polygon[i].longitude, 1e-9));
      }
    });

    test('fromJson uses default colour when absent', () {
      final json = {
        'id': 'xyz',
        'name': 'No Colour',
        'polygon': [
          {'lat': -35.0, 'lon': 149.0},
          {'lat': -35.0, 'lon': 149.1},
          {'lat': -35.1, 'lon': 149.1},
        ],
      };
      final z = CustomNfz.fromJson(json);
      expect(z.colour, 'orange');
    });

    // ─── copyWith ─────────────────────────────────────────────────────────

    test('copyWith changes only the specified field', () {
      final copy = zone.copyWith(name: 'Renamed Zone');
      expect(copy.name, 'Renamed Zone');
      expect(copy.id, zone.id);
      expect(copy.colour, zone.colour);
      expect(copy.polygon.length, zone.polygon.length);
    });

    test('copyWith with no args returns identical value', () {
      final copy = zone.copyWith();
      expect(copy, zone);
    });

    test('copyWith with new polygon reflects change', () {
      final newPoly = [
        const LatLng(-36.0, 150.0),
        const LatLng(-36.0, 150.1),
        const LatLng(-36.1, 150.1),
      ];
      final copy = zone.copyWith(polygon: newPoly);
      expect(copy.polygon.length, 3);
      expect(copy.polygon.first.latitude, -36.0);
    });

    test('copyWith changing colour', () {
      final redZone = zone.copyWith(colour: 'red');
      expect(redZone.colour, 'red');
      expect(redZone.id, zone.id);
    });

    // ─── Equality & hashCode ──────────────────────────────────────────────

    test('two identical zones are equal', () {
      final a = CustomNfz(
        id: 'abc-123',
        name: 'Test Zone',
        polygon: polygon,
        colour: 'orange',
      );
      final b = CustomNfz(
        id: 'abc-123',
        name: 'Test Zone',
        polygon: polygon,
        colour: 'orange',
      );
      expect(a, equals(b));
    });

    test('zones with different ids are not equal', () {
      final other = zone.copyWith(id: 'different-id');
      expect(zone, isNot(equals(other)));
    });

    test('zones with different names are not equal', () {
      final other = zone.copyWith(name: 'Other Name');
      expect(zone, isNot(equals(other)));
    });

    test('zones with different colours are not equal', () {
      final other = zone.copyWith(colour: 'red');
      expect(zone, isNot(equals(other)));
    });

    test('zones with different polygons are not equal', () {
      final other = zone.copyWith(polygon: [
        const LatLng(-35.3, 149.1),
        const LatLng(-35.3, 149.3),
        const LatLng(-35.1, 149.3),
      ]);
      expect(zone, isNot(equals(other)));
    });

    test('equal zones have the same hashCode', () {
      final a = CustomNfz(
        id: 'abc-123',
        name: 'Test Zone',
        polygon: polygon,
        colour: 'orange',
      );
      final b = CustomNfz(
        id: 'abc-123',
        name: 'Test Zone',
        polygon: polygon,
        colour: 'orange',
      );
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
