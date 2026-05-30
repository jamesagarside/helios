import 'dart:js_interop';

import 'serial_ports_interface.dart';
import 'web_serial_interop.dart';
import 'web_serial_registry.dart';

/// Web serial port service backed by the Web Serial API.
///
/// The Web Serial API requires a user gesture to grant access to a port, so
/// [availablePorts] returns only ports the user has previously granted (via
/// [requestPort], or in an earlier session). Granted handles are tracked in
/// [WebSerialRegistry] so the transport can resolve a name back to a handle.
final SerialPortService serialPortService = _WebSerialPortService();

class _WebSerialPortService implements SerialPortService {
  @override
  bool get isSupported => serial != null;

  @override
  bool get requiresUserGesture => true;

  @override
  List<SerialPortInfo> availablePorts() {
    // Synchronous contract: return the ports we've already discovered and
    // registered. A fresh enumeration is kicked off so the next call (e.g.
    // after a refresh tick) reflects newly granted ports.
    _refresh();
    return WebSerialRegistry.instance.names
        .map((name) => SerialPortInfo(name: name, displayName: name))
        .toList();
  }

  @override
  Future<SerialPortInfo?> requestPort() async {
    final s = serial;
    if (s == null) return null;
    try {
      final port = await s.requestPort().toDart;
      final name = WebSerialRegistry.instance.register(port);
      return SerialPortInfo(name: name, displayName: name);
    } catch (_) {
      // User cancelled the chooser, or access was denied.
      return null;
    }
  }

  /// Populate the registry from already-granted ports (fire-and-forget).
  void _refresh() {
    final s = serial;
    if (s == null) return;
    s.getPorts().toDart.then((ports) {
      for (final port in ports.toDart) {
        WebSerialRegistry.instance.register(port);
      }
    }).catchError((_) {});
  }
}
