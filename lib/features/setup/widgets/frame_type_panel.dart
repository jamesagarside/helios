import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/params/parameter_service.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Frame type selection panel — set FRAME_CLASS and FRAME_TYPE params.
class FrameTypePanel extends ConsumerStatefulWidget {
  const FrameTypePanel({super.key});

  @override
  ConsumerState<FrameTypePanel> createState() => _FrameTypePanelState();
}

// ArduPilot FRAME_CLASS values
const _frameClasses = <int, _FrameClassDef>{
  0: _FrameClassDef('Undefined', Icons.help_outline, 0),
  1: _FrameClassDef('Quad', Icons.flight, 4),
  2: _FrameClassDef('Hexa', Icons.flight, 6),
  3: _FrameClassDef('Octo', Icons.flight, 8),
  4: _FrameClassDef('OctoQuad', Icons.flight, 8),
  5: _FrameClassDef('Y6', Icons.flight, 6),
  7: _FrameClassDef('Tri', Icons.flight, 3),
  8: _FrameClassDef('Single / Heli', Icons.air, 1),
  9: _FrameClassDef('Coax / Heli Dual', Icons.air, 2),
  11: _FrameClassDef('Heli Quad', Icons.air, 4),
  13: _FrameClassDef('Hex Plus', Icons.flight, 6),
  14: _FrameClassDef('Y6B', Icons.flight, 6),
  15: _FrameClassDef('Deca', Icons.flight, 10),
};

// ArduPilot FRAME_TYPE values
const _frameTypes = <int, String>{
  0: 'Plus (+)',
  1: 'X',
  2: 'V',
  3: 'H',
  4: 'V-Tail',
  5: 'A-Tail',
  10: 'Y6B',
  11: 'Y6F',
  12: 'BetaFlightX',
  13: 'DJIX',
  14: 'CW X',
  18: 'BetaFlightXReversed',
};

class _FrameClassDef {
  const _FrameClassDef(this.label, this.icon, this.motorCount);
  final String label;
  final IconData icon;
  final int motorCount;
}

class _FrameTypePanelState extends ConsumerState<FrameTypePanel> {
  int? _pendingClass;
  int? _pendingType;
  bool _writing = false;
  String? _error;

  int _currentClass(Map<String, Parameter> params) {
    return _pendingClass ?? (params['FRAME_CLASS']?.value.toInt() ?? 0);
  }

  int _currentType(Map<String, Parameter> params) {
    return _pendingType ?? (params['FRAME_TYPE']?.value.toInt() ?? 1);
  }

