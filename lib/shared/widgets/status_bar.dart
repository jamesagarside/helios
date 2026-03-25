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
  });

  final String flightMode;
  final bool armed;
  final Duration flightTime;
  final double messageRate;
  final String gpsFixType;
  final int satellites;

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Color _gpsColor() {
    if (gpsFixType.contains('RTK')) return HeliosColors.success;
    if (gpsFixType.contains('3D') || gpsFixType.contains('DGPS')) {
      return HeliosColors.success;
    }
    if (gpsFixType.contains('2D')) return HeliosColors.warning;
    return HeliosColors.danger;
  }

  Color _linkColor() {
    if (messageRate > 5) return HeliosColors.success;
    if (messageRate > 0) return HeliosColors.warning;
    return HeliosColors.textTertiary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: HeliosColors.surfaceLight,
        border: Border(
          top: BorderSide(color: HeliosColors.accent, width: 1),
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
                color: armed ? HeliosColors.danger : HeliosColors.success,
                bold: true,
              ),
              const _Separator(),
              // Flight mode
              _StatusChip(
                icon: Icons.flight,
                label: flightMode,
                color: HeliosColors.accent,
              ),
              const _Separator(),
              // GPS
              _StatusChip(
                icon: Icons.satellite_alt,
                label: '$gpsFixType  $satellites sats',
                color: _gpsColor(),
              ),
              const _Separator(),
              // Flight time
              _StatusChip(
                icon: Icons.timer,
                label: _formatDuration(flightTime),
                color: HeliosColors.textPrimary,
                mono: true,
              ),
              const _Separator(),
              // Link health
              _StatusChip(
                icon: Icons.cell_tower,
                label: '${messageRate.toStringAsFixed(0)} msg/s',
                color: _linkColor(),
                mono: true,
              ),
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
  const _Separator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        height: 16,
        child: VerticalDivider(
          width: 1,
          color: HeliosColors.border,
        ),
      ),
    );
  }
}
