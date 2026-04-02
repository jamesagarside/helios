import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/providers/layout_provider.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Standard RC channel labels for the first four channels (Mode 2).
const _kRcChannelLabels = ['AIL', 'ELE', 'THR', 'RUD'];

/// Floating diagnostic panel showing live RC receiver inputs.
///
/// Displays RC_CHANNELS PWM values for channels 1-18 as horizontal bar graphs.
/// Shows RSSI indicator and a failsafe badge when RC failsafe is active.
///
/// Platform: All (MAVLink only)
class RcInputPanel extends ConsumerWidget {
  const RcInputPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final notifier = ref.read(layoutProvider.notifier);

    // Pad to 18 channels
    final channels = List<int>.filled(18, 0);
    for (var i = 0; i < vehicle.rcChannels.length && i < 18; i++) {
      channels[i] = vehicle.rcChannels[i];
    }

    final rssi = vehicle.rcRssi;
    final rssiInvalid = rssi == 255;
    final failsafe = vehicle.rcFailsafe;

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
                // "RC INPUT" fixed-width label
                Text(
                  'RC INPUT',
                  style: HeliosTypography.caption.copyWith(
                    color: hc.textTertiary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 6),
                // RSSI indicator — shrinks if failsafe badge is also present
                Flexible(
                  child: _RssiLabel(rssi: rssi, invalid: rssiInvalid, hc: hc),
                ),
                const SizedBox(width: 4),
                // Failsafe badge — only appears when active
                if (failsafe) _FailsafeBadge(hc: hc),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => notifier.toggleRcPanel(),
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
              children: List.generate(18, (i) {
                final label = i < _kRcChannelLabels.length
                    ? _kRcChannelLabels[i]
                    : 'CH${i + 1}';
                return _RcChannelRow(
                  label: label,
                  channelNumber: i + 1,
                  pwm: channels[i],
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

class _RssiLabel extends StatelessWidget {
  const _RssiLabel({
    required this.rssi,
    required this.invalid,
    required this.hc,
  });

  final int rssi;
  final bool invalid;
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    // Traffic-light colour for RSSI signal quality.
    // hc.* tokens do not have direct RSSI-quality equivalents;
    // green/amber/red are internationally understood signal strength colours.
    final Color rssiColor;
    if (invalid) {
      rssiColor = hc.textTertiary;
    } else if (rssi >= 150) {
      rssiColor = Colors.green.shade500;
    } else if (rssi >= 80) {
      rssiColor = Colors.amber.shade600;
    } else {
      rssiColor = Colors.red.shade500;
    }

    return Text(
      invalid ? 'RSSI: ---' : 'RSSI: $rssi',
      style: TextStyle(
        fontSize: 10,
        fontFamily: 'monospace',
        fontWeight: FontWeight.w600,
        color: rssiColor,
      ),
    );
  }
}

class _FailsafeBadge extends StatelessWidget {
  const _FailsafeBadge({required this.hc});

  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: hc.danger.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: hc.danger.withValues(alpha: 0.6)),
      ),
      child: Text(
        'FAILSAFE',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: hc.danger,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _RcChannelRow extends StatelessWidget {
  const _RcChannelRow({
    required this.label,
    required this.channelNumber,
    required this.pwm,
    required this.hc,
  });

  final String label;
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
                label,
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
    final clamped = pwm.clamp(900, 2100);
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
        const neutralFraction = 0.5;
        final neutralX = totalWidth * neutralFraction;

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: context.hc.border.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              height: 8,
              width: totalWidth * fraction,
              decoration: BoxDecoration(
                color: barColor.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
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
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dashWidth).clamp(0, size.width), y),
        paint,
      );
      x += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}
