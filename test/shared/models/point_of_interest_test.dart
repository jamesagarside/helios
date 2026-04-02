import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/models/point_of_interest.dart';

void main() {
  group('PointOfInterest', () {
    const fullPoi = PointOfInterest(
      id: 'poi-001',
      name: 'Launch Pad',
      notes: 'Check wind direction before use',
      latitude: -35.3632,
      longitude: 149.1652,
      altitudeM: 30.0,
      colour: PoiColour.red,
      icon: PoiIcon.flag,
    );

    const minimalPoi = PointOfInterest(
      id: 'poi-002',
      name: 'Waypoint Alpha',
      latitude: -33.8688,
      longitude: 151.2093,
    );

    // ─── JSON round-trip — full fields ─────────────────────────────────────

    test('toJson produces expected keys for full POI', () {
      final json = fullPoi.toJson();
      expect(json['id'], 'poi-001');
      expect(json['name'], 'Launch Pad');
      expect(json['notes'], 'Check wind direction before use');
      expect(json['lat'], closeTo(-35.3632, 1e-9));
      expect(json['lon'], closeTo(149.1652, 1e-9));
      expect(json['altM'], closeTo(30.0, 1e-9));
      expect(json['colour'], 'red');
      expect(json['icon'], 'flag');
    });

    test('fromJson round-trips all fields correctly', () {
      final json = fullPoi.toJson();
      final restored = PointOfInterest.fromJson(json);

      expect(restored.id, fullPoi.id);
      expect(restored.name, fullPoi.name);
      expect(restored.notes, fullPoi.notes);
      expect(restored.latitude, closeTo(fullPoi.latitude, 1e-9));
      expect(restored.longitude, closeTo(fullPoi.longitude, 1e-9));
      expect(restored.altitudeM, closeTo(fullPoi.altitudeM, 1e-9));
      expect(restored.colour, fullPoi.colour);
      expect(restored.icon, fullPoi.icon);
    });

    // ─── JSON round-trip — minimal / defaults ──────────────────────────────

    test('toJson round-trips minimal POI with defaults', () {
      final json = minimalPoi.toJson();
      final restored = PointOfInterest.fromJson(json);

      expect(restored.id, minimalPoi.id);
      expect(restored.name, minimalPoi.name);
      expect(restored.notes, '');
      expect(restored.altitudeM, closeTo(0.0, 1e-9));
      expect(restored.colour, PoiColour.blue);
      expect(restored.icon, PoiIcon.pin);
    });

    test('fromJson uses defaults when optional fields are absent', () {
      final json = <String, dynamic>{
        'id': 'poi-min',
        'name': 'Minimal',
        'lat': -10.0,
        'lon': 130.0,
      };
      final poi = PointOfInterest.fromJson(json);
      expect(poi.notes, '');
      expect(poi.altitudeM, closeTo(0.0, 1e-9));
      expect(poi.colour, PoiColour.blue);
      expect(poi.icon, PoiIcon.pin);
    });

    test('fromJson falls back to blue/pin when unknown colour/icon strings', () {
      final json = <String, dynamic>{
        'id': 'poi-unk',
        'name': 'Unknown Enum',
        'lat': 0.0,
        'lon': 0.0,
        'colour': 'ultraviolet',
        'icon': 'rocket',
      };
      final poi = PointOfInterest.fromJson(json);
      expect(poi.colour, PoiColour.blue);
      expect(poi.icon, PoiIcon.pin);
    });

    // ─── copyWith ──────────────────────────────────────────────────────────

    test('copyWith changes only the specified field', () {
      final updated = fullPoi.copyWith(name: 'Renamed');
      expect(updated.name, 'Renamed');
      expect(updated.id, fullPoi.id);
      expect(updated.latitude, fullPoi.latitude);
      expect(updated.colour, fullPoi.colour);
      expect(updated.icon, fullPoi.icon);
    });

    test('copyWith with no args returns equal value', () {
      final copy = fullPoi.copyWith();
      expect(copy, equals(fullPoi));
    });

    test('copyWith changing altitude preserves other fields', () {
      final updated = fullPoi.copyWith(altitudeM: 100.0);
      expect(updated.altitudeM, closeTo(100.0, 1e-9));
      expect(updated.name, fullPoi.name);
      expect(updated.id, fullPoi.id);
    });

    test('copyWith changing colour and icon', () {
      final updated = fullPoi.copyWith(colour: PoiColour.green, icon: PoiIcon.camera);
      expect(updated.colour, PoiColour.green);
      expect(updated.icon, PoiIcon.camera);
      expect(updated.id, fullPoi.id);
    });

    // ─── Equality ──────────────────────────────────────────────────────────

    test('two identical POIs are equal', () {
      const a = PointOfInterest(
        id: 'poi-001',
        name: 'Launch Pad',
        notes: 'Check wind direction before use',
        latitude: -35.3632,
        longitude: 149.1652,
        altitudeM: 30.0,
        colour: PoiColour.red,
        icon: PoiIcon.flag,
      );
      expect(a, equals(fullPoi));
    });

    test('POIs with different ids are not equal', () {
      final other = fullPoi.copyWith(id: 'different');
      expect(fullPoi, isNot(equals(other)));
    });

    test('POIs with different latitudes are not equal', () {
      final other = fullPoi.copyWith(latitude: 0.0);
      expect(fullPoi, isNot(equals(other)));
    });

    test('POIs with different longitudes are not equal', () {
      final other = fullPoi.copyWith(longitude: 0.0);
      expect(fullPoi, isNot(equals(other)));
    });

    test('POIs with different names are not equal', () {
      final other = fullPoi.copyWith(name: 'Other');
      expect(fullPoi, isNot(equals(other)));
    });

    // ─── hashCode ──────────────────────────────────────────────────────────

    test('equal POIs have the same hashCode', () {
      const a = PointOfInterest(
        id: 'poi-001',
        name: 'Launch Pad',
        notes: 'Check wind direction before use',
        latitude: -35.3632,
        longitude: 149.1652,
        altitudeM: 30.0,
        colour: PoiColour.red,
        icon: PoiIcon.flag,
      );
      expect(a.hashCode, equals(fullPoi.hashCode));
    });

    test('different POIs are unlikely to share a hashCode', () {
      const other = PointOfInterest(
        id: 'poi-999',
        name: 'Other',
        latitude: 0.0,
        longitude: 0.0,
      );
      // Not guaranteed by contract, but highly expected for distinct objects.
      expect(fullPoi.hashCode, isNot(equals(other.hashCode)));
    });

    // ─── PoiColour enum serialisation ──────────────────────────────────────

    test('all PoiColour values serialise and deserialise', () {
      for (final colour in PoiColour.values) {
        final poi = PointOfInterest(
          id: 'c-${colour.name}',
          name: colour.name,
          latitude: 0,
          longitude: 0,
          colour: colour,
        );
        final restored = PointOfInterest.fromJson(poi.toJson());
        expect(restored.colour, colour,
            reason: 'PoiColour.${colour.name} should survive JSON round-trip');
      }
    });

    // ─── PoiIcon enum serialisation ────────────────────────────────────────

    test('all PoiIcon values serialise and deserialise', () {
      for (final icon in PoiIcon.values) {
        final poi = PointOfInterest(
          id: 'i-${icon.name}',
          name: icon.name,
          latitude: 0,
          longitude: 0,
          icon: icon,
        );
        final restored = PointOfInterest.fromJson(poi.toJson());
        expect(restored.icon, icon,
            reason: 'PoiIcon.${icon.name} should survive JSON round-trip');
      }
    });
  });
}
