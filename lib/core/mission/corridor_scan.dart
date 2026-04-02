import 'dart:math' as math;

import 'package:dart_mavlink/dart_mavlink.dart';

import '../../shared/models/mission_item.dart';

/// Parameters for corridor scan pattern generation.
class CorridorScanParams {
  const CorridorScanParams({
    required this.corridorWidthM,
    this.overlapPercent = 70.0,
    required this.altitudeM,
    this.cameraTriggerDistM = 0.0,
    this.turnaroundDistM = 20.0,
    this.startFromEnd = false,
  });

  /// Corridor width in metres (10-500).
  final double corridorWidthM;

  /// Overlap percentage between lines (60-90).
  final double overlapPercent;

  /// Flight altitude AGL in metres.
  final double altitudeM;

  /// Camera trigger distance in metres. 0 = no camera triggers.
  final double cameraTriggerDistM;

  /// Extra distance beyond the corridor for turnaround.
  final double turnaroundDistM;

  /// If true, start scanning from the last point of the polyline.
  final bool startFromEnd;
}

/// Generates a corridor scan flight pattern from a polyline center line.
///
/// The algorithm offsets the polyline by +/- half the corridor width to create
/// parallel flight lines, then connects them with turnaround waypoints.
class CorridorScanGenerator {
  /// Generate corridor scan waypoints.
  ///
  /// [centerLine] defines the corridor center as a list of lat/lon pairs.
  /// Must contain at least 2 points.
  ///
  /// Returns an empty list if the input is insufficient.
  List<MissionItem> generate({
    required List<({double lat, double lon})> centerLine,
    required CorridorScanParams params,
  }) {
    if (centerLine.length < 2) return [];
    if (params.corridorWidthM < 10 || params.corridorWidthM > 500) return [];

    final halfWidth = params.corridorWidthM / 2.0;

    // Compute line spacing from overlap
    final overlapFraction =
        params.overlapPercent.clamp(60.0, 90.0) / 100.0;
    final lineSpacing = params.corridorWidthM * (1.0 - overlapFraction);
    if (lineSpacing <= 0) return [];

    // Number of flight lines across the corridor
    final numLines =
        math.max(2, (params.corridorWidthM / lineSpacing).ceil() + 1);

    // Generate offset positions for each line
    final lines = <List<({double lat, double lon})>>[];
    for (var i = 0; i < numLines; i++) {
      final offset = -halfWidth + i * lineSpacing;
      final offsetLine = _offsetPolyline(centerLine, offset);
      lines.add(offsetLine);
    }

    // Build waypoints: snake pattern along lines
    final workingLines = params.startFromEnd ? lines.reversed.toList() : lines;
    final waypoints = <MissionItem>[];
    var seq = 0;

    // Add camera trigger command if specified
    if (params.cameraTriggerDistM > 0) {
      waypoints.add(MissionItem(
        seq: seq++,
        command: MavCmd.doSetCamTriggDist,
        param1: params.cameraTriggerDistM,
        altitude: params.altitudeM,
      ));
    }

    for (var lineIdx = 0; lineIdx < workingLines.length; lineIdx++) {
      final line = workingLines[lineIdx];
      // Alternate direction for snake pattern
      final forward = lineIdx.isEven;
      final orderedLine = forward ? line : line.reversed.toList();

      // Add turnaround waypoint at the start of each line (except first)
      if (lineIdx > 0 && params.turnaroundDistM > 0) {
        final turnPt = _extendPoint(
          orderedLine.first,
          orderedLine.length > 1 ? orderedLine[1] : orderedLine.first,
          params.turnaroundDistM,
          behind: true,
        );
        waypoints.add(MissionItem(
          seq: seq++,
          command: seq == 1 ? MavCmd.navTakeoff : MavCmd.navWaypoint,
          latitude: turnPt.lat,
          longitude: turnPt.lon,
          altitude: params.altitudeM,
        ));
      }

      // Add line waypoints
      for (final pt in orderedLine) {
        waypoints.add(MissionItem(
          seq: seq++,
          command: seq == 1 ? MavCmd.navTakeoff : MavCmd.navWaypoint,
          latitude: pt.lat,
          longitude: pt.lon,
          altitude: params.altitudeM,
        ));
      }

      // Add turnaround waypoint at the end of each line (except last)
      if (lineIdx < workingLines.length - 1 && params.turnaroundDistM > 0) {
        final turnPt = _extendPoint(
          orderedLine.last,
          orderedLine.length > 1
              ? orderedLine[orderedLine.length - 2]
              : orderedLine.last,
          params.turnaroundDistM,
          behind: true,
        );
        waypoints.add(MissionItem(
          seq: seq++,
          command: MavCmd.navWaypoint,
          latitude: turnPt.lat,
          longitude: turnPt.lon,
          altitude: params.altitudeM,
        ));
      }
    }

    // Disable camera trigger at end
    if (params.cameraTriggerDistM > 0) {
      waypoints.add(MissionItem(
        seq: seq++,
        command: MavCmd.doSetCamTriggDist,
        param1: 0, // stop triggering
        altitude: params.altitudeM,
      ));
    }

    // Renumber sequentially
    final result = <MissionItem>[];
    for (var i = 0; i < waypoints.length; i++) {
      result.add(waypoints[i].copyWith(seq: i));
    }
    return result;
  }

