import 'dart:async';
import 'dart:typed_data';

import '../../../shared/models/vehicle_state.dart' show TransportState;
import 'transport.dart' show MavlinkTransport;

/// Web Serial API transport for MAVLink communication.
///
/// Uses the browser's Web Serial API to connect to flight controllers
/// via USB. Supported in Chrome 89+ and Edge 89+.
///
/// Named [SerialTransport] to match the native API so conditional
/// imports resolve seamlessly.
///
/// The full JS interop implementation requires `dart:js_interop` calls
/// to navigator.serial. This stub provides the correct API surface and
/// will be completed when the web experience is built out. For now,
/// USB connections work on native platforms; web users should use WebSocket.
class SerialTransport implements MavlinkTransport {
  SerialTransport({
    required this.portName,
    this.baudRate = 115200,
  });

  final String portName;
  final int baudRate;

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
    _disposed = false;
    _setState(TransportState.connecting);
    // Web Serial requires JS interop — not yet wired.
    // Use WebSocket transport for web connections.
    _setState(TransportState.error);
  }

  @override
  Future<void> disconnect() async {
    _setState(TransportState.disconnected);
  }

  @override
  Future<void> send(Uint8List data) async {}

  @override
  void dispose() {
    _disposed = true;
    if (!_dataController.isClosed) _dataController.close();
    if (!_stateController.isClosed) _stateController.close();
  }

  /// List available serial ports (web: returns empty).
  static List<String> availablePorts() => [];

  /// Port description (not available via Web Serial API).
  static String portDescription(String portName) => portName;
}

/// Exception for serial transport errors.
class SerialTransportException implements Exception {
  SerialTransportException(this.message);
  final String message;

  @override
  String toString() => 'SerialTransportException: $message';
}
