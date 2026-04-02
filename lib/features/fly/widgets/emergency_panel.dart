import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';
import '../../../shared/widgets/notification_overlay.dart';

/// Expandable emergency actions panel with kill switch, emergency land/RTL,
/// and autopilot reboot. Shown as a small "SOS" button that expands.
class EmergencyPanel extends ConsumerStatefulWidget {
  const EmergencyPanel({super.key});

  @override
  ConsumerState<EmergencyPanel> createState() => _EmergencyPanelState();
}

class _EmergencyPanelState extends ConsumerState<EmergencyPanel>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _animController;
  late final Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  void _logAlert(String message) {
    ref.read(alertHistoryProvider.notifier).add(AlertEntry(
          message: message,
          severity: AlertSeverity.critical,
          timestamp: DateTime.now(),
        ));
    ref.read(notificationProvider.notifier).add(
          message,
          NotificationSeverity.error,
        );
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final connected = ref.watch(connectionStatusProvider).transportState ==
        TransportState.connected;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // SOS toggle button
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _expanded
                    ? hc.danger.withValues(alpha: 0.2)
                    : hc.surfaceDim.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _expanded
                      ? hc.danger.withValues(alpha: 0.6)
                      : hc.border.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_rounded,
                    size: 14,
                    color: _expanded ? hc.danger : hc.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'SOS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _expanded ? hc.danger : hc.warning,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: _expanded ? hc.danger : hc.textTertiary,
                  ),
                ],
              ),
            ),
          ),
        ),

        // Expanded emergency actions
        SizeTransition(
          sizeFactor: _expandAnimation,
          axisAlignment: -1.0,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 200,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: hc.surfaceDim.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: hc.danger.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Kill Switch — double-tap required
                  _KillSwitchButton(
                    enabled: connected && vehicle.armed,
                    onActivate: () => _confirmKill(context, ref, vehicle),
                  ),
                  const SizedBox(height: 6),
                  // Emergency Land
                  _EmergencyButton(
                    label: 'EMERGENCY LAND',
                    icon: Icons.flight_land,
                    color: hc.warning,
                    enabled: connected && vehicle.armed,
                    onTap: () {
                      ref
                          .read(connectionControllerProvider.notifier)
                          .sendLand();
                      _logAlert('Emergency LAND activated');
                    },
                  ),
                  const SizedBox(height: 4),
                  // Emergency RTL
                  _EmergencyButton(
                    label: 'EMERGENCY RTL',
                    icon: Icons.home,
                    color: const Color(0xFFE8C43A),
                    enabled: connected && vehicle.armed,
                    onTap: () {
                      ref
                          .read(connectionControllerProvider.notifier)
                          .sendRtl();
                      _logAlert('Emergency RTL activated');
                    },
                  ),
                  const SizedBox(height: 4),
                  // Reboot Autopilot
                  _EmergencyButton(
                    label: 'REBOOT AUTOPILOT',
                    icon: Icons.restart_alt,
                    color: hc.textSecondary,
                    enabled: connected && !vehicle.armed,
                    onTap: () => _confirmReboot(context, ref),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmKill(BuildContext context, WidgetRef ref, VehicleState vehicle) {
    final hc = context.hc;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: hc.surface,
        title: Row(
          children: [
            Icon(Icons.dangerous, color: hc.danger, size: 22),
            const SizedBox(width: 8),
            Text('KILL SWITCH', style: HeliosTypography.heading2),
          ],
        ),
        content: Text(
          'This will immediately stop all motors.\n\n'
          'The vehicle WILL crash if airborne.\n\n'
          'Are you sure?',
          style: TextStyle(color: hc.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: hc.danger),
            onPressed: () {
              Navigator.pop(ctx);
              // Force disarm: param2=21196 is the magic force-disarm value.
              ref
                  .read(connectionControllerProvider.notifier)
                  .sendCommandWithRetry(
                    command: MavCmd.componentArmDisarm,
                    param1: 0, // disarm
                    param2: 21196, // force
                  );
              _logAlert('KILL SWITCH activated — motors forced off');
            },
            child: const Text('KILL MOTORS'),
          ),
        ],
      ),
    );
  }

  void _confirmReboot(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: hc.surface,
        title: Text('Reboot Autopilot?', style: HeliosTypography.heading2),
        content: Text(
          'This will reboot the flight controller. '
          'Only available when disarmed.',
          style: TextStyle(color: hc.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref
                  .read(connectionControllerProvider.notifier)
                  .sendCommandWithRetry(
                    command: MavCmd.preflightRebootShutdown,
                    param1: 1, // reboot autopilot
                  );
              _logAlert('Autopilot reboot commanded');
            },
            child: const Text('Reboot'),
          ),
        ],
      ),
    );
  }
}

// ─── Kill Switch Button (double-tap) ─────────────────────────────────────────

class _KillSwitchButton extends StatefulWidget {
  const _KillSwitchButton({
    required this.enabled,
    required this.onActivate,
  });

  final bool enabled;
  final VoidCallback onActivate;

  @override
  State<_KillSwitchButton> createState() => _KillSwitchButtonState();
}

class _KillSwitchButtonState extends State<_KillSwitchButton> {
  bool _firstTap = false;

  void _handleTap() {
    if (!widget.enabled) return;

    if (_firstTap) {
      widget.onActivate();
      setState(() => _firstTap = false);
    } else {
      setState(() => _firstTap = true);
      // Reset after 3 seconds if second tap not received.
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _firstTap = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final color = widget.enabled ? hc.danger : hc.textTertiary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _firstTap
                ? hc.danger.withValues(alpha: 0.3)
                : color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _firstTap
                  ? hc.danger
                  : color.withValues(alpha: 0.4),
              width: _firstTap ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dangerous, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _firstTap ? 'TAP AGAIN TO KILL' : 'KILL SWITCH',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Emergency Button ───────────────────────────────────────────────────────

class _EmergencyButton extends StatelessWidget {
  const _EmergencyButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        enabled ? color : context.hc.textTertiary.withValues(alpha: 0.5);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: effectiveColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: effectiveColor.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: effectiveColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: effectiveColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
