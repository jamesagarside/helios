/// Platform-resolved serial transport.
///
/// On native: uses libserialport via FFI.
/// On web: uses the Web Serial API.
library;

export 'serial_transport.dart'
    if (dart.library.js_interop) 'serial_transport_web.dart';
