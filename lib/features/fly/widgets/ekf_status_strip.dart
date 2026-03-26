import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';

/// Compact EKF health indicator strip for the Fly View.
///
/// Shows traffic-light indicators for velocity, position, compass variance.
/// Collapses to a single dot when healthy; expands on tap.
class EkfStatusStrip extends ConsumerStatefulWidget {
  const EkfStatusStrip({super.key});

  @override
  ConsumerState<EkfStatusStrip> createState() => _EkfStatusStripState();
}

class _EkfStatusStripState extends ConsumerState<EkfStatusStrip> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final vehicle = ref.watch(vehicleStateProvider);
    final health = vehicle.ekfHealth;

    // Don't show if no EKF data yet
    if (vehicle.ekfVelocityVar == 0 && vehicle.ekfPosHorizVar == 0) {
      return const SizedBox.shrink();
    }

    final color = _healthColor(health);

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: HeliosColors.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: _expanded ? _buildExpanded(vehicle) : _buildCompact(health, color),
      ),
    );
  }

  Widget _buildCompact(int health, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          'EKF',
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildExpanded(VehicleState vehicle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('EKF Status',
            style: TextStyle(color: HeliosColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        _VarianceRow(label: 'Velocity', value: vehicle.ekfVelocityVar),
        _VarianceRow(label: 'Pos Horiz', value: vehicle.ekfPosHorizVar),
        _VarianceRow(label: 'Pos Vert', value: vehicle.ekfPosVertVar),
        _VarianceRow(label: 'Compass', value: vehicle.ekfCompassVar),
        _VarianceRow(label: 'Terrain', value: vehicle.ekfTerrainVar),
      ],
    );
  }

  Color _healthColor(int health) => switch (health) {
    0 => HeliosColors.success,
    1 => HeliosColors.warning,
    _ => HeliosColors.danger,
  };
}

class _VarianceRow extends StatelessWidget {
  const _VarianceRow({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final color = value < 0.5
        ? HeliosColors.success
        : value < 0.8
            ? HeliosColors.warning
            : HeliosColors.danger;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 55,
            child: Text(label, style: const TextStyle(color: HeliosColors.textTertiary, fontSize: 12)),
          ),
          Text(
            value.toStringAsFixed(2),
            style: TextStyle(color: color, fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
