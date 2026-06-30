import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/database/database.dart';

bool get _duckdbAvailable {
  try {
    final db = databaseFactory.openMemory();
    db.close();
    return true;
  } catch (_) {
    return false;
  }
}

/// Creates a unique temporary directory for a single test and registers
/// recursive cleanup. Each test gets its own directory so that parallel test
/// isolates can never collide on a shared on-disk DuckDB path — and so that
/// the DuckDB `.wal` sidecar (and any other residual files) are always
/// removed, not just the primary `.duckdb` file.
///
/// Returns the absolute path to a `.duckdb` file inside that directory. The
/// file itself does not yet exist; DuckDB creates it on first open.
String _uniqueDbPath(String name) {
  final dir = Directory.systemTemp.createTempSync('helios_db_test_');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return '${dir.path}/$name.duckdb';
}

void main() {
  group('HeliosDatabaseFactory', () {
    test('databaseFactory is available', () {
      expect(databaseFactory, isNotNull);
    });

    test('ensureInitialised can be called multiple times', () {
      // Should not throw on repeated calls.
      databaseFactory.ensureInitialised();
      databaseFactory.ensureInitialised();
    });

    test('capabilities reports DuckDB features on native', () {
      final caps = databaseFactory.capabilities;
      expect(caps.supportsAttach, isTrue);
      expect(caps.supportsCopyExport, isTrue);
      expect(caps.supportsWindowFunctions, isTrue);
      expect(caps.maxRecommendedSize, 0); // Unlimited
    });
  });

  group('HeliosDatabase (native)', skip: !_duckdbAvailable ? 'libduckdb not available' : null, () {
    test('opens in-memory database', () {
      databaseFactory.ensureInitialised();
      final db = databaseFactory.openMemory();

      expect(db.isOpen, isTrue);
      expect(db.path, ':memory:');

      db.close();
      expect(db.isOpen, isFalse);
    });

    test('execute and fetch round-trip', () {
      databaseFactory.ensureInitialised();
      final db = databaseFactory.openMemory();

      db.execute(
        'CREATE TABLE test (id INTEGER, name VARCHAR, value DOUBLE)',
      );
      db.execute(
        "INSERT INTO test VALUES (1, 'alpha', 3.14), (2, 'beta', 2.72)",
      );

      final result = db.fetch('SELECT * FROM test ORDER BY id');

      expect(result.keys, containsAll(['id', 'name', 'value']));
      expect(result['id']!.length, 2);
      expect(result['id']![0], 1);
      expect(result['name']![1], 'beta');
      expect((result['value']![0] as double), closeTo(3.14, 0.01));

      db.close();
    });

    test('opens file-based database with persistence', () {
      databaseFactory.ensureInitialised();
      final path = _uniqueDbPath('persistence');

      // Create and write
      final db = databaseFactory.open(path);
      db.execute('CREATE TABLE t (x INTEGER)');
      db.execute('INSERT INTO t VALUES (42)');
      db.close();

      // Reopen and verify the data survived being written to disk.
      final db2 = databaseFactory.open(path);
      final result = db2.fetch('SELECT x FROM t');
      expect(result['x']![0], 42);
      db2.close();
    });

    test('close is idempotent', () {
      databaseFactory.ensureInitialised();
      final db = databaseFactory.openMemory();
      db.close();
      // Second close should not throw.
      db.close();
      expect(db.isOpen, isFalse);
    });

    test('fetch returns empty result for empty table', () {
      databaseFactory.ensureInitialised();
      final db = databaseFactory.openMemory();
      db.execute('CREATE TABLE empty_t (a INTEGER, b VARCHAR)');

      final result = db.fetch('SELECT * FROM empty_t');
      // DuckDB may return empty keys or empty lists for zero-row results.
      if (result.isNotEmpty) {
        for (final col in result.values) {
          expect(col, isEmpty);
        }
      }

      db.close();
    });

    test('ATTACH works on native (capabilities check)', () {
      databaseFactory.ensureInitialised();
      expect(databaseFactory.capabilities.supportsAttach, isTrue);

      final path = _uniqueDbPath('attach');

      // Create a file DB to attach
      final fileDb = databaseFactory.open(path);
      fileDb.execute('CREATE TABLE data (val INTEGER)');
      fileDb.execute('INSERT INTO data VALUES (99)');
      fileDb.close();

      // Attach from memory DB
      final memDb = databaseFactory.openMemory();
      final escaped = path.replaceAll("'", "''");
      memDb.execute("ATTACH '$escaped' AS ext (READ_ONLY)");

      final result = memDb.fetch('SELECT val FROM ext.data');
      expect(result['val']![0], 99);

      memDb.execute('DETACH ext');
      memDb.close();
    });
  });
}
