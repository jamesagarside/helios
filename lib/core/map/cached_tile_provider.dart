import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

import 'cached_tile_provider_native.dart'
    if (dart.library.js_interop) 'cached_tile_provider_web.dart' as impl;

/// User-Agent header identifying Helios GCS to tile servers.
///
/// Required by OSM tile usage policy:
/// https://operations.osmfoundation.org/policies/tiles/
const heliosUserAgent =
    'HeliosGCS/0.5.0 (+https://github.com/jamesagarside/helios)';

/// Tile provider that uses FMTC on native and plain HTTP on web.
///
/// All map widgets use this — the platform switch is transparent.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({this.maxCacheAgeDays = 30});

  final int maxCacheAgeDays;

  late final TileProvider _delegate = impl.createDelegate(
    maxCacheAgeDays: maxCacheAgeDays,
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _delegate.getImage(coordinates, options);
  }

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  /// Initialise platform-specific backend (no-op on web).
  static Future<void> initialise() => impl.initialise();

  /// Get the current cache size in bytes.
  static Future<int> cacheSize() => impl.cacheSize();

  /// Clear all cached tiles.
  static Future<void> clearCache() => impl.clearCache();
}
