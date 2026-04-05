import 'package:flutter_map/flutter_map.dart';

import 'cached_tile_provider_native.dart'
    if (dart.library.js_interop) 'cached_tile_provider_web.dart' as impl;

/// User-Agent header identifying Helios GCS to tile servers.
///
/// Required by OSM tile usage policy:
/// https://operations.osmfoundation.org/policies/tiles/
const heliosUserAgent =
    'HeliosGCS/0.5.0 (+https://github.com/jamesagarside/helios)';

/// Factory that returns the platform-appropriate [TileProvider].
///
/// On native: FMTC-backed with ObjectBox cache.
/// On web: plain [NetworkTileProvider] (browser HTTP cache handles caching).
///
/// Returns the actual provider directly — no wrapping — so flutter_map's
/// full API (including supportsCancelLoading) works correctly.
// ignore: non_constant_identifier_names
TileProvider CachedTileProvider({int maxCacheAgeDays = 30}) {
  return impl.createDelegate(maxCacheAgeDays: maxCacheAgeDays);
}

/// Initialise platform-specific backend (no-op on web).
Future<void> initialiseTileCache() => impl.initialise();

/// Get the current cache size in bytes.
Future<int> tileCacheSize() => impl.cacheSize();

/// Clear all cached tiles.
Future<void> clearTileCache() => impl.clearCache();
