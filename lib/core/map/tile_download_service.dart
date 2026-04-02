import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';

/// A named country/region bounding box for offline tile download.
class CountryRegion {
  const CountryRegion({
    required this.name,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  final String name;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  static const List<CountryRegion> all = [
    CountryRegion(name: 'United Kingdom', minLat: 49.9, maxLat: 60.9, minLon: -8.2, maxLon: 1.8),
    CountryRegion(name: 'Australia', minLat: -43.6, maxLat: -10.7, minLon: 113.3, maxLon: 153.6),
    CountryRegion(name: 'United States', minLat: 24.4, maxLat: 49.4, minLon: -125.0, maxLon: -66.9),
    CountryRegion(name: 'Canada', minLat: 41.7, maxLat: 70.0, minLon: -141.0, maxLon: -52.6),
    CountryRegion(name: 'France', minLat: 41.3, maxLat: 51.1, minLon: -5.2, maxLon: 9.6),
    CountryRegion(name: 'Germany', minLat: 47.3, maxLat: 55.1, minLon: 5.9, maxLon: 15.0),
    CountryRegion(name: 'New Zealand', minLat: -47.4, maxLat: -34.4, minLon: 166.4, maxLon: 178.6),
    CountryRegion(name: 'Japan', minLat: 24.0, maxLat: 45.5, minLon: 122.9, maxLon: 145.8),
    CountryRegion(name: 'South Africa', minLat: -34.8, maxLat: -22.1, minLon: 16.5, maxLon: 32.9),
    CountryRegion(name: 'Brazil', minLat: -33.7, maxLat: 5.3, minLon: -73.9, maxLon: -34.8),
    CountryRegion(name: 'India', minLat: 8.1, maxLat: 37.1, minLon: 68.2, maxLon: 97.4),
  ];

  /// Estimate total tiles for this region at the given max zoom level.
  int estimateTileCount(int maxZoom) {
    int total = 0;
    for (int z = 1; z <= maxZoom; z++) {
      final tileCount = math.pow(2, z).toInt();
      final xMin = _lonToTile(minLon, z).clamp(0, tileCount - 1);
      final xMax = _lonToTile(maxLon, z).clamp(0, tileCount - 1);
      final yMin = _latToTile(maxLat, z).clamp(0, tileCount - 1);
      final yMax = _latToTile(minLat, z).clamp(0, tileCount - 1);
      total += (xMax - xMin + 1) * (yMax - yMin + 1);
    }
    return total;
  }
}

/// FMTC store name used for bulk-downloaded region tiles.
const _downloadStoreName = 'helios_downloads';

/// Tile download service — pre-caches tiles for offline use via FMTC.
class TileDownloadService {
  TileDownloadService._();

  static bool _running = false;
  static int _downloaded = 0;
  static int _total = 0;

  static bool get isRunning => _running;
  static int get downloaded => _downloaded;
  static int get total => _total;
  static double get progress => _total == 0 ? 0 : _downloaded / _total;

  static StreamSubscription<DownloadProgress>? _progressSub;

  static void cancel() {
    const FMTCStore(_downloadStoreName).download.cancel();
  }

  /// Download all tiles in [region] at zoom levels 1..[maxZoom].
  ///
  /// Reports progress through the optional [onProgress] callback and
  /// through the static [downloaded], [total], and [progress] getters.
  static Future<void> downloadRegion({
    required CountryRegion region,
    required String urlTemplate,
    required int maxZoom,
    void Function(int downloaded, int total)? onProgress,
  }) async {
    if (_running) return;
    _running = true;
    _downloaded = 0;
    _total = 0;

    try {
      // Ensure the download store exists.
      const store = FMTCStore(_downloadStoreName);
      if (!await store.manage.ready) {
        await store.manage.create();
      }

      // Build a rectangle region from the bounding box.
      final bounds = LatLngBounds(
        LatLng(region.minLat, region.minLon),
        LatLng(region.maxLat, region.maxLon),
      );
      final fmtcRegion = RectangleRegion(bounds);
      final downloadable = fmtcRegion.toDownloadable(
        minZoom: 1,
        maxZoom: maxZoom,
        options: TileLayer(urlTemplate: urlTemplate),
      );

      // Get expected tile count so we can report accurate progress.
      _total = await store.download.countTiles(downloadable);
      onProgress?.call(0, _total);

      // Start the foreground download.
      final (:downloadProgress, tileEvents: _) =
          store.download.startForeground(
        region: downloadable,
        parallelThreads: 5,
        skipExistingTiles: true,
      );

      // Listen to the progress stream.
      final completer = Completer<void>();
      _progressSub = downloadProgress.listen(
        (event) {
          _downloaded = event.attemptedTilesCount;
          _total = event.maxTilesCount;
          onProgress?.call(_downloaded, _total);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (Object error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      );

      await completer.future;
    } finally {
      await _progressSub?.cancel();
      _progressSub = null;
      _running = false;
    }
  }

  /// Download all tiles within arbitrary [bounds] at zoom levels
  /// [minZoom]..[maxZoom] for offline use.
  ///
  /// This is used by the "cache visible area" feature in Plan View.
  static Future<void> downloadBounds({
    required LatLngBounds bounds,
    required String urlTemplate,
    int minZoom = 1,
    int maxZoom = 16,
    void Function(int downloaded, int total)? onProgress,
  }) async {
    if (_running) return;
    _running = true;
    _downloaded = 0;
    _total = 0;

    try {
      const store = FMTCStore(_downloadStoreName);
      if (!await store.manage.ready) {
        await store.manage.create();
      }

      final fmtcRegion = RectangleRegion(bounds);
      final downloadable = fmtcRegion.toDownloadable(
        minZoom: minZoom,
        maxZoom: maxZoom,
        options: TileLayer(urlTemplate: urlTemplate),
      );

      _total = await store.download.countTiles(downloadable);
      onProgress?.call(0, _total);

      final (:downloadProgress, tileEvents: _) =
          store.download.startForeground(
        region: downloadable,
        parallelThreads: 5,
        skipExistingTiles: true,
      );

      final completer = Completer<void>();
      _progressSub = downloadProgress.listen(
        (event) {
          _downloaded = event.attemptedTilesCount;
          _total = event.maxTilesCount;
          onProgress?.call(_downloaded, _total);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (Object error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      );

      await completer.future;
    } finally {
      await _progressSub?.cancel();
      _progressSub = null;
      _running = false;
    }
  }

  /// Estimate the tile count for arbitrary [bounds] at the given [maxZoom].
  static int estimateBoundsTileCount(
    LatLngBounds bounds, {
    int minZoom = 1,
    int maxZoom = 16,
  }) {
    int total = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      final tileCount = math.pow(2, z).toInt();
      final xMin = _lonToTile(bounds.west, z).clamp(0, tileCount - 1);
      final xMax = _lonToTile(bounds.east, z).clamp(0, tileCount - 1);
      final yMin = _latToTile(bounds.north, z).clamp(0, tileCount - 1);
      final yMax = _latToTile(bounds.south, z).clamp(0, tileCount - 1);
      total += (xMax - xMin + 1) * (yMax - yMin + 1);
    }
    return total;
  }
}

int _lonToTile(double lon, int z) {
  return ((lon + 180) / 360 * math.pow(2, z)).floor();
}

int _latToTile(double lat, int z) {
  final rad = lat * math.pi / 180;
  return ((1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) /
          2 *
          math.pow(2, z))
      .floor();
}
