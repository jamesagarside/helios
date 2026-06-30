import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calibration/esc_calibration.dart';
import '../../../core/params/parameter_service.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';
import 'esc_endpoint_editor.dart';
import 'esc_semi_auto_section.dart';

/// ESC calibration panel.
///
/// Detects the ESC output protocol (`MOT_PWM_TYPE`) and, for analog PWM ESCs,
/// offers a guided semi-automatic calibration plus direct editing of the
/// manual endpoint parameters. Digital (DShot) and brushed outputs are
/// factory/duty-cycle driven and need no calibration — the panel detects and
/// explains this instead of offering a flow that would do nothing.
///
/// Throttle is only ever commanded after a mandatory props-off confirmation,
/// and the semi-automatic flow refuses to arm while the vehicle is armed.
class EscCalibrationPanel extends ConsumerStatefulWidget {
  const EscCalibrationPanel({super.key});

  @override
  ConsumerState<EscCalibrationPanel> createState() =>
      _EscCalibrationPanelState();
}

class _EscCalibrationPanelState extends ConsumerState<EscCalibrationPanel> {
  final EscCalStateMachine _machine = EscCalStateMachine();
  EscCalSnapshot _snapshot = const EscCalSnapshot(phase: EscCalPhase.idle);

  final Map<String, Parameter> _params = {};
  final Map<String, double> _pending = {};
  bool _loading = false;
  String? _error;

  EscProtocol get _protocol =>
      EscProtocol.fromValue(_params[EscParams.pwmType]?.value);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  ({int sys, int comp})? get _target {
    final vehicle = ref.read(vehicleStateProvider);
    if (vehicle.systemId == 0) return null;
    return (sys: vehicle.systemId, comp: vehicle.componentId);
  }

  Future<void> _load() async {
    final svc = ref.read(connectionControllerProvider.notifier).paramService;
    final target = _target;
    if (svc == null || target == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await svc.fetchAll(
        targetSystem: target.sys,
        targetComponent: target.comp,
      );
      if (!mounted) return;
      setState(() {
        _params.clear();
        for (final id in [EscParams.pwmType, ...EscParams.editableEndpoints]) {
          if (all.containsKey(id)) _params[id] = all[id]!;
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _writeParam(String id, double value) async {
    final svc = ref.read(connectionControllerProvider.notifier).paramService;
    final target = _target;
    if (svc == null || target == null) return;
    try {
      final confirmed = await svc.setParam(
        targetSystem: target.sys,
        targetComponent: target.comp,
        paramId: id,
        value: value,
        paramType: _params[id]?.type ?? 9,
      );
      if (!mounted) return;
      setState(() {
        final existing = _params[id];
        if (existing != null) {
          _params[id] = existing.copyWith(value: confirmed);
        }
        _pending.remove(id);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to write $id: $e'),
            backgroundColor: context.hc.danger,
          ),
        );
      }
    }
  }

  void _startFlow() {
    setState(() => _snapshot = _machine.start());
  }

  void _setPropsOff(bool value) {
    setState(() => _snapshot = _machine.setPropsOff(value));
  }

  Future<void> _armCalibration() async {
    final result = _machine.armCalibration();
    setState(() => _snapshot = result.snapshot);
    if (result.action == EscCalAction.armCalibrationParam) {
      await _writeParam(
          EscParams.calibration, EscParams.semiAutoCalibrateValue);
    }
  }

  void _completePowerCycle() {
    setState(() => _snapshot = _machine.completePowerCycle());
  }

  Future<void> _cancelFlow() async {
    final result = _machine.cancel();
    setState(() => _snapshot = result.snapshot);
    if (result.action == EscCalAction.restoreCalibrationParam) {
      await _writeParam(EscParams.calibration, EscParams.normalValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final connected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ESC CALIBRATION',
                style: HeliosTypography.caption.copyWith(
                  color: hc.textTertiary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Reload parameters',
                onPressed: connected && !_loading ? _load : null,
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (!connected) ...[
            EscBanner(
              hc: hc,
              icon: Icons.info_outline,
              color: hc.warning,
              text: 'Connect to a vehicle to calibrate ESCs.',
            ),
            const SizedBox(height: 16),
          ],

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            EscBanner(
              hc: hc,
              icon: Icons.error_outline,
              color: hc.danger,
              text: _error!,
            )
          else if (connected) ...[
            _ProtocolCard(protocol: _protocol),
            const SizedBox(height: 20),
            if (!_protocol.calibratable)
              _NotNeededCard(protocol: _protocol)
            else ...[
              EscSemiAutoSection(
                snapshot: _snapshot,
                armed: vehicle.armed,
                onStart: _startFlow,
                onPropsOff: _setPropsOff,
                onArm: _armCalibration,
                onPowerCycled: _completePowerCycle,
                onCancel: _cancelFlow,
              ),
              const SizedBox(height: 24),
              EscEndpointEditor(
                params: _params,
                pending: _pending,
                onChanged: (id, v) => setState(() => _pending[id] = v),
                onWrite: (id) {
                  final v = _pending[id] ?? _params[id]?.value;
                  if (v != null) _writeParam(id, v);
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ─── Protocol detection card ─────────────────────────────────────────────────

class _ProtocolCard extends StatelessWidget {
  const _ProtocolCard({required this.protocol});
  final EscProtocol protocol;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: Row(
        children: [
          Icon(
            protocol.isDigital ? Icons.memory : Icons.electrical_services,
            size: 20,
            color: hc.accent,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Detected ESC protocol',
                  style:
                      HeliosTypography.small.copyWith(color: hc.textTertiary)),
              const SizedBox(height: 2),
              Text(protocol.label,
                  style: HeliosTypography.body.copyWith(
                      color: hc.textPrimary, fontWeight: FontWeight.w600)),
            ],
          ),
          const Spacer(),
          Text('MOT_PWM_TYPE',
              style: HeliosTypography.small
                  .copyWith(color: hc.textTertiary, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

class _NotNeededCard extends StatelessWidget {
  const _NotNeededCard({required this.protocol});
  final EscProtocol protocol;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final reason = protocol.isDigital
        ? 'Digital (DShot) ESCs are factory-calibrated — the autopilot sends an '
            'exact digital throttle value, so there are no analog endpoints to '
            'learn. ESC calibration is neither needed nor possible.'
        : protocol == EscProtocol.brushed
            ? 'Brushed motors are driven by a PWM duty cycle, not by an ESC with '
                'learnable endpoints. ESC calibration does not apply.'
            : 'This output protocol does not use analog ESC endpoints, so '
                'calibration does not apply.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hc.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 20, color: hc.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No calibration required',
                    style: HeliosTypography.body.copyWith(
                        color: hc.textPrimary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(reason,
                    style: HeliosTypography.small
                        .copyWith(color: hc.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

