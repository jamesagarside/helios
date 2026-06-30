import 'package:flutter/material.dart';
import '../../../shared/theme/helios_colors.dart';

/// A labelled column wrapping a single editor field.
class EditorRow extends StatelessWidget {
  const EditorRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: hc.textTertiary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        child,
      ],
    );
  }
}

/// A numeric text field that clamps its value on submit and stays in sync with
/// externally-driven value changes.
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.inputDecoration,
    required this.textColor,
  });

  final double value;
  final double min;
  final double max;
  final void Function(double value) onChanged;
  final InputDecoration inputDecoration;
  final Color textColor;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final text = _fmt(widget.value);
      if (_controller.text != text) {
        _controller.text = text;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _fmt(double v) => v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: TextField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        style: TextStyle(
          color: widget.textColor,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
        decoration: widget.inputDecoration,
        onSubmitted: (text) {
          final v = double.tryParse(text);
          if (v != null) {
            widget.onChanged(v.clamp(widget.min, widget.max));
          }
        },
      ),
    );
  }
}
