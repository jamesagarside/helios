import 'dart:math' as math;

import 'package:dart_mavlink/dart_mavlink.dart';

import '../../shared/models/mission_item.dart';

/// A geographic coordinate used by the survey/orbit generators.
///
/// Plain record so the generators carry no Flutter / latlong2 dependency.
typedef GeoPoint = ({double lat, double lon});

/// Parameters for a rectangular (rotatable) survey grid.
class SurveyGridParams {
  const SurveyGridParams({
    required this.laneSpacingM,
    required this.altitudeM,
    this.angleDeg = 0,
  });

  /// Spacing between adjacent scan lines in metres.
  final double laneSpacingM;

  /// Flight altitude AGL in metres.
  final double altitudeM;

  /// Rotation of the lawnmower lines in degrees.
  final int angleDeg;
}

/// Parameters for an orbit (circular loiter described as discrete waypoints).
class OrbitParams {
  const OrbitParams({
    required this.radiusM,
    required this.altitudeM,
    required this.laps,
  });

  /// Orbit radius in metres.
  final double radiusM;

  /// Flight altitude AGL in metres.
  final double altitudeM;

  /// Number of laps to fly.
  final int laps;
}

/// Pure survey / orbit geometry generators.
///
/// Every method returns a `List<MissionItem>` and has no Flutter, provider, or
/// latlong2 dependency. Callers convert their map coordinates to [GeoPoint] and
/// supply the count of items already in the mission so the generator can decide
/// whether to emit a leading TAKEOFF and how to offset sequence numbers.
class SurveyGridGenerator {
  /// Generate a lawnmower survey grid for the given bounding rectangle.
  ///
  /// [corner1] and [corner2] are two opposite corners of the rectangle.
  /// [existingItemCount] is the number of mission items already present; when 0
  /// a leading TAKEOFF is emitted at the first row endpoint.
  List<MissionItem> generateSurveyGrid({
    required GeoPoint corner1,
    required GeoPoint corner2,
    required SurveyGridParams params,
    int existingItemCount = 0,
  }) {
    final minLat = math.min(corner1.lat, corner2.lat);
    final maxLat = math.max(corner1.lat, corner2.lat);
    final minLon = math.min(corner1.lon, corner2.lon);
    final maxLon = math.max(corner1.lon, corner2.lon);

    final centreLat = (minLat + maxLat) / 2.0;
    final centreLon = (minLon + maxLon) / 2.0;

    const metersPerDegLat = 111319.0;
    final metersPerDegLon =
        111319.0 * math.cos(centreLat * math.pi / 180.0);

    final x1 = (minLon - centreLon) * metersPerDegLon;
    final y1 = (minLat - centreLat) * metersPerDegLat;
    final x2 = (maxLon - centreLon) * metersPerDegLon;
    final y2 = (maxLat - centreLat) * metersPerDegLat;

    final angleRad = params.angleDeg * math.pi / 180.0;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);

    // Find extent of bounding box in rotated frame
    final corners = [(x1, y1), (x2, y1), (x2, y2), (x1, y2)];
    var rMinX = double.infinity;
    var rMaxX = double.negativeInfinity;
    var rMinY = double.infinity;
    var rMaxY = double.negativeInfinity;
    for (final (cx, cy) in corners) {
      final rx = cx * cosA + cy * sinA;
      final ry = -cx * sinA + cy * cosA;
      if (rx < rMinX) rMinX = rx;
      if (rx > rMaxX) rMaxX = rx;
      if (ry < rMinY) rMinY = ry;
      if (ry > rMaxY) rMaxY = ry;
    }

    // Build lawnmower row endpoints in rotated frame
    final rowPoints = <(double, double)>[];
    var rowIndex = 0;
    var ry = rMinY + params.laneSpacingM / 2.0;
    while (ry < rMaxY + params.laneSpacingM / 2.0 - 1e-6) {
      if (rowIndex.isEven) {
        rowPoints.add((rMinX, ry));
        rowPoints.add((rMaxX, ry));
      } else {
        rowPoints.add((rMaxX, ry));
        rowPoints.add((rMinX, ry));
      }
      rowIndex++;
      ry += params.laneSpacingM;
    }

    if (rowPoints.isEmpty) return [];

    final items = <MissionItem>[];

    // First item is TAKEOFF if mission is currently empty
    if (existingItemCount == 0) {
      final (frx, fry) = rowPoints.first;
      final gx = frx * cosA - fry * sinA;
      final gy = frx * sinA + fry * cosA;
      items.add(MissionItem(
        seq: 0,
        frame: MavFrame.globalRelativeAlt,
        command: MavCmd.navTakeoff,
        latitude: centreLat + gy / metersPerDegLat,
        longitude: centreLon + gx / metersPerDegLon,
        altitude: params.altitudeM,
      ));
    }

    final startSeq = existingItemCount + items.length;
    for (var i = 0; i < rowPoints.length; i++) {
      final (rx, ry2) = rowPoints[i];
      final gx = rx * cosA - ry2 * sinA;
      final gy = rx * sinA + ry2 * cosA;
      items.add(MissionItem(
        seq: startSeq + i,
        frame: MavFrame.globalRelativeAlt,
        command: MavCmd.navWaypoint,
        latitude: centreLat + gy / metersPerDegLat,
        longitude: centreLon + gx / metersPerDegLon,
        altitude: params.altitudeM,
      ));
    }

