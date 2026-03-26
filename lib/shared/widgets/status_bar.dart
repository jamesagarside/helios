import 'package:flutter/material.dart';
import '../theme/helios_colors.dart';

/// Bottom status bar showing vehicle state summary.
class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    this.flightMode = 'UNKNOWN',
    this.armed = false,
    this.flightTime = Duration.zero,
    this.messageRate = 0.0,
    this.gpsFixType = 'No Fix',
    this.satellites = 0,
    this.currentWaypoint = -1,
    this.totalWaypoints = 0,
    this.alertCount = 0,
  });

  final String flightMode;
  final bool armed;
  final Duration flightTime;
  final double messageRate;
  final String gpsFixType;
  final int satellites;
  final int currentWaypoint;
  final int totalWaypoints;
  final int alertCount;

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Color _gpsColor(HeliosColors hc) {
    if (gpsFixType.contains('RTK')) return hc.success;
    if (gpsFixType.contains('3D') || gpsFixType.contains('DGPS')) {
      return hc.success;
    }
    if (gpsFixType.contains('2D')) return hc.warning;
    return hc.danger;
  }

  Color _linkColor(HeliosColors hc) {
    if (messageRate > 5) return hc.success;
    if (messageRate > 0) return hc.warning;
    return hc.textTertiary;
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: hc.surfaceLight,
        border: Border(
          top: BorderSide(color: hc.accent, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Armed state — most critical
              _StatusChip(
                icon: armed ? Icons.warning_amber : Icons.shield,
                label: armed ? 'ARMED' : 'DISARMED',
                color: armed ? hc.danger : hc.success,
                bold: true,
              ),
              _Separator(color: hc.border),
              // Flight mode
              _StatusChip(
                icon: Icons.flight,
                label: flightMode,
                color: hc.accent,
              ),
              _Separator(color: hc.border),
              // GPS
              _StatusChip(
                icon: Icons.satellite_alt,
                label: '$gpsFixType  $satellites sats',
                color: _gpsColor(hc),
              ),
              // Mission waypoint
              if (totalWaypoints > 0) ...[
                _Separator(color: hc.border),
                _StatusChip(
                  icon: Icons.route,
                  label: currentWaypoint >= 0
                      ? 'WP ${currentWaypoint + 1}/$totalWaypoints'
                      : '$totalWaypoints WPs',
                  color: currentWaypoint >= 0
                      ? hc.warning
                      : hc.textSecondary,
                ),
              ],
              _Separator(color: hc.border),
              // Flight time
              _StatusChip(
                icon: Icons.timer,
                label: _formatDuration(flightTime),
                color: hc.textPrimary,
                mono: true,
              ),
              _Separator(color: hc.border),
              // Link health
              _StatusChip(
                icon: Icons.cell_tower,
                label: '${messageRate.toStringAsFixed(0)} msg/s',
                color: _linkColor(hc),
                mono: true,
              ),
              // Maintenance alerts badge
              if (alertCount > 0) ...[
                _Separator(color: hc.border),
                _StatusChip(
                  icon: Icons.warning_amber,
                  label: '$alertCount alert${alertCount == 1 ? '' : 's'}',
                  color: hc.warning,
                  bold: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
    this.bold = false,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool bold;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            fontFamily: mono ? 'monospace' : null,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        height: 16,
        child: VerticalDivider(
          width: 1,
          color: color,
        ),
      ),
    );
  }
}
