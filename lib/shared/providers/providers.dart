import 'dart:async';
import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/mavlink/mavlink_service.dart';
import '../../core/mavlink/transports/transport.dart';
import '../../core/mavlink/transports/udp_transport.dart';
import '../../core/mavlink/transports/tcp_transport.dart';
import '../../core/telemetry/telemetry_store.dart';
import '../models/vehicle_state.dart';
import '../models/connection_state.dart';
import '../models/recording_state.dart';
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
      SerialConnectionConfig() =>
        throw UnimplementedError('Serial transport not yet available'),
    };

    _service = MavlinkService(transport);

    // Wire link state changes to connection status
    _linkSub = _service!.linkStateStream.listen((linkState) {
      state = state.copyWith(linkState: linkState);
      _ref.read(connectionStatusProvider.notifier).state = state;
    });

    // Wire all messages to VehicleStateNotifier + TelemetryStore
    _messageSub = _service!.messageStream.listen((msg) {
      _ref.read(vehicleStateProvider.notifier).handleMessage(msg);
      // Buffer to DuckDB if recording
      final store = _ref.read(telemetryStoreProvider);
      if (store.isRecording) {
        store.buffer(msg);
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
    state = const ConnectionStatus();
    _ref.read(connectionStatusProvider.notifier).state = state;
  }

  /// Send an arm/disarm command.
  Future<void> setArmed(bool arm) async {
    if (_service == null) return;
    final vehicle = _ref.read(vehicleStateProvider);
    await _service!.sendCommand(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      command: 400, // MAV_CMD_COMPONENT_ARM_DISARM
      param1: arm ? 1.0 : 0.0,
    );
  }

  @override
  void dispose() {
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
