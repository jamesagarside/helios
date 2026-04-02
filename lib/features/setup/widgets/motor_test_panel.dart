import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Motor test panel — select a motor, set throttle %, and spin it.
class MotorTestPanel extends ConsumerStatefulWidget {
  const MotorTestPanel({super.key});

  @override
  ConsumerState<MotorTestPanel> createState() => _MotorTestPanelState();
}

class _MotorTestPanelState extends ConsumerState<MotorTestPanel> {
  int? _selectedMotor; // 1-based motor index
  double _throttlePct = 5.0;
  int _durationSec = 2;
  bool _testing = false;
  String? _error;

  Future<void> _testMotor() async {
    if (_selectedMotor == null) return;
    final vehicle = ref.read(vehicleStateProvider);
    if (vehicle.armed) {
      setState(() => _error = 'Vehicle must be DISARMED to test motors.');
      return;
    }
    setState(() {
      _testing = true;
      _error = null;
    });
    try {
      final controller = ref.read(connectionControllerProvider.notifier);
      await controller.testMotor(
        motorIndex: _selectedMotor!,
        throttlePct: _throttlePct,
        durationSec: _durationSec.toDouble(),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Motor test failed: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _stopAll() async {
    setState(() => _error = null);
    try {
      final controller = ref.read(connectionControllerProvider.notifier);
      // Send motor test with 0 throttle to all motors to stop
      for (var i = 1; i <= 8; i++) {
        await controller.testMotor(
          motorIndex: i,
          throttlePct: 0,
          durationSec: 0,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Stop failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final connected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;
    final motorCount = _motorCountForType(vehicle.vehicleType);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Safety warning
          _SafetyBanner(hc: hc),
          const SizedBox(height: 16),

          // Armed check
          if (vehicle.armed)
            _WarningBanner(
              hc: hc,
              message: 'Vehicle is ARMED. Disarm before testing motors.',
            ),

          if (!connected)
            _WarningBanner(
              hc: hc,
              message: 'Not connected. Connect to a vehicle first.',
            ),

          const SizedBox(height: 16),

          // Motor layout diagram
          Text(
            'Motor Layout',
            style: HeliosTypography.heading2.copyWith(color: hc.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            _frameLabel(vehicle.vehicleType),
            style: HeliosTypography.caption.copyWith(color: hc.textSecondary),
          ),
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
              width: 260,
              height: 260,
              child: _MotorDiagram(
                vehicleType: vehicle.vehicleType,
                motorCount: motorCount,
                selectedMotor: _selectedMotor,
                testingMotor: _testing ? _selectedMotor : null,
                onMotorSelected: connected && !vehicle.armed
                    ? (m) => setState(() => _selectedMotor = m)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Throttle slider
          Text(
            'Throttle: ${_throttlePct.toStringAsFixed(0)}%',
            style: HeliosTypography.body.copyWith(color: hc.textPrimary),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('5%',
                  style: HeliosTypography.small.copyWith(
                      color: hc.textTertiary)),
              Expanded(
                child: Slider(
                  value: _throttlePct,
                  min: 5,
                  max: 15,
                  divisions: 10,
                  activeColor: hc.accent,
                  inactiveColor: hc.border,
                  onChanged: (v) => setState(() => _throttlePct = v),
                ),
              ),
              Text('15%',
                  style: HeliosTypography.small.copyWith(
                      color: hc.textTertiary)),
            ],
          ),
          Text(
            'Keep throttle between 5-15% for safe motor testing.',
            style: HeliosTypography.small.copyWith(color: hc.textTertiary),
          ),
          const SizedBox(height: 16),

          // Duration selector
          Text(
            'Duration: $_durationSec seconds',
            style: HeliosTypography.body.copyWith(color: hc.textPrimary),
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(5, (i) {
              final sec = i + 1;
              final selected = sec == _durationSec;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('${sec}s'),
                  selected: selected,
                  selectedColor: hc.accent.withValues(alpha: 0.2),
                  backgroundColor: hc.surface,
                  side: BorderSide(
                      color: selected ? hc.accent : hc.border),
                  labelStyle: TextStyle(
                    color: selected ? hc.accent : hc.textSecondary,
                    fontSize: 13,
                  ),
                  onSelected: (_) => setState(() => _durationSec = sec),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: connected &&
                          !vehicle.armed &&
                          _selectedMotor != null &&
                          !_testing
                      ? _testMotor
                      : null,
                  icon: _testing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: hc.textPrimary,
                          ),
                        )
                      : const Icon(Icons.play_arrow, size: 18),
                  label: Text(_testing
                      ? 'Testing Motor $_selectedMotor...'
                      : _selectedMotor != null
                          ? 'Test Motor $_selectedMotor'
                          : 'Select a Motor'),
                  style: FilledButton.styleFrom(
                    backgroundColor: hc.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: connected ? _stopAll : null,
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('Stop All'),
                style: FilledButton.styleFrom(
                  backgroundColor: hc.danger,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
              ),
            ],
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: HeliosTypography.small.copyWith(color: hc.danger),
            ),
          ],

          const SizedBox(height: 20),

          // Motor numbering reference
          _MotorNumberingReference(
              hc: hc, vehicleType: vehicle.vehicleType),
        ],
      ),
    );
  }

  static int _motorCountForType(VehicleType type) {
    return switch (type) {
      VehicleType.quadrotor => 4,
      VehicleType.helicopter => 1,
      _ => 4, // default to quad layout
    };
  }

  static String _frameLabel(VehicleType type) {
    return switch (type) {
      VehicleType.quadrotor => 'Quadcopter (X-frame)',
      VehicleType.helicopter => 'Helicopter',
      VehicleType.fixedWing => 'Fixed Wing',
      _ => 'Unknown frame',
    };
  }
}

// ─── Safety Banner ──────────────────────────────────────────────────────────

class _SafetyBanner extends StatelessWidget {
  const _SafetyBanner({required this.hc});
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hc.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: hc.danger, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'REMOVE ALL PROPELLERS',
                  style: HeliosTypography.heading2.copyWith(color: hc.danger),
                ),
                const SizedBox(height: 2),
                Text(
                  'Motor testing spins motors at the specified throttle. '
                  'Always remove propellers before testing.',
                  style: HeliosTypography.small.copyWith(
                      color: hc.danger.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.hc, required this.message});
  final HeliosColors hc;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hc.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: hc.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: HeliosTypography.small.copyWith(color: hc.warning),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Motor Diagram ──────────────────────────────────────────────────────────

/// Quad-X motor positions (normalised to 0..1 square).
/// ArduPilot numbering: FR=1, BL=2, FL=3, BR=4
const _quadPositions = [
  _MotorPos(0.75, 0.25, 1, 'FR'), // Motor 1 — front-right
  _MotorPos(0.25, 0.75, 2, 'BL'), // Motor 2 — back-left
  _MotorPos(0.25, 0.25, 3, 'FL'), // Motor 3 — front-left
  _MotorPos(0.75, 0.75, 4, 'BR'), // Motor 4 — back-right
];

class _MotorPos {
  const _MotorPos(this.x, this.y, this.number, this.label);
  final double x, y;
  final int number;
  final String label;
}

class _MotorDiagram extends StatelessWidget {
  const _MotorDiagram({
    required this.vehicleType,
    required this.motorCount,
    required this.selectedMotor,
    required this.testingMotor,
    required this.onMotorSelected,
  });

  final VehicleType vehicleType;
  final int motorCount;
  final int? selectedMotor;
  final int? testingMotor;
  final ValueChanged<int>? onMotorSelected;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return CustomPaint(
      painter: _FramePainter(hc: hc),
      child: Stack(
        children: [
          for (final motor in _quadPositions)
            Positioned(
              left: motor.x * 220 - 2,
              top: motor.y * 220 - 2,
              child: _MotorButton(
                motor: motor,
                isSelected: selectedMotor == motor.number,
                isTesting: testingMotor == motor.number,
                onTap: onMotorSelected != null
                    ? () => onMotorSelected!(motor.number)
                    : null,
              ),
            ),
          // Front indicator
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'FRONT',
                style: HeliosTypography.small.copyWith(
                  color: hc.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter({required this.hc});
  final HeliosColors hc;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final armPaint = Paint()
      ..color = hc.border
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Draw arms from center to each motor position
    for (final motor in _quadPositions) {
      final end = Offset(motor.x * 220 + 22, motor.y * 220 + 22);
      canvas.drawLine(center, end, armPaint);
    }

    // Draw center body
    final bodyPaint = Paint()..color = hc.surfaceLight;
    canvas.drawCircle(center, 18, bodyPaint);
    final bodyBorder = Paint()
      ..color = hc.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, 18, bodyBorder);

    // Draw front direction indicator
    final arrowPaint = Paint()
      ..color = hc.accent
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx, center.dy - 18),
      Offset(center.dx, center.dy - 35),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - 35),
      Offset(center.dx - 6, center.dy - 28),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - 35),
      Offset(center.dx + 6, center.dy - 28),
      arrowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MotorButton extends StatelessWidget {
  const _MotorButton({
    required this.motor,
    required this.isSelected,
    required this.isTesting,
    required this.onTap,
  });

  final _MotorPos motor;
  final bool isSelected;
  final bool isTesting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final color = isTesting
        ? hc.warning
        : isSelected
            ? hc.accent
            : hc.textTertiary;

    // CW motors (1 FR, 2 BL) vs CCW motors (3 FL, 4 BR)
    final isCW = motor.number == 1 || motor.number == 2;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Spin direction ring
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.1),
                border: Border.all(color: color, width: isSelected ? 2.5 : 1.5),
              ),
            ),
            // Motor number
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${motor.number}',
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  motor.label,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.7),
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            // CW / CCW indicator
            Positioned(
              bottom: 0,
              child: Text(
                isCW ? 'CW' : 'CCW',
                style: TextStyle(
                  color: color.withValues(alpha: 0.5),
                  fontSize: 7,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Motor Numbering Reference ──────────────────────────────────────────────

class _MotorNumberingReference extends StatelessWidget {
  const _MotorNumberingReference({
    required this.hc,
    required this.vehicleType,
  });

  final HeliosColors hc;
  final VehicleType vehicleType;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Motor Numbering (ArduPilot Quad-X)',
            style: HeliosTypography.caption.copyWith(
              color: hc.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _numberRow(hc, 1, 'Front-Right', 'CW'),
          _numberRow(hc, 2, 'Back-Left', 'CW'),
          _numberRow(hc, 3, 'Front-Left', 'CCW'),
          _numberRow(hc, 4, 'Back-Right', 'CCW'),
        ],
      ),
    );
  }

  Widget _numberRow(HeliosColors hc, int num, String pos, String dir) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: hc.accent, width: 1.5),
            ),
            child: Text(
              '$num',
              style: TextStyle(
                  color: hc.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            pos,
            style: HeliosTypography.small.copyWith(color: hc.textPrimary),
          ),
          const Spacer(),
          Text(
            dir,
            style: HeliosTypography.small.copyWith(color: hc.textTertiary),
          ),
        ],
      ),
    );
  }
}
