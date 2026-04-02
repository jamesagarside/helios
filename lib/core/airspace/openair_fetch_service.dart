import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../../shared/models/airspace_zone.dart';

/// Fetches airspace data from the OpenAIP v2 API for a given bounding box,
/// caching results for 7 days.
///
/// Platform: All platforms
class OpenAirFetchService {
  static const _cacheValidDays = 7;

  /// Fetches airspace zones from the OpenAIP v2 API for the given bounding box.
  ///
  /// Results are cached in `{appSupportDir}/airspace_cache/` for 7 days.
  /// Returns an empty list if the request fails or returns no data.
  Future<List<AirspaceZone>> fetchForBounds({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    required String apiKey,
  }) async {
    final cacheKey = _cacheKey(minLat, maxLat, minLon, maxLon);

    // Try cache first
    final cached = await _loadFromCache(cacheKey);
    if (cached != null) {
      return _parseApiResponse(cached);
    }

    // Build bbox polygon ring (closed ring: 5 points)
    final bboxRing = [
      [minLon, minLat],
      [maxLon, minLat],
      [maxLon, maxLat],
      [minLon, maxLat],
      [minLon, minLat],
    ];
    final geometryFilter = jsonEncode({
      'type': 'Polygon',
      'coordinates': [bboxRing],
    });

    final zones = <AirspaceZone>[];
    var page = 1;
    String? lastBody;

    // Paginate through all results
    while (true) {
      final uri = Uri(
        scheme: 'https',
        host: 'api.openaip.net',
        path: '/api/airspaces',
        queryParameters: {
          'page': '$page',
          'limit': '100',
          'geometryFilter': geometryFilter,
        },
      );

      String body;
      try {
        body = await _httpGet(uri, apiKey);
      } catch (_) {
        break;
      }

      final parsed = _parseApiResponse(body);
      zones.addAll(parsed);
      lastBody = body;

      // Check if there are more pages
      final Map<String, dynamic> root;
      try {
        root = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        break;
      }
      final totalCount = (root['totalCount'] as num?)?.toInt() ?? 0;
      if (zones.length >= totalCount || parsed.isEmpty) break;
      page++;
    }

    // Cache the combined results only if we got something meaningful
    if (lastBody != null) {
      // Re-serialise into a canonical envelope for caching
      final envelope = jsonEncode({
        'totalCount': zones.length,
        'items': zones
            .map((z) => _zoneToApiItem(z))
            .toList(),
      });
      await _cacheToFile(cacheKey, envelope);
    }

    return zones;
  }

  /// Converts a zone back to a minimal API-item map for cache serialisation.
  Map<String, dynamic> _zoneToApiItem(AirspaceZone z) => {
        '_id': z.id,
        'name': z.name,
        'type': _typeToInt(z.type),
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            z.polygon
                .map((p) => [p.longitude, p.latitude])
                .toList(),
          ],
        },
        'lowerLimit': {'value': z.lowerLimitFt},
        'upperLimit': {'value': z.upperLimitFt},
      };

  /// Public accessor for [_parseApiResponse] — exposed for unit tests only.
  @visibleForTesting
  List<AirspaceZone> parseApiResponsePublic(String body) =>
      _parseApiResponse(body);

  /// Parses the OpenAIP v2 paginated response format.
  ///
  /// Expected shape: `{ "totalCount": N, "items": [...] }`
  List<AirspaceZone> _parseApiResponse(String body) {
    final Map<String, dynamic> root;
    try {
      root = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return [];
    }

    final items = root['items'] as List<dynamic>? ?? [];
    final zones = <AirspaceZone>[];

    for (final raw in items) {
      final item = raw as Map<String, dynamic>? ?? {};

      final id = (item['_id'] ?? item['id'] ?? '').toString();
      if (id.isEmpty) continue;

      final name = item['name'] as String? ?? 'Unknown';
      final typeInt = (item['type'] as num?)?.toInt() ?? 0;
      final type = _parseTypeInt(typeInt);

      final geom = item['geometry'] as Map<String, dynamic>?;
      if (geom == null || geom['type'] != 'Polygon') continue;

      final coords = geom['coordinates'] as List<dynamic>?;
      if (coords == null || coords.isEmpty) continue;
      final ring = coords[0] as List<dynamic>;
      final polygon = ring
          .whereType<List<dynamic>>()
          .map((c) => LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ))
          .toList();
      if (polygon.length < 3) continue;

      final lower = _parseLimit(item['lowerLimit']);
      final upper = _parseLimit(item['upperLimit']);

      zones.add(AirspaceZone(
        id: id,
        name: name,
        type: type,
        polygon: polygon,
        lowerLimitFt: lower,
        upperLimitFt: upper,
      ));
    }

    return zones;
  }

  /// Executes an HTTP GET to [uri] with the OpenAIP API key header.
  Future<String> _httpGet(Uri uri, String apiKey) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set('x-openaip-api-key', apiKey);
      request.headers.set('Accept', 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          'OpenAIP returned status ${response.statusCode}',
          uri: uri,
        );
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  Future<void> _cacheToFile(String cacheKey, String body) async {
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}/$cacheKey.json');
      await file.writeAsString(body);
    } catch (_) {
      // Cache write failure is non-fatal
    }
  }

  /// Returns the cached body, or null if the cache is missing or older than 7 days.
  Future<String?> _loadFromCache(String cacheKey) async {
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}/$cacheKey.json');
      if (!await file.exists()) return null;
      final stat = await file.stat();
      final age = DateTime.now().difference(stat.modified);
      if (age.inDays >= _cacheValidDays) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _cacheDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/airspace_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _cacheKey(
    double minLat,
    double maxLat,
    double minLon,
    double maxLon,
  ) {
    // Truncate to 3dp for a stable cache key across tiny movements
    String fmt(double v) => v.toStringAsFixed(3).replaceAll('-', 'n');
    return '${fmt(minLat)}_${fmt(maxLat)}_${fmt(minLon)}_${fmt(maxLon)}';
  }

  AirspaceType _parseTypeInt(int type) => switch (type) {
        1 => AirspaceType.restricted,
        2 => AirspaceType.danger,
        3 => AirspaceType.prohibited,
        4 => AirspaceType.ctr,
        5 => AirspaceType.tma,
        7 => AirspaceType.restricted, // TFR treated as restricted
        11 => AirspaceType.danger,    // ALERT
        12 => AirspaceType.danger,    // WARNING
        _ => AirspaceType.other,
      };

  int _typeToInt(AirspaceType type) => switch (type) {
        AirspaceType.restricted => 1,
        AirspaceType.danger => 2,
        AirspaceType.prohibited => 3,
        AirspaceType.ctr => 4,
        AirspaceType.tma => 5,
        _ => 0,
      };

  int _parseLimit(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    if (value is Map) {
      final v = value['value'] ?? value['ft'] ?? value['altitude'];
      if (v is num) return v.toInt();
    }
    final str = value.toString();
    final match = RegExp(r'(\d+)').firstMatch(str);
    return match != null ? int.parse(match.group(1)!) : 0;
  }
}
