import 'dart:async';
import 'dart:math' show pi;
import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/mavlink/mavlink_service.dart';
import '../../core/mavlink/transports/transport.dart';
import '../../core/mavlink/transports/udp_transport.dart';
import '../../core/mavlink/transports/tcp_transport.dart';
import '../../core/mavlink/transports/serial_transport.dart';
import '../../core/mission/mission_service.dart';
import '../../core/msp/msp_service.dart';
import '../../core/params/parameter_service.dart';
import '../../core/protocol_detector.dart';
import '../../core/telemetry/maintenance_service.dart';
import '../../core/telemetry/replay_service.dart';
import '../../core/telemetry/telemetry_store.dart';
import '../models/vehicle_state.dart';
import '../models/connection_state.dart';
import '../models/mission_item.dart';
import '../models/recording_state.dart';
import 'connection_settings_provider.dart';
import 'stream_rate_provider.dart';
import 'vehicle_state_notifier.dart';

// ─── Alert History ───────────────────────────────────────────────────────────

/// Severity levels for alert entries.
enum AlertSeverity { info, warning, critical }

/// A single alert entry from STATUSTEXT or internal state changes.
class AlertEntry {
  const AlertEntry({
    required this.message,
    required this.severity,
    required this.timestamp,
  });

  final String message;
  final AlertSeverity severity;
  final DateTime timestamp;
}

/// Ring-buffer notifier: keeps the last [_kMaxAlerts] alert entries.
class AlertHistoryNotifier extends StateNotifier<List<AlertEntry>> {
  AlertHistoryNotifier() : super(const []);

  static const _kMaxAlerts = 100;

  void add(AlertEntry entry) {
    final next = [...state, entry];
    state = next.length > _kMaxAlerts ? next.sublist(next.length - _kMaxAlerts) : next;
  }

  void clear() => state = const [];
}

final alertHistoryProvider =
    StateNotifierProvider<AlertHistoryNotifier, List<AlertEntry>>(
  (ref) => AlertHistoryNotifier(),
);

/// Number of unread critical/warning alerts (resets when user opens drawer).
final unreadAlertCountProvider = Provider<int>((ref) {
  return ref.watch(alertHistoryProvider)
      .where((a) => a.severity != AlertSeverity.info)
      .length;
});

// ─── Vehicle State ────────────────────────────────────────────────────────────

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

// ---------------------------------------------------------------------------
// Multi-vehicle registry
// ---------------------------------------------------------------------------

/// All known vehicles keyed by systemId.
final vehicleRegistryProvider = StateProvider<Map<int, VehicleState>>(
  (ref) => {},
);

/// Currently selected vehicle systemId (0 = auto-select first).
final activeVehicleIdProvider = StateProvider<int>((ref) => 0);

/// Number of known vehicles.
final vehicleCountProvider = Provider<int>(
  (ref) => ref.watch(vehicleRegistryProvider).length,
);

/// TelemetryStore singleton provider.
final telemetryStoreProvider = Provider<TelemetryStore>((ref) {
  final store = TelemetryStore();
  ref.onDispose(store.dispose);
  return store;
});

/// ReplayService singleton provider.
final replayServiceProvider = Provider<ReplayService>((ref) {
  final service = ReplayService();
  ref.onDispose(service.dispose);
  return service;
});

/// True when the Fly View is showing replayed data instead of live telemetry.
final replayActiveProvider = StateProvider<bool>((ref) => false);

