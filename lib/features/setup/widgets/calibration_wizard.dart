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
    final isConnected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;
    final isRunning = _progress.state == CalibrationState.running;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Calibrate sensors before first flight. Keep the vehicle still during '
          'gyro/level calibration. Rotate it smoothly during compass calibration.',
          style: TextStyle(color: HeliosColors.textSecondary, fontSize: 12),
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
              color: _bgColor(),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _borderColor()),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _icon(),
                    const SizedBox(width: 8),
                    Text(
                      _title(),
                      style: TextStyle(
                        color: _color(),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (isRunning && _progress.completionPct > 0)
                      Text(
                        '${_progress.completionPct}%',
                        style: TextStyle(
                          color: _color(),
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
                    backgroundColor: HeliosColors.surfaceLight,
                    valueColor: AlwaysStoppedAnimation(_color()),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  _progress.message,
                  style: const TextStyle(color: HeliosColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],

        if (!isConnected)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Connect to a vehicle to calibrate sensors.',
              style: TextStyle(color: HeliosColors.textTertiary, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Color _color() => switch (_progress.state) {
    CalibrationState.running => HeliosColors.accent,
    CalibrationState.success => HeliosColors.success,
    CalibrationState.failed => HeliosColors.danger,
    _ => HeliosColors.textSecondary,
  };

  Color _bgColor() => switch (_progress.state) {
    CalibrationState.success => HeliosColors.success.withValues(alpha: 0.08),
    CalibrationState.failed => HeliosColors.danger.withValues(alpha: 0.08),
    _ => HeliosColors.surfaceLight,
  };

  Color _borderColor() => switch (_progress.state) {
    CalibrationState.success => HeliosColors.success.withValues(alpha: 0.3),
    CalibrationState.failed => HeliosColors.danger.withValues(alpha: 0.3),
    _ => HeliosColors.border,
  };

  Widget _icon() => switch (_progress.state) {
    CalibrationState.running => SizedBox(
        width: 16, height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: _color()),
      ),
    CalibrationState.success => Icon(Icons.check_circle, size: 16, color: _color()),
    CalibrationState.failed => Icon(Icons.error, size: 16, color: _color()),
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
