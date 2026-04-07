import 'dart:math' as math;
import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../../shared/models/adsb_vehicle.dart';
import '../../../shared/models/airspace_zone.dart';
import '../../../shared/models/fence_zone.dart';
import '../../../shared/models/point_of_interest.dart';
import '../../../shared/providers/airspace_provider.dart';
import '../../../shared/providers/openaip_key_provider.dart';
import '../../../shared/providers/poi_provider.dart';
import '../../../shared/providers/joystick_provider.dart';
import '../../../shared/providers/providers.dart';
import '../../../core/map/cached_tile_provider.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/providers/map_tile_provider.dart';
import '../../../shared/widgets/expandable_tool_column.dart';
import '../../../shared/widgets/map_search_bar.dart';
import '../../plan/providers/fence_edit_notifier.dart';

/// Maximum number of trail points to display.
const int _maxTrailPoints = 300;

/// Live map showing vehicle position, trail, and home marker.
class VehicleMap extends ConsumerStatefulWidget {
  const VehicleMap({super.key});

  @override
  ConsumerState<VehicleMap> createState() => _VehicleMapState();
}

class _VehicleMapState extends ConsumerState<VehicleMap> {
  final MapController _mapController = MapController();
  final List<LatLng> _trail = [];
  LatLng? _homePosition;
  bool _followVehicle = true;
  bool _mapReady = false;
  bool _initialCenterDone = false;

  /// Set when the user taps the map to show the quicklook card.
  LatLng? _quicklookPoint;

  /// Click & Go mode: when true, map taps set a target instead of quicklook.
  bool _clickGoMode = false;

  /// Pending Click & Go target (shows confirm chip on map).
  LatLng? _clickGoTarget;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final missionItems = ref.watch(missionItemsProvider);
    final currentWp = ref.watch(currentWaypointProvider);
    final fenceZones = ref.watch(fenceEditProvider).zones;
    final hasPosition = vehicle.hasPosition;
    final registry = ref.watch(vehicleRegistryProvider);
    final activeId = ref.watch(activeVehicleIdProvider);
    final tileType = ref.watch(mapTileTypeProvider);
    final adsbTraffic = ref.watch(adsbProvider);
    final airspaceState = ref.watch(airspaceProvider);
    final airspaceZones = airspaceState.zones;
    final airspaceEnabled = airspaceState.enabled;
    final openAipKey = ref.watch(openAipKeyProvider);
    final pois = ref.watch(poiProvider);

