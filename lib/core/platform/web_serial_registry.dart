import 'web_serial_interop.dart';

/// Process-wide registry mapping a stable port *name* (the string the rest of
/// Helios uses to identify a serial port) to the opaque Web Serial
/// [WebSerialPort] handle.
///
/// The Web Serial API never exposes a port name — ports are opaque objects
/// obtained from `navigator.serial.getPorts()` / `requestPort()`. Helios's
/// connection model is name-based, so we synthesise a name (from the USB
/// vendor/product IDs, with a disambiguating index) and keep the handle here
/// for the transport to resolve at connect time.
class WebSerialRegistry {
  WebSerialRegistry._();
  static final WebSerialRegistry instance = WebSerialRegistry._();

  final Map<String, WebSerialPort> _byName = {};

  /// Synthesise a stable display name for [port] and register its handle.
  /// Returns the name. Re-registering the same handle reuses its name.
  String register(WebSerialPort port) {
    // Reuse an existing name if this exact handle is already registered.
    for (final entry in _byName.entries) {
      if (identical(entry.value, port)) return entry.key;
    }

    final info = port.getInfo();
    final vid = info.usbVendorId;
    final pid = info.usbProductId;
    final base = (vid != null && pid != null)
        ? 'USB ${_hex4(vid)}:${_hex4(pid)}'
        : 'Serial Port';

    var name = base;
    var i = 2;
    while (_byName.containsKey(name)) {
      name = '$base #$i';
      i++;
    }
    _byName[name] = port;
    return name;
  }

  /// All registered port names.
  List<String> get names => _byName.keys.toList(growable: false);

  /// Resolve a previously-registered name to its handle, or null.
  WebSerialPort? portFor(String name) => _byName[name];

  String _hex4(int v) => v.toRadixString(16).padLeft(4, '0');
}
