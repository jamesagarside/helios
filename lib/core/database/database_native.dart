import 'dart:ffi';
import 'dart:io';
import 'package:duckdb_dart/duckdb_dart.dart' as duckdb;

import 'database_interface.dart';

// ─── Factory ─────────────────────────────────────────────────────────────────

/// The global database factory for native platforms.
///
/// On desktop (macOS, Linux, Windows): DuckDB via FFI.
/// On mobile (iOS, Android): no-op stub — recording is disabled.
final HeliosDatabaseFactory databaseFactory = _NativeDatabaseFactory();

class _NativeDatabaseFactory implements HeliosDatabaseFactory {
  bool _initialised = false;

  @override
  HeliosDatabase open(String filePath) {
    ensureInitialised();
    if (!duckdb.isSupported) {
      return _UnsupportedDatabase(filePath);
    }
    return NativeDuckDatabase._(duckdb.Connection(filePath), filePath);
  }

  @override
  HeliosDatabase openMemory() {
    ensureInitialised();
    if (!duckdb.isSupported) {
      return _UnsupportedDatabase(':memory:');
    }
    return NativeDuckDatabase._(duckdb.Connection(':memory:'), ':memory:');
  }

  @override
  HeliosDatabaseCapabilities get capabilities => duckdb.isSupported
      ? const _NativeCapabilities()
      : const _UnsupportedCapabilities();

  @override
  void ensureInitialised() {
    if (_initialised) return;
    _initialised = true;
    if (!duckdb.isSupported) return;
    if (Platform.isMacOS) _loadMacOs();
    // Linux and Windows handled by duckdb_dart's default loader.
  }
}

// ─── Connection ──────────────────────────────────────────────────────────────

/// DuckDB FFI-backed database connection.
class NativeDuckDatabase implements HeliosDatabase {
  NativeDuckDatabase._(this._conn, this._path);

  final duckdb.Connection _conn;
  final String _path;
  bool _isOpen = true;

  @override
  void execute(String sql) => _conn.execute(sql);

  @override
  Map<String, List<dynamic>> fetch(String sql) => _conn.fetch(sql);

  @override
  void close() {
    if (_isOpen) {
      _conn.close();
      _isOpen = false;
    }
  }

  @override
  bool get isOpen => _isOpen;

  @override
  String get path => _path;
}

// ─── Capabilities ────────────────────────────────────────────────────────────

class _NativeCapabilities implements HeliosDatabaseCapabilities {
  const _NativeCapabilities();

  @override
  bool get supportsAttach => true;

  @override
  bool get supportsCopyExport => true;

  @override
  bool get supportsWindowFunctions => true;

  @override
  int get maxRecommendedSize => 0; // Unlimited
}

// ─── Unsupported Platform (iOS/Android) ─────────────────────────────────────

/// No-op database for platforms where DuckDB isn't available.
///
/// All operations are safe to call but return empty results. This allows the
/// rest of the app to run without crashing — flight recording is simply
/// disabled on unsupported platforms.
class _UnsupportedDatabase implements HeliosDatabase {
  _UnsupportedDatabase(this._path);

  final String _path;

  @override
  void execute(String sql) {} // no-op

  @override
  Map<String, List<dynamic>> fetch(String sql) => {};

  @override
  void close() {}

  @override
  bool get isOpen => false;

  @override
  String get path => _path;
}

class _UnsupportedCapabilities implements HeliosDatabaseCapabilities {
  const _UnsupportedCapabilities();

  @override
  bool get supportsAttach => false;

  @override
  bool get supportsCopyExport => false;

  @override
  bool get supportsWindowFunctions => false;

  @override
  int get maxRecommendedSize => 0;
}

// ─── macOS DuckDB Loader ─────────────────────────────────────────────────────

void _loadMacOs() {
  final candidates = [
    '${File(Platform.resolvedExecutable).parent.path}/libduckdb.dylib',
    '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks/libduckdb.dylib',
    '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/libduckdb.dylib',
    '/opt/homebrew/lib/libduckdb.dylib',
    '/usr/local/lib/libduckdb.dylib',
    _findProjectNativeLib(),
  ].whereType<String>();

  for (final path in candidates) {
    if (File(path).existsSync()) {
      try {
        DynamicLibrary.open(path);
        return;
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
  var dir = Directory(File(Platform.resolvedExecutable).parent.path);
  for (var i = 0; i < 8; i++) {
    final candidate = File('${dir.path}/native/macos/libduckdb.dylib');
    if (candidate.existsSync()) return candidate.path;
    dir = dir.parent;
  }
  return null;
}
