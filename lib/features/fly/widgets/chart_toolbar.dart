import 'package:flutter/material.dart';
import '../../../shared/theme/helios_colors.dart';

/// Available chart widget types.
enum ChartType {
  altitude(label: 'ALT', icon: Icons.height),
  speed(label: 'SPD', icon: Icons.speed),
  battery(label: 'BAT', icon: Icons.battery_full),
  attitude(label: 'ATT', icon: Icons.rotate_right),
  climbRate(label: 'VS', icon: Icons.trending_up),
  vibration(label: 'VIB', icon: Icons.vibration);

  const ChartType({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

/// Floating toolbar for toggling live chart widgets.
class ChartToolbar extends StatelessWidget {
  const ChartToolbar({
    super.key,
    required this.activeCharts,
    required this.onToggle,
  });

  final Set<ChartType> activeCharts;
  final ValueChanged<ChartType> onToggle;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: hc.surfaceDim.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: hc.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart, size: 14, color: hc.textSecondary),
          const SizedBox(width: 4),
          ...ChartType.values.map((type) {
            final active = activeCharts.contains(type);
            return Padding(
              padding: const EdgeInsets.only(left: 2),
              child: _ChartToggle(
                type: type,
                active: active,
                onTap: () => onToggle(type),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ChartToggle extends StatelessWidget {
  const _ChartToggle({
    required this.type,
    required this.active,
    required this.onTap,
  });

  final ChartType type;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? hc.accent.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: active
                ? hc.accent.withValues(alpha: 0.4)
                : hc.border.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              type.icon,
              size: 11,
              color: active ? hc.accent : hc.textTertiary,
            ),
            const SizedBox(width: 3),
            Text(
              type.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? hc.accent : hc.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
