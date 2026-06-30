import 'package:flutter/material.dart';

import '../../../core/calibration/esc_calibration.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Guided semi-automatic ESC calibration section.
///
/// Renders the [EscCalStateMachine] snapshot as a stepped flow:
/// start → mandatory props-off confirmation → arm the calibration parameter →
/// power-cycle prompt → done. All throttle-affecting actions are gated behind
/// the props-off switch and refuse to run while the vehicle is armed; the
/// parent owns the state machine and performs the parameter writes.
class EscSemiAutoSection extends StatelessWidget {
  const EscSemiAutoSection({
    super.key,
    required this.snapshot,
    required this.armed,
    required this.onStart,
    required this.onPropsOff,
    required this.onArm,
    required this.onPowerCycled,
    required this.onCancel,
  });

  final EscCalSnapshot snapshot;
  final bool armed;
  final VoidCallback onStart;
  final ValueChanged<bool> onPropsOff;
  final VoidCallback onArm;
  final VoidCallback onPowerCycled;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final phase = snapshot.phase;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SEMI-AUTOMATIC CALIBRATION',
            style: HeliosTypography.caption.copyWith(
                color: hc.textTertiary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6)),
        const SizedBox(height: 4),
        Text(
          'Passes the throttle range through to all ESCs at once on the next '
          'boot so they learn their endpoints.',
          style: HeliosTypography.small.copyWith(color: hc.textTertiary),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: hc.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (armed) ...[
                EscBanner(
                  hc: hc,
                  icon: Icons.warning_amber_rounded,
                  color: hc.danger,
                  text: 'Vehicle is ARMED. Disarm before calibrating ESCs.',
                ),
                const SizedBox(height: 12),
              ],
              if (phase == EscCalPhase.idle)
                FilledButton.icon(
                  onPressed: armed ? null : onStart,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Start semi-automatic calibration'),
                  style: FilledButton.styleFrom(
                    backgroundColor: hc.accent,
                    foregroundColor: Colors.white,
                  ),
                )
              else ...[
                _PropsOffGate(
                  propsOff: snapshot.propsOff,
                  locked: phase == EscCalPhase.awaitingPowerCycle ||
                      phase == EscCalPhase.done,
                  onChanged: armed ? null : onPropsOff,
                ),
                const SizedBox(height: 12),
                if (snapshot.message.isNotEmpty)
                  Text(snapshot.message,
                      style: HeliosTypography.small
                          .copyWith(color: hc.textSecondary)),
                const SizedBox(height: 12),
                _flowActions(context, hc),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _flowActions(BuildContext context, HeliosColors hc) {
    switch (snapshot.phase) {
      case EscCalPhase.ready:
        return Row(
          children: [
            FilledButton.icon(
              onPressed: (!armed && snapshot.throttleAllowed) ? onArm : null,
              icon: const Icon(Icons.bolt, size: 18),
              label: const Text('Arm calibration'),
              style: FilledButton.styleFrom(
                backgroundColor: hc.warning,
                foregroundColor: Colors.black,
              ),
            ),
            const SizedBox(width: 12),
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        );
      case EscCalPhase.awaitingPowerCycle:
        return Row(
          children: [
            FilledButton.icon(
              onPressed: onPowerCycled,
              icon: const Icon(Icons.check, size: 18),
              label: const Text("I've power-cycled"),
              style: FilledButton.styleFrom(
                backgroundColor: hc.accent,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: onCancel,
              child: const Text('Cancel & restore'),
            ),
          ],
        );
      case EscCalPhase.done:
        return Row(
          children: [
            Icon(Icons.check_circle, size: 18, color: hc.success),
            const SizedBox(width: 8),
            Text('Done', style: TextStyle(color: hc.success)),
            const Spacer(),
            TextButton(onPressed: onStart, child: const Text('Restart')),
          ],
        );
      case EscCalPhase.awaitingPropsOff:
      case EscCalPhase.idle:
        return TextButton(onPressed: onCancel, child: const Text('Cancel'));
    }
  }
}

/// Mandatory props-off confirmation. Until this is checked, no throttle output
/// can be commanded and the calibration cannot be armed.
class _PropsOffGate extends StatelessWidget {
  const _PropsOffGate({
    required this.propsOff,
    required this.locked,
    required this.onChanged,
  });

  final bool propsOff;
  final bool locked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final color = propsOff ? hc.success : hc.danger;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            propsOff ? Icons.check_circle : Icons.warning_amber_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('REMOVE ALL PROPELLERS',
                    style: HeliosTypography.body.copyWith(
                        color: color, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  'ESC calibration passes throttle straight to the motors. '
                  'Confirm propellers are off before continuing.',
                  style:
                      HeliosTypography.small.copyWith(color: hc.textSecondary),
                ),
              ],
            ),
          ),
          Switch(
            value: propsOff,
            onChanged: locked ? null : onChanged,
            activeColor: hc.success,
          ),
        ],
      ),
    );
  }
}

/// Compact coloured info banner used across the ESC calibration UI.
class EscBanner extends StatelessWidget {
  const EscBanner({
    super.key,
    required this.hc,
    required this.icon,
    required this.color,
    required this.text,
  });

  final HeliosColors hc;
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: HeliosTypography.small.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
