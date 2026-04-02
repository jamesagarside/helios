import 'package:dart_mavlink/dart_mavlink.dart';
import '../../shared/models/mission_item.dart';

/// Parses Google Earth KML files and extracts waypoints as [MissionItem]s.
///
/// Platform: All (pure Dart, no FFI).
///
/// Supported geometry:
/// - `<Placemark>` with `<Point>` — one waypoint per placemark.
/// - `<Placemark>` with `<LineString>` — one waypoint per coordinate.
/// - `<Placemark>` with `<MultiGeometry>` — walks nested Point/LineString.
///
/// KML coordinate format: `longitude,latitude[,altitude]` (space-separated
/// triples for LineString).
class KmlImporter {
  /// Parse [kmlContent] and return a list of [MissionItem]s.
  ///
  /// Each coordinate triple becomes a [MavCmd.navWaypoint] item with
  /// sequential [seq] numbers starting from 0. The first item is assigned
  /// [MavCmd.navTakeoff].
  ///
  /// If altitude is absent in the KML, [defaultAltM] is used.
  /// Returns an empty list on malformed XML or if no coordinates are found.
  List<MissionItem> parseKml(
    String kmlContent, {
    double defaultAltM = 30.0,
  }) {
    try {
      return _parse(kmlContent, defaultAltM);
    } catch (_) {
      return [];
    }
  }

  List<MissionItem> _parse(String content, double defaultAltM) {
    if (content.trim().isEmpty) return [];

    final coords = <_Coord>[];

    // Extract all <coordinates>…</coordinates> blocks.
    // KML can have whitespace-separated lon,lat[,alt] triples.
    final coordPattern = RegExp(
      r'<coordinates[^>]*>([\s\S]*?)</coordinates>',
      caseSensitive: false,
    );

    for (final match in coordPattern.allMatches(content)) {
      final raw = match.group(1) ?? '';
      // Split on any whitespace (newline, space, tab) to get individual triples
      final triples = raw.trim().split(RegExp(r'\s+'));
      for (final triple in triples) {
        final c = _parseTriple(triple.trim(), defaultAltM);
        if (c != null) coords.add(c);
      }
    }

    return _toItems(coords);
  }

  _Coord? _parseTriple(String triple, double defaultAltM) {
    if (triple.isEmpty) return null;
    final parts = triple.split(',');
    if (parts.length < 2) return null;
    final lon = double.tryParse(parts[0].trim());
    final lat = double.tryParse(parts[1].trim());
    if (lon == null || lat == null) return null;
    final alt = parts.length >= 3
        ? double.tryParse(parts[2].trim()) ?? defaultAltM
        : defaultAltM;
    return _Coord(lat: lat, lon: lon, alt: alt);
  }

  List<MissionItem> _toItems(List<_Coord> coords) {
    final items = <MissionItem>[];
    for (var i = 0; i < coords.length; i++) {
      final c = coords[i];
      items.add(MissionItem(
        seq: i,
        command: i == 0 ? MavCmd.navTakeoff : MavCmd.navWaypoint,
        latitude: c.lat,
        longitude: c.lon,
        altitude: c.alt,
      ));
    }
    return items;
  }
}

class _Coord {
  const _Coord({required this.lat, required this.lon, required this.alt});

  final double lat;
  final double lon;
  final double alt;
}
