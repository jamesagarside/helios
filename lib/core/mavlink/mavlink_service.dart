import 'dart:async';
import 'dart:typed_data';
import 'package:dart_mavlink/dart_mavlink.dart';
import '../../shared/models/vehicle_state.dart';
import 'heartbeat_watchdog.dart';
import 'transports/transport.dart';

/// Primary MAVLink communication service.
///
/// Owns the transport, parser, heartbeat watchdog, and GCS heartbeat sender.
/// Decodes incoming messages and broadcasts them to consumers.
class MavlinkService {
  MavlinkService(this._transport);

  final MavlinkTransport _transport;
  final MavlinkParser _parser = MavlinkParser();
  final HeartbeatWatchdog _watchdog = HeartbeatWatchdog();
  late final MavlinkFrameBuilder frameBuilder = MavlinkFrameBuilder();

  StreamSubscription<Uint8List>? _dataSubscription;
  Timer? _heartbeatTimer;

  final _messageController = StreamController<MavlinkMessage>.broadcast();

  int _messagesReceived = 0;
  int _messagesSent = 0;

  /// Stream of all decoded MAVLink messages.
  Stream<MavlinkMessage> get messageStream => _messageController.stream;

  /// Filtered stream of a specific message type.
  Stream<T> messagesOf<T extends MavlinkMessage>() {
    return _messageController.stream.where((m) => m is T).cast<T>();
  }

  /// Current link state from heartbeat watchdog.
  LinkState get linkState => _watchdog.state;

  /// Stream of link state changes.
  Stream<LinkState> get linkStateStream => _watchdog.stateStream;

  /// Transport state.
  TransportState get transportState => _transport.state;

  /// Stream of transport state changes.
  Stream<TransportState> get transportStateStream => _transport.stateStream;

  /// Messages received count.
  int get messagesReceived => _messagesReceived;

  /// Messages sent count.
  int get messagesSent => _messagesSent;

  /// Parse error count.
  int get parseErrors => _parser.parseErrors;

  /// CRC error count.
  int get crcErrors => _parser.crcErrors;

