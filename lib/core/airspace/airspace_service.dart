import 'dart:convert';
import 'dart:io';
import 'package:latlong2/latlong.dart';
import '../../shared/models/airspace_zone.dart';

/// Parses OpenAIP GeoJSON airspace files into [AirspaceZone] objects.
///
/// OpenAIP exports airspace as GeoJSON FeatureCollections where each Feature
/// has a Polygon geometry and properties including `name`, `type`, `lowerLimit`,
/// and `upperLimit`. Both OpenAIP v1 and v2 export formats are handled.
class AirspaceService {
  /// Parse a GeoJSON file at [path] and return the contained airspace zones.
  Future<List<AirspaceZone>> importGeoJson(String path) async {
    final raw = await File(path).readAsString();
    return parseGeoJsonString(raw);
  }

  /// Parse GeoJSON from a string — exposed for testing.
  List<AirspaceZone> parseGeoJsonString(String geojson) {
    final Map<String, dynamic> root;
    try {
      root = jsonDecode(geojson) as Map<String, dynamic>;
    } catch (_) {
      return [];
    }

    final features = root['features'] as List<dynamic>? ?? [];
    final zones = <AirspaceZone>[];

    for (final raw in features) {
      final feature = raw as Map<String, dynamic>;
      final props = feature['properties'] as Map<String, dynamic>? ?? {};
      final geom = feature['geometry'] as Map<String, dynamic>?;
      if (geom == null) continue;
      if (geom['type'] != 'Polygon') continue;

      final coords = geom['coordinates'] as List<dynamic>?;
      if (coords == null || coords.isEmpty) continue;
      final ring = coords[0] as List<dynamic>;
      final polygon = ring
          .whereType<List<dynamic>>()
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      if (polygon.length < 3) continue;

      final id = feature['id']?.toString() ??
          props['id']?.toString() ??
          '${zones.length}';
      final name = props['name'] as String? ??
          props['Name'] as String? ??
          'Unknown';

      final typeStr = (props['type'] as String? ??
              props['Type'] as String? ??
              props['class'] as String? ??
              '')
          .toUpperCase();
      final type = _parseType(typeStr);

      // Lower/upper limits — OpenAIP uses nested objects or flat strings
      final lower = _parseLimit(props['lowerLimit'] ?? props['lower_limit'] ?? props['floor']);
      final upper = _parseLimit(props['upperLimit'] ?? props['upper_limit'] ?? props['ceiling']);

      zones.add(AirspaceZone(
        id: id,
        name: name,
        type: type,
        polygon: polygon,
        lowerLimitFt: lower,
        upperLimitFt: upper,
        description: props['description'] as String? ?? '',
      ));
    }
    return zones;
  }

  AirspaceType _parseType(String s) {
    if (s.contains('PROHIBITED') || s == 'P') return AirspaceType.prohibited;
    if (s.contains('RESTRICTED') || s == 'R') return AirspaceType.restricted;
    if (s.contains('DANGER') || s == 'D') return AirspaceType.danger;
    if (s.contains('CTR')) return AirspaceType.ctr;
    if (s.contains('TMA')) return AirspaceType.tma;
    if (s == 'A') return AirspaceType.classA;
    if (s == 'B') return AirspaceType.classB;
    if (s == 'C') return AirspaceType.classC;
    if (s == 'D') return AirspaceType.classD;
    if (s == 'E') return AirspaceType.classE;
    if (s == 'F') return AirspaceType.classF;
    if (s == 'G') return AirspaceType.classG;
    return AirspaceType.other;
  }

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
