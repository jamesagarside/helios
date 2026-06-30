import 'package:dart_mavlink/dart_mavlink.dart';

import '../../shared/models/alert_severity.dart';

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

/// Returns a short human-readable name for a MAVLink message type.
String mavlinkMsgName(MavlinkMessage msg) {
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
int mavlinkPayloadLength(MavlinkMessage msg) {
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

/// Collection of side-effecting sinks the [MavlinkMessageRouter] delegates to.
///
/// Each callback is a pure boundary: the router decides *whether* and *with
/// what* to call them, but never reads providers, services, or timers itself.
/// This is what makes routing testable — a test supplies recording stubs and
/// asserts which sinks fired for a given message.
class MavlinkRouterSinks {
  const MavlinkRouterSinks({
    required this.activeVehicleId,
    required this.handleVehicleMessage,
    required this.isRecording,
    required this.bufferTelemetry,
    required this.addAlert,
    required this.updateAdsb,
    required this.inspectorActive,
    required this.addInspectorPacket,
    required this.knownVehicleIds,
    required this.registerVehicle,
    required this.syncVehicleToRegistry,
    required this.onFirstHeartbeat,
  });

  /// The system id of the active vehicle (0 = accept all systems).
  final int Function() activeVehicleId;

  /// Forward a message to the active vehicle's state notifier.
  final void Function(MavlinkMessage msg) handleVehicleMessage;

  /// Whether telemetry is currently being recorded.
  final bool Function() isRecording;

  /// Buffer a message to the telemetry store.
  final void Function(MavlinkMessage msg) bufferTelemetry;

  /// Append an alert to the alert history.
  final void Function(AlertEntry entry) addAlert;

  /// Update ADS-B traffic from an ADSB_VEHICLE message.
  final void Function(AdsbVehicleMessage msg) updateAdsb;

  /// Whether the Inspector tab is active (and wants packet entries).
  final bool Function() inspectorActive;

  /// Append a packet entry to the inspector ring buffer.
  final void Function(MavlinkPacketEntry entry) addInspectorPacket;

  /// The set of system ids already registered for this connection.
  final Set<int> Function() knownVehicleIds;

  /// Register a newly-seen vehicle (adds to registry, auto-selects if first).
  final void Function(int systemId) registerVehicle;

  /// Sync the live state of the given system id into the vehicle registry, if
  /// it matches the current vehicle state. Called on every heartbeat.
  final void Function(int systemId) syncVehicleToRegistry;

  /// Invoked once, on the first heartbeat of the connection, to kick off
  /// stream-rate requests, firmware version probing and parameter prefetch.
  final void Function(int systemId, int componentId) onFirstHeartbeat;
}

/// Pure MAVLink message router.
///
/// Given a decoded [MavlinkMessage] and a set of [MavlinkRouterSinks], it
/// decides which sinks to call. It holds only the small per-connection routing
/// state ([_streamsRequested]) — no transports, timers, Riverpod refs or I/O —
/// so the "message in → sink calls out" behaviour is unit-testable directly.
class MavlinkMessageRouter {
  MavlinkMessageRouter(this._sinks);

  final MavlinkRouterSinks _sinks;

  bool _streamsRequested = false;

  /// True once the first heartbeat has triggered stream-rate / param setup.
  bool get streamsRequested => _streamsRequested;

  /// Route a single decoded MAVLink message to the configured sinks.
  ///
  /// Mirrors the original inline handler in `ConnectionController`: the
  /// vehicle-state and telemetry paths run unguarded; the notification paths
  /// (alert / adsb / inspector) and the registry update are each wrapped so a
  /// disposed widget element cannot prevent the critical first-heartbeat setup.
  void route(MavlinkMessage msg) {
    // Route to active vehicle's state notifier. VehicleStateNotifier uses a
    // 30Hz batch buffer so state= is called from a Timer, not directly here —
    // safe from defunct elements.
    final activeId = _sinks.activeVehicleId();
    if (activeId == 0 || msg.systemId == activeId) {
      _sinks.handleVehicleMessage(msg);
    }

    // Buffer to DuckDB if recording (no widget listeners, always safe).
    if (_sinks.isRecording()) {
      _sinks.bufferTelemetry(msg);
    }

    // Notification paths: these can trigger widget rebuilds on elements that
    // were disposed between microtasks when the user switches tabs during
    // high-frequency MAVLink traffic. Wrap each in try-catch.
    try {
      if (msg is StatusTextMessage) {
        _sinks.addAlert(AlertEntry(
          message: msg.text,
          severity: AlertSeverity.fromStatusTextSeverity(msg.severity),
          timestamp: DateTime.now(),
        ));
      }

      if (msg is AdsbVehicleMessage) {
        _sinks.updateAdsb(msg);
      }

      if (_sinks.inspectorActive()) {
        _sinks.addInspectorPacket(
          MavlinkPacketEntry(
            msgId: msg.messageId,
            msgName: mavlinkMsgName(msg),
            systemId: msg.systemId,
            componentId: msg.componentId,
            timestamp: DateTime.now(),
            payloadLength: mavlinkPayloadLength(msg),
            severity: msg is StatusTextMessage
                ? AlertSeverity.inspectorHintFromStatusTextSeverity(
                    msg.severity)
                : null,
          ),
        );
      }
    } catch (_) {
      // Widget element disposed between microtasks — safe to ignore.
    }

    // Track vehicle registry + request streams on first heartbeat per vehicle.
    if (msg is HeartbeatMessage && msg.systemId > 0) {
      // Registry updates can trigger widget rebuilds on defunct elements (same
      // race as the notification paths above). Wrap separately so a defunct
      // element does NOT prevent the critical setup below.
      try {
        if (!_sinks.knownVehicleIds().contains(msg.systemId)) {
          _sinks.registerVehicle(msg.systemId);
        }
        _sinks.syncVehicleToRegistry(msg.systemId);
      } catch (_) {
        // Defunct widget element — registry update is cosmetic, safe to skip.
      }

      // CRITICAL: stream rates, param prefetch, firmware version.
      // Must execute even if the registry update above threw.
      if (!_streamsRequested) {
        _streamsRequested = true;
        _sinks.onFirstHeartbeat(msg.systemId, msg.componentId);
      }
    }
  }
}
