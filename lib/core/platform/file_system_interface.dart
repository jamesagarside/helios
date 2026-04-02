/// Minimal file system abstraction for Helios.
///
/// Only covers what Helios actually needs: flight directory listing,
/// file size, and file deletion. Not a general-purpose FS layer.
class FlightFileInfo {
  const FlightFileInfo({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.lastModified,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final DateTime lastModified;
}

/// Abstract file system operations needed by the telemetry layer.
abstract class HeliosFileSystem {
  /// Get the directory where flight databases are stored.
  Future<String> get flightsDirectory;

  /// List all .duckdb flight files, sorted newest-first.
  Future<List<FlightFileInfo>> listFlightFiles();

  /// Delete a flight file and its associated WAL/tmp files.
  Future<void> deleteFlightFile(String filePath);

  /// Check if a file exists.
  Future<bool> exists(String filePath);

  /// Ensure a directory exists, creating it if needed.
  Future<void> ensureDirectory(String dirPath);
}
