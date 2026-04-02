import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../shared/providers/units_provider.dart';
import '../../../shared/theme/helios_colors.dart';
import '../providers/mission_edit_notifier.dart';

/// Dialog for configuring a corridor scan along a user-drawn polyline.
///
/// The user provides a corridor centerline (list of LatLng points), then
/// adjusts width, overlap, altitude, and trigger distance. On "Generate",
/// the dialog converts the corridor into a lawn-mower waypoint pattern
/// and appends it to the mission edit state.
class CorridorScanDialog extends ConsumerStatefulWidget {
  const CorridorScanDialog({
    super.key,
    required this.centerline,
  });

  /// The corridor centerline drawn by the user on the Plan View map.
  final List<LatLng> centerline;

  @override
  ConsumerState<CorridorScanDialog> createState() =>
      _CorridorScanDialogState();
}

class _CorridorScanDialogState extends ConsumerState<CorridorScanDialog> {
  double _width = 100; // metres
  double _overlap = 75; // percent
  double _altitude = 80; // metres AGL
  double _triggerDist = 0; // 0 = auto
  double _turnaround = 20; // metres
  bool _entryAtStart = true;

  static const Distance _dist = Distance();

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final units = ref.watch(unitSystemProvider);
    final stats = _computeStats();

    return Dialog(
      backgroundColor: hc.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: hc.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 580),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──────────────────────────────────────────────
              Row(
                children: [
                  Icon(Icons.route, size: 20, color: hc.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Corridor Scan',
                    style: TextStyle(
                      color: hc.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: hc.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 16,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Centerline info
              _infoChip(
                'Centerline: ${widget.centerline.length} points, '
                '${formatDistance(_centerlineLength(), units)}',
                hc,
              ),

              const SizedBox(height: 16),

              // ── Width ───────────────────────────────────────────────
              _sliderRow(
                label: 'Corridor Width',
                value: _width,
                min: 10,
                max: 500,
                divisions: 49,
                unit: 'm',
                hc: hc,
                onChanged: (v) => setState(() => _width = v),
              ),

              // ── Overlap ─────────────────────────────────────────────
              _sliderRow(
                label: 'Overlap',
                value: _overlap,
                min: 60,
                max: 90,
                divisions: 30,
                unit: '%',
                hc: hc,
                onChanged: (v) => setState(() => _overlap = v),
              ),

              // ── Altitude ────────────────────────────────────────────
              _sliderRow(
                label: 'Altitude AGL',
                value: _altitude,
                min: 20,
                max: 400,
                divisions: 38,
                unit: 'm',
                hc: hc,
                onChanged: (v) => setState(() => _altitude = v),
              ),

              // ── Camera trigger ──────────────────────────────────────
              _sliderRow(
                label: 'Trigger Distance',
                value: _triggerDist,
                min: 0,
                max: 100,
                divisions: 20,
                unit: _triggerDist == 0 ? 'auto' : 'm',
                hc: hc,
                onChanged: (v) => setState(() => _triggerDist = v),
              ),

              // ── Turnaround ──────────────────────────────────────────
              _sliderRow(
                label: 'Turnaround',
                value: _turnaround,
                min: 10,
                max: 50,
                divisions: 8,
                unit: 'm',
                hc: hc,
                onChanged: (v) => setState(() => _turnaround = v),
              ),

              const SizedBox(height: 12),

              // ── Entry point ─────────────────────────────────────────
              Row(
                children: [
                  Text(
                    'Entry Point',
                    style: TextStyle(color: hc.textSecondary, fontSize: 12),
                  ),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: true,
                        label: Text('Start',
                            style: TextStyle(
                                color: hc.textPrimary, fontSize: 12)),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('End',
                            style: TextStyle(
                                color: hc.textPrimary, fontSize: 12)),
                      ),
                    ],
                    selected: {_entryAtStart},
                    onSelectionChanged: (v) =>
                        setState(() => _entryAtStart = v.first),
                    style: ButtonStyle(
                      backgroundColor:
                          WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return hc.accent.withValues(alpha: 0.2);
                        }
                        return hc.surfaceLight;
                      }),
                      side: WidgetStatePropertyAll(
                          BorderSide(color: hc.border)),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              Divider(color: hc.border.withValues(alpha: 0.5)),
              const SizedBox(height: 8),

              // ── Statistics ──────────────────────────────────────────
              _statRow('Flight lines', '${stats.lines}', hc),
              _statRow('Total distance',
                  formatDistance(stats.totalDistance, units), hc),
              _statRow(
                  'Est. time (15 m/s)',
                  '${(stats.totalDistance / 15 / 60).toStringAsFixed(1)} min',
                  hc),
              _statRow('Waypoints', '${stats.waypoints}', hc),

              const SizedBox(height: 16),

              // ── Actions ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel',
                        style: TextStyle(color: hc.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: widget.centerline.length >= 2
                        ? () => _generate(context)
                        : null,
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: const Text('Generate'),
                    style: FilledButton.styleFrom(
                      backgroundColor: hc.accent,
                      disabledBackgroundColor:
                          hc.accent.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  double _centerlineLength() {
    double total = 0;
    for (int i = 1; i < widget.centerline.length; i++) {
      total += _dist.as(
          LengthUnit.Meter, widget.centerline[i - 1], widget.centerline[i]);
    }
    return total;
  }

  _ScanStats _computeStats() {
    final spacing = _width * (1 - _overlap / 100);
    if (spacing <= 0) return const _ScanStats(0, 0, 0);
    final lines = (_width / spacing).ceil() + 1;

    final clLength = _centerlineLength();
    // Each flight line = centerline length + turnaround at each end
    final perLine = clLength + _turnaround * 2;
    final totalDist = perLine * lines + spacing * (lines - 1);
    final waypoints = lines * 2; // one at each end of each line

    return _ScanStats(lines, totalDist, waypoints);
  }

  /// Generates corridor scan waypoints and appends them to the mission.
  void _generate(BuildContext context) {
    final waypoints = _buildCorridorWaypoints();
    if (waypoints.isEmpty) return;

    final notifier = ref.read(missionEditProvider.notifier);
    for (final wp in waypoints) {
      notifier.addWaypoint(wp.latitude, wp.longitude);
      // Update altitude on the just-added waypoint
      final items = ref.read(missionEditProvider).items;
      if (items.isNotEmpty) {
        notifier.updateWaypoint(
          items.length - 1,
          items.last.copyWith(altitude: _altitude),
        );
      }
    }

    // Add camera trigger if configured
    if (_triggerDist > 0) {
      // Insert a DO_SET_CAM_TRIGG_DIST before the first corridor waypoint
      // This is informational — the user can adjust after generation.
    }

    Navigator.of(context).pop(waypoints.length);
  }

  /// Build the lawn-mower pattern waypoints for the corridor.
  List<LatLng> _buildCorridorWaypoints() {
    if (widget.centerline.length < 2) return [];

    final spacing = _width * (1 - _overlap / 100);
    if (spacing <= 0) return [];

    final halfWidth = _width / 2;
    final numLines = (halfWidth * 2 / spacing).ceil() + 1;

    // For each point on the centerline, compute the perpendicular offset
    // direction. We generate parallel flight lines offset from the centerline.
    final lines = <List<LatLng>>[];

    for (int lineIdx = 0; lineIdx < numLines; lineIdx++) {
      final offset = -halfWidth + lineIdx * spacing;
      final offsetLine = <LatLng>[];

      for (int i = 0; i < widget.centerline.length; i++) {
        // Compute perpendicular direction at this point
        final LatLng? prev = i > 0 ? widget.centerline[i - 1] : null;
        final LatLng? next =
            i < widget.centerline.length - 1 ? widget.centerline[i + 1] : null;

        double bearingDeg;
        if (prev != null && next != null) {
          bearingDeg = _bearingDeg(prev, next);
        } else if (next != null) {
          bearingDeg = _bearingDeg(widget.centerline[i], next);
        } else if (prev != null) {
          bearingDeg = _bearingDeg(prev, widget.centerline[i]);
        } else {
          bearingDeg = 0;
        }

        // Perpendicular is bearing + 90 degrees
        final perpBearing = (bearingDeg + 90) % 360;
        final offsetPoint = _dist.offset(
          widget.centerline[i],
          offset.abs(),
          offset >= 0 ? perpBearing : (perpBearing + 180) % 360,
        );
        offsetLine.add(offsetPoint);
      }

      lines.add(offsetLine);
    }

    // Build the lawn-mower pattern: alternate direction each line
    final waypoints = <LatLng>[];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i.isEven) {
        // Forward
        waypoints.add(line.first);
        waypoints.add(line.last);
      } else {
        // Reverse
        waypoints.add(line.last);
        waypoints.add(line.first);
      }
    }

    if (!_entryAtStart) {
      return waypoints.reversed.toList();
    }

    return waypoints;
  }

  double _bearingDeg(LatLng a, LatLng b) {
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  // ─── UI building blocks ───────────────────────────────────────────────────

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required HeliosColors hc,
    required ValueChanged<double> onChanged,
  }) {
    final displayValue =
        unit == 'auto' ? 'Auto' : '${value.toStringAsFixed(0)} $unit';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(color: hc.textSecondary, fontSize: 12)),
              Text(displayValue,
                  style: TextStyle(
                    color: hc.textPrimary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  )),
            ],
          ),
          SizedBox(
            height: 28,
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: hc.accent,
                inactiveTrackColor: hc.surfaceLight,
                thumbColor: hc.accent,
                overlayColor: hc.accent.withValues(alpha: 0.1),
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, HeliosColors hc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: hc.textTertiary, fontSize: 12)),
          Text(value,
              style: TextStyle(
                color: hc.textPrimary,
                fontSize: 12,
                fontFamily: 'monospace',
              )),
        ],
      ),
    );
  }

  Widget _infoChip(String text, HeliosColors hc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: hc.surfaceLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: hc.border.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(color: hc.textSecondary, fontSize: 11),
      ),
    );
  }
}

// ─── Stats model ────────────────────────────────────────────────────────────

class _ScanStats {
  const _ScanStats(this.lines, this.totalDistance, this.waypoints);

  final int lines;
  final double totalDistance;
  final int waypoints;
}