  Future<void> _writeParam(String name, double value) async {
    final controller = ref.read(connectionControllerProvider.notifier);
    final paramService = controller.paramService;
    if (paramService == null) return;

    final vehicle = ref.read(vehicleStateProvider);
    final params = ref.read(paramCacheProvider);
    setState(() {
      _writing = true;
      _error = null;
    });
    try {
      await paramService.setParam(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
        paramId: name,
        value: value,
        paramType: params[name]?.type ?? 9,
      );
      // Update cache
      final cached = Map<String, Parameter>.from(ref.read(paramCacheProvider));
      if (cached.containsKey(name)) {
        cached[name] = cached[name]!.copyWith(value: value);
        ref.read(paramCacheProvider.notifier).state = cached;
      }
      if (mounted) {
        setState(() {
          if (name == 'FRAME_CLASS') _pendingClass = null;
          if (name == 'FRAME_TYPE') _pendingType = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final params = ref.watch(paramCacheProvider);
    final connected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;
    final hasParams = params.isNotEmpty;
    final selectedClass = _currentClass(params);
    final selectedType = _currentType(params);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select the airframe configuration. This sets FRAME_CLASS and '
            'FRAME_TYPE parameters on the flight controller.',
            style: HeliosTypography.small.copyWith(color: hc.textSecondary),
          ),
          const SizedBox(height: 12),

          if (vehicle.armed)
            _WarningBox(
              hc: hc,
              message:
                  'Vehicle is ARMED. Do not change frame type while armed.',
            ),

          if (!connected || !hasParams)
            _WarningBox(
              hc: hc,
              message: !connected
                  ? 'Connect to a vehicle to configure frame type.'
                  : 'Waiting for parameters to load...',
            ),
          const SizedBox(height: 12),

          // Current frame info
          if (hasParams) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hc.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: hc.border),
              ),
              child: Row(
                children: [
                  Icon(
                    _frameClasses[selectedClass]?.icon ?? Icons.help_outline,
                    size: 32,
                    color: hc.accent,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _frameClasses[selectedClass]?.label ?? 'Unknown',
                        style: HeliosTypography.heading2
                            .copyWith(color: hc.textPrimary),
                      ),
                      Text(
                        'Frame Type: ${_frameTypes[selectedType] ?? 'Unknown'} '
                        '(Class=$selectedClass, Type=$selectedType)',
                        style: HeliosTypography.small
                            .copyWith(color: hc.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Motor layout preview
            Text(
              'Motor Layout Preview',
              style:
                  HeliosTypography.heading2.copyWith(color: hc.textPrimary),
            ),
            const SizedBox(height: 8),
            Center(
              child: SizedBox(
                width: 200,
                height: 200,
                child: CustomPaint(
                  painter: _FrameDiagramPainter(
                    hc: hc,
                    motorCount:
                        _frameClasses[selectedClass]?.motorCount ?? 4,
                    isXFrame: selectedType == 1 ||
                        selectedType == 12 ||
                        selectedType == 13 ||
                        selectedType == 14,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Frame class selection
            Text(
              'Frame Class',
              style:
                  HeliosTypography.heading2.copyWith(color: hc.textPrimary),
            ),
            const SizedBox(height: 8),
            _FrameClassGrid(
              hc: hc,
              selectedClass: selectedClass,
              enabled: connected && !vehicle.armed && !_writing,
              onSelected: (cls) {
                setState(() => _pendingClass = cls);
                _writeParam('FRAME_CLASS', cls.toDouble());
              },
            ),
            const SizedBox(height: 20),

            // Frame type selection
            Text(
              'Frame Type',
              style:
                  HeliosTypography.heading2.copyWith(color: hc.textPrimary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _frameTypes.entries.map((e) {
                final sel = e.key == selectedType;
                return ChoiceChip(
                  label: Text(e.value),
                  selected: sel,
                  selectedColor: hc.accent.withValues(alpha: 0.2),
                  backgroundColor: hc.surface,
                  side: BorderSide(color: sel ? hc.accent : hc.border),
                  labelStyle: TextStyle(
                    color: sel ? hc.accent : hc.textSecondary,
                    fontSize: 12,
                  ),
                  onSelected: connected && !vehicle.armed && !_writing
                      ? (_) {
                          setState(() => _pendingType = e.key);
                          _writeParam('FRAME_TYPE', e.key.toDouble());
                        }
                      : null,
                );
              }).toList(),
            ),

            if (_writing) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: hc.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Writing parameter...',
                    style: HeliosTypography.small
                        .copyWith(color: hc.textSecondary),
                  ),
                ],
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: HeliosTypography.small.copyWith(color: hc.danger),
              ),
            ],

            const SizedBox(height: 20),

            // Reboot notice
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hc.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: hc.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.restart_alt, color: hc.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Changing the frame class or type requires a flight '
                      'controller reboot to take effect.',
                      style: HeliosTypography.small
                          .copyWith(color: hc.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Warning Box ────────────────────────────────────────────────────────────

class _WarningBox extends StatelessWidget {
  const _WarningBox({required this.hc, required this.message});
  final HeliosColors hc;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hc.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: hc.warning, size: 18),
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

// ─── Frame Class Grid ───────────────────────────────────────────────────────

class _FrameClassGrid extends StatelessWidget {
  const _FrameClassGrid({
    required this.hc,
    required this.selectedClass,
    required this.enabled,
    required this.onSelected,
  });

  final HeliosColors hc;
  final int selectedClass;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final entries = _frameClasses.entries
        .where((e) => e.key != 0) // skip "Undefined"
        .toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entries.map((e) {
        final sel = e.key == selectedClass;
        return GestureDetector(
          onTap: enabled ? () => onSelected(e.key) : null,
          child: Container(
            width: 110,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: sel
                  ? hc.accent.withValues(alpha: 0.12)
                  : hc.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: sel ? hc.accent : hc.border,
                width: sel ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  e.value.icon,
                  size: 28,
                  color: sel ? hc.accent : hc.textSecondary,
                ),
                const SizedBox(height: 4),
                Text(
                  e.value.label,
                  style: TextStyle(
                    color: sel ? hc.accent : hc.textPrimary,
                    fontSize: 11,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
                Text(
                  '${e.value.motorCount} motors',
                  style: TextStyle(
                    color: hc.textTertiary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Frame Diagram Painter ──────────────────────────────────────────────────

class _FrameDiagramPainter extends CustomPainter {
  const _FrameDiagramPainter({
    required this.hc,
    required this.motorCount,
    required this.isXFrame,
  });

  final HeliosColors hc;
  final int motorCount;
  final bool isXFrame;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.38;

    final armPaint = Paint()
      ..color = hc.border
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final motorPaint = Paint()..color = hc.accent;
    final motorBorderPaint = Paint()
      ..color = hc.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Body
    final bodyPaint = Paint()..color = hc.surfaceLight;
    canvas.drawCircle(center, 14, bodyPaint);
    canvas.drawCircle(
        center,
        14,
        Paint()
          ..color = hc.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    // Motor positions
    final count = motorCount.clamp(1, 12);
    final offset = isXFrame ? math.pi / count : 0.0;
    // Start from top (-pi/2) and distribute
    for (var i = 0; i < count; i++) {
      final angle = -math.pi / 2 + offset + (2 * math.pi * i / count);
      final mx = center.dx + radius * math.cos(angle);
      final my = center.dy + radius * math.sin(angle);
      final motorPos = Offset(mx, my);

      // Arm
      canvas.drawLine(center, motorPos, armPaint);

      // Motor circle
      canvas.drawCircle(motorPos, 10, motorPaint);
      canvas.drawCircle(motorPos, 10, motorBorderPaint);

      // Motor number
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(mx - textPainter.width / 2, my - textPainter.height / 2),
      );
    }

    // Front indicator
    final arrowPaint = Paint()
      ..color = hc.accent
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx, center.dy - 14),
      Offset(center.dx, center.dy - 28),
      arrowPaint,
    );
    // Arrow head
    canvas.drawLine(
      Offset(center.dx, center.dy - 28),
      Offset(center.dx - 5, center.dy - 22),
      arrowPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - 28),
      Offset(center.dx + 5, center.dy - 22),
      arrowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _FrameDiagramPainter old) =>
      old.motorCount != motorCount || old.isXFrame != isXFrame;
}
