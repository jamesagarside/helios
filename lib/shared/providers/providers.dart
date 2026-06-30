import 'dart:async';
import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../core/mavlink/message_router.dart';
import '../../core/platform/serial_ports.dart';
import '../../core/params/param_meta.dart';
import '../../core/params/parameter_service.dart';
import '../../core/telemetry/maintenance_service.dart';
import '../../core/telemetry/replay_service.dart';
import '../../core/telemetry/telemetry_store.dart';
import '../models/adsb_vehicle.dart';
import '../models/alert_severity.dart';
import '../models/vehicle_state.dart';
import '../models/connection_state.dart';
import '../models/mission_item.dart';
import '../models/recording_state.dart';
import 'connection_controller.dart';
import 'connection_settings_provider.dart';
import 'vehicle_state_notifier.dart';

// Re-export the symbols lifted into dedicated modules so the ~40 existing
// `providers.dart` importers keep compiling unchanged. providers.dart remains
// the public surface for connection/routing/alert types.
export '../../core/mavlink/message_router.dart'
    show MavlinkPacketEntry, MavlinkMessageRouter, MavlinkRouterSinks;
export '../models/alert_severity.dart' show AlertSeverity, AlertEntry;
export 'connection_controller.dart'
    show ConnectionController, connectionControllerProvider;

// ─── MAVLink Inspector ───────────────────────────────────────────────────────

/// Ring-buffer notifier: keeps the last [_kMaxPackets] decoded MAVLink packets.
///
/// Uses an internal mutable list and only copies to an immutable snapshot
/// at a throttled rate (_kFlushInterval) to avoid copying 10k items on every
/// incoming MAVLink message (50Hz ATTITUDE would be 500k copies/sec).
class MavlinkInspectorNotifier extends StateNotifier<List<MavlinkPacketEntry>> {
  MavlinkInspectorNotifier() : super(const []);

  static const _kMaxPackets = 10000;
  static const _kFlushInterval = Duration(milliseconds: 200); // 5 Hz UI refresh

  final List<MavlinkPacketEntry> _buffer = [];
  bool _paused = false;
  bool _dirty = false;
  bool _stopped = false;
  Timer? _flushTimer;

  void addPacket(MavlinkPacketEntry entry) {
    if (_paused || _stopped) return;
    _buffer.add(entry);
    if (_buffer.length > _kMaxPackets) {
      _buffer.removeRange(0, _buffer.length - _kMaxPackets);
    }
    _dirty = true;
    _ensureFlushTimer();
  }

  void _ensureFlushTimer() {
    if (_stopped) return;
    _flushTimer ??= Timer.periodic(_kFlushInterval, (_) => _flush());
  }

  void _flush() {
    if (!_dirty || !mounted) return;
    try {
      state = List.unmodifiable(_buffer);
    } catch (_) {
      stopTimer();
      return;
    }
    _dirty = false;
  }

  void clear() {
    _buffer.clear();
    _dirty = false;
    if (!mounted) return;
    try {
      state = const [];
    } catch (_) {
      // Defunct widget element — ignore.
    }
  }

  void pause() {
    _paused = true;
    stopTimer();
  }

  void resume() {
    _paused = false;
    _stopped = false;
    if (_dirty) _ensureFlushTimer();
  }

  /// Stop the flush timer and prevent recreation (called when Inspect tab is
  /// closed). [resume] resets the stopped flag so the timer can restart.
  void stopTimer() {
    _stopped = true;
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  bool get isPaused => _paused;

  /// Synchronously flush pending state for tests.
  void flushForTest() => _flush();

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }
}

final mavlinkInspectorProvider =
    StateNotifierProvider<MavlinkInspectorNotifier, List<MavlinkPacketEntry>>(
  (ref) => MavlinkInspectorNotifier(),
);

// ─── Inspector active gate ───────────────────────────────────────────────────

/// True while the Inspect tab is mounted.  [ConnectionController] checks this
/// before feeding packets into the ring-buffer so we don't waste CPU/memory
/// building inspector state that nobody is watching.
final inspectorActiveProvider = StateProvider<bool>((ref) => false);

/// Tracks whether the inspector capture is paused (for UI rebuild).
final inspectorPausedProvider = StateProvider<bool>((ref) => false);

// ─── Parameter cache ─────────────────────────────────────────────────────────

/// The most recently fetched parameter set (empty before first fetch).
final paramCacheProvider =
    StateProvider<Map<String, Parameter>>((ref) => const {});

