/// Abstract interface for the Helios database layer.
///
/// All platform-specific implementations (DuckDB FFI, sql.js WASM) implement
/// this interface. Consumers never import platform-specific code directly.
abstract class HeliosDatabase {
  /// Execute a SQL statement (DDL or DML). No return value.
  void execute(String sql);

  /// Execute a SQL query and return results as column-oriented maps.
  ///
  /// Returns `{ 'col_name': [value0, value1, ...], ... }`.
  /// This matches the DuckDB `fetch()` API and is efficient for columnar access.
  Map<String, List<dynamic>> fetch(String sql);

  /// Close the database connection and release resources.
  void close();

  /// Whether this connection is currently open.
  bool get isOpen;

  /// The file path this database was opened with (`:memory:` for in-memory).
  String get path;
}

/// Capabilities that vary by platform backend.
///
/// Consumers can check these to degrade gracefully when a feature isn't
/// available (e.g. ATTACH is DuckDB-specific).
abstract class HeliosDatabaseCapabilities {
  /// Whether the backend supports ATTACH/DETACH for multi-file queries.
  bool get supportsAttach;

  /// Whether the backend supports COPY ... TO for Parquet/CSV/JSON export.
  bool get supportsCopyExport;

  /// Whether the backend supports window functions (LAG, ROW_NUMBER, etc.).
  bool get supportsWindowFunctions;

  /// Maximum recommended database size in bytes (0 = unlimited).
  int get maxRecommendedSize;
}

/// Factory for creating database connections.
///
/// Each platform provides its own implementation via conditional imports.
/// The [openDatabase] and [openMemoryDatabase] top-level functions are
/// defined in the platform-specific files and re-exported through
/// `database.dart`.
abstract class HeliosDatabaseFactory {
  /// Open a database at the given file path.
  HeliosDatabase open(String filePath);

  /// Open an in-memory database (for temporary analytics).
  HeliosDatabase openMemory();

  /// Platform capabilities.
  HeliosDatabaseCapabilities get capabilities;

  /// Perform any one-time platform initialisation (e.g. loading native libs).
  /// Safe to call multiple times — subsequent calls are no-ops.
  void ensureInitialised();
}
