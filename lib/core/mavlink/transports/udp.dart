/// Platform-resolved UDP transport.
library;

export 'udp_transport.dart'
    if (dart.library.js_interop) 'udp_transport_web.dart';
