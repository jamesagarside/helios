import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/telemetry/telemetry_store.dart';
import 'package:helios_gcs/features/analyse/providers/analyse_state_notifier.dart';
import 'package:helios_gcs/shared/models/flight_metadata.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────

/// In-memory [AnalyseStore] fake — no DuckDB I/O.
class _FakeAnalyseStore implements AnalyseStore {
  _FakeAnalyseStore({
    this.flights = const [],
    this.metadataByPath = const {},
    this.openError,
    QueryResult? result,
  }) : _result = result;

  List<FlightSummary> flights;
  Map<String, FlightMetadata> metadataByPath;

  /// If set, [query] throws this instead of returning a result.
  Object? queryError;

  /// If set, [openFlight] throws this.
  Object? openError;

  final QueryResult? _result;

  @override
  bool isRecording = false;

  @override
  String? currentFilePath;

  // Call spies for assertions.
  String? openedPath;
  String? lastQuerySql;
  String? deletedPath;
  final Map<String, FlightMetadata> writtenMetadata = {};

  @override
  Future<List<FlightSummary>> listFlights() async => flights;

  @override
  Future<FlightMetadata> getFlightMetadata(String filePath) async =>
      metadataByPath[filePath] ?? const FlightMetadata();

  @override
  Future<void> setFlightMetadata(
      String filePath, FlightMetadata metadata) async {
    writtenMetadata[filePath] = metadata;
  }

  @override
  Future<void> openFlight(String filePath) async {
    if (openError != null) throw openError!;
    openedPath = filePath;
  }

  @override
  Future<QueryResult> query(String sql) async {
    lastQuerySql = sql;
    if (queryError != null) throw queryError!;
    return _result ??
        QueryResult(
          columnNames: const ['n'],
          rows: const [
            [1]
          ],
          executionTime: Duration.zero,
        );
  }

  @override
  Future<void> deleteFlight(String filePath) async {
    deletedPath = filePath;
    flights = flights.where((f) => f.filePath != filePath).toList();
  }
}

FlightSummary _flight(String path) =>
    FlightSummary(filePath: path, fileName: path, fileSizeBytes: 1024);

QueryResult _result({int rows = 2}) => QueryResult(
      columnNames: const ['altitude'],
      rows: List.generate(rows, (i) => [i.toDouble()]),
      executionTime: const Duration(milliseconds: 5),
    );

