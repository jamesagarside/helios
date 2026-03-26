import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter/material.dart';
import '../../../shared/models/mission_item.dart';
import '../../../shared/theme/helios_colors.dart';

/// Reorderable list of mission waypoints.
class WaypointList extends StatelessWidget {
  const WaypointList({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.currentWaypoint,
    required this.onSelect,
    required this.onRemove,
    required this.onReorder,
  });

  final List<MissionItem> items;
  final int selectedIndex;
  final int currentWaypoint;
  final void Function(int index) onSelect;
  final void Function(int index) onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return ReorderableListView.builder(
      itemCount: items.length,
      buildDefaultDragHandles: false,
      proxyDecorator: (child, index, animation) {
        return Material(
          elevation: 4,
          color: hc.surfaceLight,
          borderRadius: BorderRadius.circular(4),
          child: child,
        );
      },
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex--;
        onReorder(oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = index == selectedIndex;
        final isCurrent = index == currentWaypoint;

        return _WaypointRow(
          key: ValueKey(item.seq),
          index: index,
          item: item,
          isSelected: isSelected,
          isCurrent: isCurrent,
          onTap: () => onSelect(index),
          onRemove: () => onRemove(index),
        );
      },
    );
  }
}

class _WaypointRow extends StatelessWidget {
  const _WaypointRow({
    super.key,
    required this.index,
    required this.item,
    required this.isSelected,
    required this.isCurrent,
    required this.onTap,
    required this.onRemove,
  });

  final int index;
  final MissionItem item;
  final bool isSelected;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final bgColor = isSelected
        ? hc.accentDim.withValues(alpha: 0.2)
        : Colors.transparent;

    final icon = switch (item.command) {
      MavCmd.navTakeoff => Icons.flight_takeoff,
      MavCmd.navLand => Icons.flight_land,
      MavCmd.navReturnToLaunch => Icons.home,
      MavCmd.navLoiterUnlim ||
      MavCmd.navLoiterTurns ||
      MavCmd.navLoiterTime => Icons.loop,
      MavCmd.doChangeSpeed => Icons.speed,
      _ => Icons.place,
    };

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            left: BorderSide(
              color: isCurrent ? hc.success : Colors.transparent,
              width: 3,
            ),
            bottom: BorderSide(
              color: hc.border,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // Drag handle
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.drag_indicator,
                  size: 16,
                  color: hc.textTertiary,
                ),
              ),
            ),
            // Sequence number
            SizedBox(
              width: 22,
              child: Text(
                '$index',
                style: TextStyle(
                  color: isSelected
                      ? hc.accent
                      : hc.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            // Command icon
            Icon(icon, size: 14, color: hc.textSecondary),
            const SizedBox(width: 6),
            // Command label + coords
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.commandLabel,
                    style: TextStyle(
                      color: isSelected
                          ? hc.textPrimary
                          : hc.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (item.isNavCommand)
                    Text(
                      '${item.latitude.toStringAsFixed(5)}, ${item.longitude.toStringAsFixed(5)}',
                      style: TextStyle(
                        color: hc.textTertiary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                ],
              ),
            ),
            // Altitude
            Text(
              '${item.altitude.toStringAsFixed(0)}m',
              style: TextStyle(
                color: hc.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 4),
            // Delete button
            GestureDetector(
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: hc.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
