import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import '../../../shared/models/vehicle_state.dart' show TransportState;
import '../../platform/web_serial_interop.dart';
import '../../platform/web_serial_registry.dart';
import 'transport.dart' show MavlinkTransport;

/// Web Serial API transport for MAVLink communication.
///
/// Uses the browser's Web Serial API to connect to flight controllers over
/// USB. Supported in Chromium-based browsers (Chrome/Edge 89+) over HTTPS.
///
/// Named [SerialTransport] to match the native API so the conditional import
/// in `serial.dart` resolves seamlessly.
///
/// The [portName] is resolved to a granted [WebSerialPort] handle via
/// [WebSerialRegistry]; the user must first grant access with a gesture
/// (see `serialPortService.requestPort()`), which registers the handle.
class SerialTransport implements MavlinkTransport {
  SerialTransport({
    required this.portName,
    this.baudRate = 115200,
  });

  final String portName;
  final int baudRate;

  WebSerialPort? _port;
  ReadableStreamDefaultReader? _reader;
  WritableStreamDefaultWriter? _writer;
  bool _disposed = false;
  bool _reading = false;

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

    final port = WebSerialRegistry.instance.portFor(portName);
    if (port == null) {
      _setState(TransportState.error);
      throw SerialTransportException(
        'No granted Web Serial port named "$portName". '
        'Grant access first (Request Port).',
      );
    }

    try {
      await port.open(WebSerialOptions(baudRate: baudRate)).toDart;
      _port = port;

      final readable = port.readable;
      final writable = port.writable;
      if (readable == null || writable == null) {
        throw SerialTransportException('Port streams unavailable');
      }
      _reader = readable.getReader();
      _writer = writable.getWriter();

      _setState(TransportState.connected);
      unawaited(_readLoop());
    } catch (e) {
      await _closePort();
      _setState(TransportState.error);
      rethrow;
    }
  }

  Future<void> _readLoop() async {
    _reading = true;
    final reader = _reader;
    if (reader == null) return;
    try {
      while (!_disposed && _reader != null) {
        final result = await reader.read().toDart;
        if (result.done) break;
        final value = result.value;
        if (value == null) continue;
        // value is a JS Uint8Array.
        final chunk = (value as JSUint8Array).toDart;
        if (chunk.isNotEmpty && !_dataController.isClosed) {
          _dataController.add(chunk);
        }
      }
    } catch (_) {
      if (!_disposed) _setState(TransportState.error);
    } finally {
      _reading = false;
    }
  }

  @override
  Future<void> send(Uint8List data) async {
    final writer = _writer;
    if (writer == null) return;
    try {
      await writer.write(data.toJS).toDart;
    } catch (_) {
      _setState(TransportState.error);
    }
  }

  @override
  Future<void> disconnect() async {
    await _closePort();
    _setState(TransportState.disconnected);
  }

  Future<void> _closePort() async {
    try {
      await _reader?.cancel().toDart;
    } catch (_) {}
    try {
      _reader?.releaseLock();
    } catch (_) {}
    _reader = null;

    try {
      _writer?.releaseLock();
    } catch (_) {}
    _writer = null;

    try {
      await _port?.close().toDart;
    } catch (_) {}
    _port = null;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_closePort());
    if (!_dataController.isClosed) _dataController.close();
    if (!_stateController.isClosed) _stateController.close();
  }

  /// List available serial ports (web: granted ports from the registry).
  static List<String> availablePorts() => WebSerialRegistry.instance.names;

  /// Port description (web: the synthesised name is already descriptive).
  static String portDescription(String portName) => portName;
}

/// Exception for serial transport errors.
class SerialTransportException implements Exception {
  SerialTransportException(this.message);
  final String message;

  @override
  String toString() => 'SerialTransportException: $message';
}
