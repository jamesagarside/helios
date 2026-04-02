import 'dart:async';
import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/mavlink/mavlink_service.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// MAVLink Terminal — interactive console for sending MAVLink commands
/// and viewing decoded message traffic with field-level detail.
///
/// Supported commands:
///   arm / disarm
///   mode <MODE_NAME>
///   reboot
///   cmd <id> [p1] [p2] ... [p7]
///   request <msg_id> [interval_us]
///   preflight
///   status
///   clear
///   help
class MavlinkTerminal extends ConsumerStatefulWidget {
  const MavlinkTerminal({super.key});

  @override
  ConsumerState<MavlinkTerminal> createState() => _MavlinkTerminalState();
}

class _MavlinkTerminalState extends ConsumerState<MavlinkTerminal> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _lines = <_TerminalLine>[];
  final _history = <String>[];
  int _historyIndex = -1;

  @override
  void initState() {
    super.initState();
    _addLine('Helios MAVLink Terminal', _LineType.system);
    _addLine('Type "help" for available commands.', _LineType.system);
    _addLine('', _LineType.system);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addLine(String text, _LineType type) {
    setState(() {
      _lines.add(_TerminalLine(text, type));
      if (_lines.length > 5000) {
        _lines.removeRange(0, _lines.length - 5000);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _submit(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    _controller.clear();
    _history.add(trimmed);
    _historyIndex = -1;
    _addLine('> $trimmed', _LineType.input);

    final parts = trimmed.split(RegExp(r'\s+'));
    final cmd = parts[0].toLowerCase();

    final connController = ref.read(connectionControllerProvider.notifier);
    final vehicle = ref.read(vehicleStateProvider);
    final service = connController.mavlinkService;

    if (service == null) {
      _addLine('Error: Not connected to vehicle', _LineType.error);
      return;
    }

    try {
      switch (cmd) {
        case 'help':
          _showHelp();
        case 'clear':
          setState(() => _lines.clear());
        case 'status':
          _showStatus(vehicle);
        case 'arm':
          await service.sendCommand(
            targetSystem: vehicle.systemId,
            targetComponent: vehicle.componentId,
            command: 400, // MAV_CMD_COMPONENT_ARM_DISARM
            param1: 1,
          );
          _addLine('Sent ARM command', _LineType.success);
        case 'disarm':
          await service.sendCommand(
            targetSystem: vehicle.systemId,
            targetComponent: vehicle.componentId,
            command: 400,
            param1: 0,
          );
          _addLine('Sent DISARM command', _LineType.success);
        case 'reboot':
          await service.sendCommand(
            targetSystem: vehicle.systemId,
            targetComponent: vehicle.componentId,
            command: 246, // MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN
            param1: 1,
          );
          _addLine('Sent REBOOT command', _LineType.success);
        case 'preflight':
          await service.sendCommand(
            targetSystem: vehicle.systemId,
            targetComponent: vehicle.componentId,
            command: 241, // MAV_CMD_PREFLIGHT_CALIBRATION
            param1: 0, param2: 0, param3: 0,
            param4: 0, param5: 0, param6: 0,
          );
          _addLine('Sent PREFLIGHT_CALIBRATION command', _LineType.success);
        case 'mode':
          if (parts.length < 2) {
            _addLine('Usage: mode <MODE_NAME|number>', _LineType.error);
          } else {
            final modeNum = int.tryParse(parts[1]);
            if (modeNum != null) {
              await service.sendCommand(
                targetSystem: vehicle.systemId,
                targetComponent: vehicle.componentId,
                command: 176, // MAV_CMD_DO_SET_MODE
                param1: 1, // MAV_MODE_FLAG_CUSTOM_MODE_ENABLED
                param2: modeNum.toDouble(),
              );
              _addLine('Sent SET_MODE $modeNum', _LineType.success);
            } else {
              _addLine('Error: mode must be a number', _LineType.error);
            }
          }
        case 'cmd':
          _handleGenericCommand(parts, service, vehicle);
        case 'request':
          _handleRequestMessage(parts, service, vehicle);
        default:
          _addLine('Unknown command: $cmd (type "help" for commands)', _LineType.error);
      }
    } catch (e) {
      _addLine('Error: $e', _LineType.error);
    }

    // Listen for ACK response
    if (cmd != 'help' && cmd != 'clear' && cmd != 'status') {
      _listenForAck(service);
    }
  }

  void _handleGenericCommand(
    List<String> parts,
    MavlinkService service,
    VehicleState vehicle,
  ) {
    if (parts.length < 2) {
      _addLine('Usage: cmd <command_id> [p1] [p2] [p3] [p4] [p5] [p6] [p7]', _LineType.error);
      return;
    }
    final cmdId = int.tryParse(parts[1]);
    if (cmdId == null) {
      _addLine('Error: command_id must be a number', _LineType.error);
      return;
    }
    final params = <double>[];
    for (var i = 2; i < parts.length && i < 9; i++) {
      params.add(double.tryParse(parts[i]) ?? 0);
    }
    while (params.length < 7) {
      params.add(0);
    }
    service.sendCommand(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      command: cmdId,
      param1: params[0],
      param2: params[1],
      param3: params[2],
      param4: params[3],
      param5: params[4],
      param6: params[5],
      param7: params[6],
    );
    _addLine('Sent COMMAND_LONG #$cmdId', _LineType.success);
  }

  void _handleRequestMessage(
    List<String> parts,
    MavlinkService service,
    VehicleState vehicle,
  ) {
    if (parts.length < 2) {
      _addLine('Usage: request <msg_id> [interval_us]', _LineType.error);
      return;
    }
    final msgId = int.tryParse(parts[1]);
    if (msgId == null) {
      _addLine('Error: msg_id must be a number', _LineType.error);
      return;
    }
    final interval = parts.length > 2 ? (double.tryParse(parts[2]) ?? 1000000.0) : 1000000.0;
    service.sendCommand(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      command: 511, // MAV_CMD_SET_MESSAGE_INTERVAL
      param1: msgId.toDouble(),
      param2: interval,
    );
    _addLine('Requested msg $msgId at ${(1000000 / interval).toStringAsFixed(1)} Hz', _LineType.success);
  }

  void _listenForAck(MavlinkService service) {
    StreamSubscription<CommandAckMessage>? sub;
    sub = service.messagesOf<CommandAckMessage>().listen((ack) {
      final result = ack.accepted ? 'ACCEPTED' : 'REJECTED (${ack.result})';
      _addLine('  ACK: cmd ${ack.command} → $result', _LineType.ack);
      sub?.cancel();
    });
    // Auto-cancel after 3 seconds if no ACK
    Future<void>.delayed(const Duration(seconds: 3), () => sub?.cancel());
  }

  void _showHelp() {
    const commands = [
      'arm               Arm the vehicle',
      'disarm            Disarm the vehicle',
      'mode <number>     Set flight mode by number',
      'reboot            Reboot the flight controller',
      'preflight         Send preflight calibration',
      'cmd <id> [p1..p7] Send a generic COMMAND_LONG',
      'request <id> [us] Request message at interval',
      'status            Show current vehicle state',
      'clear             Clear terminal output',
      'help              Show this help',
    ];
    for (final line in commands) {
      _addLine('  $line', _LineType.system);
    }
  }

  void _showStatus(VehicleState vehicle) {
    _addLine('  System ID:    ${vehicle.systemId}', _LineType.system);
    _addLine('  Component ID: ${vehicle.componentId}', _LineType.system);
    _addLine('  Vehicle Type: ${vehicle.vehicleType.name}', _LineType.system);
    _addLine('  Autopilot:    ${vehicle.autopilotType.name}', _LineType.system);
    _addLine('  Flight Mode:  ${vehicle.flightMode.name}', _LineType.system);
    _addLine('  Armed:        ${vehicle.armed}', _LineType.system);
    _addLine('  GPS Fix:      ${vehicle.gpsFix.name}', _LineType.system);
    _addLine('  Satellites:   ${vehicle.satellites}', _LineType.system);
    _addLine('  HDOP:         ${vehicle.hdop < 50 ? vehicle.hdop.toStringAsFixed(2) : "unknown"}', _LineType.system);
    _addLine('  Battery:      ${vehicle.batteryVoltage.toStringAsFixed(1)}V  ${vehicle.batteryRemaining}%', _LineType.system);
    _addLine('  Firmware:     ${vehicle.firmwareVersionString}', _LineType.system);
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_history.isNotEmpty) {
        _historyIndex = _historyIndex < 0
            ? _history.length - 1
            : (_historyIndex - 1).clamp(0, _history.length - 1);
        _controller.text = _history[_historyIndex];
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_historyIndex >= 0) {
        _historyIndex++;
        if (_historyIndex >= _history.length) {
          _historyIndex = -1;
          _controller.clear();
        } else {
          _controller.text = _history[_historyIndex];
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    return Column(
      children: [
        // Output area
        Expanded(
          child: GestureDetector(
            onTap: () => _focusNode.requestFocus(),
            child: Container(
              color: hc.background,
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(8),
                itemCount: _lines.length,
                itemBuilder: (_, i) {
                  final line = _lines[i];
                  return Text(
                    line.text,
                    style: HeliosTypography.sqlEditor.copyWith(
                      fontSize: 12,
                      color: switch (line.type) {
                        _LineType.input => hc.textPrimary,
                        _LineType.system => hc.textTertiary,
                        _LineType.success => hc.success,
                        _LineType.error => hc.danger,
                        _LineType.ack => hc.accent,
                      },
                      fontWeight: line.type == _LineType.input
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Divider(height: 1, color: hc.border),
        // Input area
        Container(
          color: hc.surface,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Text(
                '> ',
                style: HeliosTypography.sqlEditor.copyWith(
                  fontSize: 13,
                  color: hc.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Expanded(
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: _handleKeyEvent,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: HeliosTypography.sqlEditor.copyWith(
                      fontSize: 13,
                      color: hc.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter MAVLink command...',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: hc.textTertiary,
                        fontFamily: 'monospace',
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onSubmitted: (value) {
                      _submit(value);
                      _focusNode.requestFocus();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _LineType { input, system, success, error, ack }

class _TerminalLine {
  const _TerminalLine(this.text, this.type);
  final String text;
  final _LineType type;
}
