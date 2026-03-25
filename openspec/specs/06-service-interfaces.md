# Helios GCS — Service Layer Interface Specification

**Version**: 1.0.0 | **Status**: Draft | **Date**: 2026-03-24

---

## 1. MavlinkService

The central service for MAVLink communication. Owns the transport, parser, and message routing.

```dart
/// Primary MAVLink communication service.
/// Runs message parsing in a dedicated isolate.
class MavlinkService {
  MavlinkService(this._transport);

  /// Connect the transport and start message processing.
  /// Throws [TransportException] if connection fails.
  Future<void> connect(ConnectionConfig config);

  /// Disconnect and stop processing.
  Future<void> disconnect();

  /// Stream of all decoded MAVLink messages (for external consumers).
  Stream<MavlinkMessage> get messageStream;

  /// Stream of specific message types (filtered).
  Stream<T> messagesOf<T extends MavlinkMessage>();

  /// Send a MAVLink message to the vehicle.
  /// Throws [NotConnectedException] if transport is not connected.
  Future<void> send(MavlinkMessage message);

  /// Current connection status.
  ConnectionStatus get status;

  /// Telemetry statistics (messages/s, errors, etc.)
  TelemetryStats get stats;

  /// Command sender for outbound vehicle commands.
  CommandSender get commands;

  /// Heartbeat watchdog state.
  LinkState get linkState;
}

/// Exceptions
class TransportException implements Exception {
  final String message;
  final Object? cause;
  TransportException(this.message, [this.cause]);
}

class NotConnectedException implements Exception {}
class CommandTimeoutException implements Exception {
  final int commandId;
  CommandTimeoutException(this.commandId);
}
```

---

## 2. TelemetryStore

Manages DuckDB operations for flight recording and analysis.

```dart
/// Embedded DuckDB flight data store.
/// All database operations run in a dedicated isolate.
class TelemetryStore {
  /// Create a new flight database file and initialise schema.
  /// Returns the file path of the created database.
  Future<String> createFlight({
    required int vehicleSysId,
    required VehicleType vehicleType,
    required AutopilotType autopilot,
    String? firmwareVersion,
  });

  /// Open an existing flight database for analysis.
  /// Throws [FlightNotFoundException] if file doesn't exist.
  /// Throws [SchemaVersionException] if schema is too new.
  Future<void> openFlight(String filePath);

  /// Close the current flight database.
  Future<void> closeFlight();

  /// Buffer a decoded MAVLink message for batch insert.
  /// Non-blocking. Messages are queued and flushed periodically.
  void buffer(MavlinkMessage message);

  /// Force flush all buffered messages to DuckDB.
  /// Called automatically every 1 second, but can be triggered manually.
  Future<int> flush();

  /// Execute a SQL query and return results.
  /// Returns column names and typed rows.
  Future<QueryResult> query(String sql);

  /// Execute a pre-built analytics template.
  Future<QueryResult> runTemplate(AnalyticsTemplate template);

  /// Export a table or query result to Parquet.
  Future<String> exportParquet({
    String? tableName,
    String? sql,
    required String outputPath,
  });

  /// Export all tables to a directory of Parquet files with manifest.
  Future<ExportManifest> exportAllParquet(String outputDirectory);

  /// List all flight database files.
  Future<List<FlightSummary>> listFlights();

  /// Delete a flight database file.
  Future<void> deleteFlight(String filePath);

  /// Current recording state.
  bool get isRecording;

  /// Statistics about the current recording.
  RecordingStats get recordingStats;
}

class QueryResult {
  final List<String> columnNames;
  final List<List<dynamic>> rows;
  final int rowCount;
  final Duration executionTime;
}

class FlightSummary {
  final String filePath;
  final String flightId;
  final DateTime startTime;
  final DateTime? endTime;
  final Duration duration;
  final int fileSizeBytes;
  final String vehicleType;
  final String autopilot;
}

class ExportManifest {
  final String directory;
  final Map<String, TableExport> tables;
  final DateTime exportTime;
}

class TableExport {
  final String fileName;
  final int rowCount;
  final String sha256;
}

/// Exceptions
class FlightNotFoundException implements Exception {
  final String filePath;
  FlightNotFoundException(this.filePath);
}

class SchemaVersionException implements Exception {
  final int fileVersion;
  final int appVersion;
  SchemaVersionException(this.fileVersion, this.appVersion);
}

class QueryException implements Exception {
  final String sql;
  final String message;
  QueryException(this.sql, this.message);
}
```

---

## 3. MissionService

Handles the MAVLink mission protocol for waypoint management.

