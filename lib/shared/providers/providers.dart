import 'dart:async';
import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/mavlink/mavlink_service.dart';
import '../../core/mavlink/transports/transport.dart';
import '../../core/mavlink/transports/udp_transport.dart';
import '../../core/mavlink/transports/tcp_transport.dart';
import '../../core/mavlink/transports/serial_transport.dart';
import '../../core/mission/mission_service.dart';
import '../../core/params/parameter_service.dart';
import '../../core/telemetry/telemetry_store.dart';
import '../models/vehicle_state.dart';
import '../models/connection_state.dart';
import '../models/mission_item.dart';
import '../models/recording_state.dart';
import 'connection_settings_provider.dart';
import 'stream_rate_provider.dart';
import 'vehicle_state_notifier.dart';

/// Vehicle state — updated from MAVLink messages.
final vehicleStateProvider =
    StateNotifierProvider<VehicleStateNotifier, VehicleState>(
  (ref) => VehicleStateNotifier(),
);

/// Connection status.
final connectionStatusProvider = StateProvider<ConnectionStatus>(
  (ref) => const ConnectionStatus(),
);

/// Recording state.
final recordingStateProvider = StateProvider<RecordingState>(
  (ref) => const RecordingState(),
);

/// Link state derived from connection status.
final linkStateProvider = Provider<LinkState>(
  (ref) => ref.watch(connectionStatusProvider).linkState,
);

/// Whether the vehicle has a valid GPS position.
final hasPositionProvider = Provider<bool>(
  (ref) => ref.watch(vehicleStateProvider).hasPosition,
);

/// Battery health assessment.
enum BatteryHealth { unknown, good, warning, critical }

final batteryHealthProvider = Provider<BatteryHealth>((ref) {
  final vehicle = ref.watch(vehicleStateProvider);
  if (vehicle.batteryRemaining < 0) return BatteryHealth.unknown;
  if (vehicle.batteryRemaining < 15) return BatteryHealth.critical;
  if (vehicle.batteryRemaining < 30) return BatteryHealth.warning;
  return BatteryHealth.good;
});

/// GPS quality assessment.
enum GpsQuality { none, poor, fair, good }

final gpsQualityProvider = Provider<GpsQuality>((ref) {
  final vehicle = ref.watch(vehicleStateProvider);
  if (vehicle.gpsFix == GpsFix.none || vehicle.gpsFix == GpsFix.noFix) {
    return GpsQuality.none;
  }
  if (vehicle.hdop > 2.5) return GpsQuality.poor;
  if (vehicle.hdop > 1.5) return GpsQuality.fair;
  return GpsQuality.good;
});

/// GPS fix label for display.
final gpsFixLabelProvider = Provider<String>((ref) {
  final vehicle = ref.watch(vehicleStateProvider);
  return switch (vehicle.gpsFix) {
    GpsFix.none || GpsFix.noFix => 'No Fix',
    GpsFix.fix2d => '2D',
    GpsFix.fix3d => '3D',
    GpsFix.dgps => 'DGPS',
    GpsFix.rtkFloat => 'RTK Float',
    GpsFix.rtkFixed => 'RTK Fixed',
  };
});

/// TelemetryStore singleton provider.
final telemetryStoreProvider = Provider<TelemetryStore>((ref) {
  final store = TelemetryStore();
  ref.onDispose(store.dispose);
  return store;
});

/// Mission state — tracks mission items, transfer state, current waypoint.
final missionStateProvider = StateProvider<MissionState>(
  (ref) => const MissionState(),
);

/// Mission items shortcut.
final missionItemsProvider = Provider<List<MissionItem>>(
  (ref) => ref.watch(missionStateProvider).items,
);

/// Current waypoint from vehicle.
final currentWaypointProvider = Provider<int>(
  (ref) => ref.watch(vehicleStateProvider).currentWaypoint,
);

/// Connection controller — manages the MavlinkService lifecycle.
class ConnectionController extends StateNotifier<ConnectionStatus> {
  ConnectionController(this._ref) : super(const ConnectionStatus());

  final Ref _ref;
  MavlinkService? _service;
  StreamSubscription<MavlinkMessage>? _messageSub;
  StreamSubscription<LinkState>? _linkSub;
  Timer? _rateTimer;
  int _lastMsgCount = 0;

  bool get isConnected =>
      state.transportState == TransportState.connected;

