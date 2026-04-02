/// Platform-agnostic database abstraction for Helios telemetry storage.
///
/// On native platforms (macOS, Linux, Windows, iOS, Android), this is backed
/// by DuckDB via FFI. On web, it uses sql.js (SQLite compiled to WASM).
///
/// Usage:
///   final db = HeliosDatabase.open('path/to/flight.duckdb');
///   db.execute('CREATE TABLE ...');
///   final result = db.fetch('SELECT * FROM ...');
///   db.close();
///
/// The factory constructor resolves at compile time via conditional imports —
/// there is zero runtime overhead for platform detection.
library;

export 'database_interface.dart';

// Conditional export: native platforms get DuckDB, web gets sql.js stub.
export 'database_native.dart'
    if (dart.library.js_interop) 'database_web.dart';
