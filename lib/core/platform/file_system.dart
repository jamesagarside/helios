/// Platform-resolved file system utilities.
///
/// On native: uses dart:io for real file system access.
/// On web: uses IndexedDB / in-memory storage.
library;

export 'file_system_interface.dart';

export 'file_system_native.dart'
    if (dart.library.js_interop) 'file_system_web.dart';
