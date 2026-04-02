import 'dart:async';
import 'dart:typed_data';
import '../../../shared/models/vehicle_state.dart' show TransportState;
import 'transport.dart' show MavlinkTransport;

/// Web stub for TCP transport.
///
/// Browsers cannot open raw TCP sockets. For web, connections to flight
/// controllers go through either:
///   1. Web Serial API (USB) — see [WebSerialTransport]
///   2. WebSocket proxy (a small relay server that bridges WS <-> TCP)
///
/// This stub allows the app to compile on web. A future WebSocket
/// transport can bridge to MAVLink over TCP via a proxy.
class TcpTransport implements MavlinkTransport {
  TcpTransport({
    required this.host,
    this.port = 5760,
    this.autoReconnect = true,
  });

  final String host;
  final int port;
  final bool autoReconnect;

  final _dataController = StreamController<Uint8List>.broadcast();
  final _stateController = StreamController<TransportState>.broadcast();
  TransportState _state = TransportState.disconnected;

  @override
  TransportState get state => _state;

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  @override
  Stream<TransportState> get stateStream => _stateController.stream;

  @override
  Future<void> connect() async {
    // Not available on web without a WebSocket proxy.
    if (!_stateController.isClosed) {
      _state = TransportState.error;
      _stateController.add(TransportState.error);
    }
  }

  @override
  Future<void> disconnect() async {
    _state = TransportState.disconnected;
    if (!_stateController.isClosed) {
      _stateController.add(TransportState.disconnected);
    }
  }

  @override
  Future<void> send(Uint8List data) async {}

  @override
  void dispose() {
    if (!_dataController.isClosed) _dataController.close();
    if (!_stateController.isClosed) _stateController.close();
  }
}
