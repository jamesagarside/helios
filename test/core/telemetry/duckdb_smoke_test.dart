import 'dart:io';
import 'package:duckdb_dart/duckdb_dart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DuckDB smoke test', () {
    test('opens in-memory database and executes queries', () {
      final conn = Connection.inMemory();

      conn.execute('CREATE TABLE test (id INTEGER, name VARCHAR, value DOUBLE)');
      conn.execute("INSERT INTO test VALUES (1, 'alpha', 3.14), (2, 'beta', 2.72)");

      final result = conn.fetch('SELECT * FROM test ORDER BY id');

      expect(result.keys, containsAll(['id', 'name', 'value']));
      expect(result['id']!.length, 2);
      expect(result['id']![0], 1);
      expect(result['name']![1], 'beta');
      expect((result['value']![0] as double), closeTo(3.14, 0.01));

      conn.close();
    });

    test('creates file-based database', () {
      final path = '/tmp/helios_test_${DateTime.now().millisecondsSinceEpoch}.duckdb';
      final conn = Connection(path);

      conn.execute('CREATE TABLE attitude (ts TIMESTAMP, roll DOUBLE, pitch DOUBLE)');
      conn.execute("INSERT INTO attitude VALUES (NOW(), 0.5, -0.1)");

      final result = conn.fetch('SELECT COUNT(*) AS cnt FROM attitude');
      expect(result['cnt']![0], 1);

      conn.close();

      // Reopen and verify data persists
      final conn2 = Connection(path);
      final result2 = conn2.fetch('SELECT COUNT(*) AS cnt FROM attitude');
      expect(result2['cnt']![0], 1);
      conn2.close();

      // Clean up
      try { File(path).deleteSync(); } catch (_) {}
    });
  });
}
