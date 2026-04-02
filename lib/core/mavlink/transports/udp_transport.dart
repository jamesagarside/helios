import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../../../shared/models/vehicle_state.dart';
import 'transport.dart';

/// UDP transport for MAVLink communication.
///
/// Binds to a local port and auto-discovers the remote endpoint
/// from the first received packet.
class UdpTransport implements MavlinkTransport {
  UdpTransport({
    this.bindAddress = '0.0.0.0',
    this.bindPort = 14550,
  });

  final String bindAddress;
  final int bindPort;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  InternetAddress? _remoteAddress;
  int? _remotePort;
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
    await disconnect();
    _setState(TransportState.connecting);
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress(bindAddress),
        bindPort,
      );
      _socket!.broadcastEnabled = true;

      _subscription = _socket!.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket?.receive();
            if (datagram != null) {
              _remoteAddress ??= datagram.address;
              _remotePort ??= datagram.port;
              if (!_dataController.isClosed) {
                _dataController.add(Uint8List.fromList(datagram.data));
              }
            }
          }
        },
        onError: (Object error) {
          _setState(TransportState.error);
        },
        onDone: () {
          _setState(TransportState.disconnected);
        },
      );

      _setState(TransportState.connected);
    } catch (e) {
      _setState(TransportState.error);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
    _remoteAddress = null;
    _remotePort = null;
    _setState(TransportState.disconnected);
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_socket == null || _remoteAddress == null || _remotePort == null) {
      return;
    }
    _socket!.send(data, _remoteAddress!, _remotePort!);
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _socket?.close();
    _socket = null;
    if (!_dataController.isClosed) _dataController.close();
    if (!_stateController.isClosed) _stateController.close();
  }
}
