import 'serial_ports_interface.dart';

/// Web serial port service backed by the Web Serial API.
///
/// The Web Serial API works differently from native serial — the browser
/// requires a user gesture to request port access, so [availablePorts]
/// returns only ports the user has previously granted access to.
///
/// Full implementation will use `dart:js_interop` to call
/// `navigator.serial.getPorts()` and `navigator.serial.requestPort()`.
final SerialPortService serialPortService = _WebSerialPortService();

class _WebSerialPortService implements SerialPortService {
  @override
  List<SerialPortInfo> availablePorts() {
    // Web Serial API: navigator.serial.getPorts() returns previously
    // granted ports. Full implementation requires async JS interop.
    return [];
  }

  @override
  bool get isSupported => true; // Chrome/Edge support Web Serial
}
