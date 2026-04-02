import 'dart:async';
import 'dart:typed_data';
import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../core/mavlink/mavlink_service.dart';
import '../../core/mavlink/transports/transport.dart';
import '../../core/mavlink/transports/udp.dart';
import '../../core/mavlink/transports/tcp.dart';
import '../../core/mavlink/transports/serial.dart';
import '../../core/mavlink/transports/websocket_transport.dart';
import '../../core/platform/serial_ports.dart';
import '../../core/mission/mission_service.dart';
import '../../core/msp/msp_service.dart';
import '../../core/logs/log_download_service.dart';
import '../../core/params/parameter_service.dart';
import '../../core/params/param_meta.dart';
import '../../core/params/param_meta_service.dart';
import '../../core/protocol_detector.dart';
import '../../core/mavlink/flight_modes.dart';
import '../../core/rally/rally_service.dart';
import '../../core/telemetry/maintenance_service.dart';
import '../../core/telemetry/replay_service.dart';
import '../../core/telemetry/telemetry_store.dart';
import '../models/adsb_vehicle.dart';
import '../models/rally_point.dart';
import '../models/vehicle_state.dart';
import '../models/connection_state.dart';
import '../models/mission_item.dart';
import '../models/recording_state.dart';
import 'connection_settings_provider.dart';
import 'stream_rate_provider.dart';
import 'vehicle_state_notifier.dart';

// ─── MAVLink Inspector ───────────────────────────────────────────────────────

/// A single decoded MAVLink packet entry for the Inspector tab.
class MavlinkPacketEntry {
  const MavlinkPacketEntry({
    required this.msgId,
    required this.msgName,
    required this.systemId,
    required this.componentId,
    required this.timestamp,
    this.payloadLength = 0,
    this.severity,
  });

  final int msgId;
  final String msgName;
  final int systemId;
  final int componentId;
  final DateTime timestamp;
  final int payloadLength;
  /// Only set for STATUSTEXT messages; null for all telemetry packets.
  final AlertSeverity? severity;
}

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

// ─── MAVLink Inspector helpers ────────────────────────────────────────────────

/// Returns a short human-readable name for a MAVLink message type.
String _mavlinkMsgName(MavlinkMessage msg) {
  return switch (msg) {
    HeartbeatMessage() => 'HEARTBEAT',
    AttitudeMessage() => 'ATTITUDE',
    GlobalPositionIntMessage() => 'GLOBAL_POSITION_INT',
    GpsRawIntMessage() => 'GPS_RAW_INT',
    SysStatusMessage() => 'SYS_STATUS',
    VfrHudMessage() => 'VFR_HUD',
    VibrationMessage() => 'VIBRATION',
    StatusTextMessage() => 'STATUSTEXT',
    CommandAckMessage() => 'COMMAND_ACK',
    RcChannelsMessage() => 'RC_CHANNELS',
    ServoOutputRawMessage() => 'SERVO_OUTPUT_RAW',
    LogEntryMessage() => 'LOG_ENTRY',
    LogDataMessage() => 'LOG_DATA',
    MagCalProgressMessage() => 'MAG_CAL_PROGRESS',
    MagCalReportMessage() => 'MAG_CAL_REPORT',
    EkfStatusReportMessage() => 'EKF_STATUS_REPORT',
    ParamRequestListMessage() => 'PARAM_REQUEST_LIST',
    ParamValueMessage() => 'PARAM_VALUE',
    ParamSetMessage() => 'PARAM_SET',
    MissionCurrentMessage() => 'MISSION_CURRENT',
    MissionRequestListMessage() => 'MISSION_REQUEST_LIST',
    MissionCountMessage() => 'MISSION_COUNT',
    MissionAckMessage() => 'MISSION_ACK',
    MissionRequestIntMessage() => 'MISSION_REQUEST_INT',
    MissionItemIntMessage() => 'MISSION_ITEM_INT',
    AutopilotVersionMessage() => 'AUTOPILOT_VERSION',
    MountStatusMessage() => 'MOUNT_STATUS',
    HomePositionMessage() => 'HOME_POSITION',
    WindMessage() => 'WIND',
    AdsbVehicleMessage() => 'ADSB_VEHICLE',
    UnknownMessage() => 'MSG_${msg.messageId}',
    _ => msg.runtimeType.toString().replaceAll('Message', '').toUpperCase(),
  };
}

