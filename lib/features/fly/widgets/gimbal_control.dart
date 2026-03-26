import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Compact gimbal control panel for the Fly View.
///
/// Shows gimbal pitch/yaw readout and provides a virtual joystick area
/// for manual gimbal control, plus camera capture and centre buttons.
/// Only visible when [hasGimbal] is true on the vehicle state.
class GimbalControl extends ConsumerStatefulWidget {
  const GimbalControl({super.key});

  @override
  ConsumerState<GimbalControl> createState() => _GimbalControlState();
}

class _GimbalControlState extends ConsumerState<GimbalControl> {
  bool _expanded = false;

  // Current commanded angles (from joystick drag)
  double _cmdPitch = 0;
  double _cmdYaw = 0;

  @override
  Widget build(BuildContext context) {
    final vehicle = ref.watch(vehicleStateProvider);
    if (!vehicle.hasGimbal) return const SizedBox.shrink();

    if (!_expanded) {
      return _GimbalToggleButton(
        pitch: vehicle.gimbalPitch,
        onTap: () => setState(() => _expanded = true),
      );
    }

    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: HeliosColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HeliosColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          GestureDetector(
            onTap: () => setState(() => _expanded = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: HeliosColors.border, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.control_camera,
                      size: 14, color: HeliosColors.accent),
                  const SizedBox(width: 6),
                  const Text('Gimbal',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: HeliosColors.textPrimary)),
                  const Spacer(),
                  Icon(Icons.keyboard_arrow_down,
                      size: 16, color: HeliosColors.textTertiary),
                ],
              ),
            ),
          ),

          // Attitude readout
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                _AngleReadout(label: 'P', value: vehicle.gimbalPitch),
                const SizedBox(width: 12),
                _AngleReadout(label: 'Y', value: vehicle.gimbalYaw),
                const SizedBox(width: 12),
                _AngleReadout(label: 'R', value: vehicle.gimbalRoll),
              ],
            ),
          ),

          // Virtual joystick area
          GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _cmdPitch = (_cmdPitch - details.delta.dy * 0.5).clamp(-90, 30);
                _cmdYaw = (_cmdYaw + details.delta.dx * 0.5).clamp(-180, 180);
              });
              ref
                  .read(connectionControllerProvider.notifier)
                  .controlGimbal(pitch: _cmdPitch, yaw: _cmdYaw);
            },
            child: Container(
              height: 100,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: HeliosColors.surfaceDim,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: HeliosColors.border),
              ),
              child: Stack(
                children: [
                  // Centre crosshair
                  Center(
                    child: Container(
                      width: 2,
                      height: 20,
                      color: HeliosColors.border,
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 20,
                      height: 2,
                      color: HeliosColors.border,
                    ),
                  ),
                  // Indicator dot (shows commanded position)
                  Positioned(
                    left: 90 + (_cmdYaw / 180) * 70 - 4,
                    top: 50 - (_cmdPitch / 90) * 40 - 4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: HeliosColors.accent,
                        boxShadow: [
                          BoxShadow(
                            color: HeliosColors.accent.withValues(alpha: 0.4),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Label
                  const Positioned(
                    bottom: 4,
                    left: 0,
                    right: 0,
                    child: Text(
                      'Drag to control',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 9, color: HeliosColors.textTertiary),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 6),

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Row(
              children: [
                _ActionButton(
                  icon: Icons.center_focus_strong,
                  label: 'Centre',
                  onTap: () {
                    setState(() {
                      _cmdPitch = 0;
                      _cmdYaw = 0;
                    });
                    ref
                        .read(connectionControllerProvider.notifier)
                        .controlGimbal(pitch: 0, yaw: 0);
                  },
                ),
                const SizedBox(width: 6),
                _ActionButton(
                  icon: Icons.camera_alt,
                  label: 'Capture',
                  onTap: () => ref
                      .read(connectionControllerProvider.notifier)
                      .triggerCamera(),
                ),
                const SizedBox(width: 6),
                _ActionButton(
                  icon: Icons.arrow_downward,
                  label: 'Nadir',
                  onTap: () {
                    setState(() {
                      _cmdPitch = -90;
                      _cmdYaw = 0;
                    });
                    ref
                        .read(connectionControllerProvider.notifier)
                        .controlGimbal(pitch: -90, yaw: 0);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GimbalToggleButton extends StatelessWidget {
  const _GimbalToggleButton({required this.pitch, required this.onTap});

  final double pitch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: HeliosColors.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: HeliosColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.control_camera,
                size: 14, color: HeliosColors.accent),
            const SizedBox(width: 4),
            Text(
              'P:${pitch.toStringAsFixed(0)}\u00B0',
              style: HeliosTypography.caption
                  .copyWith(color: HeliosColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _AngleReadout extends StatelessWidget {
  const _AngleReadout({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label:',
            style: const TextStyle(
                fontSize: 11, color: HeliosColors.textTertiary)),
        const SizedBox(width: 2),
        Text('${value.toStringAsFixed(1)}\u00B0',
            style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: HeliosColors.textPrimary)),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: HeliosColors.surfaceLight,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: HeliosColors.border),
          ),
          child: Column(
            children: [
              Icon(icon, size: 14, color: HeliosColors.textSecondary),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      fontSize: 9, color: HeliosColors.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}
