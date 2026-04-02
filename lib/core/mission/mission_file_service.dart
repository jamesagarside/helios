import 'dart:convert';

import 'package:dart_mavlink/dart_mavlink.dart';

import '../../shared/models/fence_zone.dart';
import '../../shared/models/mission_item.dart';
import '../../shared/models/rally_point.dart';

/// Supported mission file formats.
enum MissionFileFormat { plan, waypoints }

/// Result of loading a mission file.
class MissionFileResult {
  const MissionFileResult({
    this.items = const [],
    this.fenceZones = const [],
    this.rallyPoints = const [],
    this.cruiseSpeed = 15.0,
    this.hoverSpeed = 5.0,
    this.error,
  });

  final List<MissionItem> items;
  final List<FenceZone> fenceZones;
  final List<RallyPoint> rallyPoints;
  final double cruiseSpeed;
  final double hoverSpeed;
  final String? error;

  bool get hasError => error != null;
}

/// Service for saving and loading mission files in QGC Plan and ArduPilot
/// waypoint formats.
///
/// Supports:
/// - `.plan` (JSON, QGroundControl compatible)
/// - `.waypoints` (text, ArduPilot/Mission Planner compatible)
class MissionFileService {
  // ─── Save ────────────────────────────────────────────────────────────────

  /// Serialise [items] to the given [format].
  ///
  /// For `.plan` format, optional [fenceZones] and [rallyPoints] are included.
  String save({
    required List<MissionItem> items,
    required MissionFileFormat format,
    List<FenceZone> fenceZones = const [],
    List<RallyPoint> rallyPoints = const [],
    double cruiseSpeed = 15.0,
    double hoverSpeed = 5.0,
  }) {
    return switch (format) {
      MissionFileFormat.plan => _savePlan(
          items, fenceZones, rallyPoints, cruiseSpeed, hoverSpeed),
      MissionFileFormat.waypoints => _saveWaypoints(items),
    };
  }

