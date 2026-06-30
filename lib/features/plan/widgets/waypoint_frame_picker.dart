import 'package:flutter/material.dart';
import '../../../shared/theme/helios_colors.dart';
import 'waypoint_command_defs.dart';

/// Dropdown for choosing how a waypoint's altitude is interpreted.
class FramePicker extends StatelessWidget {
  const FramePicker({
    super.key,
    required this.value,
    required this.inputDecoration,
    required this.hc,
    required this.onChanged,
  });

  final int value;
  final InputDecoration inputDecoration;
  final HeliosColors hc;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: DropdownButtonFormField<int>(
        initialValue: normaliseFrame(value),
        decoration: inputDecoration,
        dropdownColor: hc.surfaceLight,
        isExpanded: true,
        style: TextStyle(color: hc.textPrimary, fontSize: 12),
        items: kFrameOptions
            .map((f) => DropdownMenuItem<int>(
                  value: f.value,
                  child: Text(f.label),
                ))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
