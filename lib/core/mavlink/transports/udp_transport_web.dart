import 'dart:async';
import 'dart:typed_data';
import '../../../shared/models/vehicle_state.dart' show TransportState;
import 'transport.dart' show MavlinkTransport;

/// Web stub for UDP transport.
///
/// Browsers cannot open raw UDP sockets. For web, connections go through
/// either Web Serial API (USB) or a WebSocket proxy. This stub allows
/// the app to compile on web with the same API as native.
class UdpTransport implements MavlinkTransport {
  UdpTransport({
    this.bindAddress = '0.0.0.0',
    this.bindPort = 14550,
  });

  final String bindAddress;
  final int bindPort;

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
