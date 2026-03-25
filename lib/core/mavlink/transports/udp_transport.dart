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
  InternetAddress? _remoteAddress;
  int? _remotePort;

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
      _socket = await RawDatagramSocket.bind(
        InternetAddress(bindAddress),
        bindPort,
      );
      _socket!.broadcastEnabled = true;

      _socket!.listen(
        (event) {
          if (event == RawSocketEvent.read) {
            final datagram = _socket!.receive();
            if (datagram != null) {
              // Auto-discover remote endpoint from first packet
              _remoteAddress ??= datagram.address;
              _remotePort ??= datagram.port;

              _dataController.add(Uint8List.fromList(datagram.data));
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
    _socket?.close();
    _socket = null;
    _remoteAddress = null;
    _remotePort = null;
    _setState(TransportState.disconnected);
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_socket == null || _remoteAddress == null || _remotePort == null) {
      return; // Silently drop if no remote endpoint known
    }
    _socket!.send(data, _remoteAddress!, _remotePort!);
  }

  @override
  void dispose() {
    _socket?.close();
    _dataController.close();
    _stateController.close();
  }
}
