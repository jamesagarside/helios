import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/telemetry/telemetry_store.dart';
import '../../../shared/models/flight_metadata.dart';
import '../../../shared/providers/providers.dart';

/// The subset of [TelemetryStore] operations the Analyse view's query state
/// depends on.
///
/// Declared as an interface so [AnalyseStateNotifier] can be exercised in
/// unit tests with a fake that performs no real DuckDB I/O. The concrete
/// [TelemetryStore] is adapted via [TelemetryAnalyseStore] in production.
abstract class AnalyseStore {
  bool get isRecording;
  String? get currentFilePath;

  Future<List<FlightSummary>> listFlights();
  Future<FlightMetadata> getFlightMetadata(String filePath);
  Future<void> setFlightMetadata(String filePath, FlightMetadata metadata);
  Future<void> openFlight(String filePath);
  Future<QueryResult> query(String sql);
  Future<void> deleteFlight(String filePath);
}

/// Adapts the concrete [TelemetryStore] to the [AnalyseStore] interface.
class TelemetryAnalyseStore implements AnalyseStore {
  TelemetryAnalyseStore(this._store);

  final TelemetryStore _store;

  @override
  bool get isRecording => _store.isRecording;

  @override
  String? get currentFilePath => _store.currentFilePath;

  @override
  Future<List<FlightSummary>> listFlights() => _store.listFlights();

  @override
  Future<FlightMetadata> getFlightMetadata(String filePath) =>
      _store.getFlightMetadata(filePath);

  @override
  Future<void> setFlightMetadata(String filePath, FlightMetadata metadata) =>
      _store.setFlightMetadata(filePath, metadata);

  @override
  Future<void> openFlight(String filePath) => _store.openFlight(filePath);

  @override
  Future<QueryResult> query(String sql) => _store.query(sql);

  @override
  Future<void> deleteFlight(String filePath) => _store.deleteFlight(filePath);
}

/// Immutable query/selection state for the Analyse view.
///
/// Lives behind a [StateNotifier] so it survives tab switches and can be
/// unit-tested in isolation (see issue #19).
class AnalyseState {
  const AnalyseState({
    this.flights = const [],
    this.metadata = const {},
    this.selectedFlight,
    this.queryResult,
    this.errorMessage,
    this.isQuerying = false,
  });

  /// All recorded flights, most recent first.
  final List<FlightSummary> flights;

  /// User metadata keyed by flight file path.
  final Map<String, FlightMetadata> metadata;

  /// The flight currently open for analysis, if any.
  final FlightSummary? selectedFlight;

  /// Result of the last successful query, if any.
  final QueryResult? queryResult;

  /// Last error message (open or query failure), if any.
  final String? errorMessage;

  /// True while a query is in flight.
  final bool isQuerying;

  AnalyseState copyWith({
    List<FlightSummary>? flights,
    Map<String, FlightMetadata>? metadata,
    FlightSummary? selectedFlight,
    QueryResult? queryResult,
    String? errorMessage,
    bool? isQuerying,
    bool clearSelectedFlight = false,
    bool clearQueryResult = false,
    bool clearError = false,
  }) {
    return AnalyseState(
      flights: flights ?? this.flights,
      metadata: metadata ?? this.metadata,
      selectedFlight:
          clearSelectedFlight ? null : (selectedFlight ?? this.selectedFlight),
      queryResult: clearQueryResult ? null : (queryResult ?? this.queryResult),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isQuerying: isQuerying ?? this.isQuerying,
    );
  }
}

/// Owns the Analyse view's query, selection, and metadata state.
class AnalyseStateNotifier extends StateNotifier<AnalyseState> {
  AnalyseStateNotifier(this._store) : super(const AnalyseState());

  final AnalyseStore _store;

  /// Refresh the flight list and load metadata for every flight.
  Future<void> refreshFlights() async {
    final flights = await _store.listFlights();
    state = state.copyWith(flights: flights);
    await _loadAllMetadata(flights);
  }

  /// On first load, refresh flights and auto-select the live or latest flight.
  ///
  /// Does nothing if a flight is already selected (e.g. returning to the tab).
  Future<void> autoSelectAndRefresh() async {
    final flights = await _store.listFlights();
    state = state.copyWith(flights: flights);
    await _loadAllMetadata(flights);

    if (state.selectedFlight != null) return; // already selected

    // Priority 1: the live recording (already open, no need to reopen).
    if (_store.isRecording && _store.currentFilePath != null) {
      final live = flights
          .where((f) => f.filePath == _store.currentFilePath)
          .firstOrNull;
      if (live != null) {
        state = state.copyWith(
          selectedFlight: live,
          clearError: true,
          clearQueryResult: true,
        );
        return;
      }
    }

    // Priority 2: the most recent flight.
    if (flights.isNotEmpty) {
      await openFlight(flights.first);
    }
  }

  Future<void> _loadAllMetadata(List<FlightSummary> flights) async {
    final map = <String, FlightMetadata>{};
    for (final flight in flights) {
      try {
        map[flight.filePath] = await _store.getFlightMetadata(flight.filePath);
      } catch (_) {
        map[flight.filePath] = const FlightMetadata();
      }
    }
    state = state.copyWith(metadata: map);
  }

  /// Open a flight for analysis, clearing any previous result/error.
  ///
  /// If the flight is the live recording, the store connection is reused.
  Future<void> openFlight(FlightSummary flight) async {
    if (_store.isRecording && _store.currentFilePath == flight.filePath) {
      state = state.copyWith(
        selectedFlight: flight,
        clearError: true,
        clearQueryResult: true,
      );
      return;
    }

    try {
      await _store.openFlight(flight.filePath);
      state = state.copyWith(
        selectedFlight: flight,
        clearError: true,
        clearQueryResult: true,
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to open: $e');
    }
  }

  /// Run a SQL query against the open flight, updating result/error state.
  Future<void> runQuery(String sql) async {
    final trimmed = sql.trim();
    if (trimmed.isEmpty) return;

    state = state.copyWith(isQuerying: true, clearError: true);

    try {
      final result = await _store.query(trimmed);
      state = state.copyWith(queryResult: result, isQuerying: false);
    } catch (e) {
      state = state.copyWith(
        errorMessage: e.toString(),
        isQuerying: false,
        clearQueryResult: true,
      );
    }
  }

  /// Set an error message (e.g. from an export failure handled by the view).
  void setError(String message) {
    state = state.copyWith(errorMessage: message);
  }

  /// Persist updated metadata for a flight and reflect it in state.
  Future<void> updateMetadata(String filePath, FlightMetadata metadata) async {
    await _store.setFlightMetadata(filePath, metadata);
    final map = Map<String, FlightMetadata>.from(state.metadata);
    map[filePath] = metadata;
    state = state.copyWith(metadata: map);
  }

  /// Delete a flight, clearing the selection if it was the active one.
  Future<void> deleteFlight(FlightSummary flight) async {
    await _store.deleteFlight(flight.filePath);
    final map = Map<String, FlightMetadata>.from(state.metadata)
      ..remove(flight.filePath);
    if (state.selectedFlight?.filePath == flight.filePath) {
      state = state.copyWith(
        metadata: map,
        clearSelectedFlight: true,
        clearQueryResult: true,
      );
    } else {
      state = state.copyWith(metadata: map);
    }
    await refreshFlights();
  }
}

/// Provider for the Analyse view's query/selection state.
final analyseStateProvider =
    StateNotifierProvider<AnalyseStateNotifier, AnalyseState>((ref) {
  final store = ref.watch(telemetryStoreProvider);
  return AnalyseStateNotifier(TelemetryAnalyseStore(store));
});
