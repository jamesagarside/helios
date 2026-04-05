import 'package:flutter_map/flutter_map.dart';

import 'cached_tile_provider.dart' show heliosUserAgent;

/// On web, use a plain network tile provider (no FMTC/ObjectBox).
/// The browser handles caching via its HTTP cache and service worker.
TileProvider createDelegate({int maxCacheAgeDays = 30}) {
  return NetworkTileProvider(
    headers: const {'User-Agent': heliosUserAgent},
  );
}

Future<void> initialise() async {
  // No-op on web — browser HTTP cache handles tile caching.
}

Future<int> cacheSize() async => 0;

Future<void> clearCache() async {
  // Could clear browser cache via service worker in future.
}