    // Update trail
    if (hasPosition) {
      final pos = LatLng(vehicle.latitude, vehicle.longitude);

      // Set home on first fix
      _homePosition ??= pos;

      // Add to trail (deduplicate if same position)
      if (_trail.isEmpty || _trail.last != pos) {
        _trail.add(pos);
        if (_trail.length > _maxTrailPoints) {
          _trail.removeAt(0);
        }
      }

      // Center on vehicle on first GPS fix
      if (!_initialCenterDone && _mapReady) {
        _initialCenterDone = true;
        try {
          _mapController.move(pos, 16);
        } catch (_) {}
      }

      // Follow vehicle
      if (_followVehicle && _mapReady) {
        try {
          _mapController.move(pos, _mapController.camera.zoom);
        } catch (_) {}
      }
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: hasPosition
                ? LatLng(vehicle.latitude, vehicle.longitude)
                : const LatLng(-35.3632, 149.1652), // Default: Canberra
            initialZoom: 16,
            minZoom: 2,
            maxZoom: 18,
            onMapReady: () => _mapReady = true,
            onTap: (_, latLng) {
              setState(() {
                if (_clickGoMode) {
                  // Set target; dismiss if tapped again at the same point
                  if (_clickGoTarget != null &&
                      (_clickGoTarget!.latitude - latLng.latitude).abs() < 1e-6 &&
                      (_clickGoTarget!.longitude - latLng.longitude).abs() < 1e-6) {
                    _clickGoTarget = null;
                  } else {
                    _clickGoTarget = latLng;
                    _quicklookPoint = null;
                  }
                } else {
                  // Dismiss quicklook on second tap at same point
                  if (_quicklookPoint != null &&
                      (_quicklookPoint!.latitude - latLng.latitude).abs() < 1e-6 &&
                      (_quicklookPoint!.longitude - latLng.longitude).abs() < 1e-6) {
                    _quicklookPoint = null;
                  } else {
                    _quicklookPoint = latLng;
                  }
                }
              });
            },
            onPositionChanged: (pos, hasGesture) {
              // Disable follow when user pans manually
              if (hasGesture) {
                setState(() => _followVehicle = false);
              }
              // Auto-fetch airspace for current viewport
              if (airspaceEnabled && openAipKey.isNotEmpty) {
                final bounds = _mapController.camera.visibleBounds;
                ref.read(airspaceProvider.notifier).fetchForViewport(
                  minLat: bounds.south,
                  maxLat: bounds.north,
                  minLon: bounds.west,
                  maxLon: bounds.east,
                  apiKey: openAipKey,
                );
              }
            },
          ),
          children: [
            // Tile layer(s) based on selected type
            ..._buildTileLayers(tileType, Theme.of(context).brightness == Brightness.dark),

            // Fence zones
            if (fenceZones.isNotEmpty)
              PolygonLayer(
                polygons: fenceZones
                    .where((z) => z.shape == FenceShape.polygon && z.vertices.length >= 3)
                    .map((z) {
                      final color = z.type == FenceZoneType.inclusion
                          ? hc.success
                          : hc.danger;
                      return Polygon(
                        points: z.vertices.map((v) => LatLng(v.lat, v.lon)).toList(),
                        color: color.withValues(alpha: 0.1),
                        borderColor: color.withValues(alpha: 0.5),
                        borderStrokeWidth: 1.5,
                      );
                    }).toList(),
              ),

            // Airspace zones overlay
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

            // Vehicle trail
            if (_trail.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _trail,
                    color: hc.accent.withValues(alpha: 0.7),
                    strokeWidth: 3,
                  ),
                ],
              ),

            // Mission path polyline
            if (missionItems.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: missionItems
                        .where((i) => i.isNavCommand)
                        .map((i) => LatLng(i.latitude, i.longitude))
                        .toList(),
                    color: hc.warning.withValues(alpha: 0.6),
                    strokeWidth: 2,
                    pattern: StrokePattern.dashed(segments: [8, 4]),
                  ),
                ],
              ),

            // Mission waypoint markers
            if (missionItems.isNotEmpty)
              MarkerLayer(
                markers: missionItems
                    .where((i) => i.isNavCommand)
                    .map((item) => Marker(
                          point: LatLng(item.latitude, item.longitude),
                          width: 24,
                          height: 24,
                          child: _MissionWaypointMarker(
                            index: item.seq,
                            isCurrent: item.seq == currentWp,
                            command: item.command,
                          ),
                        ))
                    .toList(),
              ),

            // Home marker
            if (_homePosition != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _homePosition!,
                    width: 28,
                    height: 28,
                    child: const _HomeMarker(),
                  ),
                ],
              ),

            // Non-active vehicle markers (multi-vehicle)
            if (registry.length > 1)
              MarkerLayer(
                markers: registry.entries
                    .where((e) => e.key != activeId && e.value.hasPosition)
                    .map((e) => Marker(
                          point: LatLng(e.value.latitude, e.value.longitude),
                          width: 28,
                          height: 28,
                          child: GestureDetector(
                            onTap: () => ref
                                .read(activeVehicleIdProvider.notifier)
                                .state = e.key,
                            child: Opacity(
                              opacity: 0.5,
                              child: _VehicleMarker(
                                heading: e.value.heading.toDouble(),
                                armed: e.value.armed,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),

            // Active vehicle marker
            if (hasPosition)
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(vehicle.latitude, vehicle.longitude),
                    width: 40,
                    height: 40,
                    child: _VehicleMarker(
                      heading: vehicle.heading.toDouble(),
                      armed: vehicle.armed,
                    ),
                  ),
                ],
              ),

            // ADS-B traffic markers
            if (adsbTraffic.isNotEmpty)
              MarkerLayer(
                markers: adsbTraffic.values.map((t) => Marker(
                  point: t.position,
                  width: 48,
                  height: 48,
                  child: _AdsbMarker(vehicle: t),
                )).toList(),
              ),

            // POI markers — read-only visual reference during flight
            if (pois.isNotEmpty)
              MarkerLayer(
                markers: pois.map((poi) {
                  final color = _poiColour(poi.colour, hc);
                  return Marker(
                    point: LatLng(poi.latitude, poi.longitude),
                    width: 32,
                    height: 32,
                    child: Container(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        border: Border.all(color: color, width: 1.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        _poiIcon(poi.icon),
                        size: 16,
                        color: color,
                      ),
                    ),
                  );
                }).toList(),
              ),

            // Click & Go target marker
            if (_clickGoTarget != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _clickGoTarget!,
                    width: 32,
                    height: 32,
                    child: const _ClickGoMarker(),
                  ),
                ],
              ),
          ],
        ),

        // Click & Go confirm chip
        if (_clickGoTarget != null)
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _ClickGoConfirmChip(
                target: _clickGoTarget!,
                vehicleAlt: vehicle.altitudeRel > 0 ? vehicle.altitudeRel : 20.0,
                onConfirm: (alt) async {
                  final cc = ref.read(connectionControllerProvider.notifier);
                  await cc.sendClickGo(
                    lat: _clickGoTarget!.latitude,
                    lon: _clickGoTarget!.longitude,
                    altAgl: alt,
                  );
                  if (mounted) setState(() { _clickGoTarget = null; _clickGoMode = false; });
                },
                onCancel: () => setState(() => _clickGoTarget = null),
              ),
            ),
          ),

        // Quicklook card — shown after map tap.
        // top: 140 clears the outer Stack's toolbar area (LayoutToolbar +
        // ChartToolbar + search bar) which extends to ~y=130.
        if (_quicklookPoint != null)
          Positioned(
            top: 140,
            left: 16,
            child: _QuicklookCard(
              point: _quicklookPoint!,
              vehicleLat: vehicle.hasPosition ? vehicle.latitude : null,
              vehicleLon: vehicle.hasPosition ? vehicle.longitude : null,
              homeLat: vehicle.hasHome ? vehicle.homeLatitude : null,
              homeLon: vehicle.hasHome ? vehicle.homeLongitude : null,
              onDismiss: () => setState(() => _quicklookPoint = null),
            ),
          ),

        // Location search — top-left, below the outer Stack's toolbar area
        // (LayoutToolbar ~48px + gap + ChartToolbar ~36px ≈ 96px from top).
        Positioned(
          top: 100,
          left: 16,
          child: MapSearchBar(
            mapController: _mapController,
            onLocationSelected: (_) {
              setState(() => _followVehicle = false);
            },
          ),
        ),

        // Map type picker — bottom-right to avoid overlap with action panel
        Positioned(
          bottom: 12,
          right: 12,
          child: _MapTypePicker(
            current: tileType,
            onSelect: (t) => ref.read(mapTileTypeProvider.notifier).setType(t),
          ),
        ),

        // Map tool buttons — centre-right with hover expansion
        Positioned(
          right: 12,
          top: 0,
          bottom: 0,
          child: Align(
            alignment: Alignment.centerRight,
            child: ExpandableToolColumn(
              buttons: [
                ToolButtonDef(
                  icon: Icons.add,
                  label: 'Zoom In',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    (_mapController.camera.zoom + 1).clamp(2, 18),
                  ),
                ),
                ToolButtonDef(
                  icon: Icons.remove,
                  label: 'Zoom Out',
                  onPressed: () => _mapController.move(
                    _mapController.camera.center,
                    (_mapController.camera.zoom - 1).clamp(2, 18),
                  ),
                ),
                ToolButtonDef(
                  icon: Icons.layers,
                  label: 'Airspace',
                  active: airspaceEnabled,
                  color: airspaceEnabled ? hc.accent : null,
                  onPressed: () {
                    ref.read(airspaceProvider.notifier).toggleEnabled();
                    if (!airspaceEnabled && openAipKey.isNotEmpty && _mapReady) {
                      final bounds = _mapController.camera.visibleBounds;
                      ref.read(airspaceProvider.notifier).fetchForViewport(
                        minLat: bounds.south,
                        maxLat: bounds.north,
                        minLon: bounds.west,
                        maxLon: bounds.east,
                        apiKey: openAipKey,
                      );
                    }
                  },
                ),
                ToolButtonDef(
                  icon: Icons.ads_click,
                  label: 'Click & Go',
                  active: _clickGoMode,
                  color: _clickGoMode ? hc.accent : null,
                  onPressed: () => setState(() {
                    _clickGoMode = !_clickGoMode;
                    if (!_clickGoMode) _clickGoTarget = null;
                  }),
                ),
                ToolButtonDef(
                  icon: Icons.sports_esports,
                  label: 'Joystick',
                  active: ref.watch(joystickProvider).enabled,
                  color: ref.watch(joystickProvider).enabled ? hc.accent : null,
                  onPressed: () => ref.read(joystickProvider.notifier).toggle(),
                ),
                if (!_followVehicle && hasPosition)
                  ToolButtonDef(
                    icon: Icons.my_location,
                    label: 'Re-centre',
                    color: hc.accent,
                    onPressed: () {
                      setState(() => _followVehicle = true);
                      _mapController.move(
                        LatLng(vehicle.latitude, vehicle.longitude),
                        _mapController.camera.zoom,
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── POI helpers (read-only fly view) ────────────────────────────────────

  Color _poiColour(PoiColour colour, HeliosColors hc) {
    return switch (colour) {
      PoiColour.red => hc.danger,
      PoiColour.orange => hc.warning,
      PoiColour.yellow => hc.warning.withValues(alpha: 0.75),
      PoiColour.green => hc.success,
      PoiColour.blue => hc.accent,
      PoiColour.purple => Colors.purple,
    };
  }

  IconData _poiIcon(PoiIcon icon) {
    return switch (icon) {
      PoiIcon.pin => Icons.location_on,
      PoiIcon.star => Icons.star,
      PoiIcon.camera => Icons.camera_alt,
      PoiIcon.target => Icons.my_location,
      PoiIcon.home => Icons.home,
      PoiIcon.flag => Icons.flag,
    };
  }

  /// Build tile layers based on selected map type.
  /// [dark] applies an invert filter to OSM/Terrain tiles in dark theme.
  List<Widget> _buildTileLayers(MapTileType tileType, bool dark) {
    switch (tileType) {
      case MapTileType.hybrid:
        // Satellite imagery base + semi-transparent OSM labels on top.
        // Satellite imagery is never inverted — it always looks correct.
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
        // True ESRI satellite imagery — no dark-mode filter.
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

  /// Dark tile builder — inverts and reduces brightness for dark theme.
  Widget _darkTileBuilder(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        -0.5, 0, 0, 0, 128, //
        0, -0.5, 0, 0, 128,
        0, 0, -0.5, 0, 128,
        0, 0, 0, 1, 0,
      ]),
      child: tileWidget,
    );
  }
}

/// Vehicle marker — rotated aircraft icon.
class _VehicleMarker extends StatelessWidget {
  const _VehicleMarker({required this.heading, required this.armed});

  final double heading;
  final bool armed;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Transform.rotate(
      angle: heading * math.pi / 180,
      child: CustomPaint(
        painter: _VehicleIconPainter(
          armed: armed,
          activeColor: hc.accent,
          inactiveColor: hc.textTertiary,
        ),
      ),
    );
  }
}

class _VehicleIconPainter extends CustomPainter {
  _VehicleIconPainter({
    required this.armed,
    required this.activeColor,
    required this.inactiveColor,
  });
  final bool armed;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final color = armed ? activeColor : inactiveColor;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final outlinePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Aircraft shape (top-down, nose pointing up)
    final path = Path()
      ..moveTo(cx, cy - 16) // nose
      ..lineTo(cx + 5, cy - 4)
      ..lineTo(cx + 16, cy + 2) // right wing tip
      ..lineTo(cx + 5, cy)
      ..lineTo(cx + 6, cy + 12) // right tail
      ..lineTo(cx, cy + 8) // tail centre
      ..lineTo(cx - 6, cy + 12) // left tail
      ..lineTo(cx - 5, cy)
      ..lineTo(cx - 16, cy + 2) // left wing tip
      ..lineTo(cx - 5, cy - 4)
      ..close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _VehicleIconPainter old) =>
      armed != old.armed ||
      activeColor != old.activeColor ||
      inactiveColor != old.inactiveColor;
}

/// Home position marker.
class _HomeMarker extends StatelessWidget {
  const _HomeMarker();

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hc.success.withValues(alpha: 0.2),
        border: Border.all(color: hc.success, width: 2),
      ),
      child: Center(
        child: Icon(Icons.home, size: 14, color: hc.success),
      ),
    );
  }
}

