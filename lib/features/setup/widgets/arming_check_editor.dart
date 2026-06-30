import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/params/arming_check.dart';
import '../../../core/params/parameter_service.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Editor for the `ARMING_CHECK` bitmask parameter.
///
/// Lets the pilot toggle individual pre-arm check categories (plus an "All"
/// option) and writes the resulting bitmask back to the flight controller. The
/// live pre-arm health from SYS_STATUS is surfaced as a status pill so the
/// editor reflects whether checks are currently passing.
class ArmingCheckEditor extends ConsumerStatefulWidget {
  const ArmingCheckEditor({super.key});

  @override
  ConsumerState<ArmingCheckEditor> createState() => _ArmingCheckEditorState();
}

class _ArmingCheckEditorState extends ConsumerState<ArmingCheckEditor> {
  /// Locally-pending mask while a write is in flight / before the echo lands.
  int? _pending;
  bool _writing = false;
  String? _error;

  ArmingCheckMask _currentMask(Map<String, Parameter> params) {
    if (_pending != null) return ArmingCheckMask(_pending!);
    final raw = params['ARMING_CHECK']?.value;
    return ArmingCheckMask.fromParam(raw ?? armingCheckAll.toDouble());
  }

  Future<void> _write(ArmingCheckMask mask) async {
    final controller = ref.read(connectionControllerProvider.notifier);
    final paramService = controller.paramService;
    if (paramService == null) return;

    final vehicle = ref.read(vehicleStateProvider);
    final params = ref.read(paramCacheProvider);
    setState(() {
      _pending = mask.value;
      _writing = true;
      _error = null;
    });
    try {
      await paramService.setParam(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
        paramId: 'ARMING_CHECK',
        value: mask.paramValue,
        paramType: params['ARMING_CHECK']?.type ?? 6, // MAV_PARAM_TYPE_INT32
      );
      final cached = Map<String, Parameter>.from(ref.read(paramCacheProvider));
      if (cached.containsKey('ARMING_CHECK')) {
        cached['ARMING_CHECK'] =
            cached['ARMING_CHECK']!.copyWith(value: mask.paramValue);
        ref.read(paramCacheProvider.notifier).state = cached;
      }
      if (mounted) setState(() => _pending = null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to write ARMING_CHECK: $e';
          _pending = null;
        });
      }
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
    final hasParam = params.containsKey('ARMING_CHECK');
    final mask = _currentMask(params);

    // Live pre-arm health from SYS_STATUS (MAV_SYS_STATUS_PREARM_CHECK).
    const preArmBit = 0x20000000;
    final hasSensorData = vehicle.sensorPresent != 0;
    final preArmOk = hasSensorData && vehicle.isSensorHealthy(preArmBit);

    final canEdit = connected && hasParam && !vehicle.armed && !_writing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Arming Checks',
                style:
                    HeliosTypography.heading2.copyWith(color: hc.textPrimary),
              ),
            ),
            if (connected && hasSensorData)
              _StatusPill(hc: hc, ok: preArmOk),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Select which pre-arm checks run before the vehicle will arm. '
          'Writes the ARMING_CHECK bitmask parameter.',
          style: HeliosTypography.small.copyWith(color: hc.textTertiary),
        ),
        const SizedBox(height: 12),

        if (!connected)
          _Notice(hc: hc, message: 'Connect to a vehicle to edit arming checks.')
        else if (!hasParam)
          _Notice(hc: hc, message: 'Waiting for ARMING_CHECK parameter...')
        else if (vehicle.armed)
          _Notice(
            hc: hc,
            message: 'Vehicle is ARMED. Disarm to change arming checks.',
            warning: true,
          ),

        if (hasParam) ...[
          const SizedBox(height: 8),
          // All / None controls.
          Row(
            children: [
              _ModeChip(
                hc: hc,
                label: 'All Checks',
                selected: mask.isAll,
                enabled: canEdit && !mask.isAll,
                onTap: () => _write(mask.selectAll()),
              ),
              const SizedBox(width: 8),
              _ModeChip(
                hc: hc,
                label: 'None',
                selected: mask.isNone,
                enabled: canEdit && !mask.isNone,
                danger: true,
                onTap: () => _write(mask.selectNone()),
              ),
              const Spacer(),
              Text(
                'Raw: ${mask.value}',
                style: HeliosTypography.small.copyWith(
                  color: hc.textTertiary,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Container(
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: hc.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < armingCheckBits.length; i++) ...[
                  _CheckRow(
                    hc: hc,
                    def: armingCheckBits[i],
                    enabled: mask.isEnabled(armingCheckBits[i].bit),
                    interactive: canEdit,
                    onChanged: (v) =>
                        _write(mask.toggle(armingCheckBits[i].bit, v)),
                  ),
                  if (i < armingCheckBits.length - 1)
                    Divider(height: 1, color: hc.border),
                ],
              ],
            ),
          ),
        ],

        if (_writing) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: hc.accent),
              ),
              const SizedBox(width: 8),
              Text(
                'Writing ARMING_CHECK...',
                style:
                    HeliosTypography.small.copyWith(color: hc.textSecondary),
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
      ],
    );
  }
}

// ─── Status Pill ────────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.hc, required this.ok});
  final HeliosColors hc;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final color = ok ? hc.success : hc.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            ok ? 'Pre-arm passing' : 'Pre-arm failing',
            style: HeliosTypography.small.copyWith(
                color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─── Mode Chip (All / None) ─────────────────────────────────────────────────

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.hc,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.danger = false,
  });

  final HeliosColors hc;
  final String label;
  final bool selected;
  final bool enabled;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = danger ? hc.danger : hc.accent;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: accent.withValues(alpha: 0.2),
      backgroundColor: hc.surface,
      side: BorderSide(color: selected ? accent : hc.border),
      labelStyle: TextStyle(
        color: selected ? accent : hc.textSecondary,
        fontSize: 12,
      ),
      onSelected: enabled ? (_) => onTap() : null,
    );
  }
}

// ─── Check Row ──────────────────────────────────────────────────────────────

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.hc,
    required this.def,
    required this.enabled,
    required this.interactive,
    required this.onChanged,
  });

  final HeliosColors hc;
  final ArmingCheckBit def;
  final bool enabled;
  final bool interactive;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: interactive ? () => onChanged(!enabled) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Checkbox(
              value: enabled,
              onChanged: interactive ? (v) => onChanged(v ?? false) : null,
              activeColor: hc.accent,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    def.label,
                    style: HeliosTypography.caption.copyWith(
                      color: interactive ? hc.textPrimary : hc.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    def.description,
                    style:
                        HeliosTypography.small.copyWith(color: hc.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Notice ─────────────────────────────────────────────────────────────────

class _Notice extends StatelessWidget {
  const _Notice({
    required this.hc,
    required this.message,
    this.warning = false,
  });
  final HeliosColors hc;
  final String message;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? hc.warning : hc.textTertiary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warning ? color.withValues(alpha: 0.08) : hc.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: warning ? color.withValues(alpha: 0.4) : hc.border),
      ),
      child: Row(
        children: [
          Icon(warning ? Icons.warning_amber_rounded : Icons.info_outline,
              color: color, size: 18),
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
