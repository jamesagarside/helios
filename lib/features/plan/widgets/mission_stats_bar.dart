import 'dart:math' as math;

import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/mission_item.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';
import '../providers/mission_edit_notifier.dart';

/// Compact statistics bar shown at the bottom of the Plan View.
///
/// Displays total distance, estimated flight time, waypoint count, max
/// altitude, estimated photo count, survey area, and battery estimate.
/// All values update live as waypoints are edited.
class MissionStatsBar extends ConsumerWidget {
  const MissionStatsBar({
    super.key,
    this.cruiseSpeedMs = 15.0,
    this.avgPowerDrawW = 200.0,
    this.batteryCapacityWh = 80.0,
  });

  /// Default cruise speed in m/s for flight time estimation.
  final double cruiseSpeedMs;

  /// Average power draw in watts for battery estimation.
  final double avgPowerDrawW;

  /// Battery capacity in watt-hours.
  final double batteryCapacityWh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final editState = ref.watch(missionEditProvider);
    final items = editState.items;

    if (items.isEmpty) return const SizedBox.shrink();

    final stats = _computeStats(items);

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: hc.surface,
        border: Border(top: BorderSide(color: hc.border, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _StatChip(
              icon: Icons.straighten,
              label: _formatDistance(stats.totalDistanceM),
              hc: hc,
            ),
            _StatChip(
              icon: Icons.timer_outlined,
              label: _formatDuration(stats.estimatedFlightTime),
              hc: hc,
            ),
            _StatChip(
              icon: Icons.flag_outlined,
              label: '${stats.waypointCount} WP',
              hc: hc,
            ),
            _StatChip(
              icon: Icons.height,
              label: '${stats.maxAltitude.toStringAsFixed(0)} m',
              hc: hc,
            ),
            if (stats.estimatedPhotos > 0)
              _StatChip(
                icon: Icons.camera_alt_outlined,
                label: '~${stats.estimatedPhotos} photos',
                hc: hc,
              ),
            if (stats.surveyAreaSqM > 0)
              _StatChip(
                icon: Icons.grid_on,
                label: _formatArea(stats.surveyAreaSqM),
                hc: hc,
              ),
            _StatChip(
              icon: Icons.battery_std_outlined,
              label: '~${stats.batteryEstimatePct.clamp(0, 100).toStringAsFixed(0)}%',
              hc: hc,
              color: stats.batteryEstimatePct < 30
                  ? hc.danger
                  : stats.batteryEstimatePct < 50
                      ? hc.warning
                      : null,
            ),
          ],
        ),
      ),
    );
  }

  _MissionStats _computeStats(List<MissionItem> items) {
    final navItems =
        items.where((i) => i.isNavCommand).toList();

    // Total distance
    var totalDistanceM = 0.0;
    for (var i = 1; i < navItems.length; i++) {
      totalDistanceM += _haversineMetres(
        navItems[i - 1].latitude,
        navItems[i - 1].longitude,
        navItems[i].latitude,
        navItems[i].longitude,
      );
    }

    // Estimated flight time
    final flightTimeSec =
        cruiseSpeedMs > 0 ? totalDistanceM / cruiseSpeedMs : 0.0;

    // Max altitude
    var maxAlt = 0.0;
    for (final item in navItems) {
      if (item.altitude > maxAlt) maxAlt = item.altitude;
    }

    // Estimated photos — count DO_SET_CAM_TRIGG_DIST commands and estimate
    var estimatedPhotos = 0;
    for (final item in items) {
      if (item.command == MavCmd.doSetCamTriggDist && item.param1 > 0) {
        // param1 = trigger distance in metres
        // Estimate photos for remaining nav distance after this command
        final idx = items.indexOf(item);
        var remainingDist = 0.0;
        final subsequentNav = items
            .skip(idx + 1)
            .where((i) => i.isNavCommand)
            .toList();
        for (var j = 1; j < subsequentNav.length; j++) {
          remainingDist += _haversineMetres(
            subsequentNav[j - 1].latitude,
            subsequentNav[j - 1].longitude,
            subsequentNav[j].latitude,
            subsequentNav[j].longitude,
          );
        }
        if (remainingDist > 0 && item.param1 > 0) {
          estimatedPhotos += (remainingDist / item.param1).ceil();
        }
      }
    }

    // Survey area — compute convex hull area of nav waypoints if >= 3
    var surveyAreaSqM = 0.0;
    if (navItems.length >= 3) {
      surveyAreaSqM = _computePolygonArea(navItems);
    }

    // Battery estimate
    final flightTimeHours = flightTimeSec / 3600.0;
    final energyUsedWh = avgPowerDrawW * flightTimeHours;
    final batteryPct = batteryCapacityWh > 0
        ? ((batteryCapacityWh - energyUsedWh) / batteryCapacityWh) * 100.0
        : 0.0;

    return _MissionStats(
      totalDistanceM: totalDistanceM,
      estimatedFlightTime: Duration(seconds: flightTimeSec.round()),
      waypointCount: navItems.length,
      maxAltitude: maxAlt,
      estimatedPhotos: estimatedPhotos,
      surveyAreaSqM: surveyAreaSqM,
      batteryEstimatePct: batteryPct,
    );
  }

  String _formatDistance(double metres) {
    if (metres >= 1000) {
      return '${(metres / 1000).toStringAsFixed(2)} km';
    }
    return '${metres.toStringAsFixed(0)} m';
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatArea(double sqMetres) {
    if (sqMetres >= 1e6) {
      return '${(sqMetres / 1e6).toStringAsFixed(2)} km\u00B2';
    }
    if (sqMetres >= 1e4) {
      return '${(sqMetres / 1e4).toStringAsFixed(1)} ha';
    }
    return '${sqMetres.toStringAsFixed(0)} m\u00B2';
  }

  /// Haversine distance between two coordinates in metres.
  static double _haversineMetres(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  /// Approximate polygon area using the Shoelace formula on projected coords.
  static double _computePolygonArea(List<MissionItem> navItems) {
    if (navItems.length < 3) return 0.0;

    // Project lat/lon to approximate metres relative to centroid
    final centerLat = navItems.map((i) => i.latitude).reduce((a, b) => a + b) /
        navItems.length;
    final centerLon =
        navItems.map((i) => i.longitude).reduce((a, b) => a + b) /
            navItems.length;

    final cosCenter = math.cos(centerLat * math.pi / 180);
    const metersPerDeg = 111319.9;

    final xs = navItems
        .map((i) => (i.longitude - centerLon) * metersPerDeg * cosCenter)
        .toList();
    final ys =
        navItems.map((i) => (i.latitude - centerLat) * metersPerDeg).toList();

    // Shoelace
    var area = 0.0;
    final n = xs.length;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      area += xs[i] * ys[j] - xs[j] * ys[i];
    }
    return area.abs() / 2;
  }
}

class _MissionStats {
  const _MissionStats({
    required this.totalDistanceM,
    required this.estimatedFlightTime,
    required this.waypointCount,
    required this.maxAltitude,
    required this.estimatedPhotos,
    required this.surveyAreaSqM,
    required this.batteryEstimatePct,
  });

  final double totalDistanceM;
  final Duration estimatedFlightTime;
  final int waypointCount;
  final double maxAltitude;
  final int estimatedPhotos;
  final double surveyAreaSqM;
  final double batteryEstimatePct;
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.hc,
    this.color,
  });

  final IconData icon;
  final String label;
  final HeliosColors hc;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? hc.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: HeliosTypography.small.copyWith(color: textColor),
          ),
        ],
      ),
    );
  }
}
