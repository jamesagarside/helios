import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'file_system_interface.dart';

/// Native file system implementation using dart:io.
final HeliosFileSystem heliosFileSystem = _NativeFileSystem();

class _NativeFileSystem implements HeliosFileSystem {
  String? _cachedDir;

  @override
  Future<String> get flightsDirectory async {
    if (_cachedDir != null) return _cachedDir!;
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'flights'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _cachedDir = dir.path;
    return _cachedDir!;
  }

  @override
  Future<List<FlightFileInfo>> listFlightFiles() async {
    final dir = Directory(await flightsDirectory);
    if (!dir.existsSync()) return [];

    final files = dir.listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.duckdb'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    return files.map((f) => FlightFileInfo(
      path: f.path,
      name: p.basename(f.path),
      sizeBytes: f.lengthSync(),
      lastModified: f.lastModifiedSync(),
    )).toList();
  }

  @override
  Future<void> deleteFlightFile(String filePath) async {
    final normalized = p.normalize(filePath);
    if (normalized.contains('..')) {
      throw ArgumentError('Path traversal detected: $filePath');
    }
    final file = File(normalized);
    if (file.existsSync()) file.deleteSync();
    // Also delete WAL/tmp files if present
    final wal = File('$normalized.wal');
    if (wal.existsSync()) wal.deleteSync();
    final tmp = File('$normalized.tmp');
    if (tmp.existsSync()) tmp.deleteSync();
  }

  @override
  Future<bool> exists(String filePath) async => File(filePath).existsSync();

  @override
  Future<void> ensureDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }
}
