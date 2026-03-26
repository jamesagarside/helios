import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../core/map/cached_tile_provider.dart';
import '../../shared/models/mission_item.dart';
import '../../shared/providers/providers.dart';
import '../../shared/theme/helios_colors.dart';
import '../../shared/theme/helios_typography.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/models/fence_zone.dart';
import 'providers/fence_edit_notifier.dart';
import 'providers/mission_edit_notifier.dart';
import 'widgets/waypoint_editor.dart';
import 'widgets/waypoint_list.dart';

/// Plan View — mission planning screen with interactive map.
class PlanView extends ConsumerStatefulWidget {
  const PlanView({super.key});

  @override
  ConsumerState<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends ConsumerState<PlanView> {
  final MapController _mapController = MapController();
  bool _mapReady = false;
  int? _draggingIndex;

  @override
  Widget build(BuildContext context) {
    final editState = ref.watch(missionEditProvider);
    final missionState = ref.watch(missionStateProvider);
    final fenceState = ref.watch(fenceEditProvider);
    final width = MediaQuery.sizeOf(context).width;
    final showPanel = width >= 768;

    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Row(
        children: [
          Expanded(
            child: Stack(
              children: [
                _buildMap(editState),
                _buildInfoBar(editState),
                _buildMapControls(),
                if (missionState.isTransferring)
                  _buildTransferOverlay(missionState),
              ],
            ),
          ),
          if (showPanel) ...[
            const VerticalDivider(width: 1, color: HeliosColors.border),
            SizedBox(
              width: 300,
              child: _buildSidePanel(editState, missionState),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMap(MissionEditState editState) {
    final items = editState.items;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(-35.3632, 149.1652),
        initialZoom: 15,
        onMapReady: () => _mapReady = true,
        onTap: (tapPos, latLng) {
          final fence = ref.read(fenceEditProvider);
          if (fence.drawingMode) {
            ref.read(fenceEditProvider.notifier).addVertex(
              latLng.latitude, latLng.longitude,
            );
          } else {
            ref.read(missionEditProvider.notifier).addWaypoint(
              latLng.latitude, latLng.longitude,
            );
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.argus.helios_gcs',
          maxZoom: 19,
          tileProvider: CachedTileProvider(),
          tileBuilder: _darkTileBuilder,
        ),

        // Fence zones
        ..._buildFenceLayers(ref.watch(fenceEditProvider)),

        // Mission path polyline
        if (items.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: items
                    .where((i) => i.isNavCommand)
                    .map((i) => LatLng(i.latitude, i.longitude))
                    .toList(),
                color: HeliosColors.accent,
                strokeWidth: 2.5,
                pattern: const StrokePattern.solid(),
              ),
            ],
          ),

        // Direction arrows on path segments
        if (items.length >= 2)
          MarkerLayer(
            markers: _buildDirectionArrows(items),
          ),

        // Waypoint markers
        if (items.isNotEmpty)
          MarkerLayer(
            markers: items
                .where((i) => i.isNavCommand)
                .map((item) => Marker(
                      point: LatLng(item.latitude, item.longitude),
                      width: 32,
                      height: 32,
                      child: GestureDetector(
                        onTap: () =>
                            ref.read(missionEditProvider.notifier).select(item.seq),
                        onPanStart: (_) => _draggingIndex = item.seq,
                        onPanUpdate: (details) {
                          if (_draggingIndex == null || !_mapReady) return;
                          // Convert screen offset to lat/lon
                          final pos = details.globalPosition;
                          final point = _mapController.camera
                              .pointToLatLng(math.Point(pos.dx, pos.dy));
                          ref.read(missionEditProvider.notifier).moveWaypoint(
                            _draggingIndex!,
                            point.latitude,
                            point.longitude,
                          );
                        },
                        onPanEnd: (_) => _draggingIndex = null,
                        child: _WaypointMarker(
                          index: item.seq,
                          isSelected: item.seq == editState.selectedIndex,
                          command: item.command,
                        ),
                      ),
                    ))
                .toList(),
          ),
      ],
    );
  }

  List<Marker> _buildDirectionArrows(List<MissionItem> items) {
    final navItems = items.where((i) => i.isNavCommand).toList();
    final markers = <Marker>[];

    for (var i = 0; i < navItems.length - 1; i++) {
      final from = navItems[i];
      final to = navItems[i + 1];
      // Place arrow at midpoint
      final midLat = (from.latitude + to.latitude) / 2;
      final midLon = (from.longitude + to.longitude) / 2;
      // Calculate bearing
      final bearing = _bearing(
        from.latitude, from.longitude,
        to.latitude, to.longitude,
      );

      markers.add(Marker(
        point: LatLng(midLat, midLon),
        width: 16,
        height: 16,
        child: Transform.rotate(
          angle: bearing,
          child: const Icon(
            Icons.play_arrow,
            size: 16,
            color: HeliosColors.accent,
          ),
        ),
      ));
    }

    return markers;
  }

  double _bearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2 * math.pi / 180);
    final x = math.cos(lat1 * math.pi / 180) * math.sin(lat2 * math.pi / 180) -
        math.sin(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.cos(dLon);
    return math.atan2(y, x);
  }

  List<Widget> _buildFenceLayers(FenceEditState fenceState) {
    final layers = <Widget>[];

    // Existing zones
    for (final zone in fenceState.zones) {
      if (zone.shape == FenceShape.polygon && zone.vertices.length >= 3) {
        final color = zone.type == FenceZoneType.inclusion
            ? HeliosColors.success
            : HeliosColors.danger;
        layers.add(PolygonLayer(
          polygons: [
            Polygon(
              points: zone.vertices.map((v) => LatLng(v.lat, v.lon)).toList(),
              color: color.withValues(alpha: 0.15),
              borderColor: color.withValues(alpha: 0.6),
              borderStrokeWidth: 2,
            ),
          ],
        ));
      } else if (zone.shape == FenceShape.circle) {
        final color = zone.type == FenceZoneType.inclusion
            ? HeliosColors.success
            : HeliosColors.danger;
        // Approximate circle with 36 points
        final points = <LatLng>[];
        for (var deg = 0; deg < 360; deg += 10) {
          final rad = deg * math.pi / 180;
          final dLat = zone.radius / 111320 * math.cos(rad);
          final dLon = zone.radius / (111320 * math.cos(zone.centerLat * math.pi / 180)) * math.sin(rad);
          points.add(LatLng(zone.centerLat + dLat, zone.centerLon + dLon));
        }
        layers.add(PolygonLayer(
          polygons: [
            Polygon(
              points: points,
              color: color.withValues(alpha: 0.15),
              borderColor: color.withValues(alpha: 0.6),
              borderStrokeWidth: 2,
            ),
          ],
        ));
      }
    }

    // Drawing-in-progress polyline
    if (fenceState.drawingMode && fenceState.drawingVertices.isNotEmpty) {
      final drawColor = fenceState.drawingType == FenceZoneType.inclusion
          ? HeliosColors.success
          : HeliosColors.danger;
      final points = fenceState.drawingVertices.map((v) => LatLng(v.lat, v.lon)).toList();
      layers.add(PolylineLayer(
        polylines: [
          Polyline(
            points: points,
            color: drawColor,
            strokeWidth: 2,
            pattern: StrokePattern.dashed(segments: [6, 4]),
          ),
        ],
      ));
      // Vertex markers
      layers.add(MarkerLayer(
        markers: points.asMap().entries.map((e) => Marker(
          point: e.value,
          width: 12,
          height: 12,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: drawColor,
              border: Border.all(color: Colors.white, width: 1),
            ),
          ),
        )).toList(),
      ));
    }

    return layers;
  }

