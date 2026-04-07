import 'dart:ffi';
import 'dart:io';
import 'duckdb.g.dart';

Bindings? _duckdb;

DynamicLibrary? _dynLib;

Bindings get bindings {
  return _duckdb ??= Bindings(open());
}

/// Whether DuckDB is available on this platform.
///
/// Returns false on iOS and Android where the native library is not bundled.
bool get isSupported =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

DynamicLibrary open() {
  if (_duckdb == null) {
    if (Platform.isLinux) {
      _dynLib = DynamicLibrary.open('/usr/local/lib/libduckdb.so');
    } else if (Platform.isMacOS) {
      _dynLib = _openMacOs();
    } else if (Platform.isWindows) {
      _dynLib = DynamicLibrary.open('duckdb.dll');
    } else {
      throw StateError(
        'DuckDB is not available on ${Platform.operatingSystem}. '
        'Check isSupported before calling open().',
      );
    }
  }
  return _dynLib!;
}

DynamicLibrary _openMacOs() {
  // Try paths in order of preference
  final paths = [
    '/usr/local/lib/libduckdb.dylib',
    '/opt/homebrew/lib/libduckdb.dylib',
    // App bundle locations
    '${File(Platform.resolvedExecutable).parent.path}/libduckdb.dylib',
    '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks/libduckdb.dylib',
  ];

  for (final path in paths) {
    if (File(path).existsSync()) {
      try {
        return DynamicLibrary.open(path);
      } catch (_) {
        continue;
      }
    }
  }

  throw StateError(
    'DuckDB native library not found on macOS. Install with:\n'
    '  cp libduckdb.dylib /usr/local/lib/\n'
    'Or: brew install duckdb',
  );
}
