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
  late final MavlinkFrameBuilder _frameBuilder = MavlinkFrameBuilder();

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
  Future<void> connect() async {
    await _transport.connect();

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
    final frame = _frameBuilder.buildCommandLong(
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

  void _sendHeartbeat() {
    final frame = _frameBuilder.buildHeartbeat();
    _transport.send(frame);
    _messagesSent++;
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