  Widget _buildInfoBar(MissionEditState editState) {
    final count = editState.waypointCount;
    // Calculate total distance
    final missionState = MissionState(items: editState.items);
    final distKm = missionState.totalDistanceMetres / 1000;
    // Rough time estimate at 15 m/s
    final estMin = missionState.totalDistanceMetres > 0
        ? missionState.totalDistanceMetres / 15 / 60
        : 0.0;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        height: 36,
        color: HeliosColors.surface.withValues(alpha: 0.9),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Text(
              'Waypoints: $count',
              style: const TextStyle(
                color: HeliosColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 24),
            Text(
              count >= 2
                  ? 'Distance: ${distKm.toStringAsFixed(1)} km'
                  : 'Distance: -- km',
              style: const TextStyle(
                color: HeliosColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 24),
            Text(
              estMin > 0
                  ? 'Est: ${estMin.toStringAsFixed(0)} min'
                  : 'Est: -- min',
              style: const TextStyle(
                color: HeliosColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            if (editState.isDirty)
              const Text(
                'Modified',
                style: TextStyle(
                  color: HeliosColors.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapControls() {
    final notifier = ref.read(missionEditProvider.notifier);
    final fenceNotifier = ref.read(fenceEditProvider.notifier);
    final fenceState = ref.watch(fenceEditProvider);

    return Positioned(
      right: 12,
      top: 12,
      child: Column(
        children: [
          _MapButton(
            icon: Icons.add,
            onPressed: () => _mapController.move(
              _mapController.camera.center,
              (_mapController.camera.zoom + 1).clamp(2, 19),
            ),
          ),
          const SizedBox(height: 4),
          _MapButton(
            icon: Icons.remove,
            onPressed: () => _mapController.move(
              _mapController.camera.center,
              (_mapController.camera.zoom - 1).clamp(2, 19),
            ),
          ),
          const SizedBox(height: 12),
          _MapButton(
            icon: Icons.undo,
            onPressed: notifier.canUndo ? () => notifier.undo() : null,
          ),
          const SizedBox(height: 4),
          _MapButton(
            icon: Icons.redo,
            onPressed: notifier.canRedo ? () => notifier.redo() : null,
          ),
          const SizedBox(height: 12),
          // Fence drawing tools
          _MapButton(
            icon: fenceState.drawingMode ? Icons.check : Icons.fence,
            onPressed: () {
              if (fenceState.drawingMode) {
                fenceNotifier.finishDrawing();
              } else {
                fenceNotifier.startDrawing(FenceZoneType.inclusion);
              }
            },
          ),
          if (fenceState.drawingMode) ...[
            const SizedBox(height: 4),
            _MapButton(
              icon: Icons.close,
              onPressed: () => fenceNotifier.cancelDrawing(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransferOverlay(MissionState missionState) {
    final label = missionState.transferState == MissionTransferState.uploading
        ? 'Uploading...'
        : 'Downloading...';

    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: HeliosColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: HeliosColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: HeliosTypography.body),
                const SizedBox(height: 12),
                SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(
                    value: missionState.transferProgress,
                    backgroundColor: HeliosColors.surfaceLight,
                    valueColor: const AlwaysStoppedAnimation(HeliosColors.accent),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(missionState.transferProgress * 100).toInt()}%',
                  style: HeliosTypography.caption,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidePanel(
    MissionEditState editState,
    MissionState missionState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: HeliosColors.surface,
          child: Row(
            children: [
              const Text('Mission', style: HeliosTypography.heading2),
              const Spacer(),
              if (editState.items.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: HeliosColors.textTertiary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () async {
                    final ok = await confirmMissionClear(context);
                    if (ok) ref.read(missionEditProvider.notifier).clear();
                  },
                  tooltip: 'Clear all',
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: HeliosColors.border),

        // Waypoint list
        Expanded(
          child: editState.items.isEmpty
              ? const Center(
                  child: Text(
                    'Tap map to add waypoints',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: HeliosColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                )
              : WaypointList(
                  items: editState.items,
                  selectedIndex: editState.selectedIndex,
                  currentWaypoint: ref.watch(currentWaypointProvider),
                  onSelect: (i) =>
                      ref.read(missionEditProvider.notifier).select(i),
                  onRemove: (i) =>
                      ref.read(missionEditProvider.notifier).removeWaypoint(i),
                  onReorder: (oldI, newI) => ref
                      .read(missionEditProvider.notifier)
                      .reorderWaypoint(oldI, newI),
                ),
        ),

        // Waypoint editor (when selected)
        if (editState.hasSelection) ...[
          const Divider(height: 1, color: HeliosColors.border),
          WaypointEditor(
            item: editState.selectedItem!,
            onChanged: (updated) => ref
                .read(missionEditProvider.notifier)
                .updateWaypoint(editState.selectedIndex, updated),
          ),
        ],

        // Error message
        if (missionState.errorMessage != null) ...[
          const Divider(height: 1, color: HeliosColors.border),
          Container(
            padding: const EdgeInsets.all(8),
            color: HeliosColors.dangerDim.withValues(alpha: 0.2),
            child: Text(
              missionState.errorMessage!,
              style: const TextStyle(
                color: HeliosColors.danger,
                fontSize: 12,
              ),
            ),
          ),
        ],

        // Upload / Download / Clear buttons
        const Divider(height: 1, color: HeliosColors.border),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: missionState.isTransferring
                      ? null
                      : () => _uploadMission(),
                  icon: const Icon(Icons.upload, size: 16),
                  label: const Text('Upload'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: missionState.isTransferring
                      ? null
                      : () => _downloadMission(),
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Download'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _uploadMission() async {
    final items = ref.read(missionEditProvider).items;
    if (items.isEmpty) return;

    final ok = await confirmMissionUpload(context, items.length);
    if (!ok) return;

    final controller = ref.read(connectionControllerProvider.notifier);
    final success = await controller.uploadMission(items);
    if (success) {
      ref.read(missionEditProvider.notifier).markClean();
    }
  }

  Future<void> _downloadMission() async {
    final controller = ref.read(connectionControllerProvider.notifier);
    final items = await controller.downloadMission();
    if (items.isNotEmpty) {
      ref.read(missionEditProvider.notifier).loadItems(items);
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final notifier = ref.read(missionEditProvider.notifier);

    // Ctrl+Z = undo, Ctrl+Shift+Z = redo
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (shift) {
        notifier.redo();
      } else {
        notifier.undo();
      }
    }

    // Delete selected waypoint
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      final state = ref.read(missionEditProvider);
      if (state.hasSelection) {
        notifier.removeWaypoint(state.selectedIndex);
      }
    }

    // Escape to deselect
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      notifier.select(-1);
    }
  }

  Widget _darkTileBuilder(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        -0.5, 0, 0, 0, 128,
        0, -0.5, 0, 0, 128,
        0, 0, -0.5, 0, 128,
        0, 0, 0, 1, 0,
      ]),
      child: tileWidget,
    );
  }
}

/// Numbered waypoint marker on the map.
class _WaypointMarker extends StatelessWidget {
  const _WaypointMarker({
    required this.index,
    required this.isSelected,
    required this.command,
  });

  final int index;
  final bool isSelected;
  final int command;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? HeliosColors.accent : HeliosColors.textPrimary;
    final bgColor = isSelected
        ? HeliosColors.accentDim
        : HeliosColors.surface;

    // Special icons for non-waypoint commands
    final icon = switch (command) {
      22 => Icons.flight_takeoff, // NAV_TAKEOFF
      21 => Icons.flight_land,    // NAV_LAND
      20 => Icons.home,           // NAV_RTL
      _ => null,
    };

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: color,
          width: isSelected ? 2.5 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: icon != null
            ? Icon(icon, size: 14, color: color)
            : Text(
                '$index',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

/// Small map control button.
class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: FloatingActionButton.small(
        heroTag: null,
        onPressed: onPressed,
        backgroundColor: HeliosColors.surface.withValues(alpha: 0.85),
        elevation: 2,
        child: Icon(
          icon,
          size: 16,
          color: onPressed != null
              ? HeliosColors.textPrimary
              : HeliosColors.textTertiary,
        ),
      ),
    );
  }
}
