import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../../shared/theme/helios_colors.dart';
import '../../shared/theme/helios_typography.dart';

/// Plan View — mission planning screen with interactive map.
class PlanView extends StatelessWidget {
  const PlanView({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showPanel = width >= 768;

    return Row(
      children: [
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: const LatLng(-35.3632, 149.1652),
                  initialZoom: 15,
                  onTap: (tapPos, latLng) {
                    // Phase 3: tap-to-place waypoints
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.argus.helios_gcs',
                    maxZoom: 19,
                    tileBuilder: _darkTileBuilder,
                  ),
                ],
              ),
              // Bottom info bar
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 36,
                  color: HeliosColors.surface.withValues(alpha: 0.9),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: const Row(
                    children: [
                      Text('Waypoints: 0', style: TextStyle(color: HeliosColors.textSecondary, fontSize: 12)),
                      SizedBox(width: 24),
                      Text('Distance: -- km', style: TextStyle(color: HeliosColors.textSecondary, fontSize: 12)),
                      SizedBox(width: 24),
                      Text('Est: -- min', style: TextStyle(color: HeliosColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showPanel) ...[
          const VerticalDivider(width: 1, color: HeliosColors.border),
          SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  color: HeliosColors.surface,
                  child: Text('Mission', style: HeliosTypography.heading2),
                ),
                const Divider(height: 1, color: HeliosColors.border),
                const Expanded(
                  child: Center(
                    child: Text(
                      'Tap map to add waypoints\n(Phase 3)',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: HeliosColors.textTertiary, fontSize: 13),
                    ),
                  ),
                ),
                const Divider(height: 1, color: HeliosColors.border),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.upload, size: 16),
                          label: const Text('Upload'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Download'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _darkTileBuilder(BuildContext context, Widget tileWidget, TileImage tile) {
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
