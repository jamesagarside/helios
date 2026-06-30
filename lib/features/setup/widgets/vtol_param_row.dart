import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/params/parameter_service.dart';
import '../../../core/params/vtol_setup.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// A boxed group of editable [VtolParam] rows.
///
/// Each row reads its current value from [paramCacheProvider] and writes edits
/// back through [ParameterService.setParam] with PARAM read-back confirmation,
/// holding a pending value locally until the write is confirmed — the same
/// plumbing as the other Wave-2 setup panels. Parameters absent from the cache
/// render as a dash and are not editable.
class VtolParamGroup extends ConsumerWidget {
  const VtolParamGroup({super.key, required this.params});

  final List<VtolParam> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final cache = ref.watch(paramCacheProvider);
    final present = params.where((p) => cache.containsKey(p.id)).toList();

    if (present.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: hc.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: hc.border),
        ),
        child: Text(
          cache.isEmpty
              ? 'Waiting for parameters...'
              : 'These parameters are not present on this firmware.',
          style: HeliosTypography.small.copyWith(color: hc.textTertiary),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < present.length; i++) ...[
            _VtolParamRow(def: present[i]),
            if (i < present.length - 1)
              Divider(height: 1, color: hc.border, indent: 12),
          ],
        ],
      ),
    );
  }
}

class _VtolParamRow extends ConsumerStatefulWidget {
  const _VtolParamRow({required this.def});
  final VtolParam def;

  @override
  ConsumerState<_VtolParamRow> createState() => _VtolParamRowState();
}

class _VtolParamRowState extends ConsumerState<_VtolParamRow> {
  double? _pending;
  bool _writing = false;
  String? _error;

  Future<void> _write(double value) async {
    final controller = ref.read(connectionControllerProvider.notifier);
    final paramService = controller.paramService;
    if (paramService == null) return;
    final vehicle = ref.read(vehicleStateProvider);
    final cache = ref.read(paramCacheProvider);
    setState(() {
      _pending = value;
      _writing = true;
      _error = null;
    });
    try {
      final confirmed = await paramService.setParam(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
        paramId: widget.def.id,
        value: value,
        paramType: cache[widget.def.id]?.type ?? 9,
      );
      final updated = Map<String, Parameter>.from(ref.read(paramCacheProvider));
      if (updated.containsKey(widget.def.id)) {
        updated[widget.def.id] =
            updated[widget.def.id]!.copyWith(value: confirmed);
        ref.read(paramCacheProvider.notifier).state = updated;
      }
      if (mounted) setState(() => _pending = null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Write failed: $e';
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
    final def = widget.def;
    final cache = ref.watch(paramCacheProvider);
    final vehicle = ref.watch(vehicleStateProvider);
    final connected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;
    final param = cache[def.id];
    final value = _pending ?? param?.value;
    final canEdit = connected && param != null && !vehicle.armed && !_writing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(def.label,
                    style: HeliosTypography.caption
                        .copyWith(color: hc.textPrimary)),
                Text(
                  def.help.isNotEmpty ? def.help : def.id,
                  style: def.help.isNotEmpty
                      ? HeliosTypography.small.copyWith(color: hc.textTertiary)
                      : HeliosTypography.small.copyWith(
                          color: hc.textTertiary, fontFamily: 'monospace'),
                ),
                if (_error != null)
                  Text(_error!,
                      style:
                          HeliosTypography.small.copyWith(color: hc.danger)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (value == null)
            Text('—', style: TextStyle(color: hc.textTertiary, fontSize: 13))
          else if (_writing)
            SizedBox(
              width: 14,
              height: 14,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: hc.accent),
            )
          else if (def.isEnum)
            _EnumPicker(
              value: value.round(),
              options: def.enumOptions!,
              enabled: canEdit,
              onChanged: _write,
            )
          else
            _NumberField(
              key: ValueKey('${def.id}_${value.toStringAsFixed(4)}'),
              value: value,
              unit: def.unit,
              enabled: canEdit,
              onSubmitted: _write,
            ),
        ],
      ),
    );
  }
}

class _EnumPicker extends StatelessWidget {
  const _EnumPicker({
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });
  final int value;
  final Map<int, String> options;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    // Surface an out-of-list stored value so it isn't silently dropped.
    final items = <int, String>{
      ...options,
      if (!options.containsKey(value)) value: 'Value $value',
    };
    return DropdownButton<int>(
      value: value,
      items: items.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged:
          enabled ? (v) { if (v != null) onChanged(v.toDouble()); } : null,
      style: HeliosTypography.small.copyWith(color: hc.textPrimary),
      underline: const SizedBox(),
      isDense: true,
      dropdownColor: hc.surface,
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({
    super.key,
    required this.value,
    required this.unit,
    required this.enabled,
    required this.onSubmitted,
  });
  final double value;
  final String unit;
  final bool enabled;
  final ValueChanged<double> onSubmitted;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(4);

  void _submit(String s) {
    final v = double.tryParse(s);
    if (v != null && v != widget.value) widget.onSubmitted(v);
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return SizedBox(
      width: 96,
      child: TextField(
        controller: _ctrl,
        enabled: widget.enabled,
        style: TextStyle(fontSize: 13, color: hc.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          suffixText: widget.unit,
          suffixStyle: TextStyle(fontSize: 11, color: hc.textTertiary),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: hc.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: hc.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: hc.accent),
          ),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onSubmitted: _submit,
        onTapOutside: (_) {
          FocusScope.of(context).unfocus();
          _submit(_ctrl.text);
        },
      ),
    );
  }
}
