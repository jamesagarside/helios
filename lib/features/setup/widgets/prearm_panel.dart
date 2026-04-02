import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Pre-arm status panel — shows sensor health from SYS_STATUS bitmasks
/// and pre-arm failure messages from STATUSTEXT.
class PreArmPanel extends ConsumerWidget {
  const PreArmPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final alerts = ref.watch(alertHistoryProvider);
    final connected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;

    final hasSensorData = vehicle.sensorPresent != 0;

    // Filter pre-arm failure messages from STATUSTEXT
    final preArmMessages = alerts
        .where((a) =>
            a.message.startsWith('PreArm:') ||
            a.message.startsWith('Arm:') ||
            a.message.contains('prearm'))
        .toList()
        .reversed
        .take(20)
        .toList();

    // Overall pre-arm status
    const preArmBit = 0x20000000; // MAV_SYS_STATUS_PREARM_CHECK
    final preArmOk =
        hasSensorData && vehicle.isSensorHealthy(preArmBit);
    final allSensorsHealthy = _sensors.every((s) =>
        !vehicle.isSensorPresent(s.bit) || vehicle.isSensorHealthy(s.bit));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overall status banner
          _OverallStatusBanner(
            hc: hc,
            connected: connected,
            hasSensorData: hasSensorData,
            preArmOk: preArmOk,
            allSensorsHealthy: allSensorsHealthy,
          ),
          const SizedBox(height: 16),

