import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../shared/models/vehicle_state.dart' show TransportState;
import 'transport.dart';

/// WebSocket transport for MAVLink communication.
///
/// Connects to a WebSocket endpoint and streams raw MAVLink bytes.
/// Works on **all platforms** including web — no dart:io required.
///
/// Typical usage scenarios:
///   - Web browser → helios-relay on localhost (ws://localhost:8765)
///   - Web browser → companion computer running mavlink-router with WS
///   - Native app → any WebSocket-capable MAVLink bridge
///
/// The WebSocket carries raw binary frames — no JSON wrapping, no
/// additional framing. Each WS message = one or more MAVLink packets.
class WebSocketTransport implements MavlinkTransport {
  WebSocketTransport({
    required this.uri,
    this.autoReconnect = true,
  });

  /// WebSocket URI (e.g. 'ws://localhost:8765', 'ws://192.168.4.1:8765').
  final Uri uri;
  final bool autoReconnect;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _disposed = false;

  final _dataController = StreamController<Uint8List>.broadcast();
  final _stateController = StreamController<TransportState>.broadcast();
  TransportState _state = TransportState.disconnected;

  @override
  TransportState get state => _state;

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  @override
  Stream<TransportState> get stateStream => _stateController.stream;

  void _setState(TransportState newState) {
    if (_state != newState && !_disposed) {
      _state = newState;
      if (!_stateController.isClosed) {
        _stateController.add(newState);
      }
    }
  }

  @override
  Future<void> connect() async {
    _setState(TransportState.connecting);

    try {
      _channel = WebSocketChannel.connect(uri);

      // Wait for the connection to be established
      await _channel!.ready;

      _reconnectAttempt = 0;
      _setState(TransportState.connected);

      _subscription = _channel!.stream.listen(
        (dynamic data) {
          if (_dataController.isClosed) return;
          if (data is List<int>) {
            _dataController.add(Uint8List.fromList(data));
          } else if (data is String) {
            // Some bridges send base64 or text — handle gracefully
            _dataController.add(Uint8List.fromList(data.codeUnits));
          }
        },
        onError: (Object error) {
          _setState(TransportState.error);
          _scheduleReconnect();
        },
        onDone: () {
          if (!_disposed) {
            _setState(TransportState.disconnected);
            _scheduleReconnect();
          }
        },
      );
    } catch (e) {
      _channel = null;
      _setState(TransportState.error);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!autoReconnect || _disposed) return;

    _reconnectAttempt++;
    final delay = Duration(
      seconds: _backoffSeconds(_reconnectAttempt).clamp(0, 30),
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_disposed) connect();
    });
  }

  int _backoffSeconds(int attempt) {
    if (attempt <= 1) return 1;
    return 1 << (attempt - 1); // 1, 2, 4, 8, 16, 30 max
  }

  @override
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _setState(TransportState.disconnected);
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_channel == null) return;
    try {
      _channel!.sink.add(data);
    } catch (_) {
      _setState(TransportState.error);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    if (!_dataController.isClosed) _dataController.close();
    if (!_stateController.isClosed) _stateController.close();
  }
}
