import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

import 'cached_tile_provider.dart' show heliosUserAgent;

const _defaultStoreName = 'helios_tiles';

TileProvider createDelegate({int maxCacheAgeDays = 30}) {
  return FMTCTileProvider(
    stores: const {_defaultStoreName: BrowseStoreStrategy.readUpdateCreate},
    loadingStrategy: BrowseLoadingStrategy.onlineFirst,
    cachedValidDuration: Duration(days: maxCacheAgeDays),
    headers: const {'User-Agent': heliosUserAgent},
  );
}

bool _initialised = false;

Future<void> initialise() async {
  if (_initialised) return;
  await FMTCObjectBoxBackend().initialise();
  _initialised = true;

  const store = FMTCStore(_defaultStoreName);
  if (!await store.manage.ready) {
    await store.manage.create();
  }
}

Future<int> cacheSize() async {
  if (!_initialised) return 0;
  final kib = await FMTCRoot.stats.realSize;
  return (kib * 1024).round();
}

Future<void> clearCache() async {
  if (!_initialised) return;
  const store = FMTCStore(_defaultStoreName);
  if (await store.manage.ready) {
    await store.manage.reset();
  }
}
