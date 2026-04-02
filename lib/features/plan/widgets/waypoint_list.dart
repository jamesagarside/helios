import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter/material.dart';
import '../../../shared/models/mission_item.dart';
import '../../../shared/theme/helios_colors.dart';

/// Reorderable list of mission waypoints with optional multi-select toolbar.
class WaypointList extends StatelessWidget {
  const WaypointList({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.currentWaypoint,
    required this.onSelect,
    required this.onRemove,
    required this.onReorder,
    this.selectedSeqs = const {},
    this.onToggleSelection,
    this.onBatchSetAltitude,
    this.onBatchDelete,
    this.onClearSelection,
  });

  final List<MissionItem> items;
  final int selectedIndex;
  final int currentWaypoint;
  final void Function(int index) onSelect;
  final void Function(int index) onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Currently multi-selected sequence numbers.
  final Set<int> selectedSeqs;

  /// Called when the user toggles a row's checkbox.
  final void Function(int seq)? onToggleSelection;

  /// Called when the "Set Altitude" toolbar action is confirmed.
  final void Function(double alt)? onBatchSetAltitude;

  /// Called when the "Delete selected" toolbar action is triggered.
  final VoidCallback? onBatchDelete;

  /// Called when the "×" clear-selection button is tapped.
  final VoidCallback? onClearSelection;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final hasMulti = selectedSeqs.isNotEmpty;

    return Column(
      children: [
        // Multi-select toolbar — visible when any items are selected
        if (hasMulti)
          _MultiSelectToolbar(
            count: selectedSeqs.length,
            hc: hc,
            onSetAltitude: onBatchSetAltitude,
            onDelete: onBatchDelete,
            onClear: onClearSelection,
          ),

        Expanded(
          child: ReorderableListView.builder(
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
              final isMultiSelected = selectedSeqs.contains(item.seq);

              return _WaypointRow(
                key: ValueKey(item.seq),
                index: index,
                item: item,
                isSelected: isSelected,
                isCurrent: isCurrent,
                isMultiSelected: isMultiSelected,
                showCheckbox: hasMulti,
                onTap: () => onSelect(index),
                onLongPress: onToggleSelection != null
                    ? () => onToggleSelection!(item.seq)
                    : null,
                onToggleCheck: onToggleSelection != null
                    ? () => onToggleSelection!(item.seq)
                    : null,
                onRemove: () => onRemove(index),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Multi-select toolbar ─────────────────────────────────────────────────────

class _MultiSelectToolbar extends StatelessWidget {
  const _MultiSelectToolbar({
    required this.count,
    required this.hc,
    this.onSetAltitude,
    this.onDelete,
    this.onClear,
  });

  final int count;
  final HeliosColors hc;
  final void Function(double alt)? onSetAltitude;
  final VoidCallback? onDelete;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: hc.accentDim.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(
            '$count selected',
            style: TextStyle(
              color: hc.accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),

          // Set Altitude button
          if (onSetAltitude != null)
            TextButton(
              onPressed: () => _showAltDialog(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
              ),
              child: Text(
                'Set Alt',
                style: TextStyle(color: hc.accent, fontSize: 11),
              ),
            ),

          // Delete button
          if (onDelete != null)
            TextButton(
              onPressed: onDelete,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
              ),
              child: Text(
                'Delete',
                style: TextStyle(color: hc.danger, fontSize: 11),
              ),
            ),

          const Spacer(),

          // Clear selection
          if (onClear != null)
            IconButton(
              icon: Icon(Icons.close, size: 14, color: hc.textSecondary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: onClear,
              tooltip: 'Clear selection',
            ),
        ],
      ),
    );
  }

  Future<void> _showAltDialog(BuildContext context) async {
    final hc = context.hc;
    final controller = TextEditingController();
    final alt = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: hc.surface,
        title: Text(
          'Set Altitude',
          style: TextStyle(color: hc.textPrimary, fontSize: 14),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: hc.textPrimary),
          decoration: InputDecoration(
            labelText: 'Altitude (m)',
            labelStyle: TextStyle(color: hc.textSecondary),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: hc.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: hc.accent),
            ),
          ),
          onSubmitted: (v) =>
              Navigator.of(ctx).pop(double.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: hc.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(ctx).pop(double.tryParse(controller.text)),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (alt != null && onSetAltitude != null) {
      onSetAltitude!(alt.clamp(0, 5000));
    }
  }
}

// ─── Waypoint row ──────────────────────────────────────────────────────────────

class _WaypointRow extends StatelessWidget {
  const _WaypointRow({
    super.key,
    required this.index,
    required this.item,
    required this.isSelected,
    required this.isCurrent,
    required this.isMultiSelected,
    required this.showCheckbox,
    required this.onTap,
    required this.onRemove,
    this.onLongPress,
    this.onToggleCheck,
  });

  final int index;
  final MissionItem item;
  final bool isSelected;
  final bool isCurrent;
  final bool isMultiSelected;
  final bool showCheckbox;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleCheck;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final bgColor = isMultiSelected
        ? hc.accentDim.withValues(alpha: 0.15)
        : isSelected
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
      MavCmd.doSetCamTriggDist => Icons.camera_alt_outlined,
      MavCmd.doMountControl => Icons.videocam_outlined,
      MavCmd.doJump => Icons.redo,
      MavCmd.doGripper => Icons.pan_tool_outlined,
      MavCmd.doPauseContinue => Icons.pause_circle_outline,
      _ => Icons.place,
    };

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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
            // Checkbox (shown during multi-select) or drag handle
            if (showCheckbox)
              GestureDetector(
                onTap: onToggleCheck,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    isMultiSelected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 16,
                    color: isMultiSelected ? hc.accent : hc.textTertiary,
                  ),
                ),
              )
            else
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
                  color: isSelected ? hc.accent : hc.textSecondary,
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
