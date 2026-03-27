import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/mavlink/transports/serial_transport.dart';
import '../../shared/models/connection_state.dart';
import '../../shared/providers/connection_settings_provider.dart';
import '../../shared/providers/stream_rate_provider.dart';
import 'widgets/calibration_wizard.dart';
import '../../shared/models/layout_profile.dart' as layout;
import '../../shared/models/vehicle_state.dart';
import '../../core/map/cached_tile_provider.dart';
import '../../shared/providers/display_provider.dart';
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
    (icon: Icons.sensors_outlined, label: 'Calibration'),
    (icon: Icons.videocam_outlined, label: 'Video'),
    (icon: Icons.dashboard_customize_outlined, label: 'Display'),
    (icon: Icons.map_outlined, label: 'Offline Maps'),
    (icon: Icons.build_outlined, label: 'System'),
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
                      const _CalibrationTab(),
                      const _VideoTab(),
                      const _DisplayTab(),
                      const _MapsTab(),
                      const _SystemTab(),
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
                      const _CalibrationTab(),
                      const _VideoTab(),
                      const _DisplayTab(),
                      const _MapsTab(),
                      const _SystemTab(),
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
  final _addressController = TextEditingController(text: '0.0.0.0');
  final _portController = TextEditingController(text: '14550');
  final _tcpHostController = TextEditingController(text: '127.0.0.1');
  final _tcpPortController = TextEditingController(text: '5760');
  String? _errorMessage;

  List<String> _serialPorts = [];
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
          case UdpConnectionConfig(:final bindAddress, :final port):
            _transportType = 'UDP';
            _addressController.text = bindAddress;
            _portController.text = port.toString();
          case TcpConnectionConfig(:final host, :final port):
            _transportType = 'TCP';
            _tcpHostController.text = host;
            _tcpPortController.text = port.toString();
          case SerialConnectionConfig(:final portName, :final baudRate):
            _transportType = 'Serial';
            _selectedSerialPort = portName;
            _baudRate = baudRate;
        }
      });
    });
  }

  void _refreshSerialPorts() {
    try {
      _serialPorts = SerialTransport.availablePorts();
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
        );
      } else if (_transportType == 'TCP') {
        config = TcpConnectionConfig(
          host: _tcpHostController.text.trim(),
          port: int.parse(_tcpPortController.text.trim()),
        );
      } else if (_transportType == 'Serial') {
        if (_selectedSerialPort == null) {
          setState(() => _errorMessage = 'No serial port selected');
          return;
        }
        config = SerialConnectionConfig(
          portName: _selectedSerialPort!,
          baudRate: _baudRate,
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
            title: 'TRANSPORT',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'UDP', label: Text('UDP')),
                    ButtonSegment(value: 'TCP', label: Text('TCP')),
                    ButtonSegment(value: 'Serial', label: Text('Serial')),
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
                                SerialTransport.portDescription(port);
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

// ─── Calibration Tab ─────────────────────────────────────────────────────────

class _CalibrationTab extends ConsumerWidget {
  const _CalibrationTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: _SetupSection(
        title: 'SENSOR CALIBRATION',
        child: CalibrationWizard(),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    final hc = context.hc;
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
          const SizedBox(height: 24),
          _SetupSection(
            title: 'ABOUT',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Helios GCS',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: hc.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  'v0.1.0 — Part of the Argus Platform',
                  style:
                      TextStyle(color: hc.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  'Open-source ground control station for MAVLink UAVs.\n'
                  'Apache 2.0 Licence.',
                  style:
                      TextStyle(color: hc.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
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
    final store = ref.watch(telemetryStoreProvider);
    final isRecording = store.isRecording;

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
