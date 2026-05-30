import 'package:dart_mavlink/dart_mavlink.dart';

import '../../shared/models/mission_item.dart';

/// Severity of a mission validation finding.
enum MissionIssueSeverity { error, warning, info }

/// A single validation finding, optionally tied to a mission item [seq].
class MissionIssue {
  const MissionIssue(this.severity, this.message, {this.seq});

  final MissionIssueSeverity severity;
  final String message;

  /// The sequence number of the related mission item, if the issue is
  /// item-specific.
  final int? seq;

  @override
  String toString() =>
      '[${severity.name}]${seq != null ? ' wp$seq:' : ''} $message';
}

/// Pre-upload sanity checks for a mission, mirroring the kind of warnings
/// Mission Planner surfaces before sending a mission to the vehicle.
///
/// Intentionally pure and dependency-free so it is straightforward to unit
/// test. Terrain awareness is opt-in: callers may pass per-waypoint ground
/// elevations (e.g. from [DemService]) via [terrainElevationBySeq].
class MissionValidator {
  const MissionValidator({
    this.maxItems = 32768,
    this.minTerrainClearance = 5.0,
    this.largeAltJump = 200.0,
  });

  /// Soft cap on item count; most autopilots store far fewer.
  final int maxItems;

  /// Minimum acceptable height above ground for an absolute-frame waypoint
  /// when terrain data is supplied, in metres.
  final double minTerrainClearance;

  /// Altitude delta between consecutive nav waypoints that is worth flagging
  /// as informational, in metres.
  final double largeAltJump;

  /// Validate [items], returning findings ordered errors → warnings → info.
  ///
  /// [terrainElevationBySeq] maps a waypoint's `seq` to the ground elevation
  /// (metres AMSL) beneath it; when present, absolute-frame waypoints are
  /// checked for terrain clearance.
  List<MissionIssue> validate(
    List<MissionItem> items, {
    Map<int, double>? terrainElevationBySeq,
  }) {
    final issues = <MissionIssue>[];

    if (items.isEmpty) {
      issues.add(const MissionIssue(
        MissionIssueSeverity.info,
        'Mission is empty',
      ));
      return issues;
    }

    if (items.length > maxItems) {
      issues.add(MissionIssue(
        MissionIssueSeverity.warning,
        'Mission has ${items.length} items, above the $maxItems-item limit',
      ));
    }

    final navItems = items.where((i) => i.isNavCommand).toList();

    // DO_JUMP targets must reference a real sequence index.
    for (final item in items) {
      if (item.command == MavCmd.doJump) {
        final target = item.param1.round();
        if (target < 0 || target >= items.length) {
          issues.add(MissionIssue(
            MissionIssueSeverity.error,
            'DO_JUMP target $target is out of range (0..${items.length - 1})',
            seq: item.seq,
          ));
        }
      }
    }

    // Per-waypoint altitude checks.
    for (final item in navItems) {
      final isRelativeOrTerrain = item.frame == MavFrame.globalRelativeAlt ||
          item.frame == MavFrame.globalRelativeAltInt ||
          item.frame == MavFrame.globalTerrainAlt ||
          item.frame == MavFrame.globalTerrainAltInt;

      // Non-positive AGL for a flying waypoint is almost always a mistake.
      if (isRelativeOrTerrain &&
          item.altitude <= 0 &&
          item.command != MavCmd.navLand &&
          item.command != MavCmd.navReturnToLaunch) {
        issues.add(MissionIssue(
          MissionIssueSeverity.warning,
          'Waypoint altitude is ${item.altitude.toStringAsFixed(1)} m '
          '(at or below home/ground)',
          seq: item.seq,
        ));
      }

      // Terrain clearance for absolute-frame waypoints when DEM is available.
      final ground = terrainElevationBySeq?[item.seq];
      final isAbsolute =
          item.frame == MavFrame.global || item.frame == MavFrame.globalInt;
      if (ground != null && isAbsolute) {
        final agl = item.altitude - ground;
        if (agl < minTerrainClearance) {
          issues.add(MissionIssue(
            MissionIssueSeverity.warning,
            'Only ${agl.toStringAsFixed(1)} m above terrain '
            '(min ${minTerrainClearance.toStringAsFixed(0)} m)',
            seq: item.seq,
          ));
        }
      }
    }

    // Consecutive duplicate / large-jump checks across nav waypoints.
    for (var i = 1; i < navItems.length; i++) {
      final prev = navItems[i - 1];
      final cur = navItems[i];

      final samePos = (prev.latitude - cur.latitude).abs() < 1e-7 &&
          (prev.longitude - cur.longitude).abs() < 1e-7;
      if (samePos &&
          cur.command == MavCmd.navWaypoint &&
          prev.command == MavCmd.navWaypoint) {
        issues.add(MissionIssue(
          MissionIssueSeverity.warning,
          'Duplicate of the previous waypoint (same position)',
          seq: cur.seq,
        ));
      }

      if ((cur.altitude - prev.altitude).abs() > largeAltJump) {
        issues.add(MissionIssue(
          MissionIssueSeverity.info,
          'Large altitude change of '
          '${(cur.altitude - prev.altitude).abs().toStringAsFixed(0)} m '
          'from the previous waypoint',
          seq: cur.seq,
        ));
      }
    }

    // Stable ordering: errors first, then warnings, then info.
    issues.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return issues;
  }
}
