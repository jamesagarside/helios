import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/platform/file_system.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HeliosFileSystem (native)', () {
    test('heliosFileSystem is available', () {
      expect(heliosFileSystem, isNotNull);
    });

    // Note: flightsDirectory and listFlightFiles use path_provider which
    // requires platform channel mocking in tests. These are covered by
    // integration tests in the full app build.

    test('exists returns false for nonexistent file', () async {
      final result = await heliosFileSystem.exists('/tmp/nonexistent_12345.db');
      expect(result, isFalse);
    });

    test('ensureDirectory creates nested directories', () async {
      final path =
          '/tmp/helios_fs_test_${DateTime.now().millisecondsSinceEpoch}/sub/dir';
      try {
        await heliosFileSystem.ensureDirectory(path);
        expect(Directory(path).existsSync(), isTrue);
      } finally {
        try {
          Directory('/tmp/helios_fs_test_${path.split('/')[3]}')
              .deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('deleteFlightFile removes file and WAL', () async {
      final base =
          '/tmp/helios_del_test_${DateTime.now().millisecondsSinceEpoch}.duckdb';
      final wal = '$base.wal';

      try {
        // Create dummy files
        File(base).writeAsStringSync('test');
        File(wal).writeAsStringSync('wal');

        expect(File(base).existsSync(), isTrue);
        expect(File(wal).existsSync(), isTrue);

        await heliosFileSystem.deleteFlightFile(base);

        expect(File(base).existsSync(), isFalse);
        expect(File(wal).existsSync(), isFalse);
      } finally {
        try {
          File(base).deleteSync();
        } catch (_) {}
        try {
          File(wal).deleteSync();
        } catch (_) {}
      }
    });

    test('deleteFlightFile rejects path with embedded traversal', () async {
      // Only paths that still contain '..' after normalization are rejected.
      // '/tmp/../etc' normalizes to '/etc' (no '..'), so won't trigger.
      // A path like 'flights/../../etc' would normalize with '..' on some systems.
      await expectLater(
        heliosFileSystem.deleteFlightFile('relative/../../../etc/passwd'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('FlightFileInfo', () {
    test('constructor sets fields', () {
      final info = FlightFileInfo(
        path: '/data/flights/test.duckdb',
        name: 'test.duckdb',
        sizeBytes: 1024,
        lastModified: DateTime(2025, 1, 15),
      );

      expect(info.path, '/data/flights/test.duckdb');
      expect(info.name, 'test.duckdb');
      expect(info.sizeBytes, 1024);
      expect(info.lastModified.year, 2025);
    });
  });
}
