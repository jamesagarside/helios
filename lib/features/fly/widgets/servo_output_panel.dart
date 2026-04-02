import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/providers/layout_provider.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Floating diagnostic panel showing live servo PWM outputs.
///
/// Displays SERVO_OUTPUT_RAW channels 1-16 as horizontal bar graphs with
/// traffic-light colouring indicating whether values are within normal range.
///
/// Platform: All (MAVLink only)
class ServoOutputPanel extends ConsumerWidget {
  const ServoOutputPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final notifier = ref.read(layoutProvider.notifier);

    // Pad to 16 channels
    final servos = List<int>.filled(16, 0);
    for (var i = 0; i < vehicle.servoOutputs.length && i < 16; i++) {
      servos[i] = vehicle.servoOutputs[i];
    }

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: hc.surfaceDim.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hc.border.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
            child: Row(
              children: [
                Text(
                  'SERVO OUTPUT',
                  style: HeliosTypography.caption.copyWith(
                    color: hc.textTertiary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => notifier.toggleServoPanel(),
                  child: Icon(Icons.close, size: 14, color: hc.textTertiary),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: hc.border.withValues(alpha: 0.5)),
          // Channel rows
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(16, (i) {
                return _ServoChannelRow(
                  channelNumber: i + 1,
                  pwm: servos[i],
                  hc: hc,
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServoChannelRow extends StatelessWidget {
  const _ServoChannelRow({
    required this.channelNumber,
    required this.pwm,
    required this.hc,
  });

  final int channelNumber;
  final int pwm;
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    final isUnused = pwm == 0;

    return SizedBox(
      height: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // Channel label
            SizedBox(
              width: 30,
              child: Text(
                'CH$channelNumber',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500,
                  color: isUnused ? hc.textTertiary : hc.textSecondary,
                ),
              ),
            ),
            // Bar graph
            Expanded(
              child: isUnused
                  ? _DashedDivider(color: hc.border)
                  : _PwmBar(pwm: pwm),
            ),
            const SizedBox(width: 4),
            // PWM value label
            SizedBox(
              width: 40,
              child: Text(
                isUnused ? '----' : pwm.toString(),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500,
                  color: isUnused ? hc.textTertiary : hc.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bar graph for a single PWM value (range 1000-2000µs).
///
/// Traffic-light colouring uses semantic signal colours (green/amber/red)
/// which are internationally understood and have no direct hc.* token equivalent.
class _PwmBar extends StatelessWidget {
  const _PwmBar({required this.pwm});

  final int pwm;

  @override
  Widget build(BuildContext context) {
    // Clamp to display range
    final clamped = pwm.clamp(900, 2100);
    // Normalise 1000-2000 to 0.0-1.0
    final fraction = ((clamped - 1000) / 1000.0).clamp(0.0, 1.0);

    // Traffic-light colour: semantic signal colours (green/amber/red).
    // hc.* tokens do not have direct PWM-range equivalents.
    final Color barColor;
    if (pwm < 1050 || pwm > 1950) {
      barColor = Colors.red.shade600;
    } else if (pwm < 1100 || pwm > 1900) {
      barColor = Colors.amber.shade600;
    } else {
      barColor = Colors.green.shade600;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        // Neutral marker at 1500µs = 50%
        const neutralFraction = 0.5;
        final neutralX = totalWidth * neutralFraction;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Background track
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: context.hc.border.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Filled bar
            Container(
              height: 8,
              width: totalWidth * fraction,
              decoration: BoxDecoration(
                color: barColor.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Neutral marker at 1500µs
            Positioned(
              left: neutralX - 0.5,
              top: 0,
              bottom: 0,
              child: Container(
                width: 1,
                color: context.hc.textTertiary.withValues(alpha: 0.6),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedLinePainter(color: color),
      child: const SizedBox(height: 8),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    const dashWidth = 4.0;
    const dashGap = 3.0;
    var x = 0.0;
    final y = size.height / 2;

    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset((x + dashWidth).clamp(0, size.width), y), paint);
      x += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}
