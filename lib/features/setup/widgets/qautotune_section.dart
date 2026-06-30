import 'dart:async';

import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mavlink/flight_modes.dart';
import '../../../core/params/vtol_setup.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// QAUTOTUNE guidance + engagement section for the VTOL panel.
///
/// QAUTOTUNE is the recommended route to good VTOL tuning. This GCS does **not**
/// orchestrate the tune — it guides the pilot and switches the flight mode. The
/// "Switch to QAUTOTUNE" button reuses [ConnectionController.setFlightMode]
/// /[FlightModeRegistry] (from #25). The button is never hard-disabled on the
/// ground/disarmed: instead it shows a modal explaining why it usually won't
/// help, with an "Engage anyway" escape hatch (pragmatic override, ADR 0003).
/// Live progress is decoded from `STATUSTEXT`.
class QAutotuneSection extends ConsumerStatefulWidget {
  const QAutotuneSection({super.key});

  @override
  ConsumerState<QAutotuneSection> createState() => _QAutotuneSectionState();
}

class _QAutotuneSectionState extends ConsumerState<QAutotuneSection> {
  StreamSubscription<StatusTextMessage>? _statusSub;
  QAutotuneProgress _progress = QAutotuneProgress.idle;
  String _lastStatus = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  void _subscribe() {
    final mavlink =
        ref.read(connectionControllerProvider.notifier).mavlinkService;
    if (mavlink == null) return;
    _statusSub?.cancel();
    _statusSub =
        mavlink.messagesOf<StatusTextMessage>().listen(_onStatusText);
  }

  void _onStatusText(StatusTextMessage msg) {
    final next = classifyQAutotuneStatus(msg.text);
    if (next == null || !mounted) return;
    setState(() {
      _progress = next;
      _lastStatus = msg.text.trim();
    });
  }

  Future<void> _engage() async {
    final controller = ref.read(connectionControllerProvider.notifier);
    await controller.setFlightMode(kQAutotuneMode);
    if (mounted) {
      setState(() {
        _progress = QAutotuneProgress.tuning;
        _lastStatus = 'Requested QAUTOTUNE mode...';
      });
    }
  }

  /// Engage directly if the guard is satisfied; otherwise show the override
  /// modal and only proceed on an explicit "Engage anyway".
  Future<void> _onPressed() async {
    final vehicle = ref.read(vehicleStateProvider);
    final effective = qAutotuneLikelyEffective(
      armed: vehicle.armed,
      currentMode: vehicle.flightMode.number,
    );
    if (effective) {
      await _engage();
      return;
    }
    final proceed = await _showGuardModal(vehicle);
    if (proceed == true) await _engage();
  }

  Future<bool?> _showGuardModal(VehicleState vehicle) {
    final hc = context.hc;
    final reasons = <String>[
      if (!vehicle.armed) 'the vehicle is disarmed',
      if (!isVtolMode(vehicle.flightMode.number))
        'it is not in a VTOL (Q) flight mode',
    ];
    final reasonText = reasons.isEmpty
        ? 'the aircraft does not appear to be flying in a VTOL mode'
        : reasons.join(' and ');

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: hc.surface,
        icon: Icon(Icons.warning_amber_rounded, color: hc.danger, size: 28),
        title: Text('Engage QAUTOTUNE now?',
            style:
                HeliosTypography.heading2.copyWith(color: hc.textPrimary)),
        content: Text(
          'QAUTOTUNE only learns gains while the aircraft is airborne and '
          'flying in a VTOL mode. Right now $reasonText, so switching mode '
          'usually will not tune anything and may behave unexpectedly.\n\n'
          'Engage only if you understand the risk and are ready to retake '
          'control. The GCS will not trigger the tune itself.',
          style: HeliosTypography.small.copyWith(color: hc.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style: TextStyle(color: hc.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: hc.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Engage anyway'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final connected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;
    final inQAutotune = vehicle.flightMode.number == kQAutotuneMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('VTOL Autotune (QAUTOTUNE)',
            style: HeliosTypography.heading2.copyWith(color: hc.textPrimary)),
        const SizedBox(height: 8),

        // Guidance card.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: hc.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_fix_high, size: 18, color: hc.accent),
                  const SizedBox(width: 8),
                  Text('How QAUTOTUNE works',
                      style: HeliosTypography.caption
                          .copyWith(color: hc.textPrimary)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'QAUTOTUNE flies the aircraft through small test movements in a '
                'VTOL mode and learns the rate/angle gains for you. It is the '
                'recommended route to good tuning — the manual PIDs below are '
                'for hand-finishing what QAUTOTUNE found.\n\n'
                'Before engaging: fly in calm air, hold a safe altitude, and be '
                'ready to retake control by switching back to a manual VTOL '
                'mode. New gains are saved automatically when the tune '
                'completes.',
                style:
                    HeliosTypography.small.copyWith(color: hc.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Engage button (never hard-disabled except when no link).
        Row(
          children: [
            FilledButton.icon(
              onPressed: connected ? _onPressed : null,
              icon: const Icon(Icons.tune, size: 16),
              label: Text(
                  inQAutotune ? 'In QAUTOTUNE' : 'Switch to QAUTOTUNE mode'),
              style: FilledButton.styleFrom(
                backgroundColor: inQAutotune ? hc.success : hc.accent,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 12),
            if (!connected)
              Text('Connect to a vehicle first.',
                  style: HeliosTypography.small
                      .copyWith(color: hc.textTertiary)),
          ],
        ),
        const SizedBox(height: 12),

        // Live STATUSTEXT-driven progress readout.
        _ProgressReadout(
          hc: hc,
          progress: _progress,
          lastStatus: _lastStatus,
        ),
      ],
    );
  }
}

class _ProgressReadout extends StatelessWidget {
  const _ProgressReadout({
    required this.hc,
    required this.progress,
    required this.lastStatus,
  });

  final HeliosColors hc;
  final QAutotuneProgress progress;
  final String lastStatus;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (progress) {
      QAutotuneProgress.idle => (
          Icons.remove_circle_outline,
          hc.textTertiary,
          'No tune in progress'
        ),
      QAutotuneProgress.tuning => (
          Icons.sync,
          hc.accent,
          'Tuning in progress'
        ),
      QAutotuneProgress.saved => (
          Icons.check_circle,
          hc.success,
          'Gains saved'
        ),
      QAutotuneProgress.failed => (
          Icons.error_outline,
          hc.danger,
          'Tune failed / aborted'
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: HeliosTypography.caption.copyWith(
                        color: color, fontWeight: FontWeight.w600)),
                if (lastStatus.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(lastStatus,
                      style: HeliosTypography.small
                          .copyWith(color: hc.textTertiary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
