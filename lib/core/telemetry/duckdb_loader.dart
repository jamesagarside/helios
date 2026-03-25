import 'dart:ffi';
import 'dart:io';
import 'package:duckdb_dart/duckdb_dart.dart' as duckdb_ffi;

/// Custom DuckDB library loader that supports all platforms.
///
/// The upstream duckdb_dart only supports Linux and Windows.
/// We add macOS support by loading from known paths.
void ensureDuckDbLoaded() {
  // Override the global bindings if on macOS
  if (Platform.isMacOS) {
    _loadMacOs();
  }
  // Linux and Windows handled by duckdb_dart's default loader
}

void _loadMacOs() {
  // Try several locations in order:
  final candidates = [
    // 1. Next to the executable (app bundle)
    '${File(Platform.resolvedExecutable).parent.path}/libduckdb.dylib',
    // 2. In Frameworks (standard macOS bundle location)
    '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks/libduckdb.dylib',
    // 3. In the app's Resources
    '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/libduckdb.dylib',
    // 4. Homebrew
    '/opt/homebrew/lib/libduckdb.dylib',
    // 5. System lib
    '/usr/local/lib/libduckdb.dylib',
    // 6. Project native directory (development)
    _findProjectNativeLib(),
  ].whereType<String>();

  for (final path in candidates) {
    if (File(path).existsSync()) {
      try {
        DynamicLibrary.open(path);
        return; // Successfully loaded
      } catch (_) {
        continue;
      }
    }
  }

  throw StateError(
    'DuckDB native library not found. Install with:\n'
    '  brew install duckdb\n'
    'Or copy libduckdb.dylib to /usr/local/lib/',
  );
}

String? _findProjectNativeLib() {
  // Walk up from executable to find project root with native/ dir
  var dir = Directory(File(Platform.resolvedExecutable).parent.path);
  for (var i = 0; i < 8; i++) {
    final candidate = File('${dir.path}/native/macos/libduckdb.dylib');
    if (candidate.existsSync()) return candidate.path;
    dir = dir.parent;
  }
  return null;
}