  /// Connect the transport and start message processing.
  ///
  /// Set [alreadyConnected] to true when the transport has already been
  /// connected externally (e.g. during protocol auto-detection).
  Future<void> connect({bool alreadyConnected = false}) async {
    if (!alreadyConnected) await _transport.connect();

    _dataSubscription = _transport.dataStream.listen(_onData);

    // Start GCS heartbeat at 1 Hz
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sendHeartbeat();
    });
  }

  /// Disconnect and stop all processing.
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _dataSubscription?.cancel();
    _dataSubscription = null;
    _watchdog.reset();
    await _transport.disconnect();
  }

  /// Send raw bytes to the vehicle.
  Future<void> sendRaw(Uint8List data) async {
    await _transport.send(data);
    _messagesSent++;
  }

  /// Request telemetry at specified rates.
  ///
  /// Tries MAV_CMD_SET_MESSAGE_INTERVAL (modern, per-message) first.
  /// Falls back to REQUEST_DATA_STREAM (legacy, per-stream-group) if
  /// the FC doesn't support command 511.
  Future<void> requestStreamRates({
    required int targetSystem,
    required int targetComponent,
    int attitudeHz = 10,
    int positionHz = 5,
    int vfrHz = 5,
    int statusHz = 2,
    int rcHz = 2,
  }) async {
    // Try modern per-message interval (command 511) first
    final useModern = await _trySetMessageInterval(
      targetSystem, targetComponent, 30, attitudeHz, // ATTITUDE
    );

    // Always send legacy REQUEST_DATA_STREAM first — this guarantees basic
    // telemetry flows even if the per-message interval path partially fails
    // (e.g. ACK mismatching when multiple SET_MESSAGE_INTERVAL are in flight).
    // Stream IDs: 1=RAW_SENSORS, 2=EXTENDED_STATUS (SYS_STATUS, GPS_RAW_INT,
    // EKF_STATUS_REPORT), 3=RC_CHANNELS, 6=POSITION (GLOBAL_POSITION_INT),
    // 10=EXTRA1 (ATTITUDE), 11=EXTRA2 (VFR_HUD), 12=EXTRA3 (VIBRATION, etc.)
    await _requestLegacyStream(targetSystem, targetComponent, 10, attitudeHz);
    await _requestLegacyStream(targetSystem, targetComponent, 6, positionHz);
    await _requestLegacyStream(targetSystem, targetComponent, 11, vfrHz);
    await _requestLegacyStream(targetSystem, targetComponent, 2, statusHz);
    await _requestLegacyStream(targetSystem, targetComponent, 3, rcHz);
    await _requestLegacyStream(targetSystem, targetComponent, 12, 1);

    if (useModern) {
      // FC supports command 511 — override specific rates per-message.
      // These refine the legacy stream rates for more precise control.
      await _trySetMessageInterval(targetSystem, targetComponent, 33, positionHz); // GLOBAL_POSITION_INT
      await _trySetMessageInterval(targetSystem, targetComponent, 74, vfrHz);      // VFR_HUD
      await _trySetMessageInterval(targetSystem, targetComponent, 1, statusHz);    // SYS_STATUS
      await _trySetMessageInterval(targetSystem, targetComponent, 24, statusHz);   // GPS_RAW_INT
      await _trySetMessageInterval(targetSystem, targetComponent, 65, rcHz);       // RC_CHANNELS
      await _trySetMessageInterval(targetSystem, targetComponent, 241, 1);         // VIBRATION
      await _trySetMessageInterval(targetSystem, targetComponent, 193, 1);         // EKF_STATUS_REPORT
    }
  }

  /// Try MAV_CMD_SET_MESSAGE_INTERVAL (511).
  /// Returns true if the FC accepted it, false if NACKed or timed out.
  Future<bool> _trySetMessageInterval(
    int targetSystem, int targetComponent, int msgId, int rateHz,
  ) async {
    final intervalUs = rateHz > 0 ? (1000000 / rateHz).round() : -1;
    await sendCommand(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      command: 511, // MAV_CMD_SET_MESSAGE_INTERVAL
      param1: msgId.toDouble(),
      param2: intervalUs.toDouble(),
    );

    // Wait briefly for ACK
    try {
      final ack = await messagesOf<CommandAckMessage>()
          .where((m) => m.command == 511)
          .first
          .timeout(const Duration(milliseconds: 500));
      return ack.accepted;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> _requestLegacyStream(
    int targetSystem, int targetComponent, int streamId, int rateHz,
  ) async {
    await sendRaw(frameBuilder.buildRequestDataStream(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      streamId: streamId,
      messageRate: rateHz,
    ));
  }

  /// Send a COMMAND_LONG to the vehicle.
  Future<void> sendCommand({
    required int targetSystem,
    required int targetComponent,
    required int command,
    int confirmation = 0,
    double param1 = 0,
    double param2 = 0,
    double param3 = 0,
    double param4 = 0,
    double param5 = 0,
    double param6 = 0,
    double param7 = 0,
  }) async {
    final frame = frameBuilder.buildCommandLong(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      command: command,
      confirmation: confirmation,
      param1: param1,
      param2: param2,
      param3: param3,
      param4: param4,
      param5: param5,
      param6: param6,
      param7: param7,
    );
    await sendRaw(frame);
  }

  void _onData(Uint8List data) {
    _parser.parse(data);
    final messages = _parser.takeMessages();

    for (final msg in messages) {
      _messagesReceived++;

      // Heartbeat handling
      if (msg is HeartbeatMessage) {
        _watchdog.onHeartbeatReceived();
      }

      _messageController.add(msg);
    }
  }

  Future<void> _sendHeartbeat() async {
    final frame = frameBuilder.buildHeartbeat();
    try {
      await _transport.send(frame);
      _messagesSent++;
    } catch (_) {
      // Transport errors are surfaced via transportStateStream.
    }
  }

  /// Dispose all resources.
  void dispose() {
    _heartbeatTimer?.cancel();
    _dataSubscription?.cancel();
    _watchdog.dispose();
    _transport.dispose();
    _messageController.close();
  }
}
