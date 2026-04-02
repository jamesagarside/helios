import 'file_system_interface.dart';

/// Web file system implementation using IndexedDB.
///
/// On web, "flight files" are stored as blobs in IndexedDB keyed by
/// a logical path. This stub allows compilation — the full IndexedDB
/// persistence layer will be implemented alongside the sql.js backend.
final HeliosFileSystem heliosFileSystem = _WebFileSystem();

class _WebFileSystem implements HeliosFileSystem {
  @override
  Future<String> get flightsDirectory async => '/flights';

  @override
  Future<List<FlightFileInfo>> listFlightFiles() async {
    // IndexedDB integration point: list keys in the 'flights' object store
    return [];
  }

  @override
  Future<void> deleteFlightFile(String filePath) async {
    // IndexedDB integration point: delete key from 'flights' object store
  }

  @override
  Future<bool> exists(String filePath) async => false;

  @override
  Future<void> ensureDirectory(String dirPath) async {
    // No-op on web — IndexedDB doesn't have directories
  }
}
