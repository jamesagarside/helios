import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/logs/log_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/platform/serial_ports.dart';
import '../../shared/providers/relay_status_provider.dart';
import '../../shared/models/connection_state.dart';
import '../../shared/providers/connection_settings_provider.dart';
import '../../shared/providers/stream_rate_provider.dart';
import 'widgets/simulate_panel.dart';
import '../../shared/models/layout_profile.dart' as layout;
import '../../shared/models/vehicle_state.dart';
import '../../core/map/cached_tile_provider.dart';
import '../../shared/providers/display_provider.dart';
import '../../shared/providers/theme_mode_provider.dart';
import '../../shared/providers/layout_provider.dart';
import '../../core/telemetry/maintenance_service.dart';
import '../../shared/providers/providers.dart';
import '../../shared/providers/video_provider.dart';
import '../../shared/theme/helios_colors.dart';
import '../../shared/theme/helios_typography.dart';

/// Setup View — connection, telemetry, calibration, video, display, maps, system.
class SetupView extends ConsumerStatefulWidget {
  const SetupView({super.key});

  @override
  ConsumerState<SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends ConsumerState<SetupView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = [
    (icon: Icons.link_outlined, label: 'Connection'),
    (icon: Icons.speed_outlined, label: 'Telemetry'),
    (icon: Icons.videocam_outlined, label: 'Video'),
    (icon: Icons.dashboard_customize_outlined, label: 'Display'),
    (icon: Icons.map_outlined, label: 'Offline Maps'),
    (icon: Icons.build_outlined, label: 'System'),
    (icon: Icons.info_outline, label: 'Info'),
    (icon: Icons.storage_outlined, label: 'Logs'),
    (icon: Icons.rocket_launch_outlined, label: 'Simulate'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;

    return Scaffold(
      backgroundColor: hc.background,
      body: isDesktop
          ? Row(
              children: [
                Container(
                  width: 160,
                  color: hc.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: Text(
                          'Setup',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: hc.textTertiary,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListenableBuilder(
                          listenable: _tabController,
                          builder: (_, _) {
                            return ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              itemCount: _tabs.length,
                              itemBuilder: (_, i) {
                                final tab = _tabs[i];
                                return _SidebarTabItem(
                                  icon: tab.icon,
                                  label: tab.label,
                                  selected: _tabController.index == i,
                                  onTap: () => _tabController.animateTo(i),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(width: 1, thickness: 1, color: hc.border),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _ConnectionTab(),
                      const _TelemetryTab(),
                      const _VideoTab(),
                      const _DisplayTab(),
                      const _MapsTab(),
                      const _SystemTab(),
                      const _InfoTab(),
                      const _LogsTab(),
                      const SimulatePanel(),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              children: [
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: hc.accent,
                  unselectedLabelColor: hc.textSecondary,
                  indicatorColor: hc.accent,
                  tabs: _tabs
                      .map((t) =>
                          Tab(icon: Icon(t.icon, size: 18), text: t.label))
                      .toList(),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _ConnectionTab(),
                      const _TelemetryTab(),
                      const _VideoTab(),
                      const _DisplayTab(),
                      const _MapsTab(),
                      const _SystemTab(),
                      const _InfoTab(),
                      const _LogsTab(),
                      const SimulatePanel(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Sidebar tab item ─────────────────────────────────────────────────────────

class _SidebarTabItem extends StatelessWidget {
  const _SidebarTabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color:
            selected ? hc.accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(icon,
                    size: 16,
                    color: selected ? hc.accent : hc.textSecondary),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? hc.accent : hc.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Section helper ───────────────────────────────────────────────────────────

class _SetupSection extends StatelessWidget {
  const _SetupSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: hc.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: hc.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ],
    );
  }
}

// ─── Connection Tab ───────────────────────────────────────────────────────────

class _ConnectionTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ConnectionTab> createState() => _ConnectionTabState();
}

class _ConnectionTabState extends ConsumerState<_ConnectionTab> {
  String _transportType = 'UDP';
  ProtocolType _protocol = ProtocolType.auto;
  final _addressController = TextEditingController(text: '0.0.0.0');
  final _portController = TextEditingController(text: '14550');
  final _wsHostController = TextEditingController(text: 'localhost');
  final _wsPortController = TextEditingController(text: '8765');
  final _tcpHostController = TextEditingController(text: '127.0.0.1');
  final _tcpPortController = TextEditingController(text: '5760');
  String? _errorMessage;

  List<String> _serialPorts = [];
  Map<String, String> _serialPortDescriptions = {};
  String? _selectedSerialPort;
  int _baudRate = 115200;
  static const _baudRates = [
    9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600
  ];

  @override
  void initState() {
    super.initState();
    _refreshSerialPorts();
    _loadSavedSettings();
  }

  void _loadSavedSettings() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final saved = ref.read(connectionSettingsProvider);
      if (saved == null) return;
      setState(() {
        switch (saved) {
          case UdpConnectionConfig(:final bindAddress, :final port, :final protocol):
            _transportType = 'UDP';
            _addressController.text = bindAddress;
            _portController.text = port.toString();
            _protocol = protocol;
          case TcpConnectionConfig(:final host, :final port, :final protocol):
            _transportType = 'TCP';
            _tcpHostController.text = host;
            _tcpPortController.text = port.toString();
            _protocol = protocol;
          case SerialConnectionConfig(:final portName, :final baudRate, :final protocol):
            _transportType = 'Serial';
            _selectedSerialPort = portName;
            _baudRate = baudRate;
            _protocol = protocol;
          case WebSocketConnectionConfig(:final host, :final port, :final protocol):
            _transportType = 'WebSocket';
            _wsHostController.text = host;
            _wsPortController.text = port.toString();
            _protocol = protocol;
        }
      });
    });
  }

  void _refreshSerialPorts() {
    try {
      final ports = serialPortService.availablePorts();
      _serialPorts = ports.map((info) => info.name).toList();
      _serialPortDescriptions = {
        for (final info in ports) info.name: info.displayName,
      };
      if (_serialPorts.isNotEmpty && _selectedSerialPort == null) {
        _selectedSerialPort = _serialPorts.first;
      }
      if (_selectedSerialPort != null &&
          !_serialPorts.contains(_selectedSerialPort)) {
        _selectedSerialPort =
            _serialPorts.isNotEmpty ? _serialPorts.first : null;
      }
    } catch (_) {
      _serialPorts = [];
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _addressController.dispose();
    _portController.dispose();
    _tcpHostController.dispose();
    _tcpPortController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() => _errorMessage = null);
    final ConnectionConfig config;
    try {
      if (_transportType == 'UDP') {
        config = UdpConnectionConfig(
          bindAddress: _addressController.text.trim(),
          port: int.parse(_portController.text.trim()),
          protocol: _protocol,
        );
      } else if (_transportType == 'TCP') {
        config = TcpConnectionConfig(
          host: _tcpHostController.text.trim(),
          port: int.parse(_tcpPortController.text.trim()),
          protocol: _protocol,
        );
      } else if (_transportType == 'Serial') {
        if (_selectedSerialPort == null) {
          setState(() => _errorMessage = 'No serial port selected');
          return;
        }
        config = SerialConnectionConfig(
          portName: _selectedSerialPort!,
          baudRate: _baudRate,
          protocol: _protocol,
        );
      } else if (_transportType == 'WebSocket') {
        config = WebSocketConnectionConfig(
          host: _wsHostController.text.trim(),
          port: int.parse(_wsPortController.text.trim()),
          protocol: _protocol,
        );
      } else {
        return;
      }
      await ref.read(connectionControllerProvider.notifier).connect(config);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    }
  }

  Future<void> _disconnect() async {
    await ref.read(connectionControllerProvider.notifier).disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final connection = ref.watch(connectionControllerProvider);
    final vehicle = ref.watch(vehicleStateProvider);
    final isConnected = connection.transportState == TransportState.connected;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SetupSection(
            title: 'PROTOCOL',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<ProtocolType>(
                  segments: const [
                    ButtonSegment(
                      value: ProtocolType.auto,
                      label: Text('Auto'),
                    ),
                    ButtonSegment(
                      value: ProtocolType.mavlink,
                      label: Text('MAVLink'),
                    ),
                    ButtonSegment(
                      value: ProtocolType.msp,
                      label: Text('MSP'),
                    ),
                  ],
                  selected: {_protocol},
                  onSelectionChanged: isConnected
                      ? null
                      : (v) => setState(() => _protocol = v.first),
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact),
                ),
                const SizedBox(height: 8),
                Text(
                  switch (_protocol) {
                    ProtocolType.auto =>
                      'Probes for MAVLink and MSP simultaneously — picks whichever responds first (5s timeout).',
                    ProtocolType.mavlink =>
                      'MAVLink — ArduPilot, PX4, iNav (with MAVLink enabled).',
                    ProtocolType.msp =>
                      'MSP — Betaflight & iNav. Mission planning not available.',
                  },
                  style: TextStyle(fontSize: 12, color: hc.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SetupSection(
            title: 'TRANSPORT',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'UDP', label: Text('UDP')),
                    ButtonSegment(value: 'TCP', label: Text('TCP')),
                    ButtonSegment(value: 'Serial', label: Text('Serial')),
                    ButtonSegment(value: 'WebSocket', label: Text('WS')),
                  ],
                  selected: {_transportType},
                  onSelectionChanged: isConnected
                      ? null
                      : (v) => setState(() => _transportType = v.first),
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact),
                ),
                const SizedBox(height: 16),
                if (_transportType == 'UDP') ...[
                  TextField(
                    controller: _addressController,
                    decoration:
                        const InputDecoration(labelText: 'Bind Address'),
                    enabled: !isConnected,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _portController,
                    decoration: const InputDecoration(labelText: 'Port'),
                    keyboardType: TextInputType.number,
                    enabled: !isConnected,
                  ),
                ] else if (_transportType == 'TCP') ...[
                  TextField(
                    controller: _tcpHostController,
                    decoration: const InputDecoration(labelText: 'Host'),
                    enabled: !isConnected,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tcpPortController,
                    decoration: const InputDecoration(labelText: 'Port'),
                    keyboardType: TextInputType.number,
                    enabled: !isConnected,
                  ),
                ] else if (_transportType == 'WebSocket') ...[
                  _WebSocketPanel(
                    wsHostController: _wsHostController,
                    wsPortController: _wsPortController,
                    isConnected: isConnected,
                  ),
                ] else if (Platform.isIOS) ...[
                  // iOS does not support USB serial (libserialport has no iOS backend).
                  // Users must connect via UDP or TCP (WiFi telemetry radio / network bridge).
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hc.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: hc.warning.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: hc.warning, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'USB serial is not supported on iOS. '
                            'Connect your flight controller using a WiFi telemetry radio '
                            'and select UDP or TCP above.',
                            style: TextStyle(color: hc.warning, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Serial port picker
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          value: _serialPorts.contains(_selectedSerialPort)
                              ? _selectedSerialPort
                              : null,
                          hint: const Text('Select port',
                              style: TextStyle(fontSize: 13)),
                          isExpanded: true,
                          dropdownColor: hc.surfaceLight,
                          items: _serialPorts.map((port) {
                            final desc =
                                _serialPortDescriptions[port] ?? port;
                            return DropdownMenuItem(
                              value: port,
                              child: Text(
                                desc,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: isConnected
                              ? null
                              : (v) =>
                                  setState(() => _selectedSerialPort = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Refresh ports',
                        onPressed:
                            isConnected ? null : _refreshSerialPorts,
                      ),
                    ],
                  ),
                  if (_serialPorts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'No serial ports detected. Connect your flight controller via USB.',
                        style:
                            TextStyle(color: hc.warning, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('Baud Rate: ',
                          style: TextStyle(
                              color: hc.textSecondary, fontSize: 13)),
                      DropdownButton<int>(
                        value: _baudRate,
                        dropdownColor: hc.surfaceLight,
                        items: _baudRates
                            .map((b) => DropdownMenuItem(
                                  value: b,
                                  child: Text('$b',
                                      style: const TextStyle(
                                          fontSize: 13)),
                                ))
                            .toList(),
                        onChanged: isConnected
                            ? null
                            : (v) {
                                if (v != null)
                                  setState(() => _baudRate = v);
                              },
                      ),
                    ],
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: hc.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(_errorMessage!,
                        style:
                            TextStyle(color: hc.danger, fontSize: 12)),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: isConnected ? null : _connect,
                      icon: const Icon(Icons.link, size: 16),
                      label: Text(
                        connection.transportState ==
                                TransportState.connecting
                            ? 'Connecting...'
                            : 'Connect',
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: isConnected ? _disconnect : null,
                      icon: const Icon(Icons.link_off, size: 16),
                      label: const Text('Disconnect'),
                    ),
                    const Spacer(),
                    // Auto-connect toggle
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Auto-connect',
                          style: TextStyle(
                            fontSize: 12,
                            color: hc.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 24,
                          child: Switch(
                            value: ref.watch(autoConnectEnabledProvider),
                            onChanged: (v) =>
                                ref.read(autoConnectEnabledProvider.notifier).state = v,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SetupSection(
            title: 'LINK STATUS',
            child: Column(
              children: [
                _StatusRow(
                  label: 'State',
                  value: switch (connection.transportState) {
                    TransportState.disconnected => 'Disconnected',
                    TransportState.connecting => 'Connecting...',
                    TransportState.connected => 'Connected',
                    TransportState.error => 'Error',
                  },
                  color: switch (connection.linkState) {
                    LinkState.connected => hc.success,
                    LinkState.degraded => hc.warning,
                    LinkState.lost => hc.danger,
                    LinkState.disconnected => hc.textSecondary,
                  },
                ),
                _StatusRow(
                  label: 'Link',
                  value: switch (connection.linkState) {
                    LinkState.connected => 'Healthy',
                    LinkState.degraded => 'Degraded',
                    LinkState.lost => 'Lost',
                    LinkState.disconnected => '--',
                  },
                ),
                _StatusRow(
                  label: 'Vehicle',
                  value: vehicle.vehicleType != VehicleType.unknown
                      ? '${vehicle.vehicleType.name} (SysID ${vehicle.systemId})'
                      : '--',
                ),
                _StatusRow(
                  label: 'Autopilot',
                  value: vehicle.autopilotType != AutopilotType.unknown
                      ? vehicle.autopilotType.name
                      : '--',
                ),
                if (vehicle.firmwareVersionString.isNotEmpty)
                  _StatusRow(
                    label: 'Firmware',
                    value: vehicle.firmwareVersionString,
                  ),
                if (vehicle.boardVersion > 0)
                  _StatusRow(
                    label: 'Board',
                    value: 'v${vehicle.boardVersion}',
                  ),
                if (vehicle.vehicleUid > 0)
                  _StatusRow(
                    label: 'UID',
                    value: vehicle.vehicleUid
                        .toRadixString(16)
                        .toUpperCase(),
                  ),
                _StatusRow(
                  label: 'Messages/s',
                  value: connection.messageRate.toStringAsFixed(0),
                ),
                _StatusRow(
                  label: 'Total msgs',
                  value: '${connection.messagesReceived}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Telemetry Tab ────────────────────────────────────────────────────────────

class _TelemetryTab extends ConsumerWidget {
  const _TelemetryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SetupSection(
            title: 'TELEMETRY RATES',
            child: _StreamRateSettings(),
          ),
          const SizedBox(height: 24),
          const _SetupSection(
            title: 'RECORDING',
            child: _RecordingStatus(),
          ),
        ],
      ),
    );
  }
}

// ─── Video Tab ────────────────────────────────────────────────────────────────

class _VideoTab extends ConsumerWidget {
  const _VideoTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _SetupSection(
        title: 'VIDEO STREAM',
        child: _VideoSettings(),
      ),
    );
  }
}

// ─── Display Tab ─────────────────────────────────────────────────────────────

class _DisplayTab extends ConsumerWidget {
  const _DisplayTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SetupSection(
            title: 'THEME',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text(
                    'Colour scheme',
                    style: TextStyle(
                        fontSize: 13, color: context.hc.textSecondary),
                  ),
                  const Spacer(),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined, size: 16),
                        label: Text('Dark'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined, size: 16),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined, size: 16),
                        label: Text('Auto'),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (modes) => ref
                        .read(themeModeProvider.notifier)
                        .setMode(modes.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SetupSection(
            title: 'SCALE',
            child: _DisplaySettings(),
          ),
          const SizedBox(height: 24),
          _SetupSection(
            title: 'LAYOUT PROFILES',
            child: _LayoutProfilesSection(),
          ),
        ],
      ),
    );
  }
}

// ─── Maps Tab ────────────────────────────────────────────────────────────────

class _MapsTab extends ConsumerWidget {
  const _MapsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _SetupSection(
        title: 'OFFLINE MAPS',
        child: _MapCacheSettings(),
      ),
    );
  }
}

// ─── System Tab ──────────────────────────────────────────────────────────────

class _SystemTab extends ConsumerWidget {
  const _SystemTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SetupSection(
            title: 'PREDICTIVE MAINTENANCE',
            child: _MaintenancePanel(),
          ),
          const SizedBox(height: 24),
          _SetupSection(
            title: 'RESET',
            child: _ResetSection(),
          ),
        ],
      ),
    );
  }
}

// ─── Info Tab ─────────────────────────────────────────────────────────────────

class _InfoTab extends StatelessWidget {
  const _InfoTab();

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final os = Platform.operatingSystem;
    final osVersion = Platform.operatingSystemVersion;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SetupSection(
            title: 'APPLICATION',
            child: Column(
              children: [
                _InfoRow(label: 'Name', value: 'Helios GCS', hc: hc),
                _InfoRow(label: 'Version', value: 'v0.1.0', hc: hc),
                _InfoRow(
                    label: 'Platform', value: 'Part of the Argus Platform', hc: hc),
                _InfoRow(label: 'Licence', value: 'Apache 2.0', hc: hc),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SetupSection(
            title: 'RUNTIME',
            child: Column(
              children: [
                _InfoRow(label: 'Framework', value: 'Flutter 3.38', hc: hc),
                _InfoRow(label: 'Language', value: 'Dart 3.10', hc: hc),
                _InfoRow(
                    label: 'Operating system',
                    value: '${os[0].toUpperCase()}${os.substring(1)}',
                    hc: hc),
                _InfoRow(label: 'OS version', value: osVersion, hc: hc),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SetupSection(
            title: 'KEY LIBRARIES',
            child: Column(
              children: [
                _InfoRow(label: 'Telemetry database', value: 'DuckDB (columnar OLAP)', hc: hc),
                _InfoRow(label: 'MAVLink', value: 'dart_mavlink (vendored v2 parser)', hc: hc),
                _InfoRow(label: 'Map tiles', value: 'flutter_map + OSM', hc: hc),
                _InfoRow(label: 'Video', value: 'media_kit (LGPL dynamic)', hc: hc),
                _InfoRow(label: 'Serial', value: 'flutter_libserialport', hc: hc),
                _InfoRow(label: 'State', value: 'Riverpod', hc: hc),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SetupSection(
            title: 'ABOUT',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Text(
                'Open-source ground control station for MAVLink UAVs '
                '(ArduPilot, PX4). Every flight is automatically recorded '
                'into a DuckDB database, making post-flight analysis as '
                'powerful as the live display.',
                style: TextStyle(color: hc.textSecondary, fontSize: 13, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.hc,
  });

  final String label;
  final String value;
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(fontSize: 13, color: hc.textSecondary)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  color: hc.textPrimary,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─── Predictive maintenance panel ────────────────────────────────────────────

/// Predictive maintenance panel that surfaces alerts derived from flight history.
class _MaintenancePanel extends ConsumerWidget {
  const _MaintenancePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final asyncAlerts = ref.watch(maintenanceAlertsProvider);

    return asyncAlerts.when(
      loading: () => const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Text(
        'Analysis error: $e',
        style: TextStyle(color: hc.danger, fontSize: 12),
      ),
      data: (alerts) {
        if (alerts.isEmpty) {
          return Row(
            children: [
              Icon(Icons.check_circle_outline,
                  size: 18, color: hc.success),
              const SizedBox(width: 8),
              Text(
                'No maintenance concerns detected.',
                style: TextStyle(
                    color: hc.textSecondary, fontSize: 13),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: alerts.map((alert) => _AlertTile(alert: alert)).toList(),
        );
      },
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});

  final MaintenanceAlert alert;

  IconData get _icon => switch (alert.severity) {
        MaintenanceSeverity.critical => Icons.error_outline,
        MaintenanceSeverity.warning => Icons.warning_amber_outlined,
        MaintenanceSeverity.info => Icons.info_outline,
      };

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final color = switch (alert.severity) {
      MaintenanceSeverity.critical => hc.danger,
      MaintenanceSeverity.warning => hc.warning,
      MaintenanceSeverity.info => hc.accent,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      alert.category,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: color,
                          letterSpacing: 0.5),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        alert.severity.label.toUpperCase(),
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  alert.title,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: hc.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  alert.detail,
                  style:
                      TextStyle(fontSize: 12, color: hc.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoSettings extends ConsumerStatefulWidget {
  @override
  ConsumerState<_VideoSettings> createState() => _VideoSettingsState();
}

class _VideoSettingsState extends ConsumerState<_VideoSettings> {
  late TextEditingController _urlController;
  bool _urlFocused = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(videoPlayerProvider);
    _urlController = TextEditingController(text: settings.rtspUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(videoPlayerProvider);
    final videoCtrl = ref.watch(videoPlayerProvider.notifier);

    // Sync from provider when not actively editing
    if (!_urlFocused && _urlController.text != settings.rtspUrl) {
      _urlController.text = settings.rtspUrl;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Focus(
          onFocusChange: (focused) => _urlFocused = focused,
          child: TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'RTSP URL',
              hintText: 'rtsp://192.168.0.10:8554/main',
            ),
            onChanged: (url) {
              ref.read(videoPlayerProvider.notifier).updateSettings(
                settings.copyWith(rtspUrl: url),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Low-latency mode'),
          subtitle: const Text('Minimise buffer for real-time video'),
          value: settings.lowLatency,
          onChanged: (v) {
            ref.read(videoPlayerProvider.notifier).updateSettings(
              settings.copyWith(lowLatency: v),
            );
          },
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: const Text('Auto-connect on launch'),
          subtitle: const Text('Automatically start video when app opens'),
          value: settings.autoConnect,
          onChanged: (v) {
            ref.read(videoPlayerProvider.notifier).updateSettings(
              settings.copyWith(autoConnect: v),
            );
          },
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed:
                  videoCtrl.isPlaying ? null : () => videoCtrl.connect(),
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('Test Stream'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: videoCtrl.isPlaying
                  ? () => videoCtrl.disconnect()
                  : null,
              icon: const Icon(Icons.stop, size: 16),
              label: const Text('Stop'),
            ),
          ],
        ),
        if (videoCtrl.lastError != null) ...[
          const SizedBox(height: 8),
          Text(
            videoCtrl.lastError!,
            style: TextStyle(color: context.hc.danger, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// Read-only recording status — recording is automatic (start on connect,
/// stop on disconnect) so no manual controls are needed.
class _RecordingStatus extends ConsumerWidget {
  const _RecordingStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final recording = ref.watch(recordingStateProvider);
    final isRecording = recording.isRecording;
    // rowsWritten comes from the store directly (live counter)
    final store = ref.read(telemetryStoreProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Telemetry is recorded automatically when a vehicle is connected '
          'and stops when disconnected. Each flight is saved as a DuckDB file.',
          style: TextStyle(color: hc.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isRecording
                ? hc.danger.withValues(alpha: 0.1)
                : hc.surfaceLight,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isRecording
                  ? hc.danger.withValues(alpha: 0.3)
                  : hc.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isRecording
                    ? Icons.fiber_manual_record
                    : Icons.circle_outlined,
                size: 14,
                color: isRecording ? hc.danger : hc.textTertiary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isRecording ? 'RECORDING' : 'IDLE',
                      style: TextStyle(
                        color:
                            isRecording ? hc.danger : hc.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isRecording)
                      Text(
                        '${store.rowsWritten} rows written',
                        style: TextStyle(
                            color: hc.textSecondary, fontSize: 12),
                      )
                    else
                      Text(
                        'Waiting for connection',
                        style: TextStyle(
                            color: hc.textTertiary, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Full layout profile management for Setup screen.
/// UI scale slider.
/// Map tile cache controls.
class _MapCacheSettings extends StatefulWidget {
  @override
  State<_MapCacheSettings> createState() => _MapCacheSettingsState();
}

class _MapCacheSettingsState extends State<_MapCacheSettings> {
  int? _cacheBytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _refreshSize();
  }

  Future<void> _refreshSize() async {
    final size = await CachedTileProvider.cacheSize();
    if (mounted) setState(() => _cacheBytes = size);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Map tiles are cached locally for offline use. '
          'Previously viewed areas will be available without internet.',
          style: TextStyle(color: hc.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.map, size: 18, color: hc.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Cache size: ${_cacheBytes != null ? _formatBytes(_cacheBytes!) : '...'}',
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: hc.textPrimary,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _clearing
                  ? null
                  : () async {
                      setState(() => _clearing = true);
                      await CachedTileProvider.clearCache();
                      await _refreshSize();
                      if (mounted) setState(() => _clearing = false);
                    },
              icon: Icon(
                _clearing ? Icons.hourglass_empty : Icons.delete_sweep,
                size: 14,
              ),
              label: Text(_clearing ? 'Clearing...' : 'Clear Cache'),
            ),
          ],
        ),
      ],
    );
  }
}

class _DisplaySettings extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final scale = ref.watch(displayScaleProvider);
    final notifier = ref.read(displayScaleProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Adjust the global text and widget scale for better readability.',
          style: TextStyle(color: hc.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('A',
                style: TextStyle(fontSize: 12, color: hc.textTertiary)),
            Expanded(
              child: Slider(
                value: scale,
                min: minScale,
                max: maxScale,
                divisions: ((maxScale - minScale) / scaleStep).round(),
                label: '${(scale * 100).round()}%',
                onChanged: (v) => notifier.setScale(v),
              ),
            ),
            Text('A',
                style: TextStyle(fontSize: 18, color: hc.textTertiary)),
            const SizedBox(width: 12),
            Text(
              '${(scale * 100).round()}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: hc.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            if (scale != defaultScale)
              TextButton(
                onPressed: () => notifier.reset(),
                child:
                    const Text('Reset', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ],
    );
  }
}

class _LayoutProfilesSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final layoutState = ref.watch(layoutProvider);
    final profiles = layoutState.profiles;
    final activeName = layoutState.activeProfileName;
    final notifier = ref.read(layoutProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Manage widget layout profiles for the Fly View. '
          'Each profile saves chart positions, PFD visibility, and sidebar settings.',
          style: TextStyle(color: hc.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),

        // Profile list
        ...profiles.map((profile) {
          final isActive = profile.name == activeName;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? hc.accent.withValues(alpha: 0.08)
                  : hc.surfaceLight,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isActive
                    ? hc.accent.withValues(alpha: 0.3)
                    : hc.border,
              ),
            ),
            child: ListTile(
              dense: true,
              leading: Icon(
                _vehicleIcon(profile.vehicleType),
                size: 20,
                color: isActive ? hc.accent : hc.textSecondary,
              ),
              title: Text(
                profile.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.w400,
                  color: hc.textPrimary,
                ),
              ),
              subtitle: Text(
                _profileSummary(profile),
                style: TextStyle(
                    fontSize: 12, color: hc.textTertiary),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: hc.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'ACTIVE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: hc.accent,
                        ),
                      ),
                    ),
                  if (!isActive) ...[
                    IconButton(
                      icon: const Icon(Icons.check_circle_outline,
                          size: 18),
                      color: hc.textSecondary,
                      tooltip: 'Set as active',
                      onPressed: () =>
                          notifier.selectProfile(profile.name),
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    color: hc.textSecondary,
                    tooltip: 'Duplicate',
                    onPressed: () =>
                        _showDuplicateDialog(context, ref, profile),
                  ),
                  if (!profile.isDefault)
                    IconButton(
                      icon:
                          const Icon(Icons.delete_outline, size: 16),
                      color: hc.danger,
                      tooltip: 'Delete',
                      onPressed: () =>
                          _confirmDelete(context, ref, profile.name),
                    ),
                  if (profile.isDefault)
                    IconButton(
                      icon: const Icon(Icons.restart_alt, size: 16),
                      color: hc.textSecondary,
                      tooltip: 'Reset to defaults',
                      onPressed: isActive
                          ? () => notifier.resetActiveProfile()
                          : null,
                    ),
                ],
              ),
              onTap: isActive
                  ? null
                  : () => notifier.selectProfile(profile.name),
            ),
          );
        }),

        const SizedBox(height: 12),

        OutlinedButton.icon(
          onPressed: () => _showCreateDialog(context, ref),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('New Profile'),
        ),
      ],
    );
  }

  String _profileSummary(layout.LayoutProfile profile) {
    final charts = profile.activeCharts;
    final chartLabels = charts.map((c) => c.label).join(', ');
    final parts = <String>[
      profile.vehicleType.label,
      if (charts.isNotEmpty) chartLabels else 'No charts',
      if (!profile.pfd.visible) 'PFD hidden',
      if (!profile.telemetryStrip.visible) 'Strip hidden',
    ];
    return parts.join(' | ');
  }

  IconData _vehicleIcon(layout.VehicleType type) {
    return switch (type) {
      layout.VehicleType.multirotor => Icons.toys,
      layout.VehicleType.fixedWing => Icons.flight,
      layout.VehicleType.vtol => Icons.connecting_airports,
    };
  }

  void _showCreateDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        final hc = ctx.hc;
        return AlertDialog(
          backgroundColor: hc.surface,
          title: Text('New Layout Profile',
              style:
                  TextStyle(color: hc.textPrimary, fontSize: 14)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: hc.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Profile name',
              hintStyle: TextStyle(color: hc.textTertiary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: hc.border),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: hc.accent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(
                      color: hc.textSecondary, fontSize: 12)),
            ),
            TextButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  ref.read(layoutProvider.notifier).createProfile(name);
                  Navigator.pop(ctx);
                }
              },
              child: Text('Create',
                  style:
                      TextStyle(color: hc.accent, fontSize: 12)),
            ),
          ],
        );
      },
    );
  }

  void _showDuplicateDialog(
      BuildContext context, WidgetRef ref, layout.LayoutProfile source) {
    final controller =
        TextEditingController(text: '${source.name} (copy)');
    showDialog(
      context: context,
      builder: (ctx) {
        final hc = ctx.hc;
        return AlertDialog(
          backgroundColor: hc.surface,
          title: Text('Duplicate Profile',
              style:
                  TextStyle(color: hc.textPrimary, fontSize: 14)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: hc.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'New profile name',
              hintStyle: TextStyle(color: hc.textTertiary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: hc.border),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: hc.accent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(
                      color: hc.textSecondary, fontSize: 12)),
            ),
            TextButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  final notifier = ref.read(layoutProvider.notifier);
                  notifier.selectProfile(source.name);
                  notifier.createProfile(name);
                  Navigator.pop(ctx);
                }
              },
              child: Text('Duplicate',
                  style:
                      TextStyle(color: hc.accent, fontSize: 12)),
            ),
          ],
        );
      },
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, String name) {
    showDialog(
      context: context,
      builder: (ctx) {
        final hc = ctx.hc;
        return AlertDialog(
          backgroundColor: hc.surface,
          title: Text('Delete "$name"?',
              style:
                  TextStyle(color: hc.textPrimary, fontSize: 14)),
          content: Text(
              'This layout profile will be permanently removed.',
              style:
                  TextStyle(color: hc.textSecondary, fontSize: 12)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: TextStyle(
                      color: hc.textSecondary, fontSize: 12)),
            ),
            TextButton(
              onPressed: () {
                ref.read(layoutProvider.notifier).deleteProfile(name);
                Navigator.pop(ctx);
              },
              child: Text('Delete',
                  style:
                      TextStyle(color: hc.danger, fontSize: 12)),
            ),
          ],
        );
      },
    );
  }
}

class _StreamRateSettings extends ConsumerWidget {
  const _StreamRateSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final rates = ref.watch(streamRateProvider);
    final notifier = ref.read(streamRateProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Control how fast telemetry is requested from the flight controller. '
          'Higher rates give smoother instruments but use more bandwidth and storage.',
          style: TextStyle(color: hc.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),

        // Preset buttons
        Wrap(
          spacing: 8,
          children: StreamRatePreset.values
              .where((p) => p != StreamRatePreset.custom)
              .map((preset) => ChoiceChip(
                    label: Text(preset.label,
                        style: const TextStyle(fontSize: 12)),
                    selected: rates.preset == preset,
                    onSelected: (_) => notifier.applyPreset(preset),
                    selectedColor: hc.accentDim,
                    backgroundColor: hc.surfaceLight,
                    labelStyle: TextStyle(
                      color: rates.preset == preset
                          ? hc.textPrimary
                          : hc.textSecondary,
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),

        // Individual rate sliders
        _RateSlider(
          label: 'Attitude (PFD)',
          value: rates.attitudeHz,
          min: 1,
          max: 50,
          onChanged: (v) => notifier.setRate(attitudeHz: v),
        ),
        _RateSlider(
          label: 'Position (GPS/Map)',
          value: rates.positionHz,
          min: 1,
          max: 10,
          onChanged: (v) => notifier.setRate(positionHz: v),
        ),
        _RateSlider(
          label: 'VFR HUD (Speed/Alt)',
          value: rates.vfrHudHz,
          min: 1,
          max: 10,
          onChanged: (v) => notifier.setRate(vfrHudHz: v),
        ),
        _RateSlider(
          label: 'Status (Battery/GPS fix)',
          value: rates.statusHz,
          min: 1,
          max: 5,
          onChanged: (v) => notifier.setRate(statusHz: v),
        ),

        const SizedBox(height: 8),
        Text(
          'Est. ${rates.estimatedRowsPerMinute} rows/min to DuckDB',
          style: TextStyle(
            color: hc.textTertiary,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Changes take effect on next connect.',
          style: TextStyle(color: hc.textTertiary, fontSize: 12),
        ),
      ],
    );
  }
}

class _RateSlider extends StatelessWidget {
  const _RateSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: hc.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 45,
            child: Text(
              '$value Hz',
              style: TextStyle(
                color: hc.textPrimary,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResetSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Clear all saved settings, recorded flights, and cached data. '
          'The app will restart in its default state.',
          style: TextStyle(color: hc.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => _resetSettings(context, ref),
              icon: const Icon(Icons.settings_backup_restore, size: 16),
              label: const Text('Reset Settings'),
              style: OutlinedButton.styleFrom(
                foregroundColor: hc.warning,
                side: BorderSide(color: hc.warning),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () => _resetAll(context, ref),
              icon: const Icon(Icons.delete_forever, size: 16),
              label: const Text('Wipe All Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: hc.dangerDim,
                foregroundColor: hc.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _resetSettings(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final hc = ctx.hc;
        return AlertDialog(
          backgroundColor: hc.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: hc.border),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: hc.warning, size: 20),
              const SizedBox(width: 8),
              Text('Reset Settings',
                  style: TextStyle(
                      color: hc.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          content: Text(
            'Reset all settings to defaults?\n\n'
            'This clears connection history, stream rates, video URL, '
            'layout profiles, and display preferences.\n\n'
            'Recorded flights will NOT be deleted.',
            style: TextStyle(color: hc.textSecondary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel',
                  style: TextStyle(color: hc.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: hc.warningDim,
                foregroundColor: hc.textPrimary,
              ),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings reset. Restart the app.')),
      );
    }
  }

  Future<void> _resetAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final hc = ctx.hc;
        return AlertDialog(
          backgroundColor: hc.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: hc.border),
          ),
          title: Row(
            children: [
              Icon(Icons.delete_forever, color: hc.danger, size: 20),
              const SizedBox(width: 8),
              Text('Wipe All Data',
                  style: TextStyle(
                      color: hc.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          content: Text(
            'Delete ALL local data?\n\n'
            'This permanently removes:\n'
            '  \u2022 All settings and preferences\n'
            '  \u2022 All recorded flights (.duckdb files)\n'
            '  \u2022 Cached map tiles\n'
            '  \u2022 Layout profiles\n\n'
            'This cannot be undone.',
            style: TextStyle(color: hc.textSecondary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancel',
                  style: TextStyle(color: hc.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: hc.dangerDim,
                foregroundColor: hc.textPrimary,
              ),
              child: const Text('Wipe Everything'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    // 1. Clear SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // 2. Delete recorded flights
    try {
      final appDir = await getApplicationSupportDirectory();
      final flightsDir = Directory('${appDir.path}/flights');
      if (flightsDir.existsSync()) {
        flightsDir.deleteSync(recursive: true);
      }
    } catch (_) {}

    // 3. Clear map tile cache
    try {
      await CachedTileProvider.clearCache();
    } catch (_) {}

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('All data wiped. Restart the app to continue.')),
      );
    }
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: HeliosTypography.caption),
          Text(
            value,
            style: HeliosTypography.telemetrySmall.copyWith(
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Logs Tab ────────────────────────────────────────────────────────────────

class _LogsTab extends ConsumerStatefulWidget {
  const _LogsTab();

  @override
  ConsumerState<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends ConsumerState<_LogsTab> {
  List<LogInfo>? _logs;
  bool _loading = false;
  String? _error;
  // logId -> download progress (0.0-1.0) while downloading
  final _downloading = <int, double>{};
  // logId -> completed file path
  final _downloaded = <int, String>{};

  @override
  void initState() {
    super.initState();
    // Auto-fetch logs when the tab opens and we're connected.
    // Delay slightly so the vehicle state has time to populate systemId
    // from the heartbeat (30Hz batch timer needs at least one flush).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final connected = ref.read(connectionControllerProvider).transportState ==
          TransportState.connected;
      if (connected && _logs == null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _logs == null) _fetchLogs();
        });
      }
    });
  }

  Future<void> _fetchLogs() async {
    final controller = ref.read(connectionControllerProvider.notifier);
    final logService = controller.logDownloadService;
    if (logService == null) return;

    final vehicle = ref.read(vehicleStateProvider);
    // Use default IDs if the vehicle state hasn't been populated yet.
    final sysId = vehicle.systemId > 0 ? vehicle.systemId : 1;
    final compId = vehicle.componentId > 0 ? vehicle.componentId : 1;
    setState(() { _loading = true; _error = null; });

    try {
      final logs = await logService.listLogs(
        targetSystem: sysId,
        targetComponent: compId,
      );
      if (mounted) setState(() { _logs = logs; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _downloadLog(LogInfo log) async {
    final controller = ref.read(connectionControllerProvider.notifier);
    final logService = controller.logDownloadService;
    if (logService == null) return;

    final vehicle = ref.read(vehicleStateProvider);
    setState(() => _downloading[log.id] = 0.0);

    try {
      final path = await logService.downloadLog(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
        logId: log.id,
        logSize: log.size,
        onProgress: (progress) {
          if (mounted) setState(() => _downloading[log.id] = progress);
        },
      );

      await logService.endLogRequest(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
      );

      if (mounted) {
        setState(() {
          _downloading.remove(log.id);
          _downloaded[log.id] = path;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Log ${log.id} saved to ${p.basename(path)}'),
            backgroundColor: context.hc.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading.remove(log.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: context.hc.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final isConnected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: isConnected && !_loading ? _fetchLogs : null,
                icon: _loading
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      )
                    : const Icon(Icons.refresh, size: 16),
                label: Text(_loading ? 'Fetching…' : 'Refresh Log List'),
              ),
              const SizedBox(width: 12),
              if (_logs != null)
                Text(
                  '${_logs!.length} log${_logs!.length == 1 ? '' : 's'} on vehicle',
                  style: TextStyle(color: hc.textTertiary, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: hc.danger, fontSize: 12)),
            ),

          if (!isConnected && _logs == null)
            Expanded(
              child: Center(
                child: Text(
                  'Connect to a vehicle and tap "Refresh" to list onboard logs.',
                  style: TextStyle(color: hc.textTertiary, fontSize: 13),
                ),
              ),
            ),

          if (_logs != null && _logs!.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'No logs found on vehicle.',
                  style: TextStyle(color: hc.textTertiary, fontSize: 13),
                ),
              ),
            ),

          if (_logs != null && _logs!.isNotEmpty) ...[
            // Column headers
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: hc.surfaceDim,
                border: Border(bottom: BorderSide(color: hc.border)),
              ),
              child: Row(
                children: [
                  _LogHeaderCell(label: 'ID', flex: 1),
                  _LogHeaderCell(label: 'Date', flex: 3),
                  _LogHeaderCell(label: 'Size', flex: 2),
                  _LogHeaderCell(label: 'Status', flex: 3),
                  const SizedBox(width: 90),
                ],
              ),
            ),

            // Log list
            Expanded(
              child: ListView.separated(
                itemCount: _logs!.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: hc.border),
                itemBuilder: (ctx, i) {
                  final log = _logs![i];
                  final progress = _downloading[log.id];
                  final filePath = _downloaded[log.id];

                  final dateStr = log.dateTime != null
                      ? '${log.dateTime!.year}-'
                        '${log.dateTime!.month.toString().padLeft(2, '0')}-'
                        '${log.dateTime!.day.toString().padLeft(2, '0')} '
                        '${log.dateTime!.hour.toString().padLeft(2, '0')}:'
                        '${log.dateTime!.minute.toString().padLeft(2, '0')}'
                      : '—';

                  return Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: Text(
                            '#${log.id}',
                            style: TextStyle(
                              color: hc.textPrimary,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            dateStr,
                            style: TextStyle(color: hc.textSecondary, fontSize: 12),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            log.sizeLabel,
                            style: TextStyle(color: hc.textSecondary, fontSize: 12),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: progress != null
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        backgroundColor: hc.border,
                                        color: hc.accent,
                                        minHeight: 4,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${(progress * 100).toInt()}%',
                                      style: TextStyle(
                                          color: hc.textTertiary, fontSize: 11),
                                    ),
                                  ],
                                )
                              : filePath != null
                                  ? Row(
                                      children: [
                                        Icon(Icons.check_circle_outline,
                                            size: 14, color: hc.success),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            p.basename(filePath),
                                            style: TextStyle(
                                                color: hc.success, fontSize: 11),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const SizedBox.shrink(),
                        ),
                        SizedBox(
                          width: 90,
                          child: progress == null
                              ? TextButton(
                                  onPressed: isConnected
                                      ? () => _downloadLog(log)
                                      : null,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    filePath != null ? 'Re-download' : 'Download',
                                    style: TextStyle(
                                      color: isConnected
                                          ? hc.accent
                                          : hc.textTertiary,
                                      fontSize: 12,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LogHeaderCell extends StatelessWidget {
  const _LogHeaderCell({required this.label, required this.flex});
  final String label;
  final int flex;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
            color: hc.textTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ─── WebSocket connection panel with relay detection ─────────────────────────

class _WebSocketPanel extends ConsumerStatefulWidget {
  const _WebSocketPanel({
    required this.wsHostController,
    required this.wsPortController,
    required this.isConnected,
  });

  final TextEditingController wsHostController;
  final TextEditingController wsPortController;
  final bool isConnected;

  @override
  ConsumerState<_WebSocketPanel> createState() => _WebSocketPanelState();
}

class _WebSocketPanelState extends ConsumerState<_WebSocketPanel> {
  @override
  void initState() {
    super.initState();
    // Start checking for relay on mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkRelay();
    });
  }

  void _checkRelay() {
    final host = widget.wsHostController.text.trim();
    final port = int.tryParse(widget.wsPortController.text.trim()) ?? 8765;
    ref.read(relayStatusProvider.notifier).check(host: host, port: port);
  }

  @override
  Widget build(BuildContext context) {
    final relayStatus = ref.watch(relayStatusProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.wsHostController,
          decoration: const InputDecoration(
            labelText: 'Host',
            hintText: 'localhost or relay IP',
          ),
          enabled: !widget.isConnected,
          onChanged: (_) => _checkRelay(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.wsPortController,
          decoration: const InputDecoration(labelText: 'Port'),
          keyboardType: TextInputType.number,
          enabled: !widget.isConnected,
          onChanged: (_) => _checkRelay(),
        ),
        const SizedBox(height: 12),

        // Relay status indicator
        _RelayStatusBanner(
          status: relayStatus,
          onRetry: _checkRelay,
        ),
      ],
    );
  }
}

class _RelayStatusBanner extends StatelessWidget {
  const _RelayStatusBanner({
    required this.status,
    required this.onRetry,
  });

  final RelayStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    return switch (status) {
      RelayStatus.available => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: hc.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: hc.success.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: hc.success, size: 16),
              const SizedBox(width: 8),
              Text('Relay detected', style: TextStyle(color: hc.success, fontSize: 12)),
            ],
          ),
        ),
      RelayStatus.checking => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: hc.textSecondary)),
              const SizedBox(width: 8),
              Text('Checking for relay...', style: TextStyle(color: hc.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      RelayStatus.unknown => const SizedBox.shrink(),
      RelayStatus.unavailable => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: hc.surfaceLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: hc.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: hc.accent, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Relay not detected',
                    style: TextStyle(color: hc.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onRetry,
                    child: Text('Retry', style: TextStyle(color: hc.accent, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'The relay bridges your browser to the flight controller over WiFi. '
                'Install it with one command:',
                style: TextStyle(color: hc.textSecondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 10),
              _InstallOption(
                label: 'Download binary (no dependencies)',
                command: 'curl -fsSL https://helios.argus.dev/relay/install.sh | sh',
              ),
              const SizedBox(height: 6),
              _InstallOption(
                label: 'Or with Dart SDK',
                command: 'dart pub global activate helios_relay',
              ),
              const SizedBox(height: 10),
              Text(
                'Then run:',
                style: TextStyle(color: hc.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 4),
              _InstallOption(
                label: '',
                command: 'helios-relay --fc-host 192.168.4.1',
              ),
              const SizedBox(height: 8),
              Text(
                'No admin access required. Connects to your FC on WiFi and '
                'bridges it to this browser tab.',
                style: TextStyle(color: hc.textTertiary, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
    };
  }
}

class _InstallOption extends StatelessWidget {
  const _InstallOption({required this.label, required this.command});

  final String label;
  final String command;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(label, style: TextStyle(color: hc.textSecondary, fontSize: 11)),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: hc.border.withValues(alpha: 0.5)),
          ),
          child: SelectableText(
            command,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: hc.accent,
            ),
          ),
        ),
      ],
    );
  }
}
