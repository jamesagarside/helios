import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/calibration/esc_calibration.dart';
import '../../../core/params/parameter_service.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

const _kEndpointMeta = {
  EscParams.pwmMin: ('Min PWM output', 'µs'),
  EscParams.pwmMax: ('Max PWM output', 'µs'),
  EscParams.spinArm: ('Spin when armed', ''),
  EscParams.spinMin: ('Minimum spin', ''),
  EscParams.spinMax: ('Maximum spin', ''),
};

/// Editor for the manually-adjustable ESC endpoint parameters
/// (`MOT_PWM_MIN/MAX`, `MOT_SPIN_ARM/MIN/MAX`).
///
/// Editing these is safe without spinning motors, so this section has no
/// throttle gating of its own — it simply reads back the current values and
/// writes pending edits on demand.
class EscEndpointEditor extends StatelessWidget {
  const EscEndpointEditor({
    super.key,
    required this.params,
    required this.pending,
    required this.onChanged,
    required this.onWrite,
  });

  final Map<String, Parameter> params;
  final Map<String, double> pending;
  final void Function(String id, double value) onChanged;
  final ValueChanged<String> onWrite;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    const ids = EscParams.editableEndpoints;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MANUAL ENDPOINTS',
            style: HeliosTypography.caption.copyWith(
                color: hc.textTertiary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6)),
        const SizedBox(height: 4),
        Text(
          'Set ESC output limits directly. These are safe to edit without '
          'spinning motors.',
          style: HeliosTypography.small.copyWith(color: hc.textTertiary),
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
              for (var i = 0; i < ids.length; i++) ...[
                _EndpointRow(
                  id: ids[i],
                  label: _kEndpointMeta[ids[i]]!.$1,
                  unit: _kEndpointMeta[ids[i]]!.$2,
                  param: params[ids[i]],
                  pendingValue: pending[ids[i]],
                  onChanged: (v) => onChanged(ids[i], v),
                  onWrite: () => onWrite(ids[i]),
                ),
                if (i != ids.length - 1)
                  Divider(
                      height: 1, thickness: 1, color: hc.border, indent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EndpointRow extends StatefulWidget {
  const _EndpointRow({
    required this.id,
    required this.label,
    required this.unit,
    required this.param,
    required this.pendingValue,
    required this.onChanged,
    required this.onWrite,
  });

  final String id;
  final String label;
  final String unit;
  final Parameter? param;
  final double? pendingValue;
  final ValueChanged<double> onChanged;
  final VoidCallback onWrite;

  @override
  State<_EndpointRow> createState() => _EndpointRowState();
}

class _EndpointRowState extends State<_EndpointRow> {
  late final TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(_display));
  }

  double? get _display => widget.pendingValue ?? widget.param?.value;

  @override
  void didUpdateWidget(_EndpointRow old) {
    super.didUpdateWidget(old);
    if (!_editing &&
        old.param?.value != widget.param?.value &&
        widget.pendingValue == null) {
      _ctrl.text = _fmt(_display);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _fmt(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final hasParam = widget.param != null;
    final hasPending = widget.pendingValue != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label,
                    style:
                        HeliosTypography.body.copyWith(color: hc.textPrimary)),
                Text(widget.id,
                    style: HeliosTypography.small.copyWith(
                        color: hc.textTertiary, fontFamily: 'monospace')),
              ],
            ),
          ),
          if (!hasParam)
            Text('—',
                style: HeliosTypography.small.copyWith(color: hc.textTertiary))
          else ...[
            if (hasPending)
              IconButton(
                icon: Icon(Icons.check_circle, color: hc.accent, size: 18),
                tooltip: 'Write to FC',
                onPressed: widget.onWrite,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            SizedBox(
              width: 90,
              child: TextField(
                controller: _ctrl,
                style: HeliosTypography.body.copyWith(color: hc.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  suffixText: widget.unit,
                  suffixStyle:
                      HeliosTypography.small.copyWith(color: hc.textTertiary),
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onTap: () => setState(() => _editing = true),
                onSubmitted: (s) {
                  setState(() => _editing = false);
                  final v = double.tryParse(s);
                  if (v != null) widget.onChanged(v);
                },
                onTapOutside: (_) {
                  if (!_editing) return;
                  setState(() => _editing = false);
                  final v = double.tryParse(_ctrl.text);
                  if (v != null) widget.onChanged(v);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
