/// Platform-agnostic serial port discovery and metadata.
///
/// On native platforms, uses libserialport. On web, uses the Web Serial API.
/// Resolved at compile time via conditional imports.
library;

export 'serial_ports_interface.dart';

export 'serial_ports_native.dart'
    if (dart.library.js_interop) 'serial_ports_web.dart';
