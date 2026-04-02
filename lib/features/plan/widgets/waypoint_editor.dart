import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter/material.dart';
import '../../../shared/models/mission_item.dart';
import '../../../shared/theme/helios_colors.dart';

// ─── Param metadata ──────────────────────────────────────────────────────────

/// A single parameter field descriptor.
class _ParamDef {
  const _ParamDef(this.label, {this.min = 0, this.max = double.infinity});

  final String label;
  final double min;
  final double max;
}

/// Maps a MAVLink command int to its 7 param labels.
/// Null means "not used — hide this param".
const _kParamDefs = <int, List<_ParamDef?>>{
  MavCmd.navWaypoint: [
    _ParamDef('Hold (s)', min: 0, max: 600),
    _ParamDef('Radius (m)', min: 0, max: 1000),
    null,
    _ParamDef('Yaw (deg)', min: 0, max: 360),
    null, null, null,
  ],
  MavCmd.navTakeoff: [
    null,
    null,
    null,
    _ParamDef('Yaw (deg)', min: 0, max: 360),
    null, null, null,
  ],
  MavCmd.navLand: [
    _ParamDef('Abort Alt (m)', min: 0, max: 200),
    null,
    null,
    _ParamDef('Yaw (deg)', min: 0, max: 360),
    null, null, null,
  ],
  MavCmd.navReturnToLaunch: [null, null, null, null, null, null, null],
  MavCmd.navLoiterUnlim: [
    null,
    _ParamDef('Radius (m)', min: 0, max: 2000),
    null,
    _ParamDef('Yaw (deg)', min: 0, max: 360),
    null, null, null,
  ],
  MavCmd.navLoiterTime: [
    _ParamDef('Time (s)', min: 0, max: 3600),
    _ParamDef('Radius (m)', min: 0, max: 2000),
    null,
    _ParamDef('Yaw (deg)', min: 0, max: 360),
    null, null, null,
  ],
  MavCmd.navLoiterTurns: [
    _ParamDef('Turns', min: 1, max: 100),
    _ParamDef('Radius (m)', min: 0, max: 2000),
    null,
    _ParamDef('Yaw (deg)', min: 0, max: 360),
    null, null, null,
  ],
  // DO_ commands
  MavCmd.doChangeSpeed: [
    _ParamDef('Speed Type (0=air,1=gnd)', min: 0, max: 1),
    _ParamDef('Speed (m/s, -1=nc)', min: -1, max: 50),
    _ParamDef('Throttle % (-1=nc)', min: -1, max: 100),
    null, null, null, null,
  ],
  MavCmd.doJump: [
    _ParamDef('Target Seq', min: 0, max: 9999),
    _ParamDef('Repeat Count', min: 0, max: 100),
    null, null, null, null, null,
  ],
  MavCmd.doSetCamTriggDist: [
    _ParamDef('Distance (m)', min: 0, max: 10000),
    null, null, null, null, null, null,
  ],
  MavCmd.doMountControl: [
    _ParamDef('Pitch (deg)', min: -180, max: 180),
    _ParamDef('Roll (deg)', min: -180, max: 180),
    _ParamDef('Yaw (deg)', min: -180, max: 180),
    null, null, null, null,
  ],
  MavCmd.doLandStart: [null, null, null, null, null, null, null],
  MavCmd.doGripper: [
    _ParamDef('Gripper ID', min: 0, max: 10),
    _ParamDef('Action (0=rel,1=grab)', min: 0, max: 1),
    null, null, null, null, null,
  ],
  MavCmd.doPauseContinue: [
    _ParamDef('Pause (1) or Continue (0)', min: 0, max: 1),
    null, null, null, null, null, null,
  ],
};

/// Fallback when a command has no specific param defs.
const _kFallbackDefs = [
  _ParamDef('Param 1'),
  _ParamDef('Param 2'),
  _ParamDef('Param 3'),
  _ParamDef('Param 4'),
  null, // param5 = latitude, not shown in generic fallback
  null, // param6 = longitude
  null, // param7 = altitude shown separately
];

// ─── Command groups ───────────────────────────────────────────────────────────

class _CmdEntry {
  const _CmdEntry(this.value, this.label);

  final int value;
  final String label;
}

const _kNavCommands = <_CmdEntry>[
  _CmdEntry(MavCmd.navWaypoint, 'Waypoint'),
  _CmdEntry(MavCmd.navTakeoff, 'Takeoff'),
  _CmdEntry(MavCmd.navLand, 'Land'),
  _CmdEntry(MavCmd.navReturnToLaunch, 'RTL'),
  _CmdEntry(MavCmd.navLoiterUnlim, 'Loiter'),
  _CmdEntry(MavCmd.navLoiterTime, 'Loiter Time'),
  _CmdEntry(MavCmd.navLoiterTurns, 'Loiter Turns'),
];

const _kActionCommands = <_CmdEntry>[
  _CmdEntry(MavCmd.doChangeSpeed, 'Change Speed'),
  _CmdEntry(MavCmd.doJump, 'Jump'),
  _CmdEntry(MavCmd.doSetCamTriggDist, 'Camera Trigger'),
  _CmdEntry(MavCmd.doMountControl, 'Gimbal Control'),
  _CmdEntry(MavCmd.doLandStart, 'Land Start'),
  _CmdEntry(MavCmd.doGripper, 'Gripper'),
  _CmdEntry(MavCmd.doPauseContinue, 'Pause/Continue'),
];

/// All known commands (nav + action) in a flat list for value lookup.
const _kAllCommands = [..._kNavCommands, ..._kActionCommands];

// ─── Widget ───────────────────────────────────────────────────────────────────

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
    final paramDefs = _kParamDefs[item.command] ?? _kFallbackDefs;

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
        _EditorRow(
          label: def.label,
          child: _NumberField(
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
          _EditorRow(
            label: 'Command',
            child: _GroupedCommandPicker(
              value: item.command,
              inputDecoration: inputDecoration,
              hc: hc,
              onChanged: (v) => onChanged(item.copyWith(command: v)),
            ),
          ),
          const SizedBox(height: 6),

          // Altitude row (always shown)
          _EditorRow(
            label: 'Alt (m)',
            child: _NumberField(
              value: item.altitude,
              min: 0,
              max: 5000,
              inputDecoration: inputDecoration,
              textColor: hc.textPrimary,
              onChanged: (v) => onChanged(item.copyWith(altitude: v)),
            ),
          ),
          const SizedBox(height: 6),

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

// ─── Grouped command picker ────────────────────────────────────────────────────

/// A dropdown that shows Navigation and Actions groups with dividers.
class _GroupedCommandPicker extends StatelessWidget {
  const _GroupedCommandPicker({
    required this.value,
    required this.inputDecoration,
    required this.hc,
    required this.onChanged,
  });

  final int value;
  final InputDecoration inputDecoration;
  final HeliosColors hc;
  final ValueChanged<int> onChanged;

  bool _isKnown(int cmd) => _kAllCommands.any((c) => c.value == cmd);

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
          ..._kNavCommands.map((c) => DropdownMenuItem<int>(
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
          ..._kActionCommands.map((c) => DropdownMenuItem<int>(
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

// ─── Shared sub-widgets ────────────────────────────────────────────────────────

class _EditorRow extends StatelessWidget {
  const _EditorRow({required this.label, required this.child});

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

class _NumberField extends StatefulWidget {
  const _NumberField({
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
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(_NumberField oldWidget) {
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
