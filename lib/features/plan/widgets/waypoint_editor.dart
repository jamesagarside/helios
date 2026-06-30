import 'package:flutter/material.dart';
import '../../../shared/models/mission_item.dart';
import '../../../shared/theme/helios_colors.dart';
import 'waypoint_command_defs.dart';
import 'waypoint_command_picker.dart';
import 'waypoint_editor_fields.dart';
import 'waypoint_frame_picker.dart';

/// Inline editor for the selected waypoint's properties.
/// Shows a grouped command picker (Navigation / Actions) and per-command
/// param labels based on the MAVLink spec.
class WaypointEditor extends StatelessWidget {
  const WaypointEditor({
    super.key,
    required this.item,
    required this.onChanged,
  });

  final MissionItem item;
  final void Function(MissionItem updated) onChanged;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final inputDecoration = _buildInputDecoration(hc);
    final paramDefs = kParamDefs[item.command] ?? kFallbackDefs;

    // Collect visible param field entries.
    final paramFields = <Widget>[];
    final List<(double, void Function(double))> params = [
      (item.param1, (double v) => onChanged(item.copyWith(param1: v))),
      (item.param2, (double v) => onChanged(item.copyWith(param2: v))),
      (item.param3, (double v) => onChanged(item.copyWith(param3: v))),
      (item.param4, (double v) => onChanged(item.copyWith(param4: v))),
    ];

    for (var i = 0; i < 4; i++) {
      final def = i < paramDefs.length ? paramDefs[i] : null;
      if (def == null) continue;
      final (value, setter) = params[i];
      paramFields.add(
        EditorRow(
          label: def.label,
          child: NumberField(
            value: value,
            min: def.min,
            max: def.max,
            inputDecoration: inputDecoration,
            textColor: hc.textPrimary,
            onChanged: setter,
          ),
        ),
      );
    }

    // Build rows of 2 side by side
    final paramRows = <Widget>[];
    for (var i = 0; i < paramFields.length; i += 2) {
      if (i + 1 < paramFields.length) {
        paramRows.add(Row(
          children: [
            Expanded(child: paramFields[i]),
            const SizedBox(width: 8),
            Expanded(child: paramFields[i + 1]),
          ],
        ));
      } else {
        paramRows.add(Row(
          children: [
            Expanded(child: paramFields[i]),
            const Expanded(child: SizedBox.shrink()),
          ],
        ));
      }
      paramRows.add(const SizedBox(height: 6));
    }

    return Container(
      padding: const EdgeInsets.all(10),
      color: hc.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.edit, size: 14, color: hc.accent),
              const SizedBox(width: 6),
              Text(
                'WP ${item.seq}',
                style: TextStyle(
                  color: hc.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Command dropdown — grouped via custom widget
          EditorRow(
            label: 'Command',
            child: GroupedCommandPicker(
              value: item.command,
              inputDecoration: inputDecoration,
              hc: hc,
              onChanged: (v) => onChanged(item.copyWith(command: v)),
            ),
          ),
          const SizedBox(height: 6),

          // Altitude row (always shown)
          EditorRow(
            label: 'Alt (m)',
            child: NumberField(
              value: item.altitude,
              min: 0,
              max: 5000,
              inputDecoration: inputDecoration,
              textColor: hc.textPrimary,
              onChanged: (v) => onChanged(item.copyWith(altitude: v)),
            ),
          ),
          const SizedBox(height: 6),

          // Altitude frame (only meaningful for positional/nav commands)
          if (item.isNavCommand) ...[
            EditorRow(
              label: 'Alt Frame',
              child: FramePicker(
                value: item.frame,
                inputDecoration: inputDecoration,
                hc: hc,
                onChanged: (v) => onChanged(item.copyWith(frame: v)),
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Per-command param fields
          ...paramRows,

          // Lat/Lon read-only display for nav commands
          if (item.isNavCommand)
            Text(
              '${item.latitude.toStringAsFixed(6)}, ${item.longitude.toStringAsFixed(6)}',
              style: TextStyle(
                color: hc.textTertiary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }

  static InputDecoration _buildInputDecoration(HeliosColors hc) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: hc.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: hc.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: hc.accent),
      ),
      filled: true,
      fillColor: hc.surfaceLight,
    );
  }
}
