import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/database/fake_database.dart';
import 'package:helios_gcs/core/telemetry/forensics_service.dart';
import 'package:helios_gcs/core/telemetry/maintenance_service.dart';
import 'package:helios_gcs/core/telemetry/telemetry_store.dart';

/// Exercises the cross-flight analytics seam (#15) without a live DuckDB.
///
/// A [FakeDatabaseFactory] stands in for the platform factory: each flight
/// file answers the per-table stat fetches, and the in-memory connection
/// answers the final template/analysis query. The aggregation path
/// (`supportsAttach == false`) is the same code the web backend runs.

FlightSummary _flight(String name) => FlightSummary(
      filePath: '/flights/$name.duckdb',
      fileName: '$name.duckdb',
      fileSizeBytes: 1024,
    );

/// Responders that make one opened flight file report the given stats.
List<FakeQueryResponder> _flightResponders({
  required String userName,
  required String startUtc,
  required double maxAlt,
  required double minVoltage,
  required int minBatPct,
  required double avgVibeZ,
  required int totalClips,
}) =>
    [
      FakeQueryResponder(
        (sql) => sql.contains('flight_meta'),
        (_) => {
          'key': ['user_name', 'start_time_utc'],
          'value': [userName, startUtc],
        },
      ),
      FakeQueryResponder(
        (sql) => sql.contains('FROM gps'),
        (_) {
          final ts = startUtc.replaceFirst('T', ' ').replaceFirst('Z', '');
          return {
            'v': [maxAlt],
            't0': [ts],
            't1': [ts],
          };
        },
      ),
      FakeQueryResponder(
        (sql) => sql.contains('FROM vfr_hud'),
        (_) => {
          'mi': [20.0],
          'ag': [9.0],
        },
      ),
      FakeQueryResponder(
        (sql) => sql.contains('FROM battery'),
        (_) => {
          'mv': [minVoltage],
          'mb': [minBatPct],
        },
      ),
      FakeQueryResponder(
        (sql) => sql.contains('FROM vibration'),
        (_) => {
          'ax': [0.1],
          'ay': [0.2],
          'az': [avgVibeZ],
          'mz': [avgVibeZ + 0.2],
          'tc': [totalClips],
        },
      ),
    ];

void main() {
  test('returns empty result for no flights without touching the factory', () {
    final factory = FakeDatabaseFactory();
    final service = ForensicsService(factory: factory);

    return service.query([], sql: 'SELECT 1').then((result) {
      expect(result.rowCount, 0);
      expect(factory.opened, isEmpty);
    });
  });

  test('aggregates flight stats and runs a template via the fake adapter',
      () async {
    final flightA = _flight('a');
    final flightB = _flight('b');

    // The in-memory connection answers the final template query with two rows
    // (the template SELECTs from the flight_stats table the service builds).
    final factory = FakeDatabaseFactory(
      respondersByPath: {
        flightA.filePath: _flightResponders(
          userName: 'Alpha',
          startUtc: '2026-06-01T10:00:00Z',
          maxAlt: 120.0,
          minVoltage: 14.0,
          minBatPct: 40,
          avgVibeZ: 0.3,
          totalClips: 0,
        ),
        flightB.filePath: _flightResponders(
          userName: 'Bravo',
          startUtc: '2026-06-02T10:00:00Z',
          maxAlt: 95.0,
          minVoltage: 13.2,
          minBatPct: 22,
          avgVibeZ: 0.4,
          totalClips: 3,
        ),
      },
      memoryResponders: [
        FakeQueryResponder(
          // The final template SELECT (not the CREATE/INSERT statements).
          (sql) => sql.toUpperCase().contains('FROM FLIGHT_STATS'),
          (_) => {
            'flight_id': ['Alpha', 'Bravo'],
            'start_time': ['2026-06-01T10:00:00Z', '2026-06-02T10:00:00Z'],
            'max_alt_m': [120.0, 95.0],
            'min_voltage_v': [14.0, 13.2],
          },
        ),
      ],
    );

    final service = ForensicsService(factory: factory);

    final result = await service.runTemplate(
      [flightA, flightB],
      ForensicsTemplate.flightComparison,
    );

    expect(result.rowCount, 2);
    expect(result.columnNames, contains('flight_id'));
    expect(result.rows.first['flight_id'], 'Alpha');

    // The fake factory was used (no real DuckDB): one memory conn + two files.
    expect(factory.initialisedCount, greaterThanOrEqualTo(1));
    final memConn = factory.opened.firstWhere((db) => db.path == ':memory:');
    // It created the flight_stats table and inserted two aggregated rows.
    expect(
      memConn.executed.where((s) => s.contains('CREATE TABLE flight_stats')),
      isNotEmpty,
    );
    expect(
      memConn.executed
          .where((s) => s.startsWith('INSERT INTO flight_stats'))
          .length,
      2,
    );
  });

  test('maintenance analysis runs on the fake adapter without DuckDB',
      () async {
    // Build five flights with a steadily declining min voltage so the trend
    // rule fires — all driven through the fake adapter.
    final flights = [
      for (var i = 0; i < 5; i++) _flight('f$i'),
    ];

    final respondersByPath = <String, List<FakeQueryResponder>>{};
    final statRows = <List<dynamic>>[];
    for (var i = 0; i < flights.length; i++) {
      final volt = 14.5 - i * 0.1; // declining
      respondersByPath[flights[i].filePath] = _flightResponders(
        userName: 'F$i',
        startUtc: '2026-06-0${i + 1}T10:00:00Z',
        maxAlt: 100.0,
        minVoltage: volt,
        minBatPct: 35,
        avgVibeZ: 0.3,
        totalClips: 0,
      );
      statRows.add(['F$i', '2026-06-0${i + 1}T10:00:00Z', volt, 35, 0.3, 0.5, 0, i + 1]);
    }

    final factory = FakeDatabaseFactory(
      respondersByPath: respondersByPath,
      memoryResponders: [
        FakeQueryResponder(
          (sql) => sql.toUpperCase().contains('FROM FLIGHT_STATS'),
          (_) => {
            'flight_id': [for (final r in statRows) r[0]],
            'start_time': [for (final r in statRows) r[1]],
            'min_voltage': [for (final r in statRows) r[2]],
            'min_bat_pct': [for (final r in statRows) r[3]],
            'avg_vibe_z': [for (final r in statRows) r[4]],
            'max_vibe_z': [for (final r in statRows) r[5]],
            'total_clips': [for (final r in statRows) r[6]],
            'flight_num': [for (final r in statRows) r[7]],
          },
        ),
      ],
    );

    final service = MaintenanceService(factory: factory);
    final alerts = await service.analyze(flights);

    // A declining-voltage trend should surface at least one battery alert.
    expect(alerts.any((a) => a.category == 'Battery'), isTrue);
  });
}
