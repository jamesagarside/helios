/// Platform-resolved TCP transport.
library;

export 'tcp_transport.dart'
    if (dart.library.js_interop) 'tcp_transport_web.dart';
