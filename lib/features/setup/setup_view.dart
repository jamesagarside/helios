import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/connection_state.dart';
import '../../shared/models/vehicle_state.dart';
import '../../shared/providers/providers.dart';
import '../../shared/providers/video_provider.dart';
import '../../core/telemetry/telemetry_store.dart';
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
      } else {
        setState(() => _errorMessage = 'Serial not yet implemented');
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
                  const Text(
                    'Serial transport requires flutter_libserialport — Phase 4',
                    style: TextStyle(color: HeliosColors.textTertiary, fontSize: 13),
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _RecordingControls(),
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
            style: const TextStyle(color: HeliosColors.danger, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _RecordingControls extends ConsumerStatefulWidget {
  @override
  ConsumerState<_RecordingControls> createState() => _RecordingControlsState();
}

class _RecordingControlsState extends ConsumerState<_RecordingControls> {
  String? _recordingFile;
  bool _isRecording = false;

  Future<void> _startRecording() async {
    final store = ref.read(telemetryStoreProvider);
    final vehicle = ref.read(vehicleStateProvider);

    try {
      final path = await store.createFlight(
        vehicleSysId: vehicle.systemId,
        vehicleType: vehicle.vehicleType.name,
        autopilot: vehicle.autopilotType.name,
      );
      setState(() {
        _isRecording = true;
        _recordingFile = path;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording failed: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    final store = ref.read(telemetryStoreProvider);
    await store.closeFlight();
    setState(() {
      _isRecording = false;
      _recordingFile = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(telemetryStoreProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isRecording ? null : _startRecording,
              icon: const Icon(Icons.fiber_manual_record, size: 16, color: HeliosColors.danger),
              label: const Text('Start Recording'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _isRecording ? _stopRecording : null,
              icon: const Icon(Icons.stop, size: 16),
              label: const Text('Stop'),
            ),
          ],
        ),
        if (_isRecording) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: HeliosColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: HeliosColors.danger.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.fiber_manual_record, size: 12, color: HeliosColors.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'RECORDING',
                        style: TextStyle(
                          color: HeliosColors.danger,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${store.rowsWritten} rows written',
                        style: const TextStyle(color: HeliosColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
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
