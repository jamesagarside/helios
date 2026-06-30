import 'dart:async';

import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calibration/accel_cal_state_machine.dart';
import '../../../core/calibration/calibration_service.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../airframe/airframe_model_widget.dart';
import '../../airframe/airframe_providers.dart';

/// Full 6-point accelerometer calibration wizard.
///
/// Drives `MAV_CMD_PREFLIGHT_CALIBRATION` (accel) through six orientations,
/// parses the autopilot's `STATUSTEXT` position prompts via
/// [AccelCalStateMachine], and embeds the reusable Airframe Model as a live
/// target-pose validator: for each step the model is given that step's target
/// pose and turns green when the vehicle is actually held in it, so the pilot
/// gets unambiguous hands-on feedback before confirming.
class AccelCalWizard extends ConsumerStatefulWidget {
  const AccelCalWizard({super.key, this.onClose});

  /// Invoked when the pilot dismisses the wizard (back to the calibration menu).
  final VoidCallback? onClose;

  @override
  ConsumerState<AccelCalWizard> createState() => _AccelCalWizardState();
}

class _AccelCalWizardState extends ConsumerState<AccelCalWizard> {
  final AccelCalStateMachine _machine = AccelCalStateMachine();
  CalibrationService? _calService;
  StreamSubscription<StatusTextMessage>? _statusSub;