/// Returns an estimated payload length for a MAVLink message.
int _mavlinkPayloadLength(MavlinkMessage msg) {
  return switch (msg) {
    HeartbeatMessage() => 9,
    AttitudeMessage() => 28,
    GlobalPositionIntMessage() => 28,
    GpsRawIntMessage() => 30,
    SysStatusMessage() => 31,
    VfrHudMessage() => 20,
    VibrationMessage() => 32,
    StatusTextMessage() => 54,
    CommandAckMessage() => 10,
    RcChannelsMessage() => 42,
    ServoOutputRawMessage() => 37,
    EkfStatusReportMessage() => 26,
    ParamValueMessage() => 25,
    MissionCurrentMessage() => 6,
    MissionCountMessage() => 4,
    MissionItemIntMessage() => 38,
    AutopilotVersionMessage() => 60,
    AdsbVehicleMessage() => 38,
    _ => 0,
  };
}

/// Connection controller — manages the MavlinkService lifecycle.
class ConnectionController extends StateNotifier<ConnectionStatus> {
  ConnectionController(this._ref) : super(const ConnectionStatus());

  final Ref _ref;
  MavlinkService? _service;
  MspService? _mspService;
  StreamSubscription<MavlinkMessage>? _messageSub;
  StreamSubscription<VehicleState>? _mspStateSub;
  StreamSubscription<LinkState>? _linkSub;
  StreamSubscription<TransportState>? _transportStateSub;
  Timer? _rateTimer;
  Timer? _reconnectTimer;
  int _lastMsgCount = 0;
  bool _intentionalDisconnect = false;
  bool _reconnecting = false;
  int _reconnectAttempts = 0;
  // Only true after a connection is fully established; prevents auto-reconnect
  // firing for an initial connection attempt that never succeeded.
  bool _wasConnected = false;

  static const _reconnectDelays = [2, 4, 8, 16, 30];

  bool get isConnected =>
      state.transportState == TransportState.connected;