  /// Detect format from file extension and parse the file content.
  MissionFileResult load(String content, {String fileName = ''}) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.plan')) {
      return _loadPlan(content);
    }
    if (lower.endsWith('.waypoints') || lower.endsWith('.txt')) {
      return _loadWaypoints(content);
    }
    // Try auto-detection: JSON or text
    final trimmed = content.trimLeft();
    if (trimmed.startsWith('{')) {
      return _loadPlan(content);
    }
    if (trimmed.startsWith('QGC WPL')) {
      return _loadWaypoints(content);
    }
    return const MissionFileResult(error: 'Unrecognised mission file format');
  }

  // ─── QGC Plan (.plan) ────────────────────────────────────────────────────

  String _savePlan(
    List<MissionItem> items,
    List<FenceZone> fenceZones,
    List<RallyPoint> rallyPoints,
    double cruiseSpeed,
    double hoverSpeed,
  ) {
    final missionItems = items.map(_itemToPlanJson).toList();

    final fenceCircles = <Map<String, dynamic>>[];
    final fencePolygons = <Map<String, dynamic>>[];

    for (final zone in fenceZones) {
      if (zone.shape == FenceShape.circle) {
        fenceCircles.add({
          'circle': {
            'center': [zone.centerLat, zone.centerLon],
            'radius': zone.radius,
          },
          'inclusion': zone.type == FenceZoneType.inclusion,
          'version': 1,
        });
      } else {
        fencePolygons.add({
          'polygon': zone.vertices
              .map((v) => [v.lat, v.lon])
              .toList(),
          'inclusion': zone.type == FenceZoneType.inclusion,
          'version': 1,
        });
      }
    }

    final rallyPts = rallyPoints
        .map((r) => [r.latitude, r.longitude, r.altitude])
        .toList();

    final plan = <String, dynamic>{
      'fileType': 'Plan',
      'version': 1,
      'groundStation': 'Helios GCS',
      'mission': {
        'cruiseSpeed': cruiseSpeed,
        'hoverSpeed': hoverSpeed,
        'items': missionItems,
      },
      'geoFence': {
        'circles': fenceCircles,
        'polygons': fencePolygons,
        'version': 2,
      },
      'rallyPoints': {
        'points': rallyPts,
        'version': 2,
      },
    };

    return const JsonEncoder.withIndent('  ').convert(plan);
  }

  Map<String, dynamic> _itemToPlanJson(MissionItem item) {
    return {
      'autoContinue': item.autocontinue == 1,
      'command': item.command,
      'coordinate': [item.latitude, item.longitude, item.altitude],
      'frame': item.frame,
      'params': [item.param1, item.param2, item.param3, item.param4],
      'type': 'SimpleItem',
    };
  }

  MissionFileResult _loadPlan(String content) {
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      final fileType = json['fileType'] as String? ?? '';
      if (fileType != 'Plan') {
        return const MissionFileResult(error: 'Not a QGC Plan file');
      }

      final mission = json['mission'] as Map<String, dynamic>? ?? {};
      final cruiseSpeed = (mission['cruiseSpeed'] as num?)?.toDouble() ?? 15.0;
      final hoverSpeed = (mission['hoverSpeed'] as num?)?.toDouble() ?? 5.0;
      final rawItems = mission['items'] as List<dynamic>? ?? [];

      final items = <MissionItem>[];
      for (var i = 0; i < rawItems.length; i++) {
        final raw = rawItems[i] as Map<String, dynamic>;
        final item = _planJsonToItem(raw, i);
        if (item != null) items.add(item);
      }

      // Parse geofence
      final fenceZones = <FenceZone>[];
      final geoFence = json['geoFence'] as Map<String, dynamic>?;
      if (geoFence != null) {
        final circles = geoFence['circles'] as List<dynamic>? ?? [];
        for (final c in circles) {
          final m = c as Map<String, dynamic>;
          final circle = m['circle'] as Map<String, dynamic>? ?? {};
          final center = circle['center'] as List<dynamic>? ?? [];
          if (center.length >= 2) {
            fenceZones.add(FenceZone(
              type: (m['inclusion'] as bool? ?? true)
                  ? FenceZoneType.inclusion
                  : FenceZoneType.exclusion,
              shape: FenceShape.circle,
              centerLat: (center[0] as num).toDouble(),
              centerLon: (center[1] as num).toDouble(),
              radius: (circle['radius'] as num?)?.toDouble() ?? 100,
            ));
          }
        }

        final polygons = geoFence['polygons'] as List<dynamic>? ?? [];
        for (final p in polygons) {
          final m = p as Map<String, dynamic>;
          final polygon = m['polygon'] as List<dynamic>? ?? [];
          final vertices = polygon
              .map((v) {
                final coords = v as List<dynamic>;
                if (coords.length >= 2) {
                  return (
                    lat: (coords[0] as num).toDouble(),
                    lon: (coords[1] as num).toDouble(),
                  );
                }
                return null;
              })
              .whereType<({double lat, double lon})>()
              .toList();
          if (vertices.length >= 3) {
            fenceZones.add(FenceZone(
              type: (m['inclusion'] as bool? ?? true)
                  ? FenceZoneType.inclusion
                  : FenceZoneType.exclusion,
              shape: FenceShape.polygon,
              vertices: vertices,
            ));
          }
        }
      }

      // Parse rally points
      final rallyPoints = <RallyPoint>[];
      final rally = json['rallyPoints'] as Map<String, dynamic>?;
      if (rally != null) {
        final points = rally['points'] as List<dynamic>? ?? [];
        for (var i = 0; i < points.length; i++) {
          final coords = points[i] as List<dynamic>;
          if (coords.length >= 2) {
            rallyPoints.add(RallyPoint(
              seq: i,
              latitude: (coords[0] as num).toDouble(),
              longitude: (coords[1] as num).toDouble(),
              altitude: coords.length >= 3
                  ? (coords[2] as num).toDouble()
                  : 50.0,
            ));
          }
        }
      }

      return MissionFileResult(
        items: items,
        fenceZones: fenceZones,
        rallyPoints: rallyPoints,
        cruiseSpeed: cruiseSpeed,
        hoverSpeed: hoverSpeed,
      );
    } catch (e) {
      return MissionFileResult(error: 'Failed to parse Plan file: $e');
    }
  }

  MissionItem? _planJsonToItem(Map<String, dynamic> raw, int seq) {
    final coord = raw['coordinate'] as List<dynamic>? ?? [];
    final params = raw['params'] as List<dynamic>? ?? [];
    final command = (raw['command'] as num?)?.toInt() ?? MavCmd.navWaypoint;
    final frame =
        (raw['frame'] as num?)?.toInt() ?? MavFrame.globalRelativeAlt;
    final autoContinue = raw['autoContinue'] as bool? ?? true;

    return MissionItem(
      seq: seq,
      command: command,
      frame: frame,
      autocontinue: autoContinue ? 1 : 0,
      param1: params.isNotEmpty ? (params[0] as num?)?.toDouble() ?? 0.0 : 0.0,
      param2: params.length > 1 ? (params[1] as num?)?.toDouble() ?? 0.0 : 0.0,
      param3: params.length > 2 ? (params[2] as num?)?.toDouble() ?? 0.0 : 0.0,
      param4: params.length > 3 ? (params[3] as num?)?.toDouble() ?? 0.0 : 0.0,
      latitude: coord.isNotEmpty ? (coord[0] as num?)?.toDouble() ?? 0.0 : 0.0,
      longitude:
          coord.length > 1 ? (coord[1] as num?)?.toDouble() ?? 0.0 : 0.0,
      altitude:
          coord.length > 2 ? (coord[2] as num?)?.toDouble() ?? 0.0 : 0.0,
    );
  }

  // ─── ArduPilot Waypoints (.waypoints) ────────────────────────────────────

  String _saveWaypoints(List<MissionItem> items) {
    final buf = StringBuffer('QGC WPL 110\n');
    for (final item in items) {
      buf.writeln(
        '${item.seq}\t'
        '${item.current}\t'
        '${item.frame}\t'
        '${item.command}\t'
        '${_fmtDouble(item.param1)}\t'
        '${_fmtDouble(item.param2)}\t'
        '${_fmtDouble(item.param3)}\t'
        '${_fmtDouble(item.param4)}\t'
        '${item.latitude.toStringAsFixed(8)}\t'
        '${item.longitude.toStringAsFixed(8)}\t'
        '${item.altitude.toStringAsFixed(6)}\t'
        '${item.autocontinue}',
      );
    }
    return buf.toString();
  }

  MissionFileResult _loadWaypoints(String content) {
    try {
      final lines = content.split('\n').where((l) => l.trim().isNotEmpty);
      if (lines.isEmpty) {
        return const MissionFileResult(error: 'Empty waypoint file');
      }

      final header = lines.first.trim();
      if (!header.startsWith('QGC WPL')) {
        return const MissionFileResult(
            error: 'Missing QGC WPL header');
      }

      final items = <MissionItem>[];
      for (final line in lines.skip(1)) {
        final item = _parseWaypointLine(line.trim());
        if (item != null) items.add(item);
      }

      return MissionFileResult(items: items);
    } catch (e) {
      return MissionFileResult(error: 'Failed to parse waypoint file: $e');
    }
  }

  MissionItem? _parseWaypointLine(String line) {
    if (line.isEmpty) return null;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 12) return null;

    final seq = int.tryParse(parts[0]);
    final current = int.tryParse(parts[1]);
    final frame = int.tryParse(parts[2]);
    final command = int.tryParse(parts[3]);
    final p1 = double.tryParse(parts[4]);
    final p2 = double.tryParse(parts[5]);
    final p3 = double.tryParse(parts[6]);
    final p4 = double.tryParse(parts[7]);
    final lat = double.tryParse(parts[8]);
    final lon = double.tryParse(parts[9]);
    final alt = double.tryParse(parts[10]);
    final autoCon = int.tryParse(parts[11]);

    if (seq == null || command == null || lat == null || lon == null) {
      return null;
    }

    return MissionItem(
      seq: seq,
      current: current ?? 0,
      frame: frame ?? MavFrame.globalRelativeAlt,
      command: command,
      param1: p1 ?? 0.0,
      param2: p2 ?? 0.0,
      param3: p3 ?? 0.0,
      param4: p4 ?? 0.0,
      latitude: lat,
      longitude: lon,
      altitude: alt ?? 0.0,
      autocontinue: autoCon ?? 1,
    );
  }

  String _fmtDouble(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(6);
  }
}