/// Mission waypoint marker on the Fly View map.
class _MissionWaypointMarker extends StatelessWidget {
  const _MissionWaypointMarker({
    required this.index,
    required this.isCurrent,
    required this.command,
  });

  final int index;
  final bool isCurrent;
  final int command;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final color = isCurrent ? hc.success : hc.warning;

    final icon = switch (command) {
      MavCmd.navTakeoff => Icons.flight_takeoff,
      MavCmd.navLand => Icons.flight_land,
      MavCmd.navReturnToLaunch => Icons.home,
      _ => null,
    };

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: hc.surface.withValues(alpha: 0.85),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: isCurrent ? 2.5 : 1.5),
        boxShadow: isCurrent
            ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6)]
            : null,
      ),
      child: Center(
        child: icon != null
            ? Icon(icon, size: 12, color: color)
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

/// Map tile type picker — popup menu anchored to a small icon button.
class _MapTypePicker extends StatelessWidget {
  const _MapTypePicker({required this.current, required this.onSelect});

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
    return PopupMenuButton<MapTileType>(
      tooltip: 'Map type',
      onSelected: onSelect,
      color: hc.surface,
      constraints: const BoxConstraints(minWidth: 160),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: hc.border),
      ),
      itemBuilder: (_) => MapTileType.values
          .map(
            (t) => PopupMenuItem(
              value: t,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _icon(t),
                    size: 16,
                    color: t == current ? hc.accent : hc.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    t.label,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      fontSize: 13,
                      color: t == current ? hc.accent : hc.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: hc.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: hc.border),
        ),
        child: Icon(_icon(current), size: 18, color: hc.accent),
      ),
    );
  }
}