void main() {
  group('AnalyseStateNotifier initial state', () {
    test('starts empty', () {
      final notifier = AnalyseStateNotifier(_FakeAnalyseStore());
      expect(notifier.state.flights, isEmpty);
      expect(notifier.state.metadata, isEmpty);
      expect(notifier.state.selectedFlight, isNull);
      expect(notifier.state.queryResult, isNull);
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.isQuerying, false);
    });
  });

  group('refreshFlights', () {
    test('loads flights and metadata', () async {
      final store = _FakeAnalyseStore(
        flights: [_flight('/a.duckdb'), _flight('/b.duckdb')],
        metadataByPath: {
          '/a.duckdb': const FlightMetadata(name: 'Alpha'),
        },
      );
      final notifier = AnalyseStateNotifier(store);

      await notifier.refreshFlights();

      expect(notifier.state.flights.length, 2);
      expect(notifier.state.metadata['/a.duckdb']!.name, 'Alpha');
      expect(notifier.state.metadata['/b.duckdb'], const FlightMetadata());
    });
  });

  group('autoSelectAndRefresh', () {
    test('selects the live recording when present', () async {
      final store = _FakeAnalyseStore(
        flights: [_flight('/old.duckdb'), _flight('/live.duckdb')],
      )
        ..isRecording = true
        ..currentFilePath = '/live.duckdb';
      final notifier = AnalyseStateNotifier(store);

      await notifier.autoSelectAndRefresh();

      expect(notifier.state.selectedFlight!.filePath, '/live.duckdb');
      // Live flight is already open — must not reopen.
      expect(store.openedPath, isNull);
    });

    test('selects the most recent flight when not recording', () async {
      final store = _FakeAnalyseStore(
        flights: [_flight('/recent.duckdb'), _flight('/older.duckdb')],
      );
      final notifier = AnalyseStateNotifier(store);

      await notifier.autoSelectAndRefresh();

      expect(notifier.state.selectedFlight!.filePath, '/recent.duckdb');
      expect(store.openedPath, '/recent.duckdb');
    });

    test('is a no-op for selection when one already exists', () async {
      final store = _FakeAnalyseStore(flights: [_flight('/x.duckdb')]);
      final notifier = AnalyseStateNotifier(store);
      await notifier.openFlight(_flight('/x.duckdb'));
      store.openedPath = null; // reset spy

      store.flights = [_flight('/y.duckdb')];
      await notifier.autoSelectAndRefresh();

      // Selection preserved; did not auto-open a different flight.
      expect(notifier.state.selectedFlight!.filePath, '/x.duckdb');
      expect(store.openedPath, isNull);
    });
  });

  group('openFlight', () {
    test('opens flight and clears previous result/error', () async {
      final store = _FakeAnalyseStore();
      final notifier = AnalyseStateNotifier(store);
      // Seed a prior error + result via a failed then successful path.
      store.queryError = Exception('boom');
      await notifier.runQuery('SELECT 1');
      expect(notifier.state.errorMessage, isNotNull);

      store.queryError = null;
      await notifier.openFlight(_flight('/flight.duckdb'));

      expect(notifier.state.selectedFlight!.filePath, '/flight.duckdb');
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.queryResult, isNull);
      expect(store.openedPath, '/flight.duckdb');
    });

    test('does not reopen the live recording', () async {
      final store = _FakeAnalyseStore()
        ..isRecording = true
        ..currentFilePath = '/live.duckdb';
      final notifier = AnalyseStateNotifier(store);

      await notifier.openFlight(_flight('/live.duckdb'));

      expect(notifier.state.selectedFlight!.filePath, '/live.duckdb');
      expect(store.openedPath, isNull);
    });

    test('sets an error message when open fails', () async {
      final store = _FakeAnalyseStore(openError: Exception('disk gone'));
      final notifier = AnalyseStateNotifier(store);

      await notifier.openFlight(_flight('/bad.duckdb'));

      expect(notifier.state.selectedFlight, isNull);
      expect(notifier.state.errorMessage, contains('Failed to open'));
    });
  });

  group('runQuery', () {
    test('successful query populates result and clears querying flag',
        () async {
      final store = _FakeAnalyseStore(result: _result(rows: 3));
      final notifier = AnalyseStateNotifier(store);

      await notifier.runQuery('SELECT altitude FROM attitude');

      expect(notifier.state.queryResult, isNotNull);
      expect(notifier.state.queryResult!.rowCount, 3);
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.isQuerying, false);
      expect(store.lastQuerySql, 'SELECT altitude FROM attitude');
    });

    test('trims SQL before running', () async {
      final store = _FakeAnalyseStore();
      final notifier = AnalyseStateNotifier(store);

      await notifier.runQuery('   SELECT 1   ');

      expect(store.lastQuerySql, 'SELECT 1');
    });

    test('empty SQL is a no-op', () async {
      final store = _FakeAnalyseStore();
      final notifier = AnalyseStateNotifier(store);

      await notifier.runQuery('   ');

      expect(store.lastQuerySql, isNull);
      expect(notifier.state.queryResult, isNull);
    });

    test('failed query sets error and clears result', () async {
      final store = _FakeAnalyseStore(result: _result());
      final notifier = AnalyseStateNotifier(store);
      await notifier.runQuery('SELECT 1'); // seed a result
      expect(notifier.state.queryResult, isNotNull);

      store.queryError = Exception('syntax error');
      await notifier.runQuery('SELECT broken');

      expect(notifier.state.errorMessage, contains('syntax error'));
      expect(notifier.state.queryResult, isNull);
      expect(notifier.state.isQuerying, false);
    });
  });

  group('updateMetadata', () {
    test('persists and reflects metadata in state', () async {
      final store = _FakeAnalyseStore();
      final notifier = AnalyseStateNotifier(store);

      const meta = FlightMetadata(name: 'Test Flight');
      await notifier.updateMetadata('/f.duckdb', meta);

      expect(store.writtenMetadata['/f.duckdb'], meta);
      expect(notifier.state.metadata['/f.duckdb']!.name, 'Test Flight');
    });
  });

  group('deleteFlight', () {
    test('clears selection when the deleted flight was selected', () async {
      final store = _FakeAnalyseStore(flights: [_flight('/f.duckdb')]);
      final notifier = AnalyseStateNotifier(store);
      await notifier.openFlight(_flight('/f.duckdb'));
      await notifier.runQuery('SELECT 1');
      expect(notifier.state.queryResult, isNotNull);

      await notifier.deleteFlight(_flight('/f.duckdb'));

      expect(store.deletedPath, '/f.duckdb');
      expect(notifier.state.selectedFlight, isNull);
      expect(notifier.state.queryResult, isNull);
      expect(notifier.state.flights, isEmpty);
    });

    test('keeps selection when a different flight is deleted', () async {
      final store = _FakeAnalyseStore(
        flights: [_flight('/keep.duckdb'), _flight('/drop.duckdb')],
      );
      final notifier = AnalyseStateNotifier(store);
      await notifier.openFlight(_flight('/keep.duckdb'));

      await notifier.deleteFlight(_flight('/drop.duckdb'));

      expect(notifier.state.selectedFlight!.filePath, '/keep.duckdb');
      expect(notifier.state.flights.length, 1);
    });
  });

  group('setError', () {
    test('records an arbitrary error message', () {
      final notifier = AnalyseStateNotifier(_FakeAnalyseStore());
      notifier.setError('Export failed: nope');
      expect(notifier.state.errorMessage, 'Export failed: nope');
    });
  });
}