  Future<void> connect(ConnectionConfig config) async {
    _intentionalDisconnect = false;
    await disconnect();

    final MavlinkTransport transport = switch (config) {
      UdpConnectionConfig(:final bindAddress, :final port) =>
        UdpTransport(bindAddress: bindAddress, bindPort: port),
      TcpConnectionConfig(:final host, :final port) =>
        TcpTransport(host: host, port: port),
      SerialConnectionConfig(:final portName, :final baudRate) =>
        SerialTransport(portName: portName, baudRate: baudRate),
      WebSocketConnectionConfig(:final uri) =>
        WebSocketTransport(uri: uri),
    };

    try {
      if (config.protocol == ProtocolType.auto) {
        await _connectWithDetection(transport, config);
        return;
      }

      if (config.protocol == ProtocolType.msp) {
        await _connectMsp(transport, config);
        return;
      }

      await _connectMavlink(transport, config);
    } catch (_) {
      // Connection failure is already reflected in state (TransportState.error).
      // Swallow here so unawaited callers (e.g. UI button handlers) don't crash.
    }
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
    _logDownloadService = LogDownloadService(_service!);
    _rallyService = RallyService(_service!);

    // Wire link state changes to connection status
    _linkSub = _service!.linkStateStream.listen((linkState) {
      state = state.copyWith(linkState: linkState);
      _ref.read(connectionStatusProvider.notifier).state = state;
    });

    // Watch for transport errors (e.g. USB serial unplugged) and auto-reconnect.
    // Only reconnect if the connection was fully established (_wasConnected),
    // not when the initial connect attempt fails.
    _transportStateSub = _service!.transportStateStream.listen((ts) {
      if (ts == TransportState.error && _wasConnected && !_intentionalDisconnect && !_reconnecting) {
        _scheduleReconnect(config);
      }
    });

    // Wire all messages to VehicleStateNotifier + TelemetryStore
    final Set<int> knownSystems = {};
    bool streamsRequested = false;
    _messageSub = _service!.messageStream.listen((msg) {
      // Route to active vehicle's state notifier.
      // VehicleStateNotifier uses a 30Hz batch buffer so state= is
      // called from a Timer, not directly here — safe from defunct elements.
      final activeId = _ref.read(activeVehicleIdProvider);
      if (activeId == 0 || msg.systemId == activeId) {
        _ref.read(vehicleStateProvider.notifier).handleMessage(msg);
      }

      // Buffer to DuckDB if recording (no widget listeners, always safe).
      final store = _ref.read(telemetryStoreProvider);
      if (store.isRecording) {
        store.buffer(msg);
      }

      // Notification paths: these can trigger widget rebuilds on elements
      // that were disposed between microtasks when the user switches tabs
      // during high-frequency MAVLink traffic. Wrap each in try-catch.
      try {
        if (msg is StatusTextMessage) {
          final severity = switch (msg.severity) {
            0 || 1 || 2 => AlertSeverity.critical,
            3 => AlertSeverity.critical,
            4 => AlertSeverity.warning,
            5 => AlertSeverity.warning,
            _ => AlertSeverity.info,
          };
          _ref.read(alertHistoryProvider.notifier).add(AlertEntry(
            message: msg.text,
            severity: severity,
            timestamp: DateTime.now(),
          ));
        }

        if (msg is AdsbVehicleMessage) {
          _ref.read(adsbProvider.notifier).update(msg);
          _ref.read(adsbProvider.notifier).pruneStale();
        }

        if (_ref.read(inspectorActiveProvider)) {
          _ref.read(mavlinkInspectorProvider.notifier).addPacket(
            MavlinkPacketEntry(
              msgId: msg.messageId,
              msgName: _mavlinkMsgName(msg),
              systemId: msg.systemId,
              componentId: msg.componentId,
              timestamp: DateTime.now(),
              payloadLength: _mavlinkPayloadLength(msg),
              severity: msg is StatusTextMessage
                  ? switch (msg.severity) {
                      0 || 1 || 2 || 3 => AlertSeverity.critical,
                      4 => AlertSeverity.warning,
                      _ => AlertSeverity.info,
                    }
                  : null,
            ),
          );
        }
      } catch (_) {
        // Widget element disposed between microtasks — safe to ignore.
      }

      // Track vehicle registry + request streams on first heartbeat per vehicle.
      if (msg is HeartbeatMessage && msg.systemId > 0) {
        // Registry updates can trigger widget rebuilds on defunct elements
        // (same race as the notification paths above). Wrap separately so
        // a defunct element does NOT prevent the critical setup below.
        try {
          if (!knownSystems.contains(msg.systemId)) {
            knownSystems.add(msg.systemId);
            final registry = Map<int, VehicleState>.from(
              _ref.read(vehicleRegistryProvider),
            );
            registry[msg.systemId] = const VehicleState();
            _ref.read(vehicleRegistryProvider.notifier).state = registry;

            if (_ref.read(activeVehicleIdProvider) == 0) {
              _ref.read(activeVehicleIdProvider.notifier).state = msg.systemId;
            }
          }

          final current = _ref.read(vehicleStateProvider);
          if (msg.systemId == current.systemId) {
            final registry = Map<int, VehicleState>.from(
              _ref.read(vehicleRegistryProvider),
            );
            registry[msg.systemId] = current;
            _ref.read(vehicleRegistryProvider.notifier).state = registry;
          }
        } catch (_) {
          // Defunct widget element — registry update is cosmetic, safe to skip.
        }

        // CRITICAL: stream rates, param prefetch, firmware version.
        // Must execute even if registry updates above threw.
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

          _requestFirmwareVersion(msg.systemId, msg.componentId);

          _prefetchParams(
            targetSystem: msg.systemId,
            targetComponent: msg.componentId,
          );
          // Defer metadata prefetch so the 30Hz batch has time to flush
          // vehicleType from the heartbeat before we read it.
          Future.delayed(const Duration(milliseconds: 100), () {
            final vt = _ref.read(vehicleStateProvider).vehicleType;
            _prefetchParamMetadata(vt);
          });
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

      _wasConnected = true;
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

      _wasConnected = true;
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

  /// Request AUTOPILOT_VERSION with retries and fallback to the older
  /// MAV_CMD_REQUEST_AUTOPILOT_CAPABILITIES (cmd 520) for FCs that don't
  /// support MAV_CMD_REQUEST_MESSAGE (cmd 512).
  void _requestFirmwareVersion(int targetSystem, int targetComponent) {
    void sendViaRequestMessage() {
      _service?.sendCommand(
        targetSystem: targetSystem,
        targetComponent: targetComponent,
        command: MavCmd.requestMessage,
        param1: 148, // AUTOPILOT_VERSION msg_id
      );
    }

    void sendViaLegacy() {
      _service?.sendCommand(
        targetSystem: targetSystem,
        targetComponent: targetComponent,
        command: MavCmd.requestAutopilotCapabilities,
        param1: 1, // request = 1
      );
    }

    // Attempt 1: MAV_CMD_REQUEST_MESSAGE (modern)
    sendViaRequestMessage();

    // Attempt 2 (2s): retry modern command
    Future.delayed(const Duration(seconds: 2), () {
      if (_intentionalDisconnect || _service == null) return;
      if (_ref.read(vehicleStateProvider).firmwareVersionString.isEmpty) {
        sendViaRequestMessage();
      }
    });

    // Attempt 3 (5s): fall back to legacy MAV_CMD_REQUEST_AUTOPILOT_CAPABILITIES
    Future.delayed(const Duration(seconds: 5), () {
      if (_intentionalDisconnect || _service == null) return;
      if (_ref.read(vehicleStateProvider).firmwareVersionString.isEmpty) {
        sendViaLegacy();
      }
    });

    // Attempt 4 (8s): final retry with legacy
    Future.delayed(const Duration(seconds: 8), () {
      if (_intentionalDisconnect || _service == null) return;
      if (_ref.read(vehicleStateProvider).firmwareVersionString.isEmpty) {
        sendViaLegacy();
      }
    });
  }

  static const _kParamFetchRetries = 2;

  Future<void> _prefetchParams({
    required int targetSystem,
    required int targetComponent,
  }) async {
    if (_paramService == null) return;
    // Let the FC settle and finish its initial telemetry burst first.
    await Future<void>.delayed(const Duration(seconds: 3));
    if (_paramService == null || _intentionalDisconnect) return;

    for (var attempt = 0; attempt <= _kParamFetchRetries; attempt++) {
      if (_paramService == null || _intentionalDisconnect) return;

      _ref.read(paramFetchProgressProvider.notifier).state =
          const ParamFetchProgress(received: 0, total: 0);

      StreamSubscription<ParamFetchProgress>? progressSub;
      progressSub = _paramService!.progressStream.listen((p) {
        _ref.read(paramFetchProgressProvider.notifier).state = p;
        if (p.done) progressSub?.cancel();
      });

      try {
        final params = await _paramService!.fetchAll(
          targetSystem: targetSystem,
          targetComponent: targetComponent,
        );
        if (_paramService != null && params.isNotEmpty) {
          _ref.read(paramCacheProvider.notifier).state = params;
          return; // Success — no retry needed.
        }
      } catch (e) {
        // ignore: avoid_print
        print('[Helios] Param prefetch attempt ${attempt + 1} failed: $e');
      } finally {
        progressSub.cancel();
      }

      // Wait before retrying (increasing backoff).
      if (attempt < _kParamFetchRetries) {
        await Future<void>.delayed(Duration(seconds: 3 + attempt * 2));
      }
    }
  }

  Future<void> _prefetchParamMetadata(VehicleType vt) async {
    _ref.read(paramMetaLoadingProvider.notifier).state = true;
    try {
      final meta = await ParamMetaService().loadForVehicle(vt);
      _ref.read(paramMetadataProvider.notifier).state = meta;
    } catch (_) {
      // Metadata is an optional enhancement — silent degradation.
    } finally {
      _ref.read(paramMetaLoadingProvider.notifier).state = false;
    }
  }

  void _scheduleReconnect(ConnectionConfig config) {
    _reconnecting = true;
    final delaySecs = _reconnectDelays[
        _reconnectAttempts.clamp(0, _reconnectDelays.length - 1)];
    _reconnectAttempts++;

    state = state.copyWith(transportState: TransportState.connecting);
    _ref.read(connectionStatusProvider.notifier).state = state;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySecs), () async {
      if (_intentionalDisconnect) return;
      try {
        // Tear down the broken service without flagging as intentional.
        _reconnectTimer = null;
        _rateTimer?.cancel(); _rateTimer = null;
        await _messageSub?.cancel(); _messageSub = null;
        await _linkSub?.cancel(); _linkSub = null;
        await _transportStateSub?.cancel(); _transportStateSub = null;
        await _service?.disconnect(); _service?.dispose(); _service = null;
        _lastMsgCount = 0;

        await _connectMavlink(
          switch (config) {
            SerialConnectionConfig(:final portName, :final baudRate) =>
              SerialTransport(portName: portName, baudRate: baudRate),
            UdpConnectionConfig(:final bindAddress, :final port) =>
              UdpTransport(bindAddress: bindAddress, bindPort: port),
            TcpConnectionConfig(:final host, :final port) =>
              TcpTransport(host: host, port: port),
            WebSocketConnectionConfig(:final uri) =>
              WebSocketTransport(uri: uri),
          },
          config,
        );
        _reconnecting = false;
        _reconnectAttempts = 0;
      } catch (_) {
        // Still failing — schedule another attempt if not intentionally stopped.
        if (!_intentionalDisconnect) {
          _scheduleReconnect(config);
        }
      }
    });
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnecting = false;
    _reconnectAttempts = 0;
    _wasConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _rateTimer?.cancel();
    _rateTimer = null;
    await _messageSub?.cancel();
    _messageSub = null;
    await _mspStateSub?.cancel();
    _mspStateSub = null;
    await _linkSub?.cancel();
    _linkSub = null;
    await _transportStateSub?.cancel();
    _transportStateSub = null;
    _paramService?.dispose();
    _paramService = null;
    _logDownloadService?.dispose();
    _logDownloadService = null;
    _missionService?.dispose();
    _missionService = null;
    _rallyService?.dispose();
    _rallyService = null;
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
    _ref.read(paramCacheProvider.notifier).state = const {};
    _ref.read(paramFetchProgressProvider.notifier).state = null;
    _ref.read(paramMetadataProvider.notifier).state = const {};
    _ref.read(paramMetaLoadingProvider.notifier).state = false;
    state = const ConnectionStatus();
    _ref.read(connectionStatusProvider.notifier).state = state;
  }

  MissionService? _missionService;
  ParameterService? _paramService;
  LogDownloadService? _logDownloadService;
  RallyService? _rallyService;

  /// The mission service for download/upload operations.
  MissionService? get missionService => _missionService;

  /// The parameter service for reading/writing FC params.
  ParameterService? get paramService => _paramService;

  /// The log download service for Dataflash log operations.
  LogDownloadService? get logDownloadService => _logDownloadService;

  /// The rally point service for upload/download operations.
  RallyService? get rallyService => _rallyService;

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

  /// Send a Click & Go position target using SET_POSITION_TARGET_GLOBAL_INT.
  ///
  /// Switches to GUIDED mode first (ArduCopter custom_mode = 4), then sends
  /// the position target. [altAgl] is altitude above home in metres.
  Future<void> sendClickGo({
    required double lat,
    required double lon,
    required double altAgl,
  }) async {
    if (_service == null) return;
    final vehicle = _ref.read(vehicleStateProvider);
    // Switch to GUIDED (ArduCopter = 4, ArduRover/Plane = 15).
    // Send both so it works across vehicle types.
    await _service!.sendCommand(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      command: MavCmd.doSetMode,
      param1: 1.0, // MAV_MODE_FLAG_CUSTOM_MODE_ENABLED
      param2: 4.0, // GUIDED for ArduCopter
    );
    final frame = _service!.frameBuilder.buildSetPositionTargetGlobalInt(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      latInt: (lat * 1e7).round(),
      lonInt: (lon * 1e7).round(),
      altM: altAgl,
    );
    await _service!.sendRaw(frame);
  }

  /// Send RC_CHANNELS_OVERRIDE to the vehicle (msg_id=70).
  void sendRcOverride({
    required int ch1,
    required int ch2,
    required int ch3,
    required int ch4,
  }) {
    if (_service == null) return;
    final vehicle = _ref.read(vehicleStateProvider);
    final frame = _service!.frameBuilder.buildRcChannelsOverride(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      ch1: ch1,
      ch2: ch2,
      ch3: ch3,
      ch4: ch4,
    );
    _service!.sendRaw(frame);
  }

  /// Pause the current mission (MAV_CMD_DO_PAUSE_CONTINUE, param1=0).
  Future<bool> pauseMission() async {
    return sendCommandWithRetry(command: MavCmd.doPauseContinue, param1: 0);
  }

  /// Resume the current mission (MAV_CMD_DO_PAUSE_CONTINUE, param1=1).
  Future<bool> resumeMission() async {
    return sendCommandWithRetry(command: MavCmd.doPauseContinue, param1: 1);
  }

  /// Set ROI to a specific location (MAV_CMD_DO_SET_ROI_LOCATION).
  Future<bool> setRoi({required double lat, required double lon, required double alt}) async {
    return sendCommandWithRetry(
      command: MavCmd.doSetRoiLocation,
      param5: lat,
      param6: lon,
      param7: alt,
    );
  }

  /// Clear ROI (MAV_CMD_DO_SET_ROI_NONE).
  Future<bool> clearRoi() async {
    return sendCommandWithRetry(command: MavCmd.doSetRoiNone);
  }

  /// Reboot the autopilot (MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN, param1=1).
  Future<bool> rebootAutopilot() async {
    return sendCommandWithRetry(
      command: MavCmd.preflightRebootShutdown,
      param1: 1,
    );
  }

  /// Emergency force-disarm (kills motors immediately).
  Future<void> forceDisarm() async {
    if (_service == null) return;
    final vehicle = _ref.read(vehicleStateProvider);
    await _service!.sendCommand(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      command: MavCmd.componentArmDisarm,
      param1: 0,       // disarm
      param2: 21196,   // force
    );
  }

  /// Set home position to a specific location.
  Future<bool> setHome({required double lat, required double lon, required double alt}) async {
    return sendCommandWithRetry(
      command: MavCmd.doSetHome,
      param1: 0, // Use specified location (not current position)
      param5: lat,
      param6: lon,
      param7: alt,
    );
  }

  /// Set home position to current vehicle location.
  Future<bool> setHomeHere() async {
    return sendCommandWithRetry(
      command: MavCmd.doSetHome,
      param1: 1, // Use current position
    );
  }

  /// Change flight speed (MAV_CMD_DO_CHANGE_SPEED).
  Future<bool> changeSpeed({required double speedMs, int speedType = 1}) async {
    return sendCommandWithRetry(
      command: MavCmd.doChangeSpeed,
      param1: speedType.toDouble(), // 0=airspeed, 1=groundspeed, 2=climb
      param2: speedMs,
      param3: -1, // no throttle change
    );
  }

  /// Set the current mission waypoint (skip ahead or restart).
  Future<void> setCurrentWaypoint(int seq) async {
    if (_service == null) return;
    final vehicle = _ref.read(vehicleStateProvider);
    // Send MISSION_SET_CURRENT (msg_id=41)
    final payload = Uint8List(4);
    final data = ByteData.sublistView(payload);
    data.setUint16(0, seq, Endian.little);
    payload[2] = vehicle.systemId;
    payload[3] = vehicle.componentId;
    await _service!.sendRaw(
      _service!.frameBuilder.buildFrame(messageId: 41, payload: payload),
    );
  }

  /// Enable or disable the geofence via FENCE_ENABLE param.
  Future<void> setFenceEnabled(bool enabled) async {
    if (_paramService == null) return;
    final vehicle = _ref.read(vehicleStateProvider);
    await _paramService!.setParam(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      paramId: 'FENCE_ENABLE',
      value: enabled ? 1.0 : 0.0,
    );
  }

  /// Set a single parameter on the FC and update the local cache.
  Future<double?> setParamValue(String paramId, double value) async {
    if (_paramService == null) return null;
    final vehicle = _ref.read(vehicleStateProvider);
    try {
      final confirmed = await _paramService!.setParam(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
        paramId: paramId,
        value: value,
      );
      // Update local cache
      final cache = Map<String, Parameter>.from(_ref.read(paramCacheProvider));
      if (cache.containsKey(paramId)) {
        cache[paramId]!.value = confirmed;
      }
      _ref.read(paramCacheProvider.notifier).state = cache;
      return confirmed;
    } catch (_) {
      return null;
    }
  }

  /// Send a MAV_CMD_NAV_TAKEOFF with [altM] metres above home.
  Future<void> sendTakeoff(double altM) async {
    if (_service == null) return;
    final vehicle = _ref.read(vehicleStateProvider);
    await _service!.sendCommand(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      command: MavCmd.navTakeoff,
      param7: altM,
    );
  }

  /// Command vehicle to RTL mode.
  Future<void> sendRtl() async {
    final v = _ref.read(vehicleStateProvider);
    await setFlightMode(FlightModeRegistry.rtlMode(v.vehicleType));
  }

  /// Command vehicle to LAND mode.
  Future<void> sendLand() async {
    final v = _ref.read(vehicleStateProvider);
    await setFlightMode(FlightModeRegistry.landMode(v.vehicleType));
  }

  /// Command vehicle to LOITER / HOLD mode.
  Future<void> sendLoiter() async {
    final v = _ref.read(vehicleStateProvider);
    await setFlightMode(FlightModeRegistry.loiterMode(v.vehicleType));
  }

  /// Start an autonomous mission (AUTO mode).
  Future<void> sendAuto() async {
    final v = _ref.read(vehicleStateProvider);
    await setFlightMode(FlightModeRegistry.autoMode(v.vehicleType));
  }

  /// Emergency brake (Copter) or hold (other vehicle types).
  Future<void> sendBrake() async {
    final v = _ref.read(vehicleStateProvider);
    await setFlightMode(FlightModeRegistry.brakeMode(v.vehicleType));
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

  /// Download rally points from vehicle.
  Future<List<RallyPoint>> downloadRallyPoints() async {
    if (_service == null || _rallyService == null) return [];
    final vehicle = _ref.read(vehicleStateProvider);
    try {
      return await _rallyService!.download(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
      );
    } on RallyProtocolException {
      return [];
    }
  }

  /// Upload rally points to vehicle.
  Future<bool> uploadRallyPoints(List<RallyPoint> points) async {
    if (_service == null || _rallyService == null) return false;
    final vehicle = _ref.read(vehicleStateProvider);
    try {
      await _rallyService!.upload(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
        points: points,
      );
      return true;
    } on RallyProtocolException {
      return false;
    }
  }

  @override
  void dispose() {
    _missionService?.dispose();
    _rallyService?.dispose();
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
