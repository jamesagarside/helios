import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/mission/kml_importer.dart';
import '../../core/mission/gpx_importer.dart';
import '../../core/map/cached_tile_provider.dart';
import '../../core/map/tile_download_service.dart';
import '../../shared/models/airspace_zone.dart';
import '../../shared/models/custom_nfz.dart';
import '../../shared/providers/airspace_provider.dart';
import '../../shared/providers/airspace_settings_provider.dart';
import '../../shared/providers/custom_nfz_provider.dart';
import '../../shared/providers/dem_provider.dart';
import '../../shared/providers/map_tile_provider.dart';
import '../../shared/models/mission_item.dart';
import '../../shared/models/rally_point.dart';
import '../../shared/models/point_of_interest.dart';
import '../../shared/providers/poi_provider.dart';
import '../../shared/providers/providers.dart';
import '../../shared/theme/helios_colors.dart';
import '../../shared/theme/helios_typography.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/models/fence_zone.dart';
import 'providers/fence_edit_notifier.dart';
import 'providers/mission_edit_notifier.dart';
import 'providers/rally_point_notifier.dart';
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
  bool _addRallyMode = false;
  bool _addPoiMode = false;
  bool _surveyMode = false;
  LatLng? _surveyCorner1;
  LatLng? _surveyCorner2;
  bool _polygonSurveyMode = false;
  final List<LatLng> _polygonSurveyPoints = [];
  bool _drawNfzMode = false;
  final List<LatLng> _nfzPoints = [];

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final editState = ref.watch(missionEditProvider);
    final missionState = ref.watch(missionStateProvider);
    final rallyPoints = ref.watch(rallyPointProvider);
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
                _buildMap(editState, rallyPoints, hc),
                _buildInfoBar(editState, hc),
                _buildMapControls(hc),
                Positioned(
                  left: 12,
                  top: 12,
                  child: _MapSearchBar(mapController: _mapController),
                ),
                if (missionState.isTransferring)
                  _buildTransferOverlay(missionState, hc),
              ],
            ),
          ),
          if (showPanel) ...[
            VerticalDivider(width: 1, color: hc.border),
            SizedBox(
              width: 300,
              child: _buildSidePanel(editState, missionState, rallyPoints, hc),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMap(
    MissionEditState editState,
    List<RallyPoint> rallyPoints,
    HeliosColors hc,
  ) {
    final items = editState.items;
    final tileType = ref.watch(mapTileTypeProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final airspaceState = ref.watch(airspaceProvider);
    final airspaceZones = airspaceState.zones;
    final customNfzZones = ref.watch(customNfzProvider);
    final pois = ref.watch(poiProvider);

    // Compute conflicting waypoint seq numbers (inside restricted/prohibited zones)
    final restrictedZones = airspaceZones.where((z) => z.isProhibited).toList();
    final conflictingSeqs = <int>{
      for (final item in items)
        if (item.isNavCommand &&
            restrictedZones.any(
              (z) => z.contains(LatLng(item.latitude, item.longitude)),
            ))
          item.seq,
    };

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(-35.3632, 149.1652),
        initialZoom: 15,
        minZoom: 2,
        maxZoom: 18,
        onMapReady: () => _mapReady = true,
        onTap: (tapPos, latLng) {
          final fence = ref.read(fenceEditProvider);
          if (fence.drawingMode) {
            ref.read(fenceEditProvider.notifier).addVertex(
              latLng.latitude, latLng.longitude,
            );
          } else if (_drawNfzMode) {
            setState(() => _nfzPoints.add(latLng));
          } else if (_polygonSurveyMode) {
            setState(() => _polygonSurveyPoints.add(latLng));
          } else if (_surveyMode) {
            if (_surveyCorner1 == null) {
              setState(() {
                _surveyCorner1 = latLng;
                _surveyCorner2 = null;
              });
            } else {
              setState(() => _surveyCorner2 = latLng);
              _openSurveyDialog(_surveyCorner1!, latLng);
            }
          } else if (_addPoiMode) {
            _showQuickCreatePoiDialog(latLng.latitude, latLng.longitude);
          } else if (_addRallyMode) {
            ref.read(rallyPointProvider.notifier).addPoint(
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
        ..._buildPlanTileLayers(tileType, dark),

        // Airspace overlay
        if (airspaceZones.isNotEmpty)
          PolygonLayer(
            polygons: airspaceZones
                .where((z) => z.polygon.length >= 3)
                .map((z) {
                  final color = switch (z.type) {
                    AirspaceType.prohibited => hc.danger,
                    AirspaceType.restricted => hc.warning,
                    AirspaceType.danger => hc.warning,
                    _ => hc.accent,
                  };
                  return Polygon(
                    points: z.polygon,
                    color: color.withValues(alpha: 0.08),
                    borderColor: color.withValues(alpha: 0.6),
                    borderStrokeWidth: 1.5,
                  );
                })
                .toList(),
          ),

        // Custom NFZ polygons
        ..._buildCustomNfzLayers(customNfzZones, hc),

        // In-progress NFZ drawing polyline
        if (_drawNfzMode && _nfzPoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _nfzPoints,
                color: hc.warning,
                strokeWidth: 2,
                pattern: StrokePattern.dashed(segments: [8, 4]),
              ),
            ],
          ),
        if (_drawNfzMode && _nfzPoints.isNotEmpty)
          MarkerLayer(
            markers: _nfzPoints
                .map((p) => Marker(
                      point: p,
                      width: 10,
                      height: 10,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hc.warning,
                          border: Border.all(color: hc.surface, width: 1),
                        ),
                      ),
                    ))
                .toList(),
          ),

        // Fence zones
        ..._buildFenceLayers(ref.watch(fenceEditProvider), hc),

        // Mission path polyline
        if (items.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: items
                    .where((i) => i.isNavCommand)
                    .map((i) => LatLng(i.latitude, i.longitude))
                    .toList(),
                color: hc.accent,
                strokeWidth: 2.5,
                pattern: const StrokePattern.solid(),
              ),
            ],
          ),

        // Direction arrows on path segments
        if (items.length >= 2)
          MarkerLayer(
            markers: _buildDirectionArrows(items, hc),
          ),

        // Loiter radius circle for selected loiter waypoint
        if (editState.hasSelection) ...[
          () {
            final sel = editState.selectedItem!;
            final isLoiter = sel.command == MavCmd.navLoiterUnlim ||
                sel.command == MavCmd.navLoiterTurns ||
                sel.command == MavCmd.navLoiterTime ||
                sel.command == MavCmd.navLoiterToAlt;
            final radius = sel.param3.abs();
            if (isLoiter && radius > 0 && sel.isNavCommand) {
              return CircleLayer(
                circles: [
                  CircleMarker(
                    point: LatLng(sel.latitude, sel.longitude),
                    radius: radius,
                    useRadiusInMeter: true,
                    color: hc.accent.withValues(alpha: 0.1),
                    borderColor: hc.accent.withValues(alpha: 0.6),
                    borderStrokeWidth: 2,
                  ),
                ],
              );
            }
            return const SizedBox.shrink();
          }(),
        ],

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
                              .screenOffsetToLatLng(Offset(pos.dx, pos.dy));
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
                          isConflict: conflictingSeqs.contains(item.seq),
                          command: item.command,
                        ),
                      ),
                    ))
                .toList(),
          ),

        // Rally point markers
        if (rallyPoints.isNotEmpty)
          MarkerLayer(
            markers: rallyPoints.map((rp) => Marker(
              point: LatLng(rp.latitude, rp.longitude),
              width: 32,
              height: 32,
              child: GestureDetector(
                onTap: () => ref
                    .read(rallyPointProvider.notifier)
                    .removePoint(rp.seq),
                child: _RallyMarker(index: rp.seq),
              ),
            )).toList(),
          ),

        // POI markers
        if (pois.isNotEmpty)
          MarkerLayer(
            markers: pois.map((poi) {
              final color = _poiColourValue(poi.colour, hc);
              return Marker(
                point: LatLng(poi.latitude, poi.longitude),
                width: 36,
                height: 36,
                child: GestureDetector(
                  onTap: () => _showPoiDetails(poi),
                  onLongPress: () => _showPoiEditDialog(poi),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      border: Border.all(color: color, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _poiIconData(poi.icon),
                      size: 18,
                      color: color,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

        // Survey rectangle preview
        if (_surveyCorner1 != null && _surveyCorner2 != null)
          PolygonLayer(
            polygons: [
              Polygon(
                points: [
                  _surveyCorner1!,
                  LatLng(_surveyCorner1!.latitude, _surveyCorner2!.longitude),
                  _surveyCorner2!,
                  LatLng(_surveyCorner2!.latitude, _surveyCorner1!.longitude),
                ],
                color: hc.accent.withValues(alpha: 0.15),
                borderColor: hc.accent.withValues(alpha: 0.7),
                borderStrokeWidth: 2,
              ),
            ],
          ),

        // Polygon survey preview: in-progress polyline + vertex dots
        if (_polygonSurveyMode && _polygonSurveyPoints.isNotEmpty) ...[
          PolylineLayer(
            polylines: [
              Polyline(
                points: _polygonSurveyPoints,
                color: hc.warning,
                strokeWidth: 2,
                pattern: StrokePattern.dashed(segments: [8, 4]),
              ),
            ],
          ),
          MarkerLayer(
            markers: _polygonSurveyPoints
                .map((p) => Marker(
                      point: p,
                      width: 10,
                      height: 10,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hc.warning,
                          border: Border.all(color: hc.surface, width: 1),
                        ),
                      ),
                    ))
                .toList(),
          ),
          // Close polygon preview when 3+ points
          if (_polygonSurveyPoints.length >= 3)
            PolygonLayer(
              polygons: [
                Polygon(
                  points: _polygonSurveyPoints,
                  color: hc.warning.withValues(alpha: 0.1),
                  borderColor: hc.warning.withValues(alpha: 0.5),
                  borderStrokeWidth: 1.5,
                ),
              ],
            ),
        ],
      ],
    );
  }

  List<Marker> _buildDirectionArrows(List<MissionItem> items, HeliosColors hc) {
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
          child: Icon(
            Icons.play_arrow,
            size: 16,
            color: hc.accent,
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

  List<Widget> _buildFenceLayers(FenceEditState fenceState, HeliosColors hc) {
    final layers = <Widget>[];

    // Existing zones
    for (final zone in fenceState.zones) {
      if (zone.shape == FenceShape.polygon && zone.vertices.length >= 3) {
        final color = zone.type == FenceZoneType.inclusion
            ? hc.success
            : hc.danger;
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
            ? hc.success
            : hc.danger;
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
          ? hc.success
          : hc.danger;
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

  List<Widget> _buildCustomNfzLayers(
    List<CustomNfz> zones,
    HeliosColors hc,
  ) {
    if (zones.isEmpty) return const [];
    return zones
        .where((z) => z.polygon.length >= 3)
        .map((z) {
          final color = switch (z.colour) {
            'red' => hc.danger,
            'yellow' => hc.warning,
            _ => hc.warning, // 'orange' treated as warning token
          };
          return PolygonLayer(
            polygons: [
              Polygon(
                points: z.polygon,
                color: color.withValues(alpha: 0.10),
                borderColor: color.withValues(alpha: 0.85),
                borderStrokeWidth: 2,
                pattern: StrokePattern.dashed(segments: [8, 4]),
              ),
            ],
          );
        })
        .cast<Widget>()
        .toList();
  }

  Widget _buildInfoBar(MissionEditState editState, HeliosColors hc) {
    final count = editState.waypointCount;
    // Calculate total distance
    final missionState = MissionState(items: editState.items);
    final distKm = missionState.totalDistanceMetres / 1000;
    // Rough time estimate at 15 m/s
    final estMin = missionState.totalDistanceMetres > 0
        ? missionState.totalDistanceMetres / 15 / 60
        : 0.0;

    // Count waypoints that fall inside restricted airspace
    final airspaceZones = ref.watch(airspaceProvider).zones;
    final restrictedZones = airspaceZones.where((z) => z.isProhibited).toList();
    final conflictCount = restrictedZones.isNotEmpty
        ? editState.items
            .where((item) => item.isNavCommand &&
                restrictedZones.any((z) => z.contains(LatLng(item.latitude, item.longitude))))
            .length
        : 0;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        height: 36,
        color: hc.surface.withValues(alpha: 0.9),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Text(
              'Waypoints: $count',
              style: TextStyle(
                color: hc.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 24),
            Text(
              count >= 2
                  ? 'Distance: ${distKm.toStringAsFixed(1)} km'
                  : 'Distance: -- km',
              style: TextStyle(
                color: hc.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 24),
            Text(
              estMin > 0
                  ? 'Est: ${estMin.toStringAsFixed(0)} min'
                  : 'Est: -- min',
              style: TextStyle(
                color: hc.textSecondary,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            if (conflictCount > 0) ...[
              Icon(Icons.warning_amber_rounded, size: 14, color: hc.danger),
              const SizedBox(width: 4),
              Text(
                '$conflictCount wp${conflictCount == 1 ? '' : 's'} in restricted airspace',
                style: TextStyle(
                  color: hc.danger,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
            ],
            if (editState.isDirty)
              Text(
                'Modified',
                style: TextStyle(
                  color: hc.warning,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapControls(HeliosColors hc) {
    final notifier = ref.read(missionEditProvider.notifier);
    final fenceNotifier = ref.read(fenceEditProvider.notifier);
    final fenceState = ref.watch(fenceEditProvider);

    return Positioned(
      right: 12,
      top: 48,
      child: Column(
        children: [
          // ── Navigation ──
          _ToolGroup(
            label: 'Navigation',
            children: [
              _MapButton(
                icon: Icons.add,
                onPressed: () => _mapController.move(
                  _mapController.camera.center,
                  (_mapController.camera.zoom + 1).clamp(2, 18),
                ),
              ),
              const SizedBox(height: 4),
              _MapButton(
                icon: Icons.remove,
                onPressed: () => _mapController.move(
                  _mapController.camera.center,
                  (_mapController.camera.zoom - 1).clamp(2, 18),
                ),
              ),
              const SizedBox(height: 4),
              _MapButton(
                icon: Icons.undo,
                onPressed: notifier.canUndo ? () => notifier.undo() : null,
              ),
              const SizedBox(height: 4),
              _MapButton(
                icon: Icons.redo,
                onPressed: notifier.canRedo ? () => notifier.redo() : null,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Drawing ──
          _ToolGroup(
            label: 'Drawing',
            children: [
              _MapButton(
                icon: fenceState.drawingMode ? Icons.check : Icons.fence,
                onPressed: () {
                  if (fenceState.drawingMode) {
                    fenceNotifier.finishDrawing();
                  } else {
                    setState(() {
                      _addRallyMode = false;
                      _addPoiMode = false;
                    });
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
              const SizedBox(height: 4),
              _MapButton(
                icon: Icons.grid_on,
                onPressed: () {
                  if (fenceState.drawingMode) return;
                  setState(() {
                    _surveyMode = !_surveyMode;
                    if (_surveyMode) {
                      _addRallyMode = false;
                      _addPoiMode = false;
                      _polygonSurveyMode = false;
                      _polygonSurveyPoints.clear();
                      _surveyCorner1 = null;
                      _surveyCorner2 = null;
                    }
                  });
                },
              ),
              const SizedBox(height: 4),
              _MapButton(
                icon: Icons.grid_4x4,
                onPressed: () {
                  if (fenceState.drawingMode) return;
                  setState(() {
                    _polygonSurveyMode = !_polygonSurveyMode;
                    if (_polygonSurveyMode) {
                      _addRallyMode = false;
                      _addPoiMode = false;
                      _surveyMode = false;
                      _polygonSurveyPoints.clear();
                      _surveyCorner1 = null;
                      _surveyCorner2 = null;
                    }
                  });
                },
              ),
              if (_polygonSurveyMode) ...[
                const SizedBox(height: 4),
                _MapButton(
                  icon: Icons.check,
                  onPressed: _polygonSurveyPoints.length >= 3
                      ? () => _openPolygonSurveyDialog()
                      : null,
                ),
                const SizedBox(height: 4),
                _MapButton(
                  icon: Icons.close,
                  onPressed: () {
                    setState(() {
                      _polygonSurveyMode = false;
                      _polygonSurveyPoints.clear();
                    });
                  },
                ),
              ],
              const SizedBox(height: 4),
              _MapButton(
                icon: Icons.pentagon_outlined,
                onPressed: () {
                  if (fenceState.drawingMode) return;
                  setState(() {
                    _drawNfzMode = !_drawNfzMode;
                    if (!_drawNfzMode) _nfzPoints.clear();
                    if (_drawNfzMode) {
                      _addRallyMode = false;
                      _surveyMode = false;
                    }
                  });
                },
              ),
              if (_drawNfzMode) ...[
                const SizedBox(height: 4),
                _MapButton(
                  icon: Icons.check,
                  onPressed: _nfzPoints.length >= 3
                      ? () => _closeNfzPolygon()
                      : null,
                ),
                const SizedBox(height: 4),
                _MapButton(
                  icon: Icons.close,
                  onPressed: () {
                    setState(() {
                      _drawNfzMode = false;
                      _nfzPoints.clear();
                    });
                  },
                ),
              ],
              if (ref.watch(customNfzProvider).isNotEmpty) ...[
                const SizedBox(height: 4),
                _MapButton(
                  icon: Icons.delete_sweep_outlined,
                  onPressed: () =>
                      ref.read(customNfzProvider.notifier).clear(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // ── Markers ──
          _ToolGroup(
            label: 'Markers',
            children: [
              _MapButton(
                icon: _addRallyMode ? Icons.flag : Icons.outlined_flag,
                onPressed: () {
                  if (fenceState.drawingMode) return;
                  setState(() {
                    _addRallyMode = !_addRallyMode;
                    if (_addRallyMode) {
                      _surveyMode = false;
                      _addPoiMode = false;
                    }
                  });
                },
              ),
              const SizedBox(height: 4),
              _MapButton(
                icon: _addPoiMode
                    ? Icons.location_on
                    : Icons.add_location_outlined,
                onPressed: () {
                  if (fenceState.drawingMode) return;
                  setState(() {
                    _addPoiMode = !_addPoiMode;
                    if (_addPoiMode) {
                      _addRallyMode = false;
                      _surveyMode = false;
                      _drawNfzMode = false;
                      _nfzPoints.clear();
                    }
                  });
                },
              ),
              if (ref.watch(poiProvider).isNotEmpty) ...[
                const SizedBox(height: 4),
                _MapButton(
                  icon: Icons.wrong_location_outlined,
                  onPressed: () => ref.read(poiProvider.notifier).clear(),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // ── Layers ──
          _ToolGroup(
            label: 'Layers',
            children: [
              _PlanTilePicker(
                current: ref.watch(mapTileTypeProvider),
                onSelect: (MapTileType t) =>
                    ref.read(mapTileTypeProvider.notifier).setType(t),
              ),
              const SizedBox(height: 4),
              _MapButton(
                icon: Icons.layers,
                onPressed: () async {
                  final airNotifier = ref.read(airspaceProvider.notifier);
                  final imported = await airNotifier.importFromFilePicker();
                  if (!imported && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('No airspace zones imported')),
                    );
                  }
                },
              ),
              const SizedBox(height: 4),
              _MapButton(
                icon: ref.watch(airspaceProvider).isFetching
                    ? Icons.hourglass_top
                    : Icons.cloud_download_outlined,
                onPressed: ref.watch(airspaceProvider).isFetching
                    ? null
                    : () => _fetchAirspace(),
              ),
              if (ref.watch(airspaceProvider).zones.isNotEmpty) ...[
                const SizedBox(height: 4),
                _MapButton(
                  icon: Icons.layers_clear,
                  onPressed: () =>
                      ref.read(airspaceProvider.notifier).clear(),
                ),
              ],
              const SizedBox(height: 4),
              _MapButton(
                icon: Icons.download_for_offline_outlined,
                onPressed: () => _cacheVisibleArea(),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Import ──
          _ToolGroup(
            label: 'Import',
            children: [
              _MapButton(
                icon: Icons.upload_file,
                onPressed: () => _importKmlGpx(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Returns the primary tile URL template for the current [MapTileType].
  static String _tileUrlTemplate(MapTileType type) {
    switch (type) {
      case MapTileType.hybrid:
      case MapTileType.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case MapTileType.terrain:
        return 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
      case MapTileType.osm:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
  }

  /// Cache the currently visible map area for offline use.
  Future<void> _cacheVisibleArea() async {
    final bounds = _mapController.camera.visibleBounds;
    final tileType = ref.read(mapTileTypeProvider);
    final urlTemplate = _tileUrlTemplate(tileType);
    final maxZoom = (tileType == MapTileType.terrain) ? 17 : 16;
    final estimate = TileDownloadService.estimateBoundsTileCount(
      bounds,
      maxZoom: maxZoom,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final hc = ctx.hc;
        return AlertDialog(
          backgroundColor: hc.surface,
          title: Text('Cache Visible Area', style: TextStyle(color: hc.textPrimary)),
          content: Text(
            'Download ~$estimate tiles for offline use?\n'
            'This covers zoom levels 1\u2013$maxZoom for the current view.',
            style: TextStyle(color: hc.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: hc.textTertiary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Download', style: TextStyle(color: hc.accent)),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading ~$estimate tiles\u2026')),
    );

    try {
      await TileDownloadService.downloadBounds(
        bounds: bounds,
        urlTemplate: urlTemplate,
        maxZoom: maxZoom,
        onProgress: (downloaded, total) {
          // Progress is tracked via TileDownloadService static getters.
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tile cache download complete')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cache download failed: $e')),
        );
      }
    }
  }

  Future<void> _fetchAirspace() async {
    final settings = ref.read(airspaceSettingsProvider);
    String apiKey = settings.apiKey;

    if (!settings.hasApiKey) {
      // Prompt for API key
      final entered = await _showApiKeyDialog();
      if (entered == null || entered.isEmpty) return;
      await ref.read(airspaceSettingsProvider.notifier).setApiKey(entered);
      apiKey = entered;
    }

    final camera = _mapController.camera;
    final bounds = camera.visibleBounds;
    final notifier = ref.read(airspaceProvider.notifier);

    try {
      final added = await notifier.fetchFromOpenAip(
        bounds.south,
        bounds.north,
        bounds.west,
        bounds.east,
        apiKey,
      );
      if (mounted) {
        final msg = added == 0
            ? 'No new zones found for this area'
            : 'Added $added airspace zone${added == 1 ? '' : 's'}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Airspace fetch failed: $e'),
            backgroundColor: context.hc.danger,
          ),
        );
      }
    }
  }

  Future<String?> _showApiKeyDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final hc = ctx.hc;
        return AlertDialog(
          backgroundColor: hc.surface,
          title: Text(
            'OpenAIP API Key',
            style: TextStyle(color: hc.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your OpenAIP API key to fetch live airspace data.',
                style: TextStyle(color: hc.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                style: TextStyle(color: hc.textPrimary),
                decoration: InputDecoration(
                  labelText: 'API Key',
                  labelStyle: TextStyle(color: hc.textSecondary),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: hc.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: hc.accent),
                  ),
                ),
                onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text('Cancel', style: TextStyle(color: hc.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Fetch'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _closeNfzPolygon() async {
    if (_nfzPoints.length < 3) return;
    final points = List<LatLng>.from(_nfzPoints);

    final name = await _showNfzNameDialog();
    if (name == null) return; // cancelled

    await ref.read(customNfzProvider.notifier).addZone(points, name);

    setState(() {
      _drawNfzMode = false;
      _nfzPoints.clear();
    });
  }

  Future<String?> _showNfzNameDialog() {
    final controller = TextEditingController(text: 'Custom NFZ');
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final hc = ctx.hc;
        return AlertDialog(
          backgroundColor: hc.surface,
          title: Text('Name This Zone', style: TextStyle(color: hc.textPrimary)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: hc.textPrimary),
            decoration: InputDecoration(
              labelText: 'Zone name',
              labelStyle: TextStyle(color: hc.textSecondary),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: hc.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: hc.accent),
              ),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text('Cancel', style: TextStyle(color: hc.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // ─── POI helpers ──────────────────────────────────────────────────────────

  /// Map [PoiColour] enum to a theme-aware [Color].
  Color _poiColourValue(PoiColour colour, HeliosColors hc) {
    return switch (colour) {
      PoiColour.red => hc.danger,
      PoiColour.orange => hc.warning,
      PoiColour.yellow => hc.warning.withValues(alpha: 0.75),
      PoiColour.green => hc.success,
      PoiColour.blue => hc.accent,
      PoiColour.purple => Colors.purple,
    };
  }

  /// Map [PoiIcon] enum to a Material [IconData].
  IconData _poiIconData(PoiIcon icon) {
    return switch (icon) {
      PoiIcon.pin => Icons.location_on,
      PoiIcon.star => Icons.star,
      PoiIcon.camera => Icons.camera_alt,
      PoiIcon.target => Icons.my_location,
      PoiIcon.home => Icons.home,
      PoiIcon.flag => Icons.flag,
    };
  }

  /// Shows a quick-create dialog for a new POI at [lat]/[lon].
  Future<void> _showQuickCreatePoiDialog(double lat, double lon) async {
    final nameController = TextEditingController(text: 'POI ${DateTime.now().microsecondsSinceEpoch % 10000}');
    var selectedColour = PoiColour.blue;
    var selectedIcon = PoiIcon.pin;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setS) {
          final hcD = ctx.hc;
          return AlertDialog(
            backgroundColor: hcD.surface,
            title: Text('New Point of Interest', style: TextStyle(color: hcD.textPrimary)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    style: TextStyle(color: hcD.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Name',
                      labelStyle: TextStyle(color: hcD.textSecondary),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: hcD.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: hcD.accent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Colour', style: TextStyle(color: hcD.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: PoiColour.values.map((c) {
                      final col = _poiColourValue(c, hcD);
                      return GestureDetector(
                        onTap: () => setS(() => selectedColour = c),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: col,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selectedColour == c ? hcD.textPrimary : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Text('Icon', style: TextStyle(color: hcD.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: PoiIcon.values.map((ic) {
                      final isSelected = selectedIcon == ic;
                      return GestureDetector(
                        onTap: () => setS(() => selectedIcon = ic),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isSelected ? hcD.accent.withValues(alpha: 0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected ? hcD.accent : hcD.border,
                            ),
                          ),
                          child: Icon(
                            _poiIconData(ic),
                            size: 18,
                            color: isSelected ? hcD.accent : hcD.textSecondary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}',
                    style: TextStyle(color: hcD.textTertiary, fontSize: 11),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Cancel', style: TextStyle(color: hcD.textSecondary)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Add'),
              ),
            ],
          );
        });
      },
    );

    if (result != true || !mounted) return;

    final poi = PointOfInterest(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: nameController.text.trim().isEmpty ? 'POI' : nameController.text.trim(),
      latitude: lat,
      longitude: lon,
      colour: selectedColour,
      icon: selectedIcon,
    );
    ref.read(poiProvider.notifier).addPoi(poi);
    setState(() => _addPoiMode = false);
  }

  /// Shows a detail bottom sheet for the given [poi].
  void _showPoiDetails(PointOfInterest poi) {
    final hc = context.hc;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        final hcB = ctx.hc;
        final colour = _poiColourValue(poi.colour, hcB);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_poiIconData(poi.icon), color: colour, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      poi.name,
                      style: HeliosTypography.heading2.copyWith(color: hcB.textPrimary),
                    ),
                  ),
                ],
              ),
              if (poi.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(poi.notes, style: TextStyle(color: hcB.textSecondary, fontSize: 13)),
              ],
              const SizedBox(height: 10),
              Text(
                'Lat: ${poi.latitude.toStringAsFixed(6)}  Lon: ${poi.longitude.toStringAsFixed(6)}',
                style: TextStyle(color: hcB.textTertiary, fontSize: 12, fontFamily: 'monospace'),
              ),
              Text(
                'Altitude: ${poi.altitudeM.toStringAsFixed(1)} m AGL',
                style: TextStyle(color: hcB.textTertiary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _showPoiEditDialog(poi);
                      },
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        final ok = await _confirmPoiDelete(poi.name);
                        if (ok) ref.read(poiProvider.notifier).removePoi(poi.id);
                      },
                      icon: Icon(Icons.delete_outline, size: 16, color: hcB.danger),
                      label: Text('Delete', style: TextStyle(color: hcB.danger)),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: hcB.danger)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _showOrbitDialog(poi);
                      },
                      icon: const Icon(Icons.rotate_right, size: 16),
                      label: const Text('Orbit'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Shows an edit dialog for the given [poi].
  Future<void> _showPoiEditDialog(PointOfInterest poi) async {
    final nameController = TextEditingController(text: poi.name);
    final notesController = TextEditingController(text: poi.notes);
    final altController = TextEditingController(text: poi.altitudeM.toStringAsFixed(1));
    var selectedColour = poi.colour;
    var selectedIcon = poi.icon;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setS) {
          final hcD = ctx.hc;
          return AlertDialog(
            backgroundColor: hcD.surface,
            title: Text('Edit POI', style: TextStyle(color: hcD.textPrimary)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    style: TextStyle(color: hcD.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Name',
                      labelStyle: TextStyle(color: hcD.textSecondary),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: hcD.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: hcD.accent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesController,
                    style: TextStyle(color: hcD.textPrimary),
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Notes (optional)',
                      labelStyle: TextStyle(color: hcD.textSecondary),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: hcD.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: hcD.accent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: altController,
                    style: TextStyle(color: hcD.textPrimary),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Altitude AGL (m)',
                      labelStyle: TextStyle(color: hcD.textSecondary),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: hcD.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: hcD.accent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Colour', style: TextStyle(color: hcD.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: PoiColour.values.map((c) {
                      final col = _poiColourValue(c, hcD);
                      return GestureDetector(
                        onTap: () => setS(() => selectedColour = c),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: col,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selectedColour == c ? hcD.textPrimary : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Text('Icon', style: TextStyle(color: hcD.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: PoiIcon.values.map((ic) {
                      final isSelected = selectedIcon == ic;
                      return GestureDetector(
                        onTap: () => setS(() => selectedIcon = ic),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isSelected ? hcD.accent.withValues(alpha: 0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected ? hcD.accent : hcD.border,
                            ),
                          ),
                          child: Icon(
                            _poiIconData(ic),
                            size: 18,
                            color: isSelected ? hcD.accent : hcD.textSecondary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('Cancel', style: TextStyle(color: hcD.textSecondary)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );

    if (result != true || !mounted) return;

    final updated = poi.copyWith(
      name: nameController.text.trim().isEmpty ? poi.name : nameController.text.trim(),
      notes: notesController.text.trim(),
      altitudeM: double.tryParse(altController.text) ?? poi.altitudeM,
      colour: selectedColour,
      icon: selectedIcon,
    );
    ref.read(poiProvider.notifier).updatePoi(updated);
  }

  Future<bool> _confirmPoiDelete(String name) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final hcD = ctx.hc;
        return AlertDialog(
          backgroundColor: hcD.surface,
          title: Text('Delete POI?', style: TextStyle(color: hcD.textPrimary)),
          content: Text(
            'Remove "$name" from the map?',
            style: TextStyle(color: hcD.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: hcD.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: hcD.danger),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    ).then((v) => v ?? false);
  }

  /// Shows the orbit mission generator dialog for a POI.
  Future<void> _showOrbitDialog(PointOfInterest poi) async {
    final radiusController = TextEditingController(text: '50');
    final altController = TextEditingController(
      text: poi.altitudeM > 0 ? poi.altitudeM.toStringAsFixed(0) : '30',
    );
    final speedController = TextEditingController(text: '5');
    final lapsController = TextEditingController(text: '2');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final hcD = ctx.hc;

        Widget field(TextEditingController ctrl, String label, String suffix) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: ctrl,
              style: TextStyle(color: hcD.textPrimary),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: label,
                suffixText: suffix,
                labelStyle: TextStyle(color: hcD.textSecondary),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: hcD.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: hcD.accent),
                ),
              ),
            ),
          );
        }

        return AlertDialog(
          backgroundColor: hcD.surface,
          title: Text('Generate Orbit around "${poi.name}"',
              style: TextStyle(color: hcD.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                field(radiusController, 'Radius', 'm'),
                field(altController, 'Altitude AGL', 'm'),
                field(speedController, 'Speed', 'm/s'),
                field(lapsController, 'Laps', ''),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel', style: TextStyle(color: hcD.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Generate'),
            ),
          ],
        );
      },
    );

    if (result != true || !mounted) return;

    final radius = double.tryParse(radiusController.text) ?? 50.0;
    final altitude = double.tryParse(altController.text) ?? 30.0;
    final laps = int.tryParse(lapsController.text) ?? 2;

    final orbitWaypoints = _generateOrbitWaypoints(
      poi.latitude,
      poi.longitude,
      radiusM: radius.clamp(5.0, 2000.0),
      altitudeM: altitude.clamp(1.0, 500.0),
      laps: laps.clamp(1, 20),
    );

    if (orbitWaypoints.isEmpty || !mounted) return;

    final existing = ref.read(missionEditProvider).items;
    if (existing.isNotEmpty) {
      final choice = await _showOrbitReplaceDialog();
      if (choice == null || !mounted) return;
      if (choice == 'replace') {
        ref.read(missionEditProvider.notifier).loadItems(orbitWaypoints);
      } else if (choice == 'append') {
        final reseq = orbitWaypoints.map((w) => w.copyWith(seq: existing.length + w.seq)).toList();
        ref.read(missionEditProvider.notifier).loadItems([...existing, ...reseq]);
      }
    } else {
      ref.read(missionEditProvider.notifier).loadItems(orbitWaypoints);
    }
  }

  Future<String?> _showOrbitReplaceDialog() {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final hcD = ctx.hc;
        return AlertDialog(
          backgroundColor: hcD.surface,
          title: Text('Orbit Waypoints', style: TextStyle(color: hcD.textPrimary)),
          content: Text(
            'The mission already has waypoints. Replace them or append the orbit?',
            style: TextStyle(color: hcD.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text('Cancel', style: TextStyle(color: hcD.textSecondary)),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop('append'),
              child: const Text('Append'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop('replace'),
              child: const Text('Replace'),
            ),
          ],
        );
      },
    );
  }

  /// Generates [laps] * 12 orbit waypoints clockwise around [centreLat]/[centreLon].
  List<MissionItem> _generateOrbitWaypoints(
    double centreLat,
    double centreLon, {
    required double radiusM,
    required double altitudeM,
    required int laps,
  }) {
    const pointsPerLap = 12;
    const earthRadius = 6371000.0;
    final latOffsetDeg = (radiusM / earthRadius) * (180.0 / math.pi);
    final lonOffsetDeg = latOffsetDeg / math.cos(centreLat * math.pi / 180.0);

    final items = <MissionItem>[];
    var seq = 0;

    // Takeoff at first orbit point
    const firstAngle = 0.0;
    final takeoffLat = centreLat + latOffsetDeg * math.cos(firstAngle);
    final takeoffLon = centreLon + lonOffsetDeg * math.sin(firstAngle);
    items.add(MissionItem(
      seq: seq++,
      frame: MavFrame.globalRelativeAlt,
      command: MavCmd.navTakeoff,
      latitude: takeoffLat,
      longitude: takeoffLon,
      altitude: altitudeM,
    ));

    for (var lap = 0; lap < laps; lap++) {
      for (var p = 0; p < pointsPerLap; p++) {
        // Clockwise: angle increases in positive direction
        final angle = 2.0 * math.pi * p / pointsPerLap;
        final lat = centreLat + latOffsetDeg * math.cos(angle);
        final lon = centreLon + lonOffsetDeg * math.sin(angle);
        items.add(MissionItem(
          seq: seq++,
          frame: MavFrame.globalRelativeAlt,
          command: MavCmd.navWaypoint,
          latitude: lat,
          longitude: lon,
          altitude: altitudeM,
        ));
      }
    }

    return items;
  }

  Widget _buildTransferOverlay(MissionState missionState, HeliosColors hc) {
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
              color: hc.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: hc.border),
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
                    backgroundColor: hc.surfaceLight,
                    valueColor: AlwaysStoppedAnimation(hc.accent),
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
    List<RallyPoint> rallyPoints,
    HeliosColors hc,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: hc.surface,
          child: Row(
            children: [
              const Text('Mission', style: HeliosTypography.heading2),
              const Spacer(),
              if (editState.items.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: hc.textTertiary,
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
        Divider(height: 1, color: hc.border),

        // Waypoint list
        Expanded(
          child: editState.items.isEmpty
              ? Center(
                  child: Text(
                    'Tap map to add waypoints',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: hc.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                )
              : WaypointList(
                  items: editState.items,
                  selectedIndex: editState.selectedIndex,
                  currentWaypoint: ref.watch(currentWaypointProvider),
                  selectedSeqs: editState.selectedSeqs,
                  onSelect: (i) =>
                      ref.read(missionEditProvider.notifier).select(i),
                  onRemove: (i) =>
                      ref.read(missionEditProvider.notifier).removeWaypoint(i),
                  onReorder: (oldI, newI) => ref
                      .read(missionEditProvider.notifier)
                      .reorderWaypoint(oldI, newI),
                  onToggleSelection: (seq) =>
                      ref.read(missionEditProvider.notifier).toggleSelection(seq),
                  onBatchSetAltitude: (alt) =>
                      ref.read(missionEditProvider.notifier).batchSetAltitude(alt),
                  onBatchDelete: () =>
                      ref.read(missionEditProvider.notifier).batchDelete(),
                  onClearSelection: () =>
                      ref.read(missionEditProvider.notifier).clearSelection(),
                ),
        ),

        // Altitude profile chart
        if (editState.items.where((i) => i.isNavCommand).length >= 2) ...[
          Divider(height: 1, color: hc.border),
          _AltitudeProfileChartWithDem(
            items: editState.items.where((i) => i.isNavCommand).toList(),
            selectedSeq: editState.selectedIndex,
            onSelectSeq: (seq) =>
                ref.read(missionEditProvider.notifier).select(seq),
          ),
        ],

        // Waypoint editor (when selected)
        if (editState.hasSelection) ...[
          Divider(height: 1, color: hc.border),
          WaypointEditor(
            item: editState.selectedItem!,
            onChanged: (updated) => ref
                .read(missionEditProvider.notifier)
                .updateWaypoint(editState.selectedIndex, updated),
          ),
        ],

        // Error message
        if (missionState.errorMessage != null) ...[
          Divider(height: 1, color: hc.border),
          Container(
            padding: const EdgeInsets.all(8),
            color: hc.dangerDim.withValues(alpha: 0.2),
            child: Text(
              missionState.errorMessage!,
              style: TextStyle(
                color: hc.danger,
                fontSize: 12,
              ),
            ),
          ),
        ],

        // Upload / Download / Templates buttons
        Divider(height: 1, color: hc.border),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Row(
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
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showTemplatesDialog(),
                  icon: const Icon(Icons.bookmark_outline, size: 16),
                  label: const Text('Templates'),
                ),
              ),
            ],
          ),
        ),

        // Rally Points section
        Divider(height: 1, color: hc.border),
        _buildRallySection(rallyPoints, hc),
      ],
    );
  }

  Widget _buildRallySection(List<RallyPoint> rallyPoints, HeliosColors hc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: hc.surface,
          child: Row(
            children: [
              Icon(Icons.outlined_flag, size: 14, color: hc.textSecondary),
              const SizedBox(width: 6),
              const Text('Rally Points', style: HeliosTypography.heading2),
              const Spacer(),
              if (rallyPoints.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: hc.textTertiary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () =>
                      ref.read(rallyPointProvider.notifier).clear(),
                  tooltip: 'Clear rally points',
                ),
            ],
          ),
        ),
        if (rallyPoints.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              _addRallyMode
                  ? 'Tap map to add rally points'
                  : 'Tap flag button on map to add rally points',
              style: TextStyle(color: hc.textTertiary, fontSize: 12),
            ),
          )
        else
          ...rallyPoints.asMap().entries.map((entry) {
            final rp = entry.value;
            return ListTile(
              dense: true,
              leading: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    '${rp.seq}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              title: Text(
                '${rp.latitude.toStringAsFixed(5)}, ${rp.longitude.toStringAsFixed(5)}',
                style: TextStyle(color: hc.textPrimary, fontSize: 11),
              ),
              subtitle: Text(
                'Alt: ${rp.altitude.toStringAsFixed(0)} m',
                style: TextStyle(color: hc.textSecondary, fontSize: 10),
              ),
              trailing: IconButton(
                icon: Icon(Icons.close, size: 14, color: hc.textTertiary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () =>
                    ref.read(rallyPointProvider.notifier).removePoint(rp.seq),
              ),
            );
          }),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: rallyPoints.isEmpty
                      ? null
                      : () => _uploadRallyPoints(rallyPoints),
                  icon: const Icon(Icons.upload, size: 16),
                  label: const Text('Upload'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _downloadRallyPoints(),
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

  Future<void> _uploadRallyPoints(List<RallyPoint> points) async {
    final controller = ref.read(connectionControllerProvider.notifier);
    await controller.uploadRallyPoints(points);
  }

  Future<void> _downloadRallyPoints() async {
    final controller = ref.read(connectionControllerProvider.notifier);
    final points = await controller.downloadRallyPoints();
    if (points.isNotEmpty) {
      ref.read(rallyPointProvider.notifier).loadPoints(points);
    }
  }

  Future<void> _showTemplatesDialog() async {
    final items = ref.read(missionEditProvider).items;
    await showDialog<void>(
      context: context,
      builder: (_) => _MissionTemplatesDialog(
        currentItems: items,
        onLoad: (loaded) {
          ref.read(missionEditProvider.notifier).loadItems(loaded);
        },
      ),
    );
  }

  Future<void> _openSurveyDialog(LatLng corner1, LatLng corner2) async {
    final result = await showDialog<_SurveyConfig>(
      context: context,
      builder: (_) => const _SurveyConfigDialog(),
    );
    if (result == null) {
      setState(() {
        _surveyCorner1 = null;
        _surveyCorner2 = null;
      });
      return;
    }
    final items = _generateSurveyGrid(corner1, corner2, result);
    if (items.isNotEmpty) {
      final existing = ref.read(missionEditProvider).items;
      ref.read(missionEditProvider.notifier).loadItems([...existing, ...items]);
    }
    setState(() {
      _surveyMode = false;
      _surveyCorner1 = null;
      _surveyCorner2 = null;
    });
  }

  Future<void> _openPolygonSurveyDialog() async {
    final result = await showDialog<_SurveyConfig>(
      context: context,
      builder: (_) => const _SurveyConfigDialog(),
    );
    if (result == null) return;

    final polygon = List<LatLng>.from(_polygonSurveyPoints);
    final items = _generatePolygonSurvey(polygon, result.laneSpacing, result.altitude);
    if (items.isNotEmpty) {
      final existing = ref.read(missionEditProvider).items;
      ref.read(missionEditProvider.notifier).loadItems([...existing, ...items]);
    }
    setState(() {
      _polygonSurveyMode = false;
      _polygonSurveyPoints.clear();
    });
  }

  /// Generate a lawnmower survey grid clipped to [polygon] (list of LatLng vertices).
  ///
  /// Uses a ray-casting algorithm to clip scan-line segments to only include
  /// portions inside the polygon.
  List<MissionItem> _generatePolygonSurvey(
    List<LatLng> polygon,
    double spacingM,
    double altM,
  ) {
    if (polygon.length < 3) return [];

    // Convert polygon to local metres (centred on polygon centroid)
    final centreLat =
        polygon.map((p) => p.latitude).reduce((a, b) => a + b) / polygon.length;
    final centreLon =
        polygon.map((p) => p.longitude).reduce((a, b) => a + b) / polygon.length;

    const mPerDegLat = 111319.0;
    final mPerDegLon = 111319.0 * math.cos(centreLat * math.pi / 180.0);

    List<(double, double)> toXY(LatLng ll) => [
          ((ll.longitude - centreLon) * mPerDegLon,
              (ll.latitude - centreLat) * mPerDegLat)
        ];

    final polyXY =
        polygon.map((ll) => toXY(ll).first).toList();

    // Bounding box in local metres
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    for (final (x, y) in polyXY) {
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
    }

    final existing = ref.read(missionEditProvider).items;
    final items = <MissionItem>[];

    // Add takeoff at the first polygon vertex when mission is empty
    if (existing.isEmpty) {
      final (fx, fy) = polyXY.first;
      items.add(MissionItem(
        seq: 0,
        command: MavCmd.navTakeoff,
        latitude: centreLat + fy / mPerDegLat,
        longitude: centreLon + fx / mPerDegLon,
        altitude: altM,
      ));
    }

    final startSeq = existing.length + items.length;
    var rowIndex = 0;
    var y = minY + spacingM / 2.0;

    while (y < maxY + spacingM / 2.0 - 1e-6) {
      // Find intersections of this horizontal scan line with the polygon
      final xs = <double>[];
      final n = polyXY.length;
      for (var i = 0; i < n; i++) {
        final (x1, y1) = polyXY[i];
        final (x2, y2) = polyXY[(i + 1) % n];
        if ((y1 <= y && y < y2) || (y2 <= y && y < y1)) {
          final t = (y - y1) / (y2 - y1);
          xs.add(x1 + t * (x2 - x1));
        }
      }
      xs.sort();

      // Add waypoint pairs (inside segments)
      if (xs.length >= 2) {
        final isEven = rowIndex.isEven;
        for (var k = 0; k + 1 < xs.length; k += 2) {
          final xA = isEven ? xs[k] : xs[xs.length - 1 - k - 1];
          final xB = isEven ? xs[k + 1] : xs[xs.length - 1 - k];
          for (final xi in [xA, xB]) {
            items.add(MissionItem(
              seq: startSeq + items.length - (existing.isEmpty ? 1 : 0),
              command: MavCmd.navWaypoint,
              latitude: centreLat + y / mPerDegLat,
              longitude: centreLon + xi / mPerDegLon,
              altitude: altM,
            ));
          }
        }
      }

      rowIndex++;
      y += spacingM;
    }

    // Renumber sequentially
    for (var i = 0; i < items.length; i++) {
      items[i] = items[i].copyWith(seq: existing.length + i);
    }

    return items;
  }

  /// Generate a lawnmower survey grid for the given bounding rectangle.
  List<MissionItem> _generateSurveyGrid(
    LatLng corner1,
    LatLng corner2,
    _SurveyConfig config,
  ) {
    final minLat = math.min(corner1.latitude, corner2.latitude);
    final maxLat = math.max(corner1.latitude, corner2.latitude);
    final minLon = math.min(corner1.longitude, corner2.longitude);
    final maxLon = math.max(corner1.longitude, corner2.longitude);

    final centreLat = (minLat + maxLat) / 2.0;
    final centreLon = (minLon + maxLon) / 2.0;

    const metersPerDegLat = 111319.0;
    final metersPerDegLon =
        111319.0 * math.cos(centreLat * math.pi / 180.0);

    final x1 = (minLon - centreLon) * metersPerDegLon;
    final y1 = (minLat - centreLat) * metersPerDegLat;
    final x2 = (maxLon - centreLon) * metersPerDegLon;
    final y2 = (maxLat - centreLat) * metersPerDegLat;

    final angleRad = config.angle * math.pi / 180.0;
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);

    // Find extent of bounding box in rotated frame
    final corners = [(x1, y1), (x2, y1), (x2, y2), (x1, y2)];
    var rMinX = double.infinity;
    var rMaxX = double.negativeInfinity;
    var rMinY = double.infinity;
    var rMaxY = double.negativeInfinity;
    for (final (cx, cy) in corners) {
      final rx = cx * cosA + cy * sinA;
      final ry = -cx * sinA + cy * cosA;
      if (rx < rMinX) rMinX = rx;
      if (rx > rMaxX) rMaxX = rx;
      if (ry < rMinY) rMinY = ry;
      if (ry > rMaxY) rMaxY = ry;
    }

    // Build lawnmower row endpoints in rotated frame
    final rowPoints = <(double, double)>[];
    var rowIndex = 0;
    var ry = rMinY + config.laneSpacing / 2.0;
    while (ry < rMaxY + config.laneSpacing / 2.0 - 1e-6) {
      if (rowIndex.isEven) {
        rowPoints.add((rMinX, ry));
        rowPoints.add((rMaxX, ry));
      } else {
        rowPoints.add((rMaxX, ry));
        rowPoints.add((rMinX, ry));
      }
      rowIndex++;
      ry += config.laneSpacing;
    }

    if (rowPoints.isEmpty) return [];

    final existing = ref.read(missionEditProvider).items;
    final items = <MissionItem>[];

    // First item is TAKEOFF if mission is currently empty
    if (existing.isEmpty) {
      final (frx, fry) = rowPoints.first;
      final gx = frx * cosA - fry * sinA;
      final gy = frx * sinA + fry * cosA;
      items.add(MissionItem(
        seq: 0,
        frame: MavFrame.globalRelativeAlt,
        command: MavCmd.navTakeoff,
        latitude: centreLat + gy / metersPerDegLat,
        longitude: centreLon + gx / metersPerDegLon,
        altitude: config.altitude,
      ));
    }

    final startSeq = existing.length + items.length;
    for (var i = 0; i < rowPoints.length; i++) {
      final (rx, ry2) = rowPoints[i];
      final gx = rx * cosA - ry2 * sinA;
      final gy = rx * sinA + ry2 * cosA;
      items.add(MissionItem(
        seq: startSeq + i,
        frame: MavFrame.globalRelativeAlt,
        command: MavCmd.navWaypoint,
        latitude: centreLat + gy / metersPerDegLat,
        longitude: centreLon + gx / metersPerDegLon,
        altitude: config.altitude,
      ));
    }

    return items;
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

    // Ctrl+A = select all nav waypoints
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyA) {
      notifier.selectAll();
    }

    // Delete selected waypoint
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      final state = ref.read(missionEditProvider);
      if (state.selectedSeqs.isNotEmpty) {
        notifier.batchDelete();
      } else if (state.hasSelection) {
        notifier.removeWaypoint(state.selectedIndex);
      }
    }

    // Escape to deselect
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      notifier.select(-1);
      notifier.clearSelection();
    }
  }

  /// Import waypoints from a KML or GPX file chosen via the file picker.
  Future<void> _importKmlGpx() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['kml', 'gpx'],
      dialogTitle: 'Import KML or GPX',
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    final content = await File(file.path!).readAsString();
    final ext = p.extension(file.name).toLowerCase();

    final List<MissionItem> imported;
    if (ext == '.kml') {
      imported = KmlImporter().parseKml(
        content,
        defaultAltM: ref.read(missionEditProvider).defaultAltitude,
      );
    } else if (ext == '.gpx') {
      imported = GpxImporter().parseGpx(
        content,
        defaultAltM: ref.read(missionEditProvider).defaultAltitude,
      );
    } else {
      return;
    }

    if (imported.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No waypoints found in ${file.name}')),
        );
      }
      return;
    }

    final existing = ref.read(missionEditProvider).items;
    if (existing.isNotEmpty) {
      final choice = await _showImportReplaceDialog(
        file.name,
        imported.length,
      );
      if (choice == null || !mounted) return;
      if (choice == 'replace') {
        ref.read(missionEditProvider.notifier).loadItems(imported);
      } else {
        final reseq = imported
            .map((w) => w.copyWith(seq: existing.length + w.seq))
            .toList();
        ref.read(missionEditProvider.notifier).loadItems([...existing, ...reseq]);
      }
    } else {
      ref.read(missionEditProvider.notifier).loadItems(imported);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${imported.length} waypoint${imported.length == 1 ? '' : 's'} from ${file.name}',
          ),
        ),
      );
    }
  }

  Future<String?> _showImportReplaceDialog(String filename, int count) {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final hcD = ctx.hc;
        return AlertDialog(
          backgroundColor: hcD.surface,
          title: Text(
            'Import Waypoints',
            style: TextStyle(color: hcD.textPrimary),
          ),
          content: Text(
            'Found $count waypoint${count == 1 ? '' : 's'} in $filename.\n'
            'Replace the current mission or append?',
            style: TextStyle(color: hcD.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text('Cancel', style: TextStyle(color: hcD.textSecondary)),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop('append'),
              child: const Text('Append'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop('replace'),
              child: const Text('Replace'),
            ),
          ],
        );
      },
    );
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

  List<Widget> _buildPlanTileLayers(MapTileType tileType, bool dark) {
    switch (tileType) {
      case MapTileType.hybrid:
        return [
          TileLayer(
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.argus.helios_gcs',
            maxZoom: 18,
            tileProvider: CachedTileProvider(),
          ),
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.argus.helios_gcs',
            maxZoom: 18,
            tileProvider: CachedTileProvider(),
            tileBuilder: (context, tile, tileImage) =>
                Opacity(opacity: 0.5, child: tile),
          ),
        ];
      case MapTileType.satellite:
        return [
          TileLayer(
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            userAgentPackageName: 'com.argus.helios_gcs',
            maxZoom: 18,
            tileProvider: CachedTileProvider(),
          ),
        ];
      case MapTileType.terrain:
        return [
          TileLayer(
            urlTemplate: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.argus.helios_gcs',
            maxZoom: 17,
            tileProvider: CachedTileProvider(),
            tileBuilder: dark ? _darkTileBuilder : null,
          ),
        ];
      case MapTileType.osm:
        return [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.argus.helios_gcs',
            maxZoom: 18,
            tileProvider: CachedTileProvider(),
            tileBuilder: dark ? _darkTileBuilder : null,
          ),
        ];
    }
  }
}

/// Numbered waypoint marker on the map.
class _WaypointMarker extends StatelessWidget {
  const _WaypointMarker({
    required this.index,
    required this.isSelected,
    required this.command,
    this.isConflict = false,
  });

  final int index;
  final bool isSelected;
  final int command;

  /// True when this waypoint is inside a restricted/prohibited airspace zone.
  final bool isConflict;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    // Conflict takes priority over selection colour for border/text
    final Color color;
    final Color bgColor;
    if (isConflict) {
      color = hc.danger;
      bgColor = hc.dangerDim.withValues(alpha: 0.35);
    } else if (isSelected) {
      color = hc.accent;
      bgColor = hc.accentDim;
    } else {
      color = hc.textPrimary;
      bgColor = hc.surface;
    }

    // Special icons for non-waypoint commands
    final icon = switch (command) {
      22 => Icons.flight_takeoff, // NAV_TAKEOFF
      21 => Icons.flight_land,    // NAV_LAND
      20 => Icons.home,           // NAV_RTL
      _ => null,
    };

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: color,
              width: isSelected || isConflict ? 2.5 : 1.5,
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
        ),
        // Warning badge in top-right corner when in conflict
        if (isConflict)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: hc.danger,
                shape: BoxShape.circle,
                border: Border.all(color: hc.surface, width: 1),
              ),
            ),
          ),
      ],
    );
  }
}

/// Small map control button.
/// Tile type picker button for the Plan View map.
class _PlanTilePicker extends StatelessWidget {
  const _PlanTilePicker({required this.current, required this.onSelect});

  final MapTileType current;
  final ValueChanged<MapTileType> onSelect;

  IconData _icon(MapTileType t) => switch (t) {
        MapTileType.osm => Icons.map_outlined,
        MapTileType.satellite => Icons.satellite_alt_outlined,
        MapTileType.terrain => Icons.terrain,
        MapTileType.hybrid => Icons.layers_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return SizedBox(
      width: 40,
      height: 40,
      child: PopupMenuButton<MapTileType>(
        initialValue: current,
        onSelected: onSelect,
        tooltip: 'Map layer',
        color: hc.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: hc.border),
        ),
        itemBuilder: (_) => MapTileType.values.map((t) {
          return PopupMenuItem<MapTileType>(
            value: t,
            child: Row(
              children: [
                Icon(_icon(t),
                    size: 18,
                    color: t == current ? hc.accent : hc.textSecondary),
                const SizedBox(width: 8),
                Text(
                  t.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: t == current ? hc.accent : hc.textPrimary,
                    fontWeight: t == current
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        child: FloatingActionButton.small(
          heroTag: null,
          onPressed: null,
          backgroundColor: hc.surface.withValues(alpha: 0.85),
          elevation: 2,
          child: Icon(_icon(current), size: 20, color: hc.textPrimary),
        ),
      ),
    );
  }
}

/// Small labelled group of tool buttons for the map toolbar.
class _ToolGroup extends StatelessWidget {
  const _ToolGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: hc.textTertiary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        ...children,
      ],
    );
  }
}

/// Expandable search bar with Nominatim geocoding for the plan map.
class _MapSearchBar extends StatefulWidget {
  const _MapSearchBar({required this.mapController});

  final MapController mapController;

  @override
  State<_MapSearchBar> createState() => _MapSearchBarState();
}

class _MapSearchBarState extends State<_MapSearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final client = HttpClient();
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeQueryComponent(query)}&format=json&limit=5',
      );
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'HeliosGCS/1.0');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final List<dynamic> data = jsonDecode(body) as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _results = data.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectResult(Map<String, dynamic> result) {
    final lat = double.tryParse(result['lat']?.toString() ?? '');
    final lon = double.tryParse(result['lon']?.toString() ?? '');
    if (lat != null && lon != null) {
      widget.mapController.move(LatLng(lat, lon), 15);
    }
    setState(() {
      _results = [];
      _controller.clear();
    });
    _focusNode.unfocus();
  }

  void _clearSearch() {
    setState(() {
      _results = [];
      _controller.clear();
    });
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 280,
          height: 40,
          decoration: BoxDecoration(
            color: hc.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: hc.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(Icons.search, size: 18, color: hc.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.escape) {
                      _clearSearch();
                    }
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: _onChanged,
                    style: TextStyle(
                      fontSize: 13,
                      color: hc.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search location\u2026',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: hc.textTertiary,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: hc.accent,
                    ),
                  ),
                )
              else if (_controller.text.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: hc.textTertiary),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: _clearSearch,
                )
              else
                const SizedBox(width: 10),
            ],
          ),
        ),
        if (_results.isNotEmpty)
          Container(
            width: 280,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: hc.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: hc.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _results.map((r) {
                final displayName =
                    r['display_name']?.toString() ?? 'Unknown';
                return InkWell(
                  onTap: () => _selectResult(r),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Text(
                      displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: hc.textPrimary),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return SizedBox(
      width: 40,
      height: 40,
      child: FloatingActionButton.small(
        heroTag: null,
        onPressed: onPressed,
        backgroundColor: hc.surface.withValues(alpha: 0.85),
        elevation: 2,
        child: Icon(
          icon,
          size: 20,
          color: onPressed != null
              ? hc.textPrimary
              : hc.textTertiary,
        ),
      ),
    );
  }
}

/// Rally point marker on the map — red circle with sequence number.
class _RallyMarker extends StatelessWidget {
  const _RallyMarker({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.red.shade700,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$index',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ─── Altitude Profile Chart with DEM Terrain ─────────────────────────────────

/// Altitude profile chart that overlays DEM terrain data when loaded.
class _AltitudeProfileChartWithDem extends ConsumerWidget {
  const _AltitudeProfileChartWithDem({
    required this.items,
    required this.selectedSeq,
    required this.onSelectSeq,
  });

  final List<MissionItem> items;
  final int selectedSeq;
  final ValueChanged<int> onSelectSeq;

  static double _dist(MissionItem a, MissionItem b) {
    const r = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final s = math.pow(math.sin(dLat / 2), 2) +
        math.pow(math.sin(dLon / 2), 2) * math.cos(lat1) * math.cos(lat2);
    return r * 2.0 * math.asin(math.sqrt(s.clamp(0.0, 1.0)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final hasDem = ref.watch(demProvider);
    final demNotifier = ref.read(demProvider.notifier);

    // Build waypoint altitude spots
    final waypointSpots = <FlSpot>[];
    var cumDist = 0.0;
    for (var i = 0; i < items.length; i++) {
      if (i > 0) cumDist += _dist(items[i - 1], items[i]) / 1000;
      waypointSpots.add(FlSpot(cumDist, items[i].altitude));
    }

    // Build terrain spots from DEM if available
    List<FlSpot> terrainSpots = [];
    if (hasDem) {
      final waypoints =
          items.map((it) => LatLng(it.latitude, it.longitude)).toList();
      final profile = demNotifier.service.terrainProfile(waypoints);
      terrainSpots =
          profile.map((p) => FlSpot(p.distKm, p.elevM)).toList();
    }

    final selIdx = items.indexWhere((it) => it.seq == selectedSeq);

    final bars = <LineChartBarData>[
      // Terrain line (below waypoints)
      if (terrainSpots.isNotEmpty)
        LineChartBarData(
          spots: terrainSpots,
          isCurved: false,
          color: const Color(0xFF8B6914),
          barWidth: 1.0,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: const Color(0xFF8B6914).withValues(alpha: 0.20),
          ),
        ),
      // Waypoint altitude line
      LineChartBarData(
        spots: waypointSpots,
        isCurved: false,
        color: hc.accent,
        barWidth: 1.5,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, _, _, idx) {
            final isSelected = idx == selIdx;
            return FlDotCirclePainter(
              radius: isSelected ? 5 : 3,
              color: isSelected ? hc.accent : hc.surface,
              strokeWidth: isSelected ? 0 : 1.5,
              strokeColor: hc.accent,
            );
          },
        ),
        belowBarData: BarAreaData(
          show: true,
          color: hc.accent.withValues(alpha: 0.08),
        ),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 100,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  horizontalInterval: 50,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: hc.border.withValues(alpha: 0.5),
                    strokeWidth: 0.5,
                  ),
                  drawVerticalLine: false,
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 50,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}m',
                        style: TextStyle(
                          color: hc.textTertiary,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 16,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toStringAsFixed(1)}km',
                        style: TextStyle(
                          color: hc.textTertiary,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                lineTouchData: LineTouchData(
                  touchCallback: (event, response) {
                    if (event is! FlTapUpEvent) return;
                    // Only respond to taps on the waypoint line (last bar)
                    final spot = response?.lineBarSpots
                        ?.where((s) => s.barIndex == bars.length - 1)
                        .firstOrNull;
                    final idx = spot?.spotIndex;
                    if (idx != null && idx < items.length) {
                      onSelectSeq(items[idx].seq);
                    }
                  },
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots.map((s) {
                      final label = s.barIndex == 0 && terrainSpots.isNotEmpty
                          ? 'Terrain: ${s.y.toStringAsFixed(0)}m'
                          : '${s.y.toStringAsFixed(0)}m';
                      return LineTooltipItem(
                        label,
                        TextStyle(color: hc.textPrimary, fontSize: 10),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: bars,
              ),
            ),
          ),
        ),
        // DEM import row
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Row(
            children: [
              Text(
                hasDem ? 'Terrain loaded' : 'No terrain data',
                style: TextStyle(color: hc.textTertiary, fontSize: 10),
              ),
              const Spacer(),
              if (hasDem)
                GestureDetector(
                  onTap: () => ref.read(demProvider.notifier).clear(),
                  child: Text(
                    'Clear',
                    style: TextStyle(color: hc.danger, fontSize: 10),
                  ),
                ),
              if (hasDem) const SizedBox(width: 8),
              GestureDetector(
                onTap: () =>
                    ref.read(demProvider.notifier).importFromFilePicker(),
                child: Text(
                  hasDem ? 'Load more' : 'Load terrain (.hgt)',
                  style: TextStyle(color: hc.accent, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Mission Templates ────────────────────────────────────────────────────────

/// A saved mission template entry loaded from disk.
class _TemplateEntry {
  const _TemplateEntry({
    required this.name,
    required this.saved,
    required this.items,
    required this.file,
  });

  final String name;
  final DateTime saved;
  final List<MissionItem> items;
  final File file;
}

/// Dialog for saving, loading, and deleting named mission templates.
class _MissionTemplatesDialog extends StatefulWidget {
  const _MissionTemplatesDialog({
    required this.currentItems,
    required this.onLoad,
  });

  final List<MissionItem> currentItems;
  final ValueChanged<List<MissionItem>> onLoad;

  @override
  State<_MissionTemplatesDialog> createState() =>
      _MissionTemplatesDialogState();
}

class _MissionTemplatesDialogState extends State<_MissionTemplatesDialog> {
  List<_TemplateEntry> _templates = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<Directory> _templatesDir() async {
    final appSupport = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appSupport.path, 'mission_templates'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dir = await _templatesDir();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();

      final entries = <_TemplateEntry>[];
      for (final file in files) {
        try {
          final raw = await file.readAsString();
          final json = jsonDecode(raw) as Map<String, dynamic>;
          final name = json['name'] as String? ??
              p.basenameWithoutExtension(file.path);
          final savedStr = json['saved'] as String?;
          final saved = savedStr != null
              ? DateTime.tryParse(savedStr) ??
                  DateTime.fromMillisecondsSinceEpoch(0)
              : DateTime.fromMillisecondsSinceEpoch(0);
          final rawItems = json['items'] as List<dynamic>? ?? [];
          final items = rawItems
              .map((e) => MissionItem.fromJson(e as Map<String, dynamic>))
              .toList();
          entries.add(_TemplateEntry(
            name: name,
            saved: saved,
            items: items,
            file: file,
          ));
        } catch (_) {
          // Skip malformed template files
        }
      }

      // Newest first
      entries.sort((a, b) => b.saved.compareTo(a.saved));

      if (mounted) {
        setState(() {
          _templates = entries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load templates: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveTemplate(String name) async {
    if (name.trim().isEmpty) return;
    try {
      final dir = await _templatesDir();
      final safeName =
          name.trim().replaceAll(RegExp(r'[^\w\s\-]'), '_');
      final file = File(p.join(dir.path, '$safeName.json'));
      final payload = {
        'name': name.trim(),
        'saved': DateTime.now().toIso8601String(),
        'items': widget.currentItems.map((i) => i.toJson()).toList(),
      };
      await file.writeAsString(jsonEncode(payload));
      await _loadTemplates();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to save: $e');
      }
    }
  }

  Future<void> _deleteTemplate(_TemplateEntry entry) async {
    try {
      await entry.file.delete();
      await _loadTemplates();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to delete: $e');
      }
    }
  }

  Future<void> _promptSave() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Template'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Template name',
            hintText: 'e.g. Grid Survey',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await _saveTemplate(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    return Dialog(
      backgroundColor: hc.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: hc.border),
      ),
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: hc.surface,
                border: Border(bottom: BorderSide(color: hc.border)),
              ),
              child: Row(
                children: [
                  const Text(
                    'Mission Templates',
                    style: HeliosTypography.heading2,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    color: hc.textTertiary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Template list
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _templates.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text(
                              'No saved templates.\nSave your current mission to create one.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: hc.textTertiary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _templates.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: hc.border),
                          itemBuilder: (_, i) {
                            final t = _templates[i];
                            final dateStr =
                                '${t.saved.year}-${t.saved.month.toString().padLeft(2, '0')}-${t.saved.day.toString().padLeft(2, '0')}';
                            return ListTile(
                              dense: true,
                              title: Text(
                                t.name,
                                style: TextStyle(
                                  color: hc.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                '$dateStr  •  ${t.items.length} item${t.items.length == 1 ? '' : 's'}',
                                style: TextStyle(
                                  color: hc.textTertiary,
                                  fontSize: 11,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      widget.onLoad(t.items);
                                      Navigator.of(context).pop();
                                    },
                                    child: const Text('Load'),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      size: 16,
                                      color: hc.textTertiary,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    onPressed: () => _deleteTemplate(t),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),

            // Error row
            if (_error != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                color: hc.dangerDim.withValues(alpha: 0.2),
                child: Text(
                  _error!,
                  style: TextStyle(color: hc.danger, fontSize: 12),
                ),
              ),

            // Footer
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: hc.border)),
              ),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed:
                        widget.currentItems.isEmpty ? null : _promptSave,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Save Current Mission'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Survey Grid ──────────────────────────────────────────────────────────────

/// Configuration for the survey grid generator.
class _SurveyConfig {
  const _SurveyConfig({
    required this.altitude,
    required this.laneSpacing,
    required this.angle,
    required this.speed,
  });

  final double altitude;
  final double laneSpacing;
  final int angle;
  final double speed;
}

/// Dialog to configure and trigger survey grid generation.
class _SurveyConfigDialog extends StatefulWidget {
  const _SurveyConfigDialog();

  @override
  State<_SurveyConfigDialog> createState() => _SurveyConfigDialogState();
}

class _SurveyConfigDialogState extends State<_SurveyConfigDialog> {
  final _altController = TextEditingController(text: '50');
  final _spacingController = TextEditingController(text: '50');
  final _angleController = TextEditingController(text: '0');
  final _speedController = TextEditingController(text: '0');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _altController.dispose();
    _spacingController.dispose();
    _angleController.dispose();
    _speedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return AlertDialog(
      backgroundColor: hc.surface,
      title: const Text('Survey Grid', style: HeliosTypography.heading1),
      content: SizedBox(
        width: 320,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SurveyField(
                controller: _altController,
                label: 'Altitude (m)',
                validator: _positiveDouble,
              ),
              const SizedBox(height: 12),
              _SurveyField(
                controller: _spacingController,
                label: 'Lane spacing (m)',
                validator: _positiveDouble,
              ),
              const SizedBox(height: 12),
              _SurveyField(
                controller: _angleController,
                label: 'Angle (deg, 0 = north)',
                validator: _anyInt,
              ),
              const SizedBox(height: 12),
              _SurveyField(
                controller: _speedController,
                label: 'Speed (m/s, 0 = FC default)',
                validator: _nonNegDouble,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(_SurveyConfig(
              altitude: double.parse(_altController.text),
              laneSpacing: double.parse(_spacingController.text),
              angle: int.parse(_angleController.text),
              speed: double.parse(_speedController.text),
            ));
          },
          child: const Text('Generate'),
        ),
      ],
    );
  }

  static String? _positiveDouble(String? v) {
    final val = double.tryParse(v ?? '');
    if (val == null || val <= 0) return 'Enter a positive number';
    return null;
  }

  static String? _nonNegDouble(String? v) {
    final val = double.tryParse(v ?? '');
    if (val == null || val < 0) return 'Enter 0 or a positive number';
    return null;
  }

  static String? _anyInt(String? v) {
    if (int.tryParse(v ?? '') == null) return 'Enter a whole number';
    return null;
  }
}

class _SurveyField extends StatelessWidget {
  const _SurveyField({
    required this.controller,
    required this.label,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      style: TextStyle(color: hc.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: hc.textSecondary, fontSize: 13),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: hc.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: hc.accent),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: hc.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: hc.danger),
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      validator: validator,
    );
  }
}
