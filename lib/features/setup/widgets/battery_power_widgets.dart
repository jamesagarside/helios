part of 'battery_power_panel.dart';

// ─── Live Readouts ──────────────────────────────────────────────────────────

class _LiveReadouts extends StatelessWidget {
  const _LiveReadouts({
    required this.hc,
    required this.vehicle,
    required this.connected,
  });
  final HeliosColors hc;
  final VehicleState vehicle;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final voltage = vehicle.batteryVoltage;
    final current = vehicle.batteryCurrent;
    final remaining = vehicle.batteryRemaining;
    final consumed = vehicle.batteryConsumed;

    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_outlined,
                  size: 18, color: hc.accent),
              const SizedBox(width: 8),
              Text('Live Readings',
                  style: HeliosTypography.heading2
                      .copyWith(color: hc.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Readout(
                hc: hc,
                label: 'Voltage',
                value: connected && voltage > 0
                    ? '${voltage.toStringAsFixed(2)} V'
                    : '—',
              ),
              _Readout(
                hc: hc,
                label: 'Current',
                value: connected && current != 0
                    ? '${current.toStringAsFixed(2)} A'
                    : '—',
              ),
              _Readout(
                hc: hc,
                label: 'Remaining',
                value: connected && remaining >= 0 ? '$remaining %' : '—',
              ),
              _Readout(
                hc: hc,
                label: 'Consumed',
                value: connected && consumed > 0
                    ? '${consumed.toStringAsFixed(0)} mAh'
                    : '—',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.hc, required this.label, required this.value});
  final HeliosColors hc;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: HeliosTypography.small.copyWith(color: hc.textTertiary)),
          const SizedBox(height: 2),
          Text(
            value,
            style: HeliosTypography.telemetryMedium
                .copyWith(color: hc.accent, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// ─── Measurement Calibrator ─────────────────────────────────────────────────

class _MeasurementCalibrator extends StatefulWidget {
  const _MeasurementCalibrator({
    required this.hc,
    required this.label,
    required this.unit,
    required this.hintText,
    required this.enabled,
    required this.compute,
    required this.onApply,
    required this.resultLabel,
    required this.resultDecimals,
  });

  final HeliosColors hc;
  final String label;
  final String unit;
  final String hintText;
  final bool enabled;

  /// Returns the new parameter value for a measured reading, or null if the
  /// computation is not valid (e.g. no live reading yet).
  final double? Function(double measured) compute;
  final ValueChanged<double> onApply;
  final String resultLabel;
  final int resultDecimals;

  @override
  State<_MeasurementCalibrator> createState() =>
      _MeasurementCalibratorState();
}

class _MeasurementCalibratorState extends State<_MeasurementCalibrator> {
  final _ctrl = TextEditingController();
  double? _computed;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _recompute() {
    final measured = double.tryParse(_ctrl.text.trim());
    setState(() {
      _computed = measured == null ? null : widget.compute(measured);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hc = widget.hc;
    final computed = _computed;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hc.surfaceDim,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  enabled: widget.enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.\-]')),
                  ],
                  style: HeliosTypography.body.copyWith(color: hc.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: widget.label,
                    labelStyle: HeliosTypography.small
                        .copyWith(color: hc.textSecondary),
                    suffixText: widget.unit,
                    suffixStyle: HeliosTypography.small
                        .copyWith(color: hc.textTertiary),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
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
                  onChanged: (_) => _recompute(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: (widget.enabled && computed != null)
                    ? () => widget.onApply(computed)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: hc.accent,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Compute'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (computed != null)
            Text(
              '${widget.resultLabel}: '
              '${computed.toStringAsFixed(widget.resultDecimals)}'
              '  (tap Compute to stage, then Write)',
              style: HeliosTypography.small.copyWith(color: hc.success),
            )
          else if (_ctrl.text.trim().isNotEmpty)
            Text(
              'No valid live reading to calibrate against. Ensure the monitor '
              'is enabled and reporting a non-zero value.',
              style: HeliosTypography.small.copyWith(color: hc.warning),
            )
          else
            Text(widget.hintText,
                style:
                    HeliosTypography.small.copyWith(color: hc.textTertiary)),
        ],
      ),
    );
  }
}

// ─── Info Banner / Hint ─────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.hc, required this.message});
  final HeliosColors hc;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hc.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: hc.textTertiary, size: 18),
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

