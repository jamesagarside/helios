import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/dem/dem_service.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('DemService.parseTileName', () {
    test('parses northern hemisphere N35E149', () {
      final result = DemService.parseTileName('N35E149.hgt');
      expect(result, isNotNull);
      expect(result!.lat, 35);
      expect(result.lon, 149);
    });

    test('parses southern hemisphere S35W149', () {
      final result = DemService.parseTileName('S35W149.hgt');
      expect(result, isNotNull);
      expect(result!.lat, -35);
      expect(result.lon, -149);
    });

    test('parses with full path prefix', () {
      final result = DemService.parseTileName('/some/path/N51E000.hgt');
      expect(result, isNotNull);
      expect(result!.lat, 51);
      expect(result.lon, 0);
    });

    test('returns null for invalid filename', () {
      expect(DemService.parseTileName('terrain.hgt'), isNull);
      expect(DemService.parseTileName('N999E000.hgt'), isNull);
      expect(DemService.parseTileName('notahgt.txt'), isNull);
    });
  });

  group('DemService.elevationAt', () {
    late DemService service;

    setUp(() {
      service = DemService();
    });

    test('returns null when no tiles loaded', () {
      expect(service.elevationAt(35.5, 149.5), isNull);
    });

    test('hasData is false when empty', () {
      expect(service.hasData, isFalse);
    });

    test('hasData is true after loading a tile', () async {
      // Create a minimal synthetic SRTM3 tile (1201×1201 = 1442401 samples)
      // All samples set to 100m (big-endian int16)
      const size = 1201;
      const totalSamples = size * size;
      final bytes = Uint8List(totalSamples * 2);
      // Set every sample to 100 (0x0064 big-endian)
      for (var i = 0; i < totalSamples; i++) {
        bytes[i * 2] = 0x00;
        bytes[i * 2 + 1] = 0x64;
      }

      // Write the bytes to a temp file
      final tmpDir = Directory.systemTemp.createTempSync('dem_test_');
      final hgtFile = File('${tmpDir.path}/N35E149.hgt');
      await hgtFile.writeAsBytes(bytes);

      await service.loadHgt(hgtFile.path);

      expect(service.hasData, isTrue);

      // Elevation at any point in the tile should be 100m
      final elev = service.elevationAt(35.5, 149.5);
      expect(elev, isNotNull);
      expect(elev!, closeTo(100.0, 0.5));

      await tmpDir.delete(recursive: true);
    });
  });

  group('DemService.terrainProfile', () {
    test('returns empty list with fewer than 2 waypoints', () {
      final service = DemService();
      expect(
        service.terrainProfile([const LatLng(35.0, 149.0)]),
        isEmpty,
      );
    });

    test('returns empty list when no DEM data loaded', () {
      final service = DemService();
      expect(
        service.terrainProfile([
          const LatLng(35.0, 149.0),
          const LatLng(35.1, 149.1),
        ]),
        isEmpty,
      );
    });
  });

  group('DemService.clear', () {
    test('clears loaded tiles', () async {
      final service = DemService();
      const size = 1201;
      const totalSamples = size * size;
      final bytes = Uint8List(totalSamples * 2);
      for (var i = 0; i < totalSamples; i++) {
        bytes[i * 2] = 0x00;
        bytes[i * 2 + 1] = 0x32; // 50m
      }

      final tmpDir = Directory.systemTemp.createTempSync('dem_clear_test_');
      final hgtFile = File('${tmpDir.path}/N10E010.hgt');
      await hgtFile.writeAsBytes(bytes);

      await service.loadHgt(hgtFile.path);
      expect(service.hasData, isTrue);

      service.clear();
      expect(service.hasData, isFalse);
      expect(service.elevationAt(10.5, 10.5), isNull);

      await tmpDir.delete(recursive: true);
    });
  });
}
