import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';

import '../../../shared/widgets/notification_overlay.dart';

/// State provider to toggle the quick-actions drawer open/closed.
final quickActionsOpenProvider = StateProvider<bool>((ref) => false);

/// Slide-out drawer with a grid of common in-flight action tiles.
class QuickActionsGrid extends ConsumerWidget {
  const QuickActionsGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOpen = ref.watch(quickActionsOpenProvider);
    final hc = context.hc;

    return AnimatedSlide(
      offset: isOpen ? Offset.zero : const Offset(1.0, 0.0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: isOpen ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 150),
        child: IgnorePointer(
          ignoring: !isOpen,
          child: Container(
            width: 200,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: hc.surfaceDim.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: hc.border.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(-2, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Icon(Icons.grid_view, size: 12, color: hc.accent),
                    const SizedBox(width: 5),
                    Text(
                      'QUICK ACTIONS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: hc.accent,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => ref
                          .read(quickActionsOpenProvider.notifier)
                          .state = false,
                      child:
                          Icon(Icons.close, size: 14, color: hc.textTertiary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Grid
                _ActionGrid(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Toggle button for the quick-actions drawer (placed on the Fly View).
class QuickActionsToggle extends ConsumerWidget {
  const QuickActionsToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOpen = ref.watch(quickActionsOpenProvider);
    final hc = context.hc;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () =>
            ref.read(quickActionsOpenProvider.notifier).state = !isOpen,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isOpen
                ? hc.accent.withValues(alpha: 0.15)
                : hc.surfaceDim.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isOpen
                  ? hc.accent.withValues(alpha: 0.5)
                  : hc.border.withValues(alpha: 0.6),
            ),
          ),
          child: Icon(
            Icons.grid_view,
            size: 16,
            color: isOpen ? hc.accent : hc.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ─── Action Grid ─────────────────────────────────────────────────────────────

class _ActionGrid extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final connected = ref.watch(connectionStatusProvider).transportState ==
        TransportState.connected;
    final armed = vehicle.armed;

    final actions = _buildActions(
      hc: hc,
      ref: ref,
      vehicle: vehicle,
      connected: connected,
      armed: armed,
    );

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: actions
          .map((a) => SizedBox(
                width: 90,
                child: _ActionTile(action: a),
              ))
          .toList(),
    );
  }

  List<_QuickAction> _buildActions({
    required HeliosColors hc,
    required WidgetRef ref,
    required VehicleState vehicle,
    required bool connected,
    required bool armed,
  }) {
    return [
      _QuickAction(
        icon: Icons.home_work,
        label: 'Set Home Here',
        color: hc.accent,
        enabled: connected && armed && vehicle.hasPosition,
        onTap: () {
          ref.read(connectionControllerProvider.notifier).sendCommandWithRetry(
                command: MavCmd.doSetHome,
                param1: 0, // use specified location
                param5: vehicle.latitude,
                param6: vehicle.longitude,
                param7: vehicle.altitudeMsl,
              );
          ref.read(notificationProvider.notifier).add(
                'Home position updated to current location',
                NotificationSeverity.success,
              );
        },
      ),
      _QuickAction(
        icon: Icons.camera_alt,
        label: 'Camera Trigger',
        color: hc.textPrimary,
        enabled: connected,
        onTap: () {
          ref.read(connectionControllerProvider.notifier).triggerCamera();
          ref.read(notificationProvider.notifier).add(
                'Camera triggered',
                NotificationSeverity.info,
              );
        },
      ),
      _QuickAction(
        icon: Icons.videocam,
        label: 'Start Video',
        color: hc.danger,
        enabled: connected,
        onTap: () {
          // MAV_CMD_VIDEO_START_CAPTURE (2500)
          // param1 = stream ID (0=all), param2 = status freq Hz
          ref.read(connectionControllerProvider.notifier).sendCommandWithRetry(
                command: 2500,
                param1: 0,
                param2: 1,
              );
          ref.read(notificationProvider.notifier).add(
                'Video recording started',
                NotificationSeverity.success,
              );
        },
      ),
      _QuickAction(
        icon: Icons.stop,
        label: 'Stop Video',
        color: hc.warning,
        enabled: connected,
        onTap: () {
          // MAV_CMD_VIDEO_STOP_CAPTURE (2501)
          ref.read(connectionControllerProvider.notifier).sendCommandWithRetry(
                command: 2501,
                param1: 0,
              );
          ref.read(notificationProvider.notifier).add(
                'Video recording stopped',
                NotificationSeverity.info,
              );
        },
      ),
      _QuickAction(
        icon: Icons.gps_fixed,
        label: 'Set ROI',
        color: hc.accent,
        enabled: connected && armed && vehicle.hasPosition,
        onTap: () {
          // Set ROI at current vehicle position (for gimbal pointing)
          ref.read(connectionControllerProvider.notifier).sendCommandWithRetry(
                command: 195, // MAV_CMD_DO_SET_ROI_LOCATION
                param5: vehicle.latitude,
                param6: vehicle.longitude,
                param7: 0, // ground level
              );
          ref.read(notificationProvider.notifier).add(
                'ROI set at current position',
                NotificationSeverity.info,
              );
        },
      ),
      _QuickAction(
        icon: Icons.center_focus_weak,
        label: 'Gimbal Center',
        color: hc.textSecondary,
        enabled: connected,
        onTap: () {
          ref
              .read(connectionControllerProvider.notifier)
              .controlGimbal(pitch: 0, yaw: 0, roll: 0);
          ref.read(notificationProvider.notifier).add(
                'Gimbal centered',
                NotificationSeverity.info,
              );
        },
      ),
      _QuickAction(
        icon: Icons.gps_off,
        label: 'Clear ROI',
        color: hc.textTertiary,
        enabled: connected && armed,
        onTap: () {
          ref.read(connectionControllerProvider.notifier).sendCommandWithRetry(
                command: MavCmd.doSetRoiNone,
              );
          ref.read(notificationProvider.notifier).add(
                'ROI cleared',
                NotificationSeverity.info,
              );
        },
      ),
      _QuickAction(
        icon: Icons.fence,
        label: 'Toggle Fence',
        color: hc.warning,
        enabled: connected,
        onTap: () {
          _toggleFence(ref, vehicle);
        },
      ),
      _QuickAction(
        icon: Icons.refresh,
        label: 'Refresh Streams',
        color: hc.textSecondary,
        enabled: connected,
        onTap: () {
          // MAV_CMD_REQUEST_MESSAGE for common messages
          // Request GLOBAL_POSITION_INT (33), ATTITUDE (30), SYS_STATUS (1)
          final ctrl = ref.read(connectionControllerProvider.notifier);
          ctrl.sendCommandWithRetry(
            command: MavCmd.requestMessage,
            param1: 33,
          );
          ctrl.sendCommandWithRetry(
            command: MavCmd.requestMessage,
            param1: 30,
          );
          ctrl.sendCommandWithRetry(
            command: MavCmd.requestMessage,
            param1: 1,
          );
          ref.read(notificationProvider.notifier).add(
                'Data stream refresh requested',
                NotificationSeverity.info,
              );
        },
      ),
      _QuickAction(
        icon: Icons.pin_drop,
        label: 'Mark Waypoint',
        color: hc.success,
        enabled: connected && vehicle.hasPosition,
        onTap: () {
          // Save current position as an alert entry for user reference.
          final lat = vehicle.latitude.toStringAsFixed(6);
          final lon = vehicle.longitude.toStringAsFixed(6);
          final alt = vehicle.altitudeRel.toStringAsFixed(1);
          ref.read(alertHistoryProvider.notifier).add(AlertEntry(
                message: 'POI: $lat, $lon @ ${alt}m AGL',
                severity: AlertSeverity.info,
                timestamp: DateTime.now(),
              ));
          ref.read(notificationProvider.notifier).add(
                'Waypoint marked: $lat, $lon',
                NotificationSeverity.success,
              );
        },
      ),
      _QuickAction(
        icon: Icons.download,
        label: 'Download Mission',
        color: hc.accent,
        enabled: connected,
        onTap: () {
          ref.read(connectionControllerProvider.notifier).downloadMission();
          ref.read(notificationProvider.notifier).add(
                'Mission download started',
                NotificationSeverity.info,
              );
        },
      ),
    ];
  }

  void _toggleFence(WidgetRef ref, VehicleState vehicle) {
    final ctrl = ref.read(connectionControllerProvider.notifier);
    final paramService = ctrl.paramService;
    if (paramService == null) return;

    // Read current FENCE_ENABLE value from param cache, toggle it.
    final params = ref.read(paramCacheProvider);
    final current = params['FENCE_ENABLE']?.value ?? 0;
    final newValue = current == 0 ? 1.0 : 0.0;

    paramService.setParam(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      paramId: 'FENCE_ENABLE',
      value: newValue,
    );
    ref.read(notificationProvider.notifier).add(
          newValue == 1.0 ? 'Geofence enabled' : 'Geofence disabled',
          NotificationSeverity.warning,
        );
  }
}

// ─── Action Tile ─────────────────────────────────────────────────────────────

class _QuickAction {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final _QuickAction action;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final color =
        action.enabled ? action.color : hc.textTertiary.withValues(alpha: 0.4);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.enabled ? action.onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 18, color: color),
              const SizedBox(height: 3),
              Text(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: color,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
