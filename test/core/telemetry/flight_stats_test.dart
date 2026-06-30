import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/database/fake_database.dart';
import 'package:helios_gcs/core/telemetry/flight_stats.dart';

void main() {
  group('FlightStats.createTable', () {
    test('lists every column in order', () {
      final sql = FlightStats.createTable();
      expect(sql, contains('CREATE TABLE ${FlightStats.tableName}'));
      for (final col in FlightStats.columns.keys) {
        expect(sql, contains(col));
      }
      expect(sql, isNot(contains('TEMP')));
    });

    test('temp variant emits the TEMP keyword', () {
      expect(FlightStats.createTable(temp: true), contains('CREATE TEMP TABLE'));
    });
  });

  group('FlightStats.toValuesTuple', () {
    test('renders nulls and escapes the flight id', () {
      const stats = FlightStats(
        flightId: "O'Brien's flight",
        startTime: null,
        durationMin: 12.5,
        maxAltM: 100.0,
        maxIasMs: null,
        avgGsMs: 8.0,
        minVoltage: 14.2,
        minBatPct: 30,
        avgVibeX: null,
        avgVibeY: 0.1,
        avgVibeZ: 0.2,
        maxVibeZ: 0.5,
        totalClips: 0,
      );
      final tuple = stats.toValuesTuple();
      // Single quote doubled for SQL safety.
      expect(tuple, contains("'O''Brien''s flight'"));
      // Null start time and null aggregates rendered as SQL NULL.
      expect(tuple, contains('NULL'));
      expect(tuple, contains('12.5'));
      expect(stats.toInsert(),
          startsWith('INSERT INTO ${FlightStats.tableName} VALUES ('));
    });
  });

  group('FlightStats.fromDatabase', () {
    test('derives per-table aggregates from a fake database', () {
      final db = FakeHeliosDatabase(
        '/flights/a.duckdb',
        responders: [
          FakeQueryResponder(
            (sql) => sql.contains('FROM gps'),
            (_) => {
              'v': [125.0],
              't0': ['2026-06-30 10:00:00'],
              't1': ['2026-06-30 10:10:00'],
            },
          ),
          FakeQueryResponder(
            (sql) => sql.contains('FROM vfr_hud'),
            (_) => {
              'mi': [22.0],
              'ag': [9.5],
            },
          ),
          FakeQueryResponder(
            (sql) => sql.contains('FROM battery'),
            (_) => {
              'mv': [13.8],
              'mb': [18],
            },
          ),
          FakeQueryResponder(
            (sql) => sql.contains('FROM vibration'),
            (_) => {
              'ax': [0.3],
              'ay': [0.4],
              'az': [0.6],
              'mz': [1.1],
              'tc': [5],
            },
          ),
        ],
      );

      final stats = FlightStats.fromDatabase(
        db,
        flightId: 'My Flight',
        startTime: '2026-06-30T10:00:00Z',
      );

      expect(stats.flightId, 'My Flight');
      expect(stats.startTime, '2026-06-30T10:00:00Z');
      expect(stats.maxAltM, 125.0);
      expect(stats.durationMin, closeTo(10.0, 0.001));
      expect(stats.maxIasMs, 22.0);
      expect(stats.avgGsMs, 9.5);
      expect(stats.minVoltage, 13.8);
      expect(stats.minBatPct, 18);
      expect(stats.avgVibeZ, 0.6);
      expect(stats.maxVibeZ, 1.1);
      expect(stats.totalClips, 5);
    });

    test('leaves fields null when a table query returns nothing', () {
      // No responders → every fetch returns an empty map.
      final db = FakeHeliosDatabase('/flights/empty.duckdb');

      final stats = FlightStats.fromDatabase(
        db,
        flightId: 'empty',
        startTime: '',
      );

      expect(stats.startTime, isNull); // empty string normalised to null
      expect(stats.maxAltM, isNull);
      expect(stats.minBatPct, isNull);
      expect(stats.totalClips, 0);
      expect(stats.durationMin, 0);
    });
  });
}
