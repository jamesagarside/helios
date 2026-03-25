import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../../../shared/models/vehicle_state.dart';
import 'transport.dart';

/// TCP transport for MAVLink communication.
///
/// Connects to a remote host:port. Reconnects automatically
/// with exponential backoff on disconnect.
class TcpTransport implements MavlinkTransport {
  TcpTransport({
    required this.host,
    this.port = 5760,
    this.autoReconnect = true,
  });

  final String host;
  final int port;
  final bool autoReconnect;

  Socket? _socket;
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
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  @override
  Future<void> connect() async {
    _setState(TransportState.connecting);
    try {
      _socket = await Socket.connect(host, port);
      _reconnectAttempt = 0;
      _setState(TransportState.connected);

      _socket!.listen(
        (data) {
          _dataController.add(Uint8List.fromList(data));
        },
        onError: (Object error) {
          _setState(TransportState.error);
          _scheduleReconnect();
        },
        onDone: () {
          _setState(TransportState.disconnected);
          _scheduleReconnect();
        },
      );
    } on SocketException {
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
    await _socket?.close();
    _socket = null;
    _setState(TransportState.disconnected);
  }

  @override
  Future<void> send(Uint8List data) async {
    _socket?.add(data);
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _socket?.destroy();
    _dataController.close();
    _stateController.close();
  }
}