  AccelCalSnapshot _snapshot =
      const AccelCalSnapshot(phase: AccelCalPhase.idle);
  bool _posMatched = false;
  bool _rateAcquired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(airframeAttitudeControllerProvider).acquire();
      _rateAcquired = true;
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    if (_rateAcquired) {
      ref.read(airframeAttitudeControllerProvider).release();
    }
    super.dispose();
  }

  ({int sys, int comp})? get _target {
    final vehicle = ref.read(vehicleStateProvider);
    if (vehicle.systemId == 0) return null;
    return (sys: vehicle.systemId, comp: vehicle.componentId);
  }

  void _start() {
    final mavlink =
        ref.read(connectionControllerProvider.notifier).mavlinkService;
    final target = _target;
    if (mavlink == null || target == null) return;

    _calService ??= CalibrationService(mavlink);

    _statusSub?.cancel();
    _statusSub = mavlink.messagesOf<StatusTextMessage>().listen(_onStatusText);

    setState(() {
      _posMatched = false;
      _snapshot = _machine.start();
    });

    _calService!.startSixPointAccelCal(
      targetSystem: target.sys,
      targetComponent: target.comp,
    );
  }

  void _onStatusText(StatusTextMessage msg) {
    final next = _machine.onStatusText(msg.text);
    if (!mounted) return;
    setState(() {
      // A new position prompt resets the live match until re-evaluated.
      if (next.position != _snapshot.position) _posMatched = false;
      _snapshot = next;
    });
    if (next.isTerminal) {
      _statusSub?.cancel();
      _statusSub = null;
    }
  }

  void _confirm() {
    final target = _target;
    if (target == null || _calService == null) return;
    final result = _machine.confirmPosition();
    final pos = result.snapshot.position;
    if (result.action == AccelCalAction.sendPositionConfirm && pos != null) {
      _calService!.confirmAccelPosition(
        targetSystem: target.sys,
        targetComponent: target.comp,
        positionIndex: pos.posIndex,
      );
    }
    setState(() => _snapshot = result.snapshot);
  }

  void _cancel() {
    final target = _target;
    if (target != null && _calService != null) {
      _calService!.cancel(
        targetSystem: target.sys,
        targetComponent: target.comp,
      );
    }
    _statusSub?.cancel();
    _statusSub = null;
    setState(() => _snapshot = _machine.cancel());
  }

  void _restart() {
    setState(() {
      _posMatched = false;
      _snapshot = _machine.reset();
    });
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final controller = ref.watch(airframeAttitudeControllerProvider);
    final config = ref.watch(airframeConfigProvider);
    final connection = ref.watch(connectionStatusProvider);
    final connected = connection.linkState == LinkState.connected ||
        connection.linkState == LinkState.degraded;
    final source = controller.source;
    final phase = _snapshot.phase;
    final pos = _snapshot.position;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.onClose != null)
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  tooltip: 'Back',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              if (widget.onClose != null) const SizedBox(width: 8),
              Text(
                '6-POINT ACCELEROMETER CALIBRATION',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: hc.textTertiary,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Hold the vehicle in each requested orientation. The model turns '
            'green when you are within tolerance — then confirm to advance.',
            style: TextStyle(color: hc.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (!connected)
            _Banner(
              hc: hc,
              icon: Icons.info_outline,
              color: hc.warning,
              message: 'Connect to a vehicle to run calibration.',
            ),
          const SizedBox(height: 16),
          _ProgressDots(snapshot: _snapshot, hc: hc),
          const SizedBox(height: 16),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              child: AspectRatio(
                aspectRatio: 1.2,
                child: Container(
                  decoration: BoxDecoration(
                    color: hc.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _posMatched && pos != null
                          ? hc.success
                          : hc.border,
                      width: _posMatched && pos != null ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: source == null
                      ? _Placeholder(
                          hc: hc, icon: Icons.link_off, label: 'Not connected')
                      : AirframeModelWidget(
                          source: source,
                          config: config,
                          targetPose: pos?.targetPose,
                          onMatchChanged: (m) {
                            if (mounted) setState(() => _posMatched = m);
                          },
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _StatusCard(snapshot: _snapshot, posMatched: _posMatched, hc: hc),
          const SizedBox(height: 16),
          _Controls(
            phase: phase,
            connected: connected,
            posMatched: _posMatched,
            hasPosition: pos != null,
            onStart: _start,
            onConfirm: _confirm,
            onCancel: _cancel,
            onRestart: _restart,
            onClose: widget.onClose,
            hc: hc,
          ),
        ],
      ),
    );
  }
}

/// Row of six dots showing per-position progress.
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.snapshot, required this.hc});
  final AccelCalSnapshot snapshot;
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AccelCalPosition.values.map((p) {
        final done = snapshot.completedPositions.contains(p);
        final current = snapshot.position == p &&
            (snapshot.phase == AccelCalPhase.awaitingPosition ||
                snapshot.phase == AccelCalPhase.confirming);
        final color = done
            ? hc.success
            : current
                ? hc.accent
                : hc.textTertiary;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                done
                    ? Icons.check_circle
                    : current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                p.label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.snapshot,
    required this.posMatched,
    required this.hc,
  });
  final AccelCalSnapshot snapshot;
  final bool posMatched;
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    final (color, title) = switch (snapshot.phase) {
      AccelCalPhase.idle => (hc.textSecondary, 'Ready'),
      AccelCalPhase.starting => (hc.accent, 'Starting…'),
      AccelCalPhase.awaitingPosition => posMatched
          ? (hc.success, 'Hold — position matched')
          : (hc.accent, 'Position: ${snapshot.position?.label ?? ''}'),
      AccelCalPhase.confirming => (hc.accent, 'Confirming…'),
      AccelCalPhase.success => (hc.success, 'Calibration complete'),
      AccelCalPhase.failed => (hc.danger, 'Calibration failed'),
      AccelCalPhase.cancelled => (hc.warning, 'Calibration cancelled'),
    };

    final icon = switch (snapshot.phase) {
      AccelCalPhase.success => Icons.check_circle,
      AccelCalPhase.failed => Icons.error,
      AccelCalPhase.cancelled => Icons.cancel,
      AccelCalPhase.awaitingPosition when posMatched => Icons.check_circle,
      _ => Icons.sensors,
    };

    final message = snapshot.message.isEmpty
        ? (snapshot.phase == AccelCalPhase.awaitingPosition
            ? 'Place the vehicle ${snapshot.position?.label.toLowerCase() ?? ''} and hold steady.'
            : '')
        : snapshot.message;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: hc.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.phase,
    required this.connected,
    required this.posMatched,
    required this.hasPosition,
    required this.onStart,
    required this.onConfirm,
    required this.onCancel,
    required this.onRestart,
    required this.onClose,
    required this.hc,
  });

  final AccelCalPhase phase;
  final bool connected;
  final bool posMatched;
  final bool hasPosition;
  final VoidCallback onStart;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onRestart;
  final VoidCallback? onClose;
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case AccelCalPhase.idle:
        return FilledButton.icon(
          onPressed: connected ? onStart : null,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('Start 6-point calibration'),
        );
      case AccelCalPhase.starting:
      case AccelCalPhase.confirming:
        return Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text('Working…', style: TextStyle(color: hc.textSecondary)),
            const Spacer(),
            OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        );
      case AccelCalPhase.awaitingPosition:
        return Row(
          children: [
            FilledButton.icon(
              onPressed: hasPosition ? onConfirm : null,
              icon: Icon(
                posMatched ? Icons.check : Icons.touch_app,
                size: 18,
              ),
              label: Text(
                posMatched ? 'Confirm position' : 'Confirm (override)',
              ),
              style: posMatched
                  ? FilledButton.styleFrom(backgroundColor: hc.success)
                  : null,
            ),
            const Spacer(),
            OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        );
      case AccelCalPhase.success:
        return Row(
          children: [
            Icon(Icons.check_circle, color: hc.success, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Accelerometer calibrated. Reboot the flight controller to '
                'apply.',
                style: TextStyle(color: hc.textSecondary, fontSize: 12),
              ),
            ),
            if (onClose != null)
              FilledButton(onPressed: onClose, child: const Text('Done')),
          ],
        );
      case AccelCalPhase.failed:
      case AccelCalPhase.cancelled:
        return Row(
          children: [
            FilledButton.icon(
              onPressed: connected ? onRestart : null,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
            ),
            const SizedBox(width: 8),
            if (onClose != null)
              OutlinedButton(onPressed: onClose, child: const Text('Back')),
          ],
        );
    }
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.hc,
    required this.icon,
    required this.color,
    required this.message,
  });
  final HeliosColors hc;
  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: TextStyle(color: hc.textSecondary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.hc,
    required this.icon,
    required this.label,
  });
  final HeliosColors hc;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: hc.textTertiary),
          const SizedBox(height: 10),
          Text(label,
              style: TextStyle(color: hc.textTertiary, fontSize: 13)),
        ],
      ),
    );
  }
}
