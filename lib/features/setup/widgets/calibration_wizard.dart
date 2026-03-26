import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/calibration/calibration_service.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';

/// Sensor calibration wizard with step-by-step guidance.
class CalibrationWizard extends ConsumerStatefulWidget {
  const CalibrationWizard({super.key});

  @override
  ConsumerState<CalibrationWizard> createState() => _CalibrationWizardState();
}

class _CalibrationWizardState extends ConsumerState<CalibrationWizard> {
  CalibrationService? _calService;
  StreamSubscription<CalibrationProgress>? _progressSub;
  CalibrationProgress _progress = const CalibrationProgress();

  @override
  void dispose() {
    _progressSub?.cancel();
    _calService?.dispose();
    super.dispose();
  }

  void _ensureService() {
    if (_calService != null) return;
    final mavlink = ref.read(connectionControllerProvider.notifier).mavlinkService;
    if (mavlink == null) return;
    _calService = CalibrationService(mavlink);
    _progressSub = _calService!.progressStream.listen((p) {
      if (mounted) setState(() => _progress = p);
    });
  }

  void _startCal(CalibrationType type) {
    _ensureService();
    if (_calService == null) return;

    final vehicle = ref.read(vehicleStateProvider);
    final sys = vehicle.systemId;
    final comp = vehicle.componentId;

    switch (type) {
      case CalibrationType.compass:
        _calService!.startCompassCal(targetSystem: sys, targetComponent: comp);
      case CalibrationType.accel:
        _calService!.startAccelCal(targetSystem: sys, targetComponent: comp);
      case CalibrationType.gyro:
        _calService!.startGyroCal(targetSystem: sys, targetComponent: comp);
      case CalibrationType.level:
        _calService!.startLevelCal(targetSystem: sys, targetComponent: comp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final isConnected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;
    final isRunning = _progress.state == CalibrationState.running;
    final color = _color(hc);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Calibrate sensors before first flight. Keep the vehicle still during '
          'gyro/level calibration. Rotate it smoothly during compass calibration.',
          style: TextStyle(color: hc.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CalButton(
              icon: Icons.explore,
              label: 'Compass',
              onPressed: isConnected && !isRunning
                  ? () => _startCal(CalibrationType.compass) : null,
            ),
            _CalButton(
              icon: Icons.straighten,
              label: 'Accel',
              onPressed: isConnected && !isRunning
                  ? () => _startCal(CalibrationType.accel) : null,
            ),
            _CalButton(
              icon: Icons.sync,
              label: 'Gyro',
              onPressed: isConnected && !isRunning
                  ? () => _startCal(CalibrationType.gyro) : null,
            ),
            _CalButton(
              icon: Icons.horizontal_rule,
              label: 'Level',
              onPressed: isConnected && !isRunning
                  ? () => _startCal(CalibrationType.level) : null,
            ),
          ],
        ),

        if (_progress.state != CalibrationState.idle) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _bgColor(hc),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _borderColor(hc)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _icon(color),
                    const SizedBox(width: 8),
                    Text(
                      _title(),
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (isRunning && _progress.completionPct > 0)
                      Text(
                        '${_progress.completionPct}%',
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                  ],
                ),
                if (_progress.completionPct > 0 && isRunning) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _progress.completionPct / 100,
                    backgroundColor: hc.surfaceLight,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  _progress.message,
                  style: TextStyle(color: hc.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],

        if (!isConnected)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Connect to a vehicle to calibrate sensors.',
              style: TextStyle(color: hc.textTertiary, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Color _color(HeliosColors hc) => switch (_progress.state) {
    CalibrationState.running => hc.accent,
    CalibrationState.success => hc.success,
    CalibrationState.failed => hc.danger,
    _ => hc.textSecondary,
  };

  Color _bgColor(HeliosColors hc) => switch (_progress.state) {
    CalibrationState.success => hc.success.withValues(alpha: 0.08),
    CalibrationState.failed => hc.danger.withValues(alpha: 0.08),
    _ => hc.surfaceLight,
  };

  Color _borderColor(HeliosColors hc) => switch (_progress.state) {
    CalibrationState.success => hc.success.withValues(alpha: 0.3),
    CalibrationState.failed => hc.danger.withValues(alpha: 0.3),
    _ => hc.border,
  };

  Widget _icon(Color color) => switch (_progress.state) {
    CalibrationState.running => SizedBox(
        width: 16, height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
    CalibrationState.success => Icon(Icons.check_circle, size: 16, color: color),
    CalibrationState.failed => Icon(Icons.error, size: 16, color: color),
    _ => const SizedBox.shrink(),
  };

  String _title() => switch (_progress.state) {
    CalibrationState.running => '${_progress.type?.name.toUpperCase() ?? ''} Calibrating...',
    CalibrationState.success => 'Calibration Complete',
    CalibrationState.failed => 'Calibration Failed',
    _ => '',
  };
}

class _CalButton extends StatelessWidget {
  const _CalButton({required this.icon, required this.label, this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}