```dart
/// Mission planning and transfer service.
class MissionService {
  MissionService(this._mavlink);

  /// Download the current mission from the vehicle.
  /// Emits progress via [transferProgress].
  Future<List<MissionItem>> downloadMission();

  /// Upload a mission to the vehicle.
  /// Emits progress via [transferProgress].
  Future<void> uploadMission(List<MissionItem> items);

  /// Clear the mission on the vehicle.
  Future<void> clearMission();

  /// Set the current waypoint (jump to).
  Future<void> setCurrentWaypoint(int seq);

  /// Stream of transfer progress (0.0 - 1.0).
  Stream<double> get transferProgress;

  /// Stream of current mission state.
  Stream<MissionState> get missionState;

  /// Create a new waypoint at the given position.
  MissionItem createWaypoint({
    required int seq,
    required double latitude,
    required double longitude,
    double altitude = 100.0,
    MavFrame frame = MavFrame.globalRelativeAlt,
    MavCmd command = MavCmd.navWaypoint,
    double holdTime = 0,
    double acceptRadius = 10,
    double passRadius = 0,
  });

  /// Generate a survey pattern (P1).
  List<MissionItem> generateSurvey({
    required List<LatLng> polygon,
    required double altitude,
    required double lineSpacing,
    required double overshoot,
    SurveyPattern pattern = SurveyPattern.lawnmower,
  });
}

enum SurveyPattern { lawnmower, crosshatch }

/// Mission transfer exceptions
class MissionTransferException implements Exception {
  final String message;
  final MavMissionResult? result;
  MissionTransferException(this.message, [this.result]);
}
```

---

## 4. ExportService

Handles data export and Argus synchronisation.

```dart
/// Data export and platform synchronisation.
class ExportService {
  ExportService(this._store);

  /// Export a single flight to Parquet files.
  Future<ExportManifest> exportFlight({
    required String flightPath,
    required String outputDirectory,
  });

  /// Export a custom query result to Parquet.
  Future<String> exportQuery({
    required String sql,
    required String outputPath,
  });

  /// Sync a Parquet export to an Argus endpoint (P2).
  Future<SyncResult> syncToArgus({
    required String exportDirectory,
    required ArgusEndpoint endpoint,
  });

  /// List available export formats.
  List<ExportFormat> get supportedFormats;
}

enum ExportFormat { parquet, csv, json }

class ArgusEndpoint {
  final String url;
  final String apiKey;
  final bool useMtls;
  final String? clientCertPath;
}

class SyncResult {
  final bool success;
  final int tablesUploaded;
  final int rowsUploaded;
  final String? errorMessage;
}
```

---

## 5. MapTileService

Manages offline map tile caching.

```dart
/// Offline map tile management.
class MapTileService {
  /// Download tiles for a region at specified zoom levels.
  Stream<DownloadProgress> downloadRegion({
    required LatLngBounds bounds,
    required List<int> zoomLevels,
    String? regionName,
  });

  /// Cancel an in-progress download.
  Future<void> cancelDownload();

  /// List all cached tile regions.
  Future<List<CachedRegion>> listRegions();

  /// Delete a cached tile region.
  Future<void> deleteRegion(String regionId);

  /// Total tile cache size in bytes.
  Future<int> totalCacheSize();

  /// Clear the entire tile cache.
  Future<void> clearCache();
}

class DownloadProgress {
  final int tilesDownloaded;
  final int tilesTotal;
  final int bytesDownloaded;
  final double percentComplete;
}

class CachedRegion {
  final String id;
  final String? name;
  final LatLngBounds bounds;
  final List<int> zoomLevels;
  final int tileCount;
  final int sizeBytes;
  final DateTime cachedAt;
}
```

---

## 6. Error Handling Strategy

### 6.1 Error Classification

| Category | Examples | Handling |
|----------|---------|----------|
| Transient | Network timeout, serial buffer overflow | Retry with backoff |
| Recoverable | DuckDB write failure, parse error | Log, continue, surface warning |
| Fatal | DuckDB corruption, out of disk space | Stop recording, alert user, preserve data |
| User Error | Invalid SQL, bad waypoint values | Inline validation message |

### 6.2 Error Propagation Rules

1. **Service layer** catches all exceptions, wraps in typed exceptions, never throws raw Dart exceptions.
2. **State layer** surfaces errors via dedicated error state fields (not thrown exceptions).
3. **Presentation layer** reads error state and shows appropriate UI (snackbar, dialog, inline message).
4. **Isolate errors** are caught via `Isolate.errors` stream and forwarded to the main isolate.

### 6.3 Logging

```dart
/// Structured logging with levels and source context.
enum LogLevel { debug, info, warning, error, fatal }

class HeliosLogger {
  void log(LogLevel level, String message, {
    String? source,
    Object? error,
    StackTrace? stackTrace,
  });
}
```

- All log messages include timestamp, level, source (service name), message.
- WARNING and above are stored in the events table (if recording).
- DEBUG logs only in debug builds.
- No `print()` calls anywhere — all output via logger.
