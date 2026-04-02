import 'package:dart_mavlink/dart_mavlink.dart';
import '../../shared/models/mission_item.dart';

/// Parses GPS Exchange Format (GPX) files and extracts waypoints as
/// [MissionItem]s.
///
/// Platform: All (pure Dart, no FFI).
///
/// Supported elements:
/// - `<wpt lat="..." lon="...">` — standalone waypoints.
/// - `<trkpt lat="..." lon="...">` inside `<trkseg>` — track points.
/// - `<rtept lat="..." lon="...">` — route points.
///
/// Altitude is read from the `<ele>` child element when present; otherwise
/// [defaultAltM] is used.
class GpxImporter {
  /// Parse [gpxContent] and return a list of [MissionItem]s.
  ///
  /// Points are appended in document order: wpt, then trkpt/rtept.
  /// Each point becomes a [MavCmd.navWaypoint] item (first is
  /// [MavCmd.navTakeoff]) with sequential [seq] numbers starting from 0.
  ///
  /// Returns an empty list on malformed XML or if no points are found.
  List<MissionItem> parseGpx(
    String gpxContent, {
    double defaultAltM = 30.0,
  }) {
    try {
      return _parse(gpxContent, defaultAltM);
    } catch (_) {
      return [];
    }
  }

  List<MissionItem> _parse(String content, double defaultAltM) {
    if (content.trim().isEmpty) return [];

    final coords = <_Coord>[];

    // Match <wpt>, <trkpt>, and <rtept> elements (they all have the same
    // lat/lon attribute structure).
    final pointPattern = RegExp(
      r'<(wpt|trkpt|rtept)\b([^>]*)>([\s\S]*?)</(wpt|trkpt|rtept)>',
      caseSensitive: false,
    );

    final latAttr = RegExp(r'lat="([^"]+)"', caseSensitive: false);
    final lonAttr = RegExp(r'lon="([^"]+)"', caseSensitive: false);
    final eleTag =
        RegExp(r'<ele[^>]*>([\s\S]*?)</ele>', caseSensitive: false);

    for (final match in pointPattern.allMatches(content)) {
      final attrs = match.group(2) ?? '';
      final body = match.group(3) ?? '';

      final latM = latAttr.firstMatch(attrs);
      final lonM = lonAttr.firstMatch(attrs);
      if (latM == null || lonM == null) continue;

      final lat = double.tryParse(latM.group(1)!.trim());
      final lon = double.tryParse(lonM.group(1)!.trim());
      if (lat == null || lon == null) continue;

      final eleM = eleTag.firstMatch(body);
      final alt = eleM != null
          ? double.tryParse(eleM.group(1)!.trim()) ?? defaultAltM
          : defaultAltM;

      coords.add(_Coord(lat: lat, lon: lon, alt: alt));
    }

    return _toItems(coords);
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
