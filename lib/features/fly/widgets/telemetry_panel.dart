import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/telemetry/telemetry_field_registry.dart';
import '../../../shared/models/telemetry_tile_config.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/layout_provider.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Configurable telemetry sidebar panel.
///
/// Replaces the old hardcoded _TelemetryStrip with user-selectable tiles.
/// Long-press a tile to remove it. Tap the "+" at the bottom to add.
class TelemetryPanel extends ConsumerWidget {
  const TelemetryPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(vehicleStateProvider);
    final layout = ref.watch(activeLayoutProvider);
    final hc = context.hc;
    final tiles = layout.effectiveTiles;

    return Container(
      color: hc.surface,
      child: Column(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              buildDefaultDragHandles: false,
              itemCount: tiles.length,
              onReorder: (oldIndex, newIndex) {
                final updated = [...tiles];
                if (newIndex > oldIndex) newIndex--;
                final item = updated.removeAt(oldIndex);
                updated.insert(newIndex, item);
                ref.read(layoutProvider.notifier).setTelemetryTiles(updated);
              },
              itemBuilder: (_, i) {
                final tile = tiles[i];
                return _TelemetryTile(
                  key: ValueKey(tile.fieldId),
                  tile: tile,
                  vehicle: vehicle,
                  index: i,
                  hc: hc,
                  onRemove: () {
                    final updated = [...tiles]..removeAt(i);
                    ref
                        .read(layoutProvider.notifier)
                        .setTelemetryTiles(updated);
                  },
                );
              },
            ),
          ),
          // Add tile button
          Divider(height: 1, color: hc.border),
          InkWell(
            onTap: () => _showFieldPicker(context, ref, tiles),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 14, color: hc.accent),
                  const SizedBox(width: 4),
                  Text(
                    'Add field',
                    style: TextStyle(
                      fontSize: 12,
                      color: hc.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFieldPicker(
    BuildContext context,
    WidgetRef ref,
    List<TelemetryTileConfig> current,
  ) {
    final currentIds = current.map((t) => t.fieldId).toSet();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _FieldPickerSheet(
        currentIds: currentIds,
        onSelect: (fieldId) {
          final updated = [...current, TelemetryTileConfig(fieldId: fieldId)];
          ref.read(layoutProvider.notifier).setTelemetryTiles(updated);
        },
      ),
    );
  }
}

// ─── Individual Tile ─────────────────────────────────────────────────────────

class _TelemetryTile extends StatelessWidget {
  const _TelemetryTile({
    super.key,
    required this.tile,
    required this.vehicle,
    required this.index,
    required this.hc,
    required this.onRemove,
  });

  final TelemetryTileConfig tile;
  final VehicleState vehicle;
  final int index;
  final HeliosColors hc;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final def = TelemetryFieldRegistry.byId(tile.fieldId);
    if (def == null) return const SizedBox.shrink();

    final raw = def.getter(vehicle);
    final formatted = def.format(raw);
    final label = def.label;
    final unit = def.unit;

    // Determine colour based on warn thresholds
    Color valueColor = hc.textPrimary;
    if (tile.warnLow != null && raw < tile.warnLow!) {
      valueColor = hc.danger;
    } else if (tile.warnHigh != null && raw > tile.warnHigh!) {
      valueColor = hc.danger;
    }

    // Built-in semantic colours for known fields
    if (valueColor == hc.textPrimary) {
      valueColor = _semanticColor(tile.fieldId, raw, hc);
    }

    return GestureDetector(
      onLongPress: onRemove,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: hc.surfaceDim,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: valueColor == hc.danger || valueColor == hc.warning
                ? valueColor.withValues(alpha: 0.4)
                : hc.border.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            // Drag handle
            ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle,
                size: 14,
                color: hc.textTertiary,
              ),
            ),
            const SizedBox(width: 6),
            // Label
            SizedBox(
              width: 46,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: hc.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const Spacer(),
            // Value
            Text(
              formatted,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: valueColor,
                fontFamily: 'monospace',
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 10,
                  color: hc.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _semanticColor(String fieldId, double value, HeliosColors hc) {
    return switch (fieldId) {
      'bat_v' => value < 10.5
          ? hc.danger
          : value < 11.5
              ? hc.warning
              : hc.textPrimary,
      'bat_pct' => value < 15
          ? hc.danger
          : value < 30
              ? hc.warning
              : hc.textPrimary,
      'gps_sats' => value < 5
          ? hc.danger
          : value < 8
              ? hc.warning
              : hc.success,
      'gps_hdop' => value > 5
          ? hc.danger
          : value > 2
              ? hc.warning
              : hc.textPrimary,
      'rssi' => value < 50
          ? hc.danger
          : value < 100
              ? hc.warning
              : hc.textPrimary,
      _ => hc.textPrimary,
    };
  }
}

// ─── Field Picker Sheet ───────────────────────────────────────────────────────

class _FieldPickerSheet extends StatefulWidget {
  const _FieldPickerSheet({
    required this.currentIds,
    required this.onSelect,
  });

  final Set<String> currentIds;
  final ValueChanged<String> onSelect;

  @override
  State<_FieldPickerSheet> createState() => _FieldPickerSheetState();
}

class _FieldPickerSheetState extends State<_FieldPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    // Filter by query
    final filtered = _query.isEmpty
        ? TelemetryFieldRegistry.all
        : TelemetryFieldRegistry.all
            .where((f) =>
                f.label.toLowerCase().contains(_query.toLowerCase()) ||
                f.id.toLowerCase().contains(_query.toLowerCase()) ||
                f.category.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    final filteredByCategory = <String, List<TelemetryFieldDef>>{};
    for (final f in filtered) {
      if (!widget.currentIds.contains(f.id)) {
        (filteredByCategory[f.category] ??= []).add(f);
      }
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text('Add Telemetry Field', style: HeliosTypography.heading2),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Icon(Icons.close, size: 18, color: hc.textTertiary),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search fields...',
                hintStyle: TextStyle(color: hc.textTertiary),
                prefixIcon:
                    Icon(Icons.search, size: 16, color: hc.textTertiary),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
              ),
            ),
          ),
          Expanded(
            child: filteredByCategory.isEmpty
                ? Center(
                    child: Text('No fields available',
                        style: TextStyle(color: hc.textTertiary)))
                : ListView(
                    controller: controller,
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      for (final entry in filteredByCategory.entries) ...[
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 10, 16, 4),
                          child: Text(
                            entry.key.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: hc.accent.withValues(alpha: 0.7),
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        for (final field in entry.value)
                          ListTile(
                            dense: true,
                            title: Text(
                              field.label,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              field.id,
                              style: TextStyle(
                                fontSize: 10,
                                color: hc.textTertiary,
                              ),
                            ),
                            trailing: Text(
                              field.unit.isNotEmpty ? field.unit : '—',
                              style: TextStyle(
                                  fontSize: 11, color: hc.textSecondary),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              widget.onSelect(field.id);
                            },
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
