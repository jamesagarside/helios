import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter/material.dart';
import '../../../shared/models/mission_item.dart';
import '../../../shared/theme/helios_colors.dart';

/// Inline editor for the selected waypoint's properties.
class WaypointEditor extends StatelessWidget {
  const WaypointEditor({
    super.key,
    required this.item,
    required this.onChanged,
  });

  final MissionItem item;
  final void Function(MissionItem updated) onChanged;

  static const _commands = [
    (MavCmd.navWaypoint, 'Waypoint'),
    (MavCmd.navTakeoff, 'Takeoff'),
    (MavCmd.navLand, 'Land'),
    (MavCmd.navReturnToLaunch, 'RTL'),
    (MavCmd.navLoiterUnlim, 'Loiter'),
    (MavCmd.navLoiterTime, 'Loiter Time'),
    (MavCmd.navLoiterTurns, 'Loiter Turns'),
  ];

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final inputDecoration = _buildInputDecoration(hc);
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

          // Command dropdown
          _EditorRow(
            label: 'Command',
            child: SizedBox(
              height: 30,
              child: DropdownButtonFormField<int>(
                initialValue: _commands.any((c) => c.$1 == item.command)
                    ? item.command
                    : MavCmd.navWaypoint,
                decoration: inputDecoration,
                dropdownColor: hc.surfaceLight,
                style: TextStyle(
                  color: hc.textPrimary,
                  fontSize: 12,
                ),
                items: _commands
                    .map((c) => DropdownMenuItem(
                          value: c.$1,
                          child: Text(c.$2),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChanged(item.copyWith(command: v));
                },
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Altitude
          Row(
            children: [
              Expanded(
                child: _EditorRow(
                  label: 'Alt (m)',
                  child: _NumberField(
                    value: item.altitude,
                    min: 0,
                    max: 5000,
                    inputDecoration: inputDecoration,
                    textColor: hc.textPrimary,
                    onChanged: (v) =>
                        onChanged(item.copyWith(altitude: v)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _EditorRow(
                  label: 'Hold (s)',
                  child: _NumberField(
                    value: item.param1,
                    min: 0,
                    max: 600,
                    inputDecoration: inputDecoration,
                    textColor: hc.textPrimary,
                    onChanged: (v) =>
                        onChanged(item.copyWith(param1: v)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Acceptance radius + yaw
          Row(
            children: [
              Expanded(
                child: _EditorRow(
                  label: 'Radius (m)',
                  child: _NumberField(
                    value: item.param2,
                    min: 0,
                    max: 1000,
                    inputDecoration: inputDecoration,
                    textColor: hc.textPrimary,
                    onChanged: (v) =>
                        onChanged(item.copyWith(param2: v)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _EditorRow(
                  label: 'Yaw (deg)',
                  child: _NumberField(
                    value: item.param4,
                    min: 0,
                    max: 360,
                    inputDecoration: inputDecoration,
                    textColor: hc.textPrimary,
                    onChanged: (v) =>
                        onChanged(item.copyWith(param4: v)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Lat/Lon (read-only display)
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
    _controller = TextEditingController(
      text: widget.value == widget.value.roundToDouble()
          ? widget.value.toStringAsFixed(0)
          : widget.value.toStringAsFixed(1),
    );
  }

  @override
  void didUpdateWidget(_NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final text = widget.value == widget.value.roundToDouble()
          ? widget.value.toStringAsFixed(0)
          : widget.value.toStringAsFixed(1);
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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: TextField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
