import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../core/map/cached_tile_provider.dart';
import '../../../shared/theme/helios_colors.dart';

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

  @override
  Widget build(BuildContext context) {
    final vehicle = ref.watch(vehicleStateProvider);
    final hasPosition = vehicle.hasPosition;

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

      // Follow vehicle
      if (_followVehicle && _mapReady) {
        try {
          _mapController.move(pos, _mapController.camera.zoom);
        } catch (_) {
          // Map not ready yet
        }
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
            onMapReady: () => _mapReady = true,
            onPositionChanged: (pos, hasGesture) {
              // Disable follow when user pans manually
              if (hasGesture) {
                setState(() => _followVehicle = false);
              }
            },
          ),
          children: [
            // OSM tile layer with offline cache
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.argus.helios_gcs',
              maxZoom: 19,
              tileProvider: CachedTileProvider(),
              tileBuilder: _darkTileBuilder,
            ),

            // Vehicle trail
            if (_trail.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _trail,
                    color: HeliosColors.accent.withValues(alpha: 0.7),
                    strokeWidth: 3,
                  ),
                ],
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

            // Vehicle marker
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
          ],
        ),

        // Re-centre button (shown when not following)
        if (!_followVehicle && hasPosition)
          Positioned(
            right: 12,
            bottom: 12,
            child: FloatingActionButton.small(
              onPressed: () {
                setState(() => _followVehicle = true);
                _mapController.move(
                  LatLng(vehicle.latitude, vehicle.longitude),
                  _mapController.camera.zoom,
                );
              },
              backgroundColor: HeliosColors.surface,
              child: const Icon(
                Icons.my_location,
                color: HeliosColors.accent,
                size: 20,
              ),
            ),
          ),

        // Zoom controls
        Positioned(
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
            ],
          ),
        ),
      ],
    );
  }

  /// Dark tile builder — inverts and adjusts colours for dark theme.
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
    return Transform.rotate(
      angle: heading * math.pi / 180,
      child: CustomPaint(
        painter: _VehicleIconPainter(armed: armed),
      ),
    );
  }
}

class _VehicleIconPainter extends CustomPainter {
  _VehicleIconPainter({required this.armed});
  final bool armed;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final color = armed ? HeliosColors.accent : HeliosColors.textTertiary;

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
  bool shouldRepaint(covariant _VehicleIconPainter old) => armed != old.armed;
}

/// Home position marker.
class _HomeMarker extends StatelessWidget {
  const _HomeMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: HeliosColors.success.withValues(alpha: 0.2),
        border: Border.all(color: HeliosColors.success, width: 2),
      ),
      child: const Center(
        child: Icon(Icons.home, size: 14, color: HeliosColors.success),
      ),
    );
  }
}

/// Small map control button.
class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

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
        child: Icon(icon, size: 16, color: HeliosColors.textPrimary),
      ),
    );
  }
}