/// Progress of the current or most recent parameter fetch (null = idle).
final paramFetchProgressProvider =
    StateProvider<ParamFetchProgress?>((ref) => null);

/// Holds fetched ArduPilot parameter metadata keyed by param name.
/// Empty until the connection controller fetches it for the connected vehicle.
final paramMetadataProvider =
    StateProvider<Map<String, ParamMeta>>((ref) => const {});

/// True while parameter metadata is being fetched from the network/cache.
final paramMetaLoadingProvider = StateProvider<bool>((ref) => false);

// ─── ADS-B Traffic ───────────────────────────────────────────────────────────

/// Tracks live ADS-B traffic from ADSB_VEHICLE messages, expiring targets
/// that haven't been heard from in 60 seconds.
class AdsbNotifier extends StateNotifier<Map<int, AdsbVehicle>> {
  AdsbNotifier() : super({});

  void update(AdsbVehicleMessage msg) {
    if (!mounted) return;
    final vehicle = AdsbVehicle(
      icaoAddress: msg.icaoAddress,
      callsign: msg.callsign,
      position: LatLng(msg.latDeg, msg.lonDeg),
      altMetres: msg.altMetres,
      headingDeg: msg.headingDeg,
      speedMs: msg.speedMs,
      emitterType: msg.emitterType,
      lastSeen: DateTime.now(),
    );
    state = Map.from(state)..[msg.icaoAddress] = vehicle;
  }

  void pruneStale() {
    if (!mounted) return;
    final now = DateTime.now();
    final pruned = Map<int, AdsbVehicle>.from(state)
      ..removeWhere((_, v) => v.isStale(now));
    if (pruned.length != state.length) state = pruned;
  }
}

final adsbProvider =
    StateNotifierProvider<AdsbNotifier, Map<int, AdsbVehicle>>(
  (ref) => AdsbNotifier(),
);

// ─── Alert History ───────────────────────────────────────────────────────────

/// Ring-buffer notifier: keeps the last [_kMaxAlerts] alert entries.
class AlertHistoryNotifier extends StateNotifier<List<AlertEntry>> {
  AlertHistoryNotifier() : super(const []);

  static const _kMaxAlerts = 100;

  void add(AlertEntry entry) {
    if (!mounted) return;
    final next = [...state, entry];
    state = next.length > _kMaxAlerts ? next.sublist(next.length - _kMaxAlerts) : next;
  }

  void clear() {
    if (!mounted) return;
    state = const [];
  }
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

// ─── Auto-Connect (Serial Port Detection) ────────────────────────────────────

/// Whether auto-connect is enabled (persisted via SharedPreferences).
final autoConnectEnabledProvider = StateProvider<bool>((ref) => true);

/// Monitors available serial ports and auto-connects when a saved serial
/// connection is detected. Only active when:
///   - Auto-connect is enabled
///   - A serial connection config is saved
///   - Not already connected
class SerialPortMonitor extends StateNotifier<List<String>> {
  SerialPortMonitor(this._ref) : super([]) {
    _startMonitoring();
  }

  final Ref _ref;
  Timer? _pollTimer;
  static const _pollInterval = Duration(seconds: 2);

  void _startMonitoring() {
    // Initial scan
    _scan();
    // Poll every 2 seconds
    _pollTimer = Timer.periodic(_pollInterval, (_) => _scan());
  }

  void _scan() {
    if (!mounted) return;

    final enabled = _ref.read(autoConnectEnabledProvider);
    if (!enabled) return;

    List<String> ports;
    try {
      ports = serialPortService.availablePorts()
          .map((info) => info.name).toList();
    } catch (_) {
      return;
    }

    final previous = state;
    state = ports;

    // Detect newly appeared ports
    final newPorts = ports.where((p) => !previous.contains(p)).toSet();
    if (newPorts.isEmpty) return;

    // Check if we should auto-connect
    final connection = _ref.read(connectionControllerProvider);
    if (connection.transportState == TransportState.connected ||
        connection.transportState == TransportState.connecting) {
      return;
    }

    final savedConfig = _ref.read(connectionSettingsProvider);
    if (savedConfig is SerialConnectionConfig &&
        newPorts.contains(savedConfig.portName)) {
      // Saved serial port just appeared — auto-connect
      _ref.read(connectionControllerProvider.notifier).connect(savedConfig);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final serialPortMonitorProvider =
    StateNotifierProvider<SerialPortMonitor, List<String>>(
  (ref) => SerialPortMonitor(ref),
);