          // Sensor health grid
          Text(
            'Sensor Health',
            style: HeliosTypography.heading2.copyWith(color: hc.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'From SYS_STATUS onboard sensor bitmasks.',
            style: HeliosTypography.small.copyWith(color: hc.textTertiary),
          ),
          const SizedBox(height: 12),

          if (!connected)
            _InfoBox(hc: hc, message: 'Connect to see sensor health.'),

          if (connected && !hasSensorData)
            _InfoBox(
                hc: hc, message: 'Waiting for SYS_STATUS message...'),

          if (hasSensorData)
            Container(
              decoration: BoxDecoration(
                color: hc.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: hc.border),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: hc.surfaceLight,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(7)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Sensor',
                            style: HeliosTypography.caption.copyWith(
                              color: hc.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        _HeaderCell(hc: hc, label: 'Present'),
                        _HeaderCell(hc: hc, label: 'Enabled'),
                        _HeaderCell(hc: hc, label: 'Healthy'),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: hc.border),
                  // Sensor rows
                  for (var i = 0; i < _sensors.length; i++) ...[
                    _SensorRow(
                      hc: hc,
                      sensor: _sensors[i],
                      present: vehicle.isSensorPresent(_sensors[i].bit),
                      enabled: vehicle.isSensorEnabled(_sensors[i].bit),
                      healthy: vehicle.isSensorHealthy(_sensors[i].bit),
                    ),
                    if (i < _sensors.length - 1)
                      Divider(height: 1, color: hc.border),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 20),

          // Pre-arm failure messages
          Text(
            'Pre-arm Messages',
            style: HeliosTypography.heading2.copyWith(color: hc.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Recent pre-arm failure messages from STATUSTEXT.',
            style: HeliosTypography.small.copyWith(color: hc.textTertiary),
          ),
          const SizedBox(height: 12),

          if (preArmMessages.isEmpty)
            _InfoBox(
              hc: hc,
              message: connected
                  ? 'No pre-arm failure messages received.'
                  : 'Connect to see pre-arm messages.',
            ),

          if (preArmMessages.isNotEmpty)
            Container(
              decoration: BoxDecoration(
                color: hc.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: hc.border),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < preArmMessages.length; i++) ...[
                    _PreArmMessageRow(
                      hc: hc,
                      alert: preArmMessages[i],
                    ),
                    if (i < preArmMessages.length - 1)
                      Divider(height: 1, color: hc.border),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 20),

          // Refresh hint
          if (connected)
            Center(
              child: Text(
                'Sensor status updates automatically from SYS_STATUS messages.',
                style: HeliosTypography.small
                    .copyWith(color: hc.textTertiary),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Sensor definitions ─────────────────────────────────────────────────────

class _SensorDef {
  const _SensorDef(this.bit, this.label, this.icon);
  final int bit;
  final String label;
  final IconData icon;
}

const _sensors = [
  _SensorDef(0x01, '3D Gyro', Icons.rotate_right),
  _SensorDef(0x02, '3D Accelerometer', Icons.speed),
  _SensorDef(0x04, '3D Magnetometer', Icons.explore),
  _SensorDef(0x08, 'Barometer', Icons.compress),
  _SensorDef(0x10, 'Differential Pressure', Icons.air),
  _SensorDef(0x20, 'GPS', Icons.gps_fixed),
  _SensorDef(0x40, 'Optical Flow', Icons.camera),
  _SensorDef(0x80, 'Vision Position', Icons.visibility),
  _SensorDef(0x100, 'Laser Position', Icons.sensors),
  _SensorDef(0x400, 'Rate Controller', Icons.tune),
  _SensorDef(0x800, 'Attitude Stabilization', Icons.straighten),
  _SensorDef(0x1000, 'Yaw Position', Icons.navigation),
  _SensorDef(0x2000, 'Z/Altitude Control', Icons.height),
  _SensorDef(0x4000, 'XY Position Control', Icons.control_camera),
  _SensorDef(0x8000, 'Motor Outputs', Icons.settings_input_component),
  _SensorDef(0x10000, 'RC Receiver', Icons.settings_remote),
  _SensorDef(0x04000000, 'AHRS', Icons.screen_rotation),
  _SensorDef(0x08000000, 'Terrain', Icons.terrain),
  _SensorDef(0x20000000, 'Pre-arm Check', Icons.verified),
  _SensorDef(0x40000000, 'Logging', Icons.save),
  _SensorDef(0x80000000, 'Battery', Icons.battery_full),
];

// ─── Overall Status Banner ──────────────────────────────────────────────────

class _OverallStatusBanner extends StatelessWidget {
  const _OverallStatusBanner({
    required this.hc,
    required this.connected,
    required this.hasSensorData,
    required this.preArmOk,
    required this.allSensorsHealthy,
  });

  final HeliosColors hc;
  final bool connected;
  final bool hasSensorData;
  final bool preArmOk;
  final bool allSensorsHealthy;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String label;
    final String detail;

    if (!connected) {
      color = hc.textTertiary;
      icon = Icons.link_off;
      label = 'Disconnected';
      detail = 'Connect to a vehicle to check pre-arm status.';
    } else if (!hasSensorData) {
      color = hc.textTertiary;
      icon = Icons.hourglass_empty;
      label = 'Waiting';
      detail = 'Waiting for sensor data from the flight controller.';
    } else if (preArmOk && allSensorsHealthy) {
      color = hc.success;
      icon = Icons.check_circle;
      label = 'Ready to Arm';
      detail = 'All sensors healthy. Pre-arm checks passed.';
    } else if (allSensorsHealthy) {
      color = hc.warning;
      icon = Icons.warning;
      label = 'Sensors OK, Pre-arm Failing';
      detail = 'All sensors healthy but pre-arm check is not passing.';
    } else {
      color = hc.danger;
      icon = Icons.cancel;
      label = 'Not Ready';
      detail = 'One or more sensors are unhealthy.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: HeliosTypography.heading2.copyWith(color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: HeliosTypography.small.copyWith(
                      color: color.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header Cell ────────────────────────────────────────────────────────────

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.hc, required this.label});
  final HeliosColors hc;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      child: Text(
        label,
        style: HeliosTypography.caption.copyWith(
          color: hc.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─── Sensor Row ─────────────────────────────────────────────────────────────

class _SensorRow extends StatelessWidget {
  const _SensorRow({
    required this.hc,
    required this.sensor,
    required this.present,
    required this.enabled,
    required this.healthy,
  });

  final HeliosColors hc;
  final _SensorDef sensor;
  final bool present;
  final bool enabled;
  final bool healthy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            sensor.icon,
            size: 16,
            color: present
                ? (healthy ? hc.success : hc.danger)
                : hc.textTertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              sensor.label,
              style: HeliosTypography.caption.copyWith(
                color: present ? hc.textPrimary : hc.textTertiary,
              ),
            ),
          ),
          _StatusIcon(hc: hc, value: present, dimIfFalse: true),
          _StatusIcon(hc: hc, value: enabled, dimIfFalse: !present),
          _StatusIcon(
            hc: hc,
            value: healthy,
            dimIfFalse: !present,
            showWarning: present && !healthy,
          ),
        ],
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.hc,
    required this.value,
    this.dimIfFalse = false,
    this.showWarning = false,
  });

  final HeliosColors hc;
  final bool value;
  final bool dimIfFalse;
  final bool showWarning;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;

    if (showWarning) {
      color = hc.danger;
      icon = Icons.cancel;
    } else if (value) {
      color = hc.success;
      icon = Icons.check_circle;
    } else if (dimIfFalse) {
      color = hc.textTertiary.withValues(alpha: 0.3);
      icon = Icons.remove_circle_outline;
    } else {
      color = hc.warning;
      icon = Icons.warning;
    }

    return SizedBox(
      width: 68,
      child: Icon(icon, size: 16, color: color),
    );
  }
}

// ─── Pre-arm Message Row ────────────────────────────────────────────────────

class _PreArmMessageRow extends StatelessWidget {
  const _PreArmMessageRow({required this.hc, required this.alert});
  final HeliosColors hc;
  final AlertEntry alert;

  @override
  Widget build(BuildContext context) {
    final isCritical = alert.severity == AlertSeverity.critical;
    final color = isCritical ? hc.danger : hc.warning;
    final timeStr =
        '${alert.timestamp.hour.toString().padLeft(2, '0')}:'
        '${alert.timestamp.minute.toString().padLeft(2, '0')}:'
        '${alert.timestamp.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            isCritical ? Icons.error : Icons.warning_amber_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              alert.message,
              style: HeliosTypography.caption.copyWith(color: hc.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            timeStr,
            style: HeliosTypography.small.copyWith(
              color: hc.textTertiary,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Info Box ───────────────────────────────────────────────────────────────

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.hc, required this.message});
  final HeliosColors hc;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hc.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: hc.textTertiary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: HeliosTypography.small.copyWith(color: hc.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
