import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';

/// Default FMTC store name used for browse caching.
const _defaultStoreName = 'helios_tiles';

/// Tile provider backed by flutter_map_tile_caching (FMTC).
///
/// Wraps FMTC's ObjectBox-based tile cache while preserving the same
/// public API that the rest of the codebase depends on.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({this.maxCacheAgeDays = 30});

  /// Max age of cached tiles before they're re-fetched (if online).
  final int maxCacheAgeDays;

  /// Lazily-built FMTC tile provider, created once per instance.
  FMTCTileProvider? _delegate;

  FMTCTileProvider _getDelegate() {
    return _delegate ??= FMTCTileProvider(
      stores: const {_defaultStoreName: BrowseStoreStrategy.readUpdateCreate},
      loadingStrategy: BrowseLoadingStrategy.onlineFirst,
      cachedValidDuration: Duration(days: maxCacheAgeDays),
    );
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _getDelegate().getImage(coordinates, options);
  }

  @override
  void dispose() {
    _delegate?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Static helpers — same API surface as the original implementation
  // ---------------------------------------------------------------------------

  /// Whether FMTC has been initialised.
  static bool _initialised = false;

  /// Initialise the FMTC ObjectBox backend.
  ///
  /// Must be called once before any tile provider is used — typically in
  /// `main()` before `runApp`.
  static Future<void> initialise() async {
    if (_initialised) return;
    await FMTCObjectBoxBackend().initialise();
    _initialised = true;

    // Ensure the default store exists.
    const store = FMTCStore(_defaultStoreName);
    if (!await store.manage.ready) {
      await store.manage.create();
    }
  }

  /// Get the current cache size in bytes.
  ///
  /// Returns the total size of tiles across all FMTC stores, converted
  /// from KiB (which FMTC returns) to bytes.
  static Future<int> cacheSize() async {
    if (!_initialised) return 0;
    final kib = await FMTCRoot.stats.realSize;
    return (kib * 1024).round();
  }

  /// Clear all cached tiles from the default store.
  static Future<void> clearCache() async {
    if (!_initialised) return;
    const store = FMTCStore(_defaultStoreName);
    if (await store.manage.ready) {
      await store.manage.reset();
    }
  }
}