class _Hint extends StatelessWidget {
  const _Hint({required this.hc, required this.text});
  final HeliosColors hc;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: HeliosTypography.small.copyWith(color: hc.textTertiary),
      ),
    );
  }
}

// ─── Write Bar ──────────────────────────────────────────────────────────────

class _WriteBar extends StatelessWidget {
  const _WriteBar({
    required this.hc,
    required this.modifiedCount,
    required this.error,
    required this.writing,
    required this.onWrite,
    required this.onReset,
  });
  final HeliosColors hc;
  final int modifiedCount;
  final String? error;
  final bool writing;
  final VoidCallback onWrite;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hc.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$modifiedCount parameter(s) modified',
            style: HeliosTypography.caption.copyWith(color: hc.warning),
          ),
          if (error != null) ...[
            const SizedBox(height: 4),
            Text(error!,
                style: HeliosTypography.small.copyWith(color: hc.danger)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: writing ? null : onWrite,
                  icon: writing
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: hc.textPrimary,
                          ),
                        )
                      : const Icon(Icons.save, size: 16),
                  label: Text(writing ? 'Writing...' : 'Write Changes'),
                  style: FilledButton.styleFrom(
                    backgroundColor: hc.accent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: writing ? null : onReset,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: hc.border),
                  foregroundColor: hc.textSecondary,
                ),
                child: const Text('Reset'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Section Card ───────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.hc,
    required this.icon,
    required this.title,
    required this.children,
  });

  final HeliosColors hc;
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: hc.accent),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: HeliosTypography.heading2
                      .copyWith(color: hc.textPrimary),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: hc.border),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1) const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dropdown Param ─────────────────────────────────────────────────────────

class _DropdownParam extends StatelessWidget {
  const _DropdownParam({
    required this.hc,
    required this.paramName,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final HeliosColors hc;
  final String paramName;
  final String label;
  final int value;
  final Map<int, String> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      HeliosTypography.body.copyWith(color: hc.textPrimary)),
              Text(
                paramName,
                style: HeliosTypography.small.copyWith(
                  color: hc.textTertiary,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: hc.surfaceLight,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: hc.border),
          ),
          child: DropdownButton<int>(
            value: options.containsKey(value) ? value : options.keys.first,
            items: options.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(
                        e.value,
                        style: HeliosTypography.caption
                            .copyWith(color: hc.textPrimary),
                      ),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            underline: const SizedBox.shrink(),
            dropdownColor: hc.surface,
            iconEnabledColor: hc.textSecondary,
            isDense: true,
          ),
        ),
      ],
    );
  }
}

// ─── Number Param ───────────────────────────────────────────────────────────

class _NumberParam extends StatefulWidget {
  const _NumberParam({
    required this.hc,
    required this.paramName,
    required this.label,
    required this.value,
    required this.decimals,
    required this.onChanged,
    this.unit = '',
  });

  final HeliosColors hc;
  final String paramName;
  final String label;
  final double value;
  final int decimals;
  final String unit;
  final ValueChanged<double> onChanged;

  @override
  State<_NumberParam> createState() => _NumberParamState();
}

class _NumberParamState extends State<_NumberParam> {
  late final TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(_NumberParam old) {
    super.didUpdateWidget(old);
    if (!_editing && old.value != widget.value) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _fmt(double v) => v.toStringAsFixed(widget.decimals);

  void _commit(String s) {
    final v = double.tryParse(s.trim());
    if (v != null) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final hc = widget.hc;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.label,
                  style:
                      HeliosTypography.body.copyWith(color: hc.textPrimary)),
              Text(
                widget.paramName,
                style: HeliosTypography.small.copyWith(
                  color: hc.textTertiary,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 110,
          child: TextField(
            controller: _ctrl,
            style: HeliosTypography.body.copyWith(color: hc.textPrimary),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
            ],
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              isDense: true,
              suffixText: widget.unit.isEmpty ? null : widget.unit,
              suffixStyle:
                  HeliosTypography.small.copyWith(color: hc.textTertiary),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
            onTap: () => _editing = true,
            onSubmitted: (s) {
              _editing = false;
              _commit(s);
            },
            onTapOutside: (_) {
              if (_editing) {
                _editing = false;
                _commit(_ctrl.text);
                FocusScope.of(context).unfocus();
              }
            },
          ),
        ),
      ],
    );
  }
}