/// Compact overlay card shown when user taps the map.
/// Displays lat/lon, distance from vehicle, and distance from home.
class _QuicklookCard extends StatelessWidget {
  const _QuicklookCard({
    required this.point,
    required this.onDismiss,
    this.vehicleLat,
    this.vehicleLon,
    this.homeLat,
    this.homeLon,
  });

  final LatLng point;
  final VoidCallback onDismiss;
  final double? vehicleLat;
  final double? vehicleLon;
  final double? homeLat;
  final double? homeLon;

  static double _haversine(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.pow(math.sin(dLon / 2), 2) *
            math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180);
    return r * 2.0 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
  }

  static String _fmtDist(double metres) {
    if (metres >= 1000) return '${(metres / 1000).toStringAsFixed(2)} km';
    return '${metres.round()} m';
  }

  static String _fmtCoord(double deg, bool isLat) {
    final dir = isLat ? (deg >= 0 ? 'N' : 'S') : (deg >= 0 ? 'E' : 'W');
    final abs = deg.abs();
    final d = abs.floor();
    final mFrac = (abs - d) * 60;
    final m = mFrac.floor();
    final s = (mFrac - m) * 60;
    return "$d° $m' ${s.toStringAsFixed(1)}\" $dir";
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    final distVehicle = vehicleLat != null
        ? _haversine(vehicleLat!, vehicleLon!, point.latitude, point.longitude)
        : null;
    final distHome = homeLat != null
        ? _haversine(homeLat!, homeLon!, point.latitude, point.longitude)
        : null;

    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: hc.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Icon(Icons.location_pin, size: 12, color: hc.accent),
              const SizedBox(width: 4),
              Text(
                'Point',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: hc.accent,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onDismiss,
                child: Icon(Icons.close, size: 14, color: hc.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Row(label: 'Lat', value: _fmtCoord(point.latitude, true), hc: hc),
          _Row(label: 'Lon', value: _fmtCoord(point.longitude, false), hc: hc),
          if (distVehicle != null) ...[
            const SizedBox(height: 4),
            _Row(
              label: 'From UAV',
              value: _fmtDist(distVehicle),
              hc: hc,
              valueColor: hc.accent,
            ),
          ],
          if (distHome != null)
            _Row(
              label: 'From Home',
              value: _fmtDist(distHome),
              hc: hc,
              valueColor: hc.textSecondary,
            ),
          const SizedBox(height: 4),
          Text(
            '${point.latitude.toStringAsFixed(6)}, '
            '${point.longitude.toStringAsFixed(6)}',
            style: TextStyle(
              fontSize: 9,
              color: hc.textTertiary,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.hc,
    this.valueColor,
  });
  final String label;
  final String value;
  final HeliosColors hc;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: hc.textTertiary),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: valueColor ?? hc.textPrimary,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

/// ADS-B traffic marker — a small aircraft icon with callsign label.
class _AdsbMarker extends StatelessWidget {
  const _AdsbMarker({required this.vehicle});

  final AdsbVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(
          angle: vehicle.headingDeg * math.pi / 180,
          child: Icon(
            Icons.airplanemode_active,
            size: 20,
            color: hc.warning,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: hc.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            vehicle.displayId,
            style: TextStyle(
              fontSize: 8,
              color: hc.warning,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Pin marker shown at the Click & Go target position.
class _ClickGoMarker extends StatelessWidget {
  const _ClickGoMarker();

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Icon(Icons.location_on, color: hc.accent, size: 32);
  }
}

/// Confirm chip shown above the map tile picker when a Click & Go target is set.
class _ClickGoConfirmChip extends StatefulWidget {
  const _ClickGoConfirmChip({
    required this.target,
    required this.vehicleAlt,
    required this.onConfirm,
    required this.onCancel,
  });

  final LatLng target;
  final double vehicleAlt;
  final Future<void> Function(double altAgl) onConfirm;
  final VoidCallback onCancel;

  @override
  State<_ClickGoConfirmChip> createState() => _ClickGoConfirmChipState();
}

class _ClickGoConfirmChipState extends State<_ClickGoConfirmChip> {
  late double _alt;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _alt = widget.vehicleAlt.clamp(5.0, 500.0);
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final latStr = widget.target.latitude.toStringAsFixed(6);
    final lonStr = widget.target.longitude.toStringAsFixed(6);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: hc.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.accent.withValues(alpha: 0.6)),
        boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 8)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.ads_click, size: 16, color: hc.accent),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$latStr, $lonStr',
                style: TextStyle(fontSize: 11, color: hc.textSecondary, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Alt AGL:', style: TextStyle(fontSize: 11, color: hc.textTertiary)),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 48,
                    height: 20,
                    child: TextFormField(
                      initialValue: _alt.round().toString(),
                      keyboardType: TextInputType.number,
                      style: TextStyle(fontSize: 11, color: hc.textPrimary),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(3),
                          borderSide: BorderSide(color: hc.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(3),
                          borderSide: BorderSide(color: hc.border),
                        ),
                      ),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) setState(() => _alt = parsed.clamp(5.0, 500.0));
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('m', style: TextStyle(fontSize: 11, color: hc.textTertiary)),
                ],
              ),
            ],
          ),
          const SizedBox(width: 12),
          if (_sending)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: hc.accent),
            )
          else ...[
            TextButton(
              onPressed: widget.onCancel,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('Cancel', style: TextStyle(fontSize: 12, color: hc.textSecondary)),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: () async {
                setState(() => _sending = true);
                await widget.onConfirm(_alt);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: hc.accent,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Go', style: TextStyle(fontSize: 12, color: Colors.white)),
            ),
          ],
        ],
      ),
    );
  }
}

