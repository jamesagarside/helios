import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/models/home_location.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('HomeLocation', () {
    const loc = HomeLocation(
      name: 'CMAC',
      position: LatLng(-35.363261, 149.165230),
      altitude: 584,
      isDefault: true,
      notes: 'ArduPilot test site',
    );

    test('roundtrip JSON', () {
      final json = loc.toJson();
      final restored = HomeLocation.fromJson(json);
      expect(restored, equals(loc));
    });

    test('copyWith preserves unset fields', () {
      final updated = loc.copyWith(name: 'New Name');
      expect(updated.name, 'New Name');
      expect(updated.altitude, 584);
      expect(updated.isDefault, true);
    });

    test('equatable compares by value', () {
      const a = HomeLocation(name: 'A', position: LatLng(1, 2));
      const b = HomeLocation(name: 'A', position: LatLng(1, 2));
      const c = HomeLocation(name: 'C', position: LatLng(1, 2));
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