/// Predictive maintenance alerts computed from historical flight data.
///
/// Automatically re-evaluates whenever the telemetry store changes.
/// Returns an empty list if fewer than 3 flights are recorded.
final maintenanceAlertsProvider =
    FutureProvider<List<MaintenanceAlert>>((ref) async {
  final store = ref.watch(telemetryStoreProvider);
  final flights = await store.listFlights();
  return MaintenanceService().analyze(flights);
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
  MspService? _mspService;
  StreamSubscription<MavlinkMessage>? _messageSub;
  StreamSubscription<VehicleState>? _mspStateSub;
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

    if (config.protocol == ProtocolType.auto) {
      await _connectWithDetection(transport, config);
      return;
    }

    if (config.protocol == ProtocolType.msp) {
      await _connectMsp(transport, config);
      return;
    }

    await _connectMavlink(transport, config);
  }

  /// Connect using protocol auto-detection.
  ///
  /// Connects the transport, runs [ProtocolDetector.detect], then hands off
  /// to [_connectMavlink] or [_connectMsp] with [alreadyConnected] = true so
  /// the transport is not re-connected.
  Future<void> _connectWithDetection(
    MavlinkTransport transport,
    ConnectionConfig config,
  ) async {
    state = state.copyWith(
      transportState: TransportState.connecting,
      activeConfig: config,
    );
    _ref.read(connectionStatusProvider.notifier).state = state;

    try {
      await transport.connect();
    } catch (e) {
      transport.dispose();
      state = state.copyWith(transportState: TransportState.error);
      _ref.read(connectionStatusProvider.notifier).state = state;
      rethrow;
    }

    final detected = await ProtocolDetector.detect(transport);

    if (detected == ProtocolType.msp) {
      await _connectMsp(transport, config, alreadyConnected: true);
    } else {
      await _connectMavlink(transport, config, alreadyConnected: true);
    }
  }

  /// MAVLink connection path.
  Future<void> _connectMavlink(
    MavlinkTransport transport,
    ConnectionConfig config, {
    bool alreadyConnected = false,
  }) async {
    _service = MavlinkService(transport);
    _missionService = MissionService(_service!);
    _paramService = ParameterService(_service!);

    // Wire link state changes to connection status
    _linkSub = _service!.linkStateStream.listen((linkState) {
      state = state.copyWith(linkState: linkState);
      _ref.read(connectionStatusProvider.notifier).state = state;
    });

    // Wire all messages to VehicleStateNotifier + TelemetryStore
    final Set<int> knownSystems = {};
    bool streamsRequested = false;
    _messageSub = _service!.messageStream.listen((msg) {
      // Route to active vehicle's state notifier
      final activeId = _ref.read(activeVehicleIdProvider);
      if (activeId == 0 || msg.systemId == activeId) {
        _ref.read(vehicleStateProvider.notifier).handleMessage(msg);
      }

      // Buffer to DuckDB if recording
      final store = _ref.read(telemetryStoreProvider);
      if (store.isRecording) {
        store.buffer(msg);
      }

      // Route STATUSTEXT to alert history
      if (msg is StatusTextMessage) {
        final severity = switch (msg.severity) {
          0 || 1 || 2 => AlertSeverity.critical, // EMERGENCY, ALERT, CRITICAL
          3 => AlertSeverity.critical,            // ERROR
          4 => AlertSeverity.warning,             // WARNING
          5 => AlertSeverity.warning,             // NOTICE
          _ => AlertSeverity.info,                // INFO, DEBUG
        };
        _ref.read(alertHistoryProvider.notifier).add(AlertEntry(
          message: msg.text,
          severity: severity,
          timestamp: DateTime.now(),
        ));
      }

      // Track vehicle registry + request streams on first heartbeat per vehicle
      if (msg is HeartbeatMessage && msg.systemId > 0) {
        // Register new vehicle in registry
        if (!knownSystems.contains(msg.systemId)) {
          knownSystems.add(msg.systemId);
          final registry = Map<int, VehicleState>.from(
            _ref.read(vehicleRegistryProvider),
          );
          registry[msg.systemId] = const VehicleState();
          _ref.read(vehicleRegistryProvider.notifier).state = registry;

          // Auto-select first vehicle
          if (_ref.read(activeVehicleIdProvider) == 0) {
            _ref.read(activeVehicleIdProvider.notifier).state = msg.systemId;
          }
        }

        // Update registry with latest state for this vehicle
        final current = _ref.read(vehicleStateProvider);
        if (msg.systemId == current.systemId) {
          final registry = Map<int, VehicleState>.from(
            _ref.read(vehicleRegistryProvider),
          );
          registry[msg.systemId] = current;
          _ref.read(vehicleRegistryProvider.notifier).state = registry;
        }

        // Request stream rates + firmware version after first heartbeat
        if (!streamsRequested) {
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
          // Request AUTOPILOT_VERSION (msg_id 148)
          _service!.sendCommand(
            targetSystem: msg.systemId,
            targetComponent: msg.componentId,
            command: MavCmd.requestMessage,
            param1: 148,
          );
        }
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
      if (!alreadyConnected) {
        state = state.copyWith(
          transportState: TransportState.connecting,
          activeConfig: config,
        );
        _ref.read(connectionStatusProvider.notifier).state = state;
      }

      await _service!.connect(alreadyConnected: alreadyConnected);

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
          final path = await store.createFlight(protocol: 'mavlink');
          _ref.read(recordingStateProvider.notifier).state = RecordingState(
            isRecording: true,
            currentFilePath: path,
            recordingStarted: DateTime.now(),
          );
        }
      } catch (e, st) {
        // Recording failure shouldn't prevent connection, but log it
        // ignore: avoid_print
        print('[Helios] Auto-record failed: $e\n$st');
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

  /// MSP connection path — separate from MAVLink to keep each path readable.
  Future<void> _connectMsp(
    MavlinkTransport transport,
    ConnectionConfig config, {
    bool alreadyConnected = false,
  }) async {
    _mspService = MspService(transport);

    _linkSub = _mspService!.linkStateStream.listen((linkState) {
      state = state.copyWith(linkState: linkState);
      _ref.read(connectionStatusProvider.notifier).state = state;
    });

    _mspStateSub = _mspService!.vehicleStateStream.listen((mspState) {
      _ref.read(vehicleStateProvider.notifier).applyMspState(mspState);

      // Buffer to DuckDB if recording
      final store = _ref.read(telemetryStoreProvider);
      if (store.isRecording) {
        store.bufferMspAttitude(
          rollDeg: mspState.roll * 180 / pi,
          pitchDeg: mspState.pitch * 180 / pi,
          headingDeg: mspState.heading,
        );
        if (mspState.hasPosition) {
          store.bufferMspGps(
            fixType: mspState.gpsFix.index,
            numSat: mspState.satellites,
            lat: mspState.latitude,
            lon: mspState.longitude,
            altitudeM: mspState.altitudeMsl,
            speedMs: mspState.groundspeed,
            courseDeg: mspState.heading.toDouble(),
          );
        }
        if (mspState.batteryVoltage > 0) {
          store.bufferMspAnalog(
            voltageV: mspState.batteryVoltage,
            currentA: mspState.batteryCurrent,
            consumedMah: mspState.batteryConsumed,
            remainingPct: mspState.batteryRemaining.clamp(0, 100),
            rssi: mspState.rssi,
          );
        }
        store.bufferMspAltitude(
          altitudeRelM: mspState.altitudeRel,
          climbMs: mspState.climbRate,
        );
        store.bufferMspStatus(
          armed: mspState.armed,
          flightModeFlags: mspState.flightMode.number,
          flightModeName: mspState.flightMode.name,
          sensorsOk: mspState.sensorHealth == 0,
          cycleTimeUs: 0,
        );
      }
    });

    _rateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = _mspService?.messagesReceived ?? 0;
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

      await _mspService!.connect(alreadyConnected: alreadyConnected);

      state = state.copyWith(
        transportState: TransportState.connected,
        connectedSince: DateTime.now(),
      );
      _ref.read(connectionStatusProvider.notifier).state = state;

      _ref.read(connectionSettingsProvider.notifier).save(config);

      // Auto-record on connect
      try {
        final store = _ref.read(telemetryStoreProvider);
        if (!store.isRecording) {
          final path = await store.createFlight(protocol: 'msp');
          _ref.read(recordingStateProvider.notifier).state = RecordingState(
            isRecording: true,
            currentFilePath: path,
            recordingStarted: DateTime.now(),
          );
        }
      } catch (e, st) {
        // ignore: avoid_print
        print('[Helios] Auto-record failed: $e\n$st');
      }
    } catch (e) {
      await _mspService?.disconnect();
      _mspService?.dispose();
      _mspService = null;
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
    await _mspStateSub?.cancel();
    _mspStateSub = null;
    await _linkSub?.cancel();
    _linkSub = null;
    _paramService?.dispose();
    _paramService = null;
    _missionService?.dispose();
    _missionService = null;
    await _service?.disconnect();
    _service?.dispose();
    _service = null;
    await _mspService?.disconnect();
    _mspService?.dispose();
    _mspService = null;
    _lastMsgCount = 0;

    // Stop recording on disconnect
    final store = _ref.read(telemetryStoreProvider);
    if (store.isRecording) {
      await store.closeFlight();
      _ref.read(recordingStateProvider.notifier).state = const RecordingState();
    }

    _ref.read(vehicleStateProvider.notifier).reset();
    _ref.read(missionStateProvider.notifier).state = const MissionState();
    _ref.read(vehicleRegistryProvider.notifier).state = {};
    _ref.read(activeVehicleIdProvider.notifier).state = 0;
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

  /// Control gimbal pitch and yaw via MAV_CMD_DO_MOUNT_CONTROL.
  Future<void> controlGimbal({
    double pitch = 0,
    double yaw = 0,
    double roll = 0,
  }) async {
    if (_service == null) return;
    final vehicle = _ref.read(vehicleStateProvider);
    await _service!.sendCommand(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      command: MavCmd.doMountControl,
      param1: pitch,
      param2: roll,
      param3: yaw,
      param7: 2, // MAV_MOUNT_MODE_MAVLINK_TARGETING
    );
  }

  /// Trigger camera single capture via MAV_CMD_DO_DIGICAM_CONTROL.
  Future<void> triggerCamera() async {
    if (_service == null) return;
    final vehicle = _ref.read(vehicleStateProvider);
    await _service!.sendCommand(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      command: MavCmd.doDigicamControl,
      param5: 1, // shot = 1 (single capture)
    );
  }

  /// Test a single motor via MAV_CMD_DO_MOTOR_TEST.
  ///
  /// [motorIndex] is 1-based. [throttlePct] is 0.0–100.0.
  /// [durationSec] is how long the motor runs (ArduPilot enforces a cap).
  Future<void> testMotor({
    required int motorIndex,
    required double throttlePct,
    double durationSec = 2.0,
  }) async {
    if (_service == null) return;
    final vehicle = _ref.read(vehicleStateProvider);
    await _service!.sendCommand(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      command: MavCmd.doMotorTest,
      param1: motorIndex.toDouble(), // motor number (1-based)
      param2: 1,                      // throttle type: 1 = percent
      param3: throttlePct,
      param4: durationSec,
      param5: 0,                      // motor count (0 = this motor only)
      param6: 0,                      // test order: 0 = board order
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
    _mspStateSub?.cancel();
    _linkSub?.cancel();
    _service?.dispose();
    _mspService?.dispose();
    super.dispose();
  }
}

final connectionControllerProvider =
    StateNotifierProvider<ConnectionController, ConnectionStatus>(
  (ref) => ConnectionController(ref),
);
