import 'package:flutter/material.dart';
import '../theme/helios_colors.dart';
import '../theme/helios_typography.dart';

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

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: const BoxDecoration(
        color: HeliosColors.surface,
        border: Border(
          top: BorderSide(color: HeliosColors.border),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _StatusItem(
                label: 'Mode',
                value: flightMode,
                valueColor: HeliosColors.accent,
              ),
              const _Divider(),
              _StatusItem(
                label: armed ? 'ARMED' : 'DISARMED',
                value: '',
                valueColor: armed ? HeliosColors.danger : HeliosColors.success,
              ),
              const _Divider(),
              _StatusItem(
                label: 'GPS',
                value: '$gpsFixType ($satellites)',
              ),
              const _Divider(),
              _StatusItem(
                label: 'Time',
                value: _formatDuration(flightTime),
              ),
              const SizedBox(width: 16),
              _StatusItem(
                label: 'Msg/s',
                value: messageRate.toStringAsFixed(0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: HeliosTypography.caption.copyWith(
            color: valueColor ?? HeliosColors.textSecondary,
          ),
        ),
        if (value.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            value,
            style: HeliosTypography.caption.copyWith(
              fontFamily: 'monospace',
              color: HeliosColors.textPrimary,
            ),
          ),
        ],
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 14,
        child: VerticalDivider(
          width: 1,
          color: HeliosColors.border,
        ),
      ),
    );
  }
}
