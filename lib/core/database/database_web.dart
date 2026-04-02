import 'database_interface.dart';

// ─── Factory ─────────────────────────────────────────────────────────────────

/// The global database factory for web (sql.js / IndexedDB).
///
/// Phase 1: In-memory SQL via sql.js (SQLite compiled to WASM).
/// Phase 2: Persistence via IndexedDB for flight storage.
///
/// This is a compile-time stub — the web backend will be fleshed out when
/// the full web experience is built. For now it provides enough to compile
/// and to support read-only / demo scenarios.
final HeliosDatabaseFactory databaseFactory = _WebDatabaseFactory();

class _WebDatabaseFactory implements HeliosDatabaseFactory {
  @override
  HeliosDatabase open(String filePath) {
    // On web, "file paths" are logical identifiers stored in IndexedDB.
    return _WebDatabase(filePath);
  }

  @override
  HeliosDatabase openMemory() {
    return _WebDatabase(':memory:');
  }

  @override
  HeliosDatabaseCapabilities get capabilities => const _WebCapabilities();

  @override
  void ensureInitialised() {
    // sql.js WASM module loading will go here.
  }
}

// ─── Connection ──────────────────────────────────────────────────────────────

/// Web-backed database connection.
///
/// Will integrate sql.js WASM for real SQL execution. For now, provides
/// a no-op implementation that allows the app to compile and run on web
/// with telemetry features gracefully disabled.
class _WebDatabase implements HeliosDatabase {
  _WebDatabase(this._path);

  final String _path;
  bool _isOpen = true;

  @override
  void execute(String sql) {
    // sql.js integration point: db.run(sql)
  }

  @override
  Map<String, List<dynamic>> fetch(String sql) {
    // sql.js integration point: db.exec(sql) -> column-oriented map
    return {};
  }

  @override
  void close() {
    _isOpen = false;
  }

  @override
  bool get isOpen => _isOpen;

  @override
  String get path => _path;
}

// ─── Capabilities ────────────────────────────────────────────────────────────

class _WebCapabilities implements HeliosDatabaseCapabilities {
  const _WebCapabilities();

  @override
  bool get supportsAttach => false; // No multi-file attach in sql.js

  @override
  bool get supportsCopyExport => false; // No COPY TO on web

  @override
  bool get supportsWindowFunctions => true; // sql.js supports these

  @override
  int get maxRecommendedSize => 50 * 1024 * 1024; // 50 MB for IndexedDB
}
