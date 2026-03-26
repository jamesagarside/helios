import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

/// Tile download service — pre-caches tiles for offline use.
class TileDownloadService {
  TileDownloadService._();

  static bool _running = false;
  static int _downloaded = 0;
  static int _total = 0;
  static bool _cancelled = false;

  static bool get isRunning => _running;
  static int get downloaded => _downloaded;
  static int get total => _total;
  static double get progress => _total == 0 ? 0 : _downloaded / _total;

  static final _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  static void cancel() => _cancelled = true;

  static Future<void> downloadRegion({
    required CountryRegion region,
    required String urlTemplate,
    required int maxZoom,
    void Function(int downloaded, int total)? onProgress,
  }) async {
    if (_running) return;
    _running = true;
    _cancelled = false;
    _downloaded = 0;

    try {
      final appDir = await getApplicationSupportDirectory();
      final cacheDir = p.join(appDir.path, 'tile_cache');

      // Build tile list
      final tiles = <(int z, int x, int y)>[];
      for (int z = 1; z <= maxZoom; z++) {
        final tileCount = math.pow(2, z).toInt();
        final xMin = _lonToTile(region.minLon, z).clamp(0, tileCount - 1);
        final xMax = _lonToTile(region.maxLon, z).clamp(0, tileCount - 1);
        final yMin = _latToTile(region.maxLat, z).clamp(0, tileCount - 1);
        final yMax = _latToTile(region.minLat, z).clamp(0, tileCount - 1);
        for (int x = xMin; x <= xMax; x++) {
          for (int y = yMin; y <= yMax; y++) {
            tiles.add((z, x, y));
          }
        }
      }

      _total = tiles.length;
      onProgress?.call(0, _total);

      for (final (z, x, y) in tiles) {
        if (_cancelled) break;

        final tilePath = p.join(cacheDir, '$z', '$x', '$y.png');
        final file = File(tilePath);

        // Skip if already cached and fresh
        if (file.existsSync()) {
          final age = DateTime.now().difference(file.lastModifiedSync());
          if (age.inDays < 30) {
            _downloaded++;
            onProgress?.call(_downloaded, _total);
            continue;
          }
        }

        try {
          final url = urlTemplate
              .replaceAll('{z}', '$z')
              .replaceAll('{x}', '$x')
              .replaceAll('{y}', '$y');

          final request = await _httpClient.getUrl(Uri.parse(url));
          request.headers.set('User-Agent', 'com.argus.helios_gcs');
          final response = await request.close();

          if (response.statusCode == 200) {
            final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
            final dir = Directory(p.dirname(tilePath));
            if (!dir.existsSync()) dir.createSync(recursive: true);
            await file.writeAsBytes(bytes);
          }
        } catch (_) {
          // Skip failed tiles — network may be unavailable
        }

        _downloaded++;
        onProgress?.call(_downloaded, _total);

        // Small delay to avoid hammering tile servers
        await Future.delayed(const Duration(milliseconds: 20));
      }
    } finally {
      _running = false;
    }
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
