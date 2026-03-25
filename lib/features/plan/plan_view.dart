import 'package:flutter/material.dart';
import '../../shared/theme/helios_colors.dart';
import '../../shared/theme/helios_typography.dart';

/// Plan View — mission planning screen.
///
/// Interactive map for tap-to-place waypoints, waypoint list panel,
/// and upload/download controls.
class PlanView extends StatelessWidget {
  const PlanView({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showPanel = width >= 768;

    return Row(
      children: [
        // Map area
        Expanded(
          child: Stack(
            children: [
              Container(
                color: HeliosColors.background,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_outlined, size: 48, color: HeliosColors.textTertiary),
                      SizedBox(height: 8),
                      Text(
                        'Tap to place waypoints — Phase 3',
                        style: TextStyle(color: HeliosColors.textTertiary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
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
        // Waypoint panel (desktop/tablet only)
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
                      'No waypoints',
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
}
