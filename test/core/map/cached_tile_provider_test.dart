import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/map/cached_tile_provider.dart';
import 'package:flutter_map/flutter_map.dart';

void main() {
  group('CachedTileProvider', () {
    test('returns a TileProvider', () {
      final provider = CachedTileProvider();
      expect(provider, isA<TileProvider>());
    });

    test('accepts custom max age parameter', () {
      final provider = CachedTileProvider(maxCacheAgeDays: 7);
      expect(provider, isA<TileProvider>());
    });

    test('is a NetworkTileProvider when FMTC is not initialised', () {
      final provider = CachedTileProvider();
      expect(provider, isA<NetworkTileProvider>());
    });
  });
}
