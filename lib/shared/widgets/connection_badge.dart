import 'package:flutter/material.dart';
import '../models/vehicle_state.dart';
import '../theme/helios_colors.dart';

/// Connection state badge displayed in the app bar area.
class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({
    super.key,
    required this.linkState,
    this.vehicleType,
    this.messageRate = 0.0,
  });

  final LinkState linkState;
  final VehicleType? vehicleType;
  final double messageRate;

  Color get _color => switch (linkState) {
        LinkState.connected => HeliosColors.success,
        LinkState.degraded => HeliosColors.warning,
        LinkState.lost => HeliosColors.danger,
        LinkState.disconnected => HeliosColors.textTertiary,
      };

  String get _label => switch (linkState) {
        LinkState.connected => 'Connected',
        LinkState.degraded => 'Degraded',
        LinkState.lost => 'Link Lost',
        LinkState.disconnected => 'Disconnected',
      };

  IconData get _icon => switch (linkState) {
        LinkState.connected => Icons.link,
        LinkState.degraded => Icons.link,
        LinkState.lost => Icons.link_off,
        LinkState.disconnected => Icons.link_off,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 14, color: _color),
          const SizedBox(width: 4),
          Text(
            _label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}
