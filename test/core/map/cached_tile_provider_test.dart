import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/map/cached_tile_provider.dart';
import 'package:flutter_map/flutter_map.dart';

void main() {
  group('CachedTileProvider', () {
    test('can be instantiated with defaults', () {
      final provider = CachedTileProvider();
      expect(provider.maxCacheAgeDays, 30);
    });

    test('can be instantiated with custom max age', () {
      final provider = CachedTileProvider(maxCacheAgeDays: 7);
      expect(provider.maxCacheAgeDays, 7);
    });

    test('getImage returns an ImageProvider', () {
      final provider = CachedTileProvider();
      final coords = const TileCoordinates(1, 2, 3);
      final layer = TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      );
      final image = provider.getImage(coords, layer);
      expect(image, isA<ImageProvider>());
    });
  });
}
