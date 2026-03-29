import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// File-based tile cache for offline map support.
///
/// Downloads tiles from the network and stores them locally.
/// When offline, serves previously cached tiles.
/// Apache 2.0 compatible — no flutter_map_tile_caching (GPL) dependency.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({this.maxCacheAgeDays = 30});

  /// Max age of cached tiles before they're re-fetched (if online).
  final int maxCacheAgeDays;

  static String? _cacheDir;
  static final _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);

  /// Get the tile cache directory (lazy-init, cached).
  static Future<String> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'tile_cache'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _cacheDir = dir.path;
    return _cacheDir!;
  }

  /// Derive a stable per-source subdirectory name from the URL template.
  static String _sourceId(String urlTemplate) {
    if (urlTemplate.contains('arcgisonline')) return 'esri';
    if (urlTemplate.contains('opentopomap')) return 'topo';
    if (urlTemplate.contains('openstreetmap')) return 'osm';
    try {
      return Uri.parse(urlTemplate).host;
    } catch (_) {
      return 'tiles';
    }
  }

  /// Build the local file path for a tile, scoped by source.
  static String _tilePath(String cacheDir, String sourceId, int z, int x, int y) {
    return p.join(cacheDir, sourceId, '$z', '$x', '$y.png');
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _CachedTileImageProvider(
      z: coordinates.z.toInt(),
      x: coordinates.x.toInt(),
      y: coordinates.y.toInt(),
      urlTemplate: options.urlTemplate ?? '',
      maxCacheAgeDays: maxCacheAgeDays,
    );
  }

  /// Get the current cache size in bytes.
  static Future<int> cacheSize() async {
    final cacheDir = await _getCacheDir();
    final dir = Directory(cacheDir);
    if (!dir.existsSync()) return 0;
    int total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Clear all cached tiles.
  static Future<void> clearCache() async {
    final cacheDir = await _getCacheDir();
    final dir = Directory(cacheDir);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
  }
}

/// Custom ImageProvider that checks local cache before network.
class _CachedTileImageProvider extends ImageProvider<_CachedTileImageProvider> {
  _CachedTileImageProvider({
    required this.z,
    required this.x,
    required this.y,
    required this.urlTemplate,
    required this.maxCacheAgeDays,
  });

  final int z;
  final int x;
  final int y;
  final String urlTemplate;
  final int maxCacheAgeDays;

  @override
  Future<_CachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadTile(decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadTile(ImageDecoderCallback decode) async {
    final bytes = await _fetchTileBytes();
    if (bytes != null && bytes.isNotEmpty) {
      try {
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        return decode(buffer);
      } catch (_) {
        // Corrupt image data — fall through to placeholder
      }
    }
    // Generate a valid 1x1 transparent image via the engine
    return _emptyCodec();
  }

  Future<Uint8List?> _fetchTileBytes() async {
    final cacheDir = await CachedTileProvider._getCacheDir();
    final sourceId = CachedTileProvider._sourceId(urlTemplate);
    final tilePath = CachedTileProvider._tilePath(cacheDir, sourceId, z, x, y);
    final file = File(tilePath);

    // Check cache
    if (file.existsSync()) {
      final age = DateTime.now().difference(file.lastModifiedSync());
      if (age.inDays < maxCacheAgeDays) {
        return file.readAsBytes();
      }
    }

    // Fetch from network
    try {
      final url = urlTemplate
          .replaceAll('{z}', '$z')
          .replaceAll('{x}', '$x')
          .replaceAll('{y}', '$y');

      final request = await CachedTileProvider._httpClient.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'com.argus.helios_gcs');
      final response = await request.close();

      if (response.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(response);

        // Save to cache
        final dir = Directory(p.dirname(tilePath));
        if (!dir.existsSync()) dir.createSync(recursive: true);
        await File(tilePath).writeAsBytes(bytes);

        return bytes;
      }
    } catch (_) {
      // Network unavailable — fall through to cache
    }

    // Fallback: stale cache
    if (file.existsSync()) {
      return file.readAsBytes();
    }

    return null;
  }

  /// Create a valid 1x1 transparent image codec via the engine.
  static Future<ui.Codec> _emptyCodec() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      ui.Paint()..color = const Color(0x00000000),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    final pngBytes = byteData!.buffer.asUint8List();
    final buffer = await ui.ImmutableBuffer.fromUint8List(pngBytes);
    return ui.instantiateImageCodecWithSize(buffer);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CachedTileImageProvider &&
          z == other.z &&
          x == other.x &&
          y == other.y &&
          urlTemplate == other.urlTemplate;

  @override
  int get hashCode => Object.hash(z, x, y, urlTemplate);
}
