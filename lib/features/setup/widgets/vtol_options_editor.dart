import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/params/parameter_service.dart';
import '../../../core/params/vtol_setup.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Editor for the `Q_OPTIONS` quadplane behaviour bitmask.
///
/// Per-bit checkboxes following the merged `ARMING_CHECK` editor pattern: each
/// toggle writes the recomputed bitmask back through [ParameterService] with a
/// pending-value local state until the PARAM echo lands. The pure bit logic
/// lives in [QOptionsMask] (`lib/core/params/vtol_setup.dart`) so it is tested.
class VtolOptionsEditor extends ConsumerStatefulWidget {
  const VtolOptionsEditor({super.key});

  @override
  ConsumerState<VtolOptionsEditor> createState() => _VtolOptionsEditorState();
}

class _VtolOptionsEditorState extends ConsumerState<VtolOptionsEditor> {
  /// Locally-pending mask while a write is in flight / before the echo lands.
  int? _pending;
  bool _writing = false;
  String? _error;

  QOptionsMask _currentMask(Map<String, Parameter> params) {
    if (_pending != null) return QOptionsMask(_pending!);
    final raw = params[kQOptionsParam]?.value;
    return QOptionsMask.fromParam(raw ?? 0);
  }

  Future<void> _write(QOptionsMask mask) async {
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
        paramId: kQOptionsParam,
        value: mask.paramValue,
        paramType: params[kQOptionsParam]?.type ?? 6, // MAV_PARAM_TYPE_INT32
      );
      final cached = Map<String, Parameter>.from(ref.read(paramCacheProvider));
      if (cached.containsKey(kQOptionsParam)) {
        cached[kQOptionsParam] =
            cached[kQOptionsParam]!.copyWith(value: mask.paramValue);
        ref.read(paramCacheProvider.notifier).state = cached;
      }
      if (mounted) setState(() => _pending = null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to write Q_OPTIONS: $e';
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
    final hasParam = params.containsKey(kQOptionsParam);
    final mask = _currentMask(params);
    final canEdit = connected && hasParam && !vehicle.armed && !_writing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Quadplane Behaviour (Q_OPTIONS)',
                style:
                    HeliosTypography.heading2.copyWith(color: hc.textPrimary),
              ),
            ),
            Text(
              'Raw: ${mask.value}',
              style: HeliosTypography.small.copyWith(
                color: hc.textTertiary,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Toggle individual quadplane behaviours. Writes the Q_OPTIONS bitmask '
          'parameter; each box is one bit.',
          style: HeliosTypography.small.copyWith(color: hc.textTertiary),
        ),
        const SizedBox(height: 12),

        if (!hasParam)
          _OptionsNotice(
            hc: hc,
            message: connected
                ? 'Waiting for Q_OPTIONS parameter...'
                : 'Connect to a vehicle to edit quadplane behaviour.',
          )
        else if (vehicle.armed)
          _OptionsNotice(
            hc: hc,
            message: 'Vehicle is ARMED. Disarm to change Q_OPTIONS.',
            warning: true,
          ),

        if (hasParam) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: hc.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < qOptionBits.length; i++) ...[
                  _OptionRow(
                    hc: hc,
                    def: qOptionBits[i],
                    enabled: mask.isEnabled(qOptionBits[i].bit),
                    interactive: canEdit,
                    onChanged: (v) =>
                        _write(mask.toggle(qOptionBits[i].bit, v)),
                  ),
                  if (i < qOptionBits.length - 1)
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
                'Writing Q_OPTIONS...',
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

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.hc,
    required this.def,
    required this.enabled,
    required this.interactive,
    required this.onChanged,
  });

  final HeliosColors hc;
  final QOptionBit def;
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

class _OptionsNotice extends StatelessWidget {
  const _OptionsNotice({
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