    return items;
  }

  /// Generate a lawnmower survey grid clipped to [polygon] (vertex list).
  ///
  /// Uses a ray-casting algorithm to clip scan-line segments to only include
  /// portions inside the polygon. Returns an empty list if fewer than 3
  /// vertices are supplied.
  ///
  /// [existingItemCount] is the number of mission items already present; when 0
  /// a leading TAKEOFF is emitted at the first polygon vertex.
  List<MissionItem> generatePolygonSurvey({
    required List<GeoPoint> polygon,
    required double spacingM,
    required double altM,
    int existingItemCount = 0,
  }) {
    if (polygon.length < 3) return [];

    // Convert polygon to local metres (centred on polygon centroid)
    final centreLat =
        polygon.map((p) => p.lat).reduce((a, b) => a + b) / polygon.length;
    final centreLon =
        polygon.map((p) => p.lon).reduce((a, b) => a + b) / polygon.length;

    const mPerDegLat = 111319.0;
    final mPerDegLon = 111319.0 * math.cos(centreLat * math.pi / 180.0);

    List<(double, double)> toXY(GeoPoint ll) => [
          ((ll.lon - centreLon) * mPerDegLon,
              (ll.lat - centreLat) * mPerDegLat)
        ];

    final polyXY = polygon.map((ll) => toXY(ll).first).toList();

    // Bounding box in local metres
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    for (final (x, y) in polyXY) {
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
    }

    final items = <MissionItem>[];

    // Add takeoff at the first polygon vertex when mission is empty
    if (existingItemCount == 0) {
      final (fx, fy) = polyXY.first;
      items.add(MissionItem(
        seq: 0,
        command: MavCmd.navTakeoff,
        latitude: centreLat + fy / mPerDegLat,
        longitude: centreLon + fx / mPerDegLon,
        altitude: altM,
      ));
    }

    final startSeq = existingItemCount + items.length;
    var rowIndex = 0;
    var y = minY + spacingM / 2.0;

    while (y < maxY + spacingM / 2.0 - 1e-6) {
      // Find intersections of this horizontal scan line with the polygon
      final xs = <double>[];
      final n = polyXY.length;
      for (var i = 0; i < n; i++) {
        final (x1, y1) = polyXY[i];
        final (x2, y2) = polyXY[(i + 1) % n];
        if ((y1 <= y && y < y2) || (y2 <= y && y < y1)) {
          final t = (y - y1) / (y2 - y1);
          xs.add(x1 + t * (x2 - x1));
        }
      }
      xs.sort();

      // Add waypoint pairs (inside segments)
      if (xs.length >= 2) {
        final isEven = rowIndex.isEven;
        for (var k = 0; k + 1 < xs.length; k += 2) {
          final xA = isEven ? xs[k] : xs[xs.length - 1 - k - 1];
          final xB = isEven ? xs[k + 1] : xs[xs.length - 1 - k];
          for (final xi in [xA, xB]) {
            items.add(MissionItem(
              seq: startSeq + items.length - (existingItemCount == 0 ? 1 : 0),
              command: MavCmd.navWaypoint,
              latitude: centreLat + y / mPerDegLat,
              longitude: centreLon + xi / mPerDegLon,
              altitude: altM,
            ));
          }
        }
      }

      rowIndex++;
      y += spacingM;
    }

    // Renumber sequentially
    for (var i = 0; i < items.length; i++) {
      items[i] = items[i].copyWith(seq: existingItemCount + i);
    }

    return items;
  }

  /// Generate [laps] * 12 orbit waypoints clockwise around [centre].
  ///
  /// The first waypoint is a TAKEOFF at the 0-radian orbit point, followed by
  /// `laps` full circles of 12 waypoints each.
  List<MissionItem> generateOrbitWaypoints({
    required GeoPoint centre,
    required OrbitParams params,
  }) {
    const pointsPerLap = 12;
    const earthRadius = 6371000.0;
    final centreLat = centre.lat;
    final centreLon = centre.lon;
    final latOffsetDeg = (params.radiusM / earthRadius) * (180.0 / math.pi);
    final lonOffsetDeg = latOffsetDeg / math.cos(centreLat * math.pi / 180.0);

    final items = <MissionItem>[];
    var seq = 0;

    // Takeoff at first orbit point
    const firstAngle = 0.0;
    final takeoffLat = centreLat + latOffsetDeg * math.cos(firstAngle);
    final takeoffLon = centreLon + lonOffsetDeg * math.sin(firstAngle);
    items.add(MissionItem(
      seq: seq++,
      frame: MavFrame.globalRelativeAlt,
      command: MavCmd.navTakeoff,
      latitude: takeoffLat,
      longitude: takeoffLon,
      altitude: params.altitudeM,
    ));

    for (var lap = 0; lap < params.laps; lap++) {
      for (var p = 0; p < pointsPerLap; p++) {
        // Clockwise: angle increases in positive direction
        final angle = 2.0 * math.pi * p / pointsPerLap;
        final lat = centreLat + latOffsetDeg * math.cos(angle);
        final lon = centreLon + lonOffsetDeg * math.sin(angle);
        items.add(MissionItem(
          seq: seq++,
          frame: MavFrame.globalRelativeAlt,
          command: MavCmd.navWaypoint,
          latitude: lat,
          longitude: lon,
          altitude: params.altitudeM,
        ));
      }
    }

    return items;
  }
}