  Future<void> connect(ConnectionConfig config) async {
    await disconnect();

    final MavlinkTransport transport = switch (config) {
      UdpConnectionConfig(:final bindAddress, :final port) =>
        UdpTransport(bindAddress: bindAddress, bindPort: port),
      TcpConnectionConfig(:final host, :final port) =>
        TcpTransport(host: host, port: port),
      SerialConnectionConfig(:final portName, :final baudRate) =>
        SerialTransport(portName: portName, baudRate: baudRate),
    };

    _service = MavlinkService(transport);
    _missionService = MissionService(_service!);
    _paramService = ParameterService(_service!);

    // Wire link state changes to connection status
    _linkSub = _service!.linkStateStream.listen((linkState) {
      state = state.copyWith(linkState: linkState);
      _ref.read(connectionStatusProvider.notifier).state = state;
    });

    // Wire all messages to VehicleStateNotifier + TelemetryStore
    bool streamsRequested = false;
    _messageSub = _service!.messageStream.listen((msg) {
      _ref.read(vehicleStateProvider.notifier).handleMessage(msg);
      // Buffer to DuckDB if recording
      final store = _ref.read(telemetryStoreProvider);
      if (store.isRecording) {
        store.buffer(msg);
      }
      // Request stream rates after first heartbeat identifies the vehicle
      if (!streamsRequested && msg is HeartbeatMessage) {
        streamsRequested = true;
        final rates = _ref.read(streamRateProvider);
        _service!.requestStreamRates(
          targetSystem: msg.systemId,
          targetComponent: msg.componentId,
          attitudeHz: rates.attitudeHz,
          positionHz: rates.positionHz,
          vfrHz: rates.vfrHudHz,
          statusHz: rates.statusHz,
          rcHz: rates.rcChannelsHz,
        );
      }
    });

    // Message rate calculation (every second)
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = _service?.messagesReceived ?? 0;
      final rate = (current - _lastMsgCount).toDouble();
      _lastMsgCount = current;
      state = state.copyWith(
        messageRate: rate,
        messagesReceived: current,
      );
      _ref.read(connectionStatusProvider.notifier).state = state;
    });

    try {
      state = state.copyWith(
        transportState: TransportState.connecting,
        activeConfig: config,
      );
      _ref.read(connectionStatusProvider.notifier).state = state;

      await _service!.connect();

      state = state.copyWith(
        transportState: TransportState.connected,
        connectedSince: DateTime.now(),
      );
      _ref.read(connectionStatusProvider.notifier).state = state;

      // Save last connection for quick reconnect
      _ref.read(connectionSettingsProvider.notifier).save(config);

      // Auto-record on connect
      try {
        final store = _ref.read(telemetryStoreProvider);
        if (!store.isRecording) {
          await store.createFlight();
        }
      } catch (_) {
        // Recording failure shouldn't prevent connection
      }
    } catch (e) {
      // Clean up on connection failure
      await _service?.disconnect();
      _service?.dispose();
      _service = null;
      state = state.copyWith(transportState: TransportState.error);
      _ref.read(connectionStatusProvider.notifier).state = state;
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _rateTimer?.cancel();
    _rateTimer = null;
    await _messageSub?.cancel();
    _messageSub = null;
    await _linkSub?.cancel();
    _linkSub = null;
    _paramService?.dispose();
    _paramService = null;
    _missionService?.dispose();
    _missionService = null;
    await _service?.disconnect();
    _service?.dispose();
    _service = null;
    _lastMsgCount = 0;

    // Stop recording on disconnect
    final store = _ref.read(telemetryStoreProvider);
    if (store.isRecording) {
      await store.closeFlight();
    }

    _ref.read(vehicleStateProvider.notifier).reset();
    _ref.read(missionStateProvider.notifier).state = const MissionState();
    state = const ConnectionStatus();
    _ref.read(connectionStatusProvider.notifier).state = state;
  }

  MissionService? _missionService;
  ParameterService? _paramService;

  /// The mission service for download/upload operations.
  MissionService? get missionService => _missionService;

  /// The parameter service for reading/writing FC params.
  ParameterService? get paramService => _paramService;

  /// The underlying MAVLink service (for calibration, etc.).
  MavlinkService? get mavlinkService => _service;

  /// Send an arm/disarm command.
  Future<void> setArmed(bool arm) async {
    if (_service == null) return;
    final vehicle = _ref.read(vehicleStateProvider);
    await _service!.sendCommand(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      command: MavCmd.componentArmDisarm,
      param1: arm ? 1.0 : 0.0,
    );
  }

  /// Set flight mode via MAV_CMD_DO_SET_MODE.
  Future<void> setFlightMode(int customMode) async {
    if (_service == null) return;
    final vehicle = _ref.read(vehicleStateProvider);
    await _service!.sendCommand(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      command: MavCmd.doSetMode,
      param1: 1.0, // MAV_MODE_FLAG_CUSTOM_MODE_ENABLED
      param2: customMode.toDouble(),
    );
  }

  /// Send a command with retry logic.
  /// Listens for COMMAND_ACK and retries up to [maxRetries] times.
  Future<bool> sendCommandWithRetry({
    required int command,
    double param1 = 0,
    double param2 = 0,
    double param3 = 0,
    double param4 = 0,
    double param5 = 0,
    double param6 = 0,
    double param7 = 0,
    int maxRetries = 3,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (_service == null) return false;
    final vehicle = _ref.read(vehicleStateProvider);

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      await _service!.sendCommand(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
        command: command,
        confirmation: attempt,
        param1: param1,
        param2: param2,
        param3: param3,
        param4: param4,
        param5: param5,
        param6: param6,
        param7: param7,
      );

      // Wait for ACK
      try {
        final ack = await _service!.messagesOf<CommandAckMessage>()
            .where((msg) => msg.command == command)
            .first
            .timeout(timeout);
        return ack.accepted;
      } on TimeoutException {
        if (attempt >= maxRetries) return false;
      }
    }
    return false;
  }

  /// Download mission from vehicle.
  Future<List<MissionItem>> downloadMission() async {
    if (_service == null || _missionService == null) return [];
    final vehicle = _ref.read(vehicleStateProvider);
    final missionNotifier = _ref.read(missionStateProvider.notifier);

    missionNotifier.state = missionNotifier.state.copyWith(
      transferState: MissionTransferState.downloading,
      transferProgress: 0.0,
      errorMessage: null,
    );

    try {
      final items = await _missionService!.download(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
        onProgress: (p) {
          missionNotifier.state = missionNotifier.state.copyWith(
            transferProgress: p,
          );
        },
      );

      missionNotifier.state = MissionState(
        items: items,
        transferState: MissionTransferState.complete,
        transferProgress: 1.0,
        currentWaypoint: vehicle.currentWaypoint,
      );

      // Save snapshot to DuckDB
      _ref.read(telemetryStoreProvider).saveMission(
        items,
        direction: 'download',
      );

      return items;
    } on MissionProtocolException catch (e) {
      missionNotifier.state = missionNotifier.state.copyWith(
        transferState: MissionTransferState.error,
        errorMessage: e.message,
      );
      return [];
    }
  }

  /// Upload mission to vehicle.
  Future<bool> uploadMission(List<MissionItem> items) async {
    if (_service == null || _missionService == null) return false;
    final vehicle = _ref.read(vehicleStateProvider);
    final missionNotifier = _ref.read(missionStateProvider.notifier);

    missionNotifier.state = missionNotifier.state.copyWith(
      transferState: MissionTransferState.uploading,
      transferProgress: 0.0,
      errorMessage: null,
    );

    try {
      await _missionService!.upload(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
        items: items,
        onProgress: (p) {
          missionNotifier.state = missionNotifier.state.copyWith(
            transferProgress: p,
          );
        },
      );

      missionNotifier.state = MissionState(
        items: items,
        transferState: MissionTransferState.complete,
        transferProgress: 1.0,
      );

      // Save snapshot to DuckDB
      if (items.isNotEmpty) {
        _ref.read(telemetryStoreProvider).saveMission(
          items,
          direction: 'upload',
        );
      }

      return true;
    } on MissionProtocolException catch (e) {
      missionNotifier.state = missionNotifier.state.copyWith(
        transferState: MissionTransferState.error,
        errorMessage: e.message,
      );
      return false;
    }
  }

  /// Clear mission on vehicle.
  Future<bool> clearMission() async {
    final result = await uploadMission([]);
    if (result) {
      _ref.read(missionStateProvider.notifier).state = const MissionState();
    }
    return result;
  }

  @override
  void dispose() {
    _missionService?.dispose();
    _rateTimer?.cancel();
    _messageSub?.cancel();
    _linkSub?.cancel();
    _service?.dispose();
    super.dispose();
  }
}

final connectionControllerProvider =
    StateNotifierProvider<ConnectionController, ConnectionStatus>(
  (ref) => ConnectionController(ref),
);
