import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../../../shared/models/vehicle_state.dart';
import 'transport.dart';

/// Serial (USB) transport for MAVLink communication.
///
/// Connects to a flight controller via USB serial port at the given baud rate.
/// Common configurations:
///   - Pixhawk USB: 115200 baud
///   - SiK telemetry radio: 57600 baud
///   - Holybro telemetry: 57600 baud
class SerialTransport implements MavlinkTransport {
  SerialTransport({
    required this.portName,
    this.baudRate = 115200,
  });

  final String portName;
  final int baudRate;

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _readSub;
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
      _port = SerialPort(portName);

      final config = SerialPortConfig()
        ..baudRate = baudRate
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none
        ..setFlowControl(SerialPortFlowControl.none);

      if (!_port!.openReadWrite()) {
        throw SerialTransportException(
          'Failed to open $portName: ${SerialPort.lastError}',
        );
      }

      _port!.config = config;

      // Low timeout for responsive telemetry — 10ms is enough to batch
      // a full MAVLink frame at 115200 baud without adding visible latency.
      _reader = SerialPortReader(_port!, timeout: 10);
      _readSub = _reader!.stream.listen(
        (data) {
          if (!_dataController.isClosed) {
            _dataController.add(Uint8List.fromList(data));
          }
        },
        onError: (Object error) {
          _setState(TransportState.error);
        },
        onDone: () {
          if (!_disposed) {
            _setState(TransportState.disconnected);
          }
        },
      );

      _setState(TransportState.connected);
    } catch (e) {
      _port?.close();
      _port?.dispose();
      _port = null;
      _setState(TransportState.error);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _readSub?.cancel();
    _readSub = null;
    _reader = null;

    if (_port?.isOpen ?? false) {
      _port!.close();
    }
    _port?.dispose();
    _port = null;
    _setState(TransportState.disconnected);
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_port == null || !_port!.isOpen) return;
    _port!.write(data);
  }

  @override
  void dispose() {
    _disposed = true;
    _readSub?.cancel();
    _reader = null;
    if (_port?.isOpen ?? false) {
      _port!.close();
    }
    _port?.dispose();
    _port = null;
    if (!_dataController.isClosed) _dataController.close();
    if (!_stateController.isClosed) _stateController.close();
  }

  /// List available serial ports on the system.
  static List<String> availablePorts() {
    return SerialPort.availablePorts;
  }

  /// Get a human-readable description for a port.
  static String portDescription(String portName) {
    try {
      final port = SerialPort(portName);
      final desc = port.description ?? portName;
      final manufacturer = port.manufacturer;
      port.dispose();
      if (manufacturer != null && manufacturer.isNotEmpty) {
        return '$desc ($manufacturer)';
      }
      return desc;
    } catch (_) {
      return portName;
    }
  }
}

/// Exception for serial transport errors.
class SerialTransportException implements Exception {
  SerialTransportException(this.message);
  final String message;

  @override
  String toString() => 'SerialTransportException: $message';
}
