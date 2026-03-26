import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/mavlink/transports/serial_transport.dart';
import '../../shared/models/connection_state.dart';
import '../../shared/providers/connection_settings_provider.dart';
import '../../shared/providers/stream_rate_provider.dart';
import 'widgets/calibration_wizard.dart';
import 'widgets/parameter_editor.dart';
import '../../shared/models/layout_profile.dart' as layout;
import '../../shared/models/vehicle_state.dart';
import '../../core/map/cached_tile_provider.dart';
import '../../shared/providers/display_provider.dart';
import '../../shared/providers/layout_provider.dart';
import '../../shared/providers/providers.dart';
import '../../shared/providers/video_provider.dart';
import '../../shared/theme/helios_colors.dart';
import '../../shared/theme/helios_typography.dart';

/// Setup View — connection and recording configuration.
class SetupView extends ConsumerStatefulWidget {
  const SetupView({super.key});

  @override
  ConsumerState<SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends ConsumerState<SetupView> {
  String _transportType = 'UDP';
  final _addressController = TextEditingController(text: '0.0.0.0');
  final _portController = TextEditingController(text: '14550');
  final _tcpHostController = TextEditingController(text: '127.0.0.1');
  final _tcpPortController = TextEditingController(text: '5760');
  String? _errorMessage;

  // Serial port state
  List<String> _serialPorts = [];
  String? _selectedSerialPort;
  int _baudRate = 115200;
  static const _baudRates = [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600];

  @override
  void initState() {
    super.initState();
    _refreshSerialPorts();
    _loadSavedSettings();
  }

  void _loadSavedSettings() {
    // Load last-used connection config after the first frame
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
    final connection = ref.watch(connectionControllerProvider);
    final vehicle = ref.watch(vehicleStateProvider);
    final isConnected = connection.transportState == TransportState.connected;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Connection Manager
        Text('Connection Manager', style: HeliosTypography.heading2),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Transport', style: HeliosTypography.caption),
                const SizedBox(height: 8),
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
                ),
                const SizedBox(height: 16),

                if (_transportType == 'UDP') ...[
                  TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(labelText: 'Bind Address'),
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
                ] else ...[
                  // Serial port picker
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          value: _serialPorts.contains(_selectedSerialPort)
                              ? _selectedSerialPort
                              : null,
                          hint: const Text('Select port', style: TextStyle(fontSize: 13)),
                          isExpanded: true,
                          dropdownColor: HeliosColors.surfaceLight,
                          items: _serialPorts.map((port) {
                            final desc = SerialTransport.portDescription(port);
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
                              : (v) => setState(() => _selectedSerialPort = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Refresh ports',
                        onPressed: isConnected ? null : _refreshSerialPorts,
                      ),
                    ],
                  ),
                  if (_serialPorts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'No serial ports detected. Connect your flight controller via USB.',
                        style: TextStyle(color: HeliosColors.warning, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 12),
                  // Baud rate selector
                  Row(
                    children: [
                      const Text('Baud Rate: ', style: TextStyle(color: HeliosColors.textSecondary, fontSize: 13)),
                      DropdownButton<int>(
                        value: _baudRate,
                        dropdownColor: HeliosColors.surfaceLight,
                        items: _baudRates
                            .map((b) => DropdownMenuItem(
                                  value: b,
                                  child: Text('$b', style: const TextStyle(fontSize: 13)),
                                ))
                            .toList(),
                        onChanged: isConnected
                            ? null
                            : (v) {
                                if (v != null) setState(() => _baudRate = v);
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
                      color: HeliosColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: HeliosColors.danger, fontSize: 12),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: isConnected ? null : _connect,
                      icon: const Icon(Icons.link, size: 16),
                      label: Text(
                        connection.transportState == TransportState.connecting
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
        ),

        const SizedBox(height: 24),

        // Status
        Text('Status', style: HeliosTypography.heading2),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                    LinkState.connected => HeliosColors.success,
                    LinkState.degraded => HeliosColors.warning,
                    LinkState.lost => HeliosColors.danger,
                    LinkState.disconnected => HeliosColors.textSecondary,
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
        ),

        const SizedBox(height: 24),

        // Stream Rates
        Text('Telemetry Rates', style: HeliosTypography.heading2),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _StreamRateSettings(),
          ),
        ),

        const SizedBox(height: 24),

        // Sensor Calibration
        Text('Sensor Calibration', style: HeliosTypography.heading2),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: const CalibrationWizard(),
          ),
        ),

        const SizedBox(height: 24),

        // Parameters
        Text('Parameters', style: HeliosTypography.heading2),
        const SizedBox(height: 12),
        Card(
          child: SizedBox(
            height: 400,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: const ParameterEditor(),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Video Settings
        Text('Video Stream', style: HeliosTypography.heading2),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _VideoSettings(),
          ),
        ),

        const SizedBox(height: 24),

        // Recording
        Text('Recording', style: HeliosTypography.heading2),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: _RecordingStatus(),
          ),
        ),

        const SizedBox(height: 24),

        // Layout Profiles
        Text('Layout Profiles', style: HeliosTypography.heading2),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _LayoutProfilesSection(),
          ),
        ),

        const SizedBox(height: 24),

        // Display
        Text('Display', style: HeliosTypography.heading2),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _DisplaySettings(),
          ),
        ),

        const SizedBox(height: 24),

        // Maps
        Text('Offline Maps', style: HeliosTypography.heading2),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _MapCacheSettings(),
          ),
        ),

        const SizedBox(height: 24),

        // About
        Text('About', style: HeliosTypography.heading2),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Helios GCS', style: HeliosTypography.heading2),
                const SizedBox(height: 4),
                const Text(
                  'v0.1.0 — Part of the Argus Platform',
                  style: TextStyle(color: HeliosColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Open-source ground control station for MAVLink UAVs.\n'
                  'Apache 2.0 Licence.',
                  style: TextStyle(color: HeliosColors.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VideoSettings extends ConsumerStatefulWidget {
  @override
  ConsumerState<_VideoSettings> createState() => _VideoSettingsState();
}

class _VideoSettingsState extends ConsumerState<_VideoSettings> {
  late TextEditingController _urlController;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
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
              onPressed: videoCtrl.isPlaying ? null : () => videoCtrl.connect(),
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('Test Stream'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: videoCtrl.isPlaying ? () => videoCtrl.disconnect() : null,
              icon: const Icon(Icons.stop, size: 16),
              label: const Text('Stop'),
            ),
          ],
        ),
        if (videoCtrl.lastError != null) ...[
          const SizedBox(height: 8),
          Text(
            videoCtrl.lastError!,
            style: const TextStyle(color: HeliosColors.danger, fontSize: 12),
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
    final store = ref.watch(telemetryStoreProvider);
    final isRecording = store.isRecording;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Telemetry is recorded automatically when a vehicle is connected '
          'and stops when disconnected. Each flight is saved as a DuckDB file.',
          style: TextStyle(color: HeliosColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isRecording
                ? HeliosColors.danger.withValues(alpha: 0.1)
                : HeliosColors.surfaceLight,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isRecording
                  ? HeliosColors.danger.withValues(alpha: 0.3)
                  : HeliosColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isRecording ? Icons.fiber_manual_record : Icons.circle_outlined,
                size: 14,
                color: isRecording ? HeliosColors.danger : HeliosColors.textTertiary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isRecording ? 'RECORDING' : 'IDLE',
                      style: TextStyle(
                        color: isRecording ? HeliosColors.danger : HeliosColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isRecording)
                      Text(
                        '${store.rowsWritten} rows written',
                        style: const TextStyle(color: HeliosColors.textSecondary, fontSize: 12),
                      )
                    else
                      const Text(
                        'Waiting for connection',
                        style: TextStyle(color: HeliosColors.textTertiary, fontSize: 12),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Map tiles are cached locally for offline use. '
          'Previously viewed areas will be available without internet.',
          style: TextStyle(color: HeliosColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.map, size: 18, color: HeliosColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Cache size: ${_cacheBytes != null ? _formatBytes(_cacheBytes!) : '...'}',
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: HeliosColors.textPrimary,
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
    final scale = ref.watch(displayScaleProvider);
    final notifier = ref.read(displayScaleProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Adjust the global text and widget scale for better readability.',
          style: TextStyle(color: HeliosColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('A', style: TextStyle(fontSize: 12, color: HeliosColors.textTertiary)),
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
            const Text('A', style: TextStyle(fontSize: 18, color: HeliosColors.textTertiary)),
            const SizedBox(width: 12),
            Text(
              '${(scale * 100).round()}%',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: HeliosColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            if (scale != defaultScale)
              TextButton(
                onPressed: () => notifier.reset(),
                child: const Text('Reset', style: TextStyle(fontSize: 12)),
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
    final layoutState = ref.watch(layoutProvider);
    final profiles = layoutState.profiles;
    final activeName = layoutState.activeProfileName;
    final notifier = ref.read(layoutProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Manage widget layout profiles for the Fly View. '
          'Each profile saves chart positions, PFD visibility, and sidebar settings.',
          style: TextStyle(color: HeliosColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),

        // Profile list
        ...profiles.map((profile) {
          final isActive = profile.name == activeName;
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? HeliosColors.accent.withValues(alpha: 0.08)
                  : HeliosColors.surfaceLight,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isActive
                    ? HeliosColors.accent.withValues(alpha: 0.3)
                    : HeliosColors.border,
              ),
            ),
            child: ListTile(
              dense: true,
              leading: Icon(
                _vehicleIcon(profile.vehicleType),
                size: 20,
                color: isActive ? HeliosColors.accent : HeliosColors.textSecondary,
              ),
              title: Text(
                profile.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: HeliosColors.textPrimary,
                ),
              ),
              subtitle: Text(
                _profileSummary(profile),
                style: const TextStyle(fontSize: 12, color: HeliosColors.textTertiary),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: HeliosColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'ACTIVE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: HeliosColors.accent,
                        ),
                      ),
                    ),
                  if (!isActive) ...[
                    IconButton(
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      color: HeliosColors.textSecondary,
                      tooltip: 'Set as active',
                      onPressed: () => notifier.selectProfile(profile.name),
                    ),
                  ],
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    color: HeliosColors.textSecondary,
                    tooltip: 'Duplicate',
                    onPressed: () => _showDuplicateDialog(context, ref, profile),
                  ),
                  if (!profile.isDefault)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      color: HeliosColors.danger,
                      tooltip: 'Delete',
                      onPressed: () => _confirmDelete(context, ref, profile.name),
                    ),
                  if (profile.isDefault)
                    IconButton(
                      icon: const Icon(Icons.restart_alt, size: 16),
                      color: HeliosColors.textSecondary,
                      tooltip: 'Reset to defaults',
                      onPressed: isActive
                          ? () => notifier.resetActiveProfile()
                          : null,
                    ),
                ],
              ),
              onTap: isActive ? null : () => notifier.selectProfile(profile.name),
            ),
          );
        }),

        const SizedBox(height: 12),

        // New profile button
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
      builder: (ctx) => AlertDialog(
        backgroundColor: HeliosColors.surface,
        title: const Text('New Layout Profile',
            style: TextStyle(color: HeliosColors.textPrimary, fontSize: 14)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: HeliosColors.textPrimary, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'Profile name',
            hintStyle: TextStyle(color: HeliosColors.textTertiary),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: HeliosColors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: HeliosColors.accent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: HeliosColors.textSecondary, fontSize: 12)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(layoutProvider.notifier).createProfile(name);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create',
                style: TextStyle(color: HeliosColors.accent, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _showDuplicateDialog(BuildContext context, WidgetRef ref, layout.LayoutProfile source) {
    final controller = TextEditingController(text: '${source.name} (copy)');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HeliosColors.surface,
        title: const Text('Duplicate Profile',
            style: TextStyle(color: HeliosColors.textPrimary, fontSize: 14)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: HeliosColors.textPrimary, fontSize: 13),
          decoration: const InputDecoration(
            hintText: 'New profile name',
            hintStyle: TextStyle(color: HeliosColors.textTertiary),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: HeliosColors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: HeliosColors.accent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: HeliosColors.textSecondary, fontSize: 12)),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                // Temporarily select source, create copy, then switch to new
                final notifier = ref.read(layoutProvider.notifier);
                final currentActive = ref.read(layoutProvider).activeProfileName;
                notifier.selectProfile(source.name);
                notifier.createProfile(name);
                // If the source wasn't active, this creates a copy of it
                if (currentActive != source.name) {
                  // Stay on the new copy
                }
                Navigator.pop(ctx);
              }
            },
            child: const Text('Duplicate',
                style: TextStyle(color: HeliosColors.accent, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HeliosColors.surface,
        title: Text('Delete "$name"?',
            style: const TextStyle(color: HeliosColors.textPrimary, fontSize: 14)),
        content: const Text('This layout profile will be permanently removed.',
            style: TextStyle(color: HeliosColors.textSecondary, fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: HeliosColors.textSecondary, fontSize: 12)),
          ),
          TextButton(
            onPressed: () {
              ref.read(layoutProvider.notifier).deleteProfile(name);
              Navigator.pop(ctx);
            },
            child: const Text('Delete',
                style: TextStyle(color: HeliosColors.danger, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _StreamRateSettings extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rates = ref.watch(streamRateProvider);
    final notifier = ref.read(streamRateProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Control how fast telemetry is requested from the flight controller. '
          'Higher rates give smoother instruments but use more bandwidth and storage.',
          style: TextStyle(color: HeliosColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),

        // Preset buttons
        Wrap(
          spacing: 8,
          children: StreamRatePreset.values
              .where((p) => p != StreamRatePreset.custom)
              .map((preset) => ChoiceChip(
                    label: Text(preset.label, style: const TextStyle(fontSize: 12)),
                    selected: rates.preset == preset,
                    onSelected: (_) => notifier.applyPreset(preset),
                    selectedColor: HeliosColors.accentDim,
                    backgroundColor: HeliosColors.surfaceLight,
                    labelStyle: TextStyle(
                      color: rates.preset == preset
                          ? HeliosColors.textPrimary
                          : HeliosColors.textSecondary,
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
          style: const TextStyle(
            color: HeliosColors.textTertiary,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Changes take effect on next connect.',
          style: TextStyle(color: HeliosColors.textTertiary, fontSize: 12),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                color: HeliosColors.textSecondary,
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
              style: const TextStyle(
                color: HeliosColors.textPrimary,
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
