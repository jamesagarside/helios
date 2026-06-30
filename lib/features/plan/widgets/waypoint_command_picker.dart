import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter/material.dart';
import '../../../shared/theme/helios_colors.dart';
import 'waypoint_command_defs.dart';

/// A dropdown that shows Navigation and Actions groups with dividers.
class GroupedCommandPicker extends StatelessWidget {
  const GroupedCommandPicker({
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

  bool _isKnown(int cmd) => kAllCommands.any((c) => c.value == cmd);

  @override
  Widget build(BuildContext context) {
    // Normalise unknown commands to navWaypoint for display purposes only
    final displayValue = _isKnown(value) ? value : MavCmd.navWaypoint;

    return SizedBox(
      height: 30,
      child: DropdownButtonFormField<int>(
        initialValue: displayValue,
        decoration: inputDecoration,
        dropdownColor: hc.surfaceLight,
        isExpanded: true,
        style: TextStyle(
          color: hc.textPrimary,
          fontSize: 12,
        ),
        items: [
          // Navigation group header
          DropdownMenuItem<int>(
            enabled: false,
            value: -1,
            child: Text(
              'NAVIGATION',
              style: TextStyle(
                color: hc.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          ...kNavCommands.map((c) => DropdownMenuItem<int>(
                value: c.value,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(c.label),
                ),
              )),
          // Actions group header
          DropdownMenuItem<int>(
            enabled: false,
            value: -2,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'ACTIONS',
                style: TextStyle(
                  color: hc.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          ...kActionCommands.map((c) => DropdownMenuItem<int>(
                value: c.value,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(c.label),
                ),
              )),
        ],
        onChanged: (v) {
          if (v != null && v >= 0) onChanged(v);
        },
      ),
    );
  }
}