  /// Offset a polyline perpendicular to each segment by [offsetM] metres.
  /// Positive offset = right side, negative = left side (relative to direction).
  List<({double lat, double lon})> _offsetPolyline(
    List<({double lat, double lon})> line,
    double offsetM,
  ) {
    if (offsetM == 0) return List.from(line);

    final result = <({double lat, double lon})>[];
    for (var i = 0; i < line.length; i++) {
      double bearing;
      if (i == 0) {
        bearing = _bearing(line[0], line[1]);
      } else if (i == line.length - 1) {
        bearing = _bearing(line[i - 1], line[i]);
      } else {
        // Average bearing at interior points
        final b1 = _bearing(line[i - 1], line[i]);
        final b2 = _bearing(line[i], line[i + 1]);
        bearing = _averageAngle(b1, b2);
      }

      // Perpendicular: +90 degrees for right offset
      final perpBearing = bearing + math.pi / 2;
      final offset = _destinationPoint(line[i], offsetM, perpBearing);
      result.add(offset);
    }
    return result;
  }

  /// Bearing from point a to point b in radians.
  double _bearing(
      ({double lat, double lon}) a, ({double lat, double lon}) b) {
    final lat1 = a.lat * math.pi / 180;
    final lat2 = b.lat * math.pi / 180;
    final dLon = (b.lon - a.lon) * math.pi / 180;

    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return math.atan2(y, x);
  }

  /// Average of two angles (in radians), handling wrap-around.
  double _averageAngle(double a, double b) {
    final x = math.cos(a) + math.cos(b);
    final y = math.sin(a) + math.sin(b);
    return math.atan2(y, x);
  }

  /// Compute destination point given start, distance (m), and bearing (rad).
  ({double lat, double lon}) _destinationPoint(
    ({double lat, double lon}) start,
    double distanceM,
    double bearingRad,
  ) {
    const r = 6371000.0;
    final lat1 = start.lat * math.pi / 180;
    final lon1 = start.lon * math.pi / 180;
    final angDist = distanceM / r;

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angDist) +
          math.cos(lat1) * math.sin(angDist) * math.cos(bearingRad),
    );
    final lon2 = lon1 +
        math.atan2(
          math.sin(bearingRad) * math.sin(angDist) * math.cos(lat1),
          math.cos(angDist) - math.sin(lat1) * math.sin(lat2),
        );

    return (
      lat: lat2 * 180 / math.pi,
      lon: lon2 * 180 / math.pi,
    );
  }

  /// Extend a point beyond a segment by [distM] metres.
  /// If [behind] is true, extends in the opposite direction.
  ({double lat, double lon}) _extendPoint(
    ({double lat, double lon}) from,
    ({double lat, double lon}) toward,
    double distM, {
    bool behind = false,
  }) {
    var bearing = _bearing(toward, from);
    if (!behind) {
      bearing = bearing + math.pi; // reverse
    }
    return _destinationPoint(from, distM, bearing);
  }
}
