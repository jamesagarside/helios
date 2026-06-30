import 'database_interface.dart';

/// A canned `fetch` response keyed by a SQL matcher.
///
/// The [match] predicate decides whether this responder answers a given SQL
/// string; [build] produces the column-oriented result. Responders are tried
/// in registration order, so register more specific matchers first.
class FakeQueryResponder {
  const FakeQueryResponder(this.match, this.build);

  /// Convenience: match when [sql] contains [needle] (case-insensitive).
  factory FakeQueryResponder.contains(
    String needle,
    Map<String, List<dynamic>> result,
  ) {
    final lower = needle.toLowerCase();
    return FakeQueryResponder(
      (sql) => sql.toLowerCase().contains(lower),
      (_) => result,
    );
  }

  /// True if this responder should answer [sql].
  final bool Function(String sql) match;

  /// Build the column-oriented result for [sql].
  final Map<String, List<dynamic>> Function(String sql) build;
}

/// In-memory [HeliosDatabase] that runs no real SQL.
///
/// It records every `execute` and `fetch` call so tests can assert on the
/// statements a module emitted, and returns canned results from a list of
/// [FakeQueryResponder]s. This makes the analytics, forensics and maintenance
/// modules unit-testable without a live DuckDB: a test scripts the per-flight
/// stat fetches and the final template query, then asserts on the outcome.
///
/// Unmatched `fetch` calls return an empty map (mirroring DuckDB's behaviour
/// for zero-row results), and `execute` is a no-op aside from recording.
class FakeHeliosDatabase implements HeliosDatabase {
  FakeHeliosDatabase(
    this._path, {
    List<FakeQueryResponder> responders = const [],
  }) : _responders = List.of(responders);

  final String _path;
  final List<FakeQueryResponder> _responders;
  bool _isOpen = true;

  /// Every SQL string passed to [execute], in order.
  final List<String> executed = [];

  /// Every SQL string passed to [fetch], in order.
  final List<String> fetched = [];

  /// Add a responder after construction (e.g. to script a follow-up query).
  void addResponder(FakeQueryResponder responder) =>
      _responders.add(responder);

  @override
  void execute(String sql) {
    executed.add(sql);
  }

  @override
  Map<String, List<dynamic>> fetch(String sql) {
    fetched.add(sql);
    for (final r in _responders) {
      if (r.match(sql)) return r.build(sql);
    }
    return {};
  }

  @override
  void close() => _isOpen = false;

  @override
  bool get isOpen => _isOpen;

  @override
  String get path => _path;
}

/// Capabilities for the fake backend.
///
/// Defaults mirror the web backend (no ATTACH/COPY) so callers exercise the
/// per-flight aggregation path, but [supportsAttach] is configurable for tests
/// that want to drive the ATTACH branch.
class FakeDatabaseCapabilities implements HeliosDatabaseCapabilities {
  const FakeDatabaseCapabilities({
    this.supportsAttach = false,
    this.supportsCopyExport = false,
    this.supportsWindowFunctions = true,
    this.maxRecommendedSize = 0,
  });

  @override
  final bool supportsAttach;

  @override
  final bool supportsCopyExport;

  @override
  final bool supportsWindowFunctions;

  @override
  final int maxRecommendedSize;
}

/// In-memory [HeliosDatabaseFactory] that hands out [FakeHeliosDatabase]s.
///
/// A test supplies, per file path, the list of responders the opened database
/// should answer with — plus a separate set for the in-memory (`openMemory`)
/// connection forensics builds its `flight_stats` table on. Every opened
/// database is retained in [opened] so assertions can inspect emitted SQL.
class FakeDatabaseFactory implements HeliosDatabaseFactory {
  FakeDatabaseFactory({
    Map<String, List<FakeQueryResponder>> respondersByPath = const {},
    List<FakeQueryResponder> memoryResponders = const [],
    this.capabilities = const FakeDatabaseCapabilities(),
  })  : _respondersByPath = Map.of(respondersByPath),
        _memoryResponders = List.of(memoryResponders);

  final Map<String, List<FakeQueryResponder>> _respondersByPath;
  final List<FakeQueryResponder> _memoryResponders;

  @override
  final HeliosDatabaseCapabilities capabilities;

  /// Number of times [ensureInitialised] was called.
  int initialisedCount = 0;

  /// Every database handed out by [open] or [openMemory], in order.
  final List<FakeHeliosDatabase> opened = [];

  /// Register responders for a file path opened later via [open].
  void registerPath(String path, List<FakeQueryResponder> responders) =>
      _respondersByPath[path] = responders;

  /// Register responders for the next [openMemory] connection.
  void registerMemory(List<FakeQueryResponder> responders) =>
      _memoryResponders
        ..clear()
        ..addAll(responders);

  @override
  HeliosDatabase open(String filePath) {
    final db = FakeHeliosDatabase(
      filePath,
      responders: _respondersByPath[filePath] ?? const [],
    );
    opened.add(db);
    return db;
  }

  @override
  HeliosDatabase openMemory() {
    final db = FakeHeliosDatabase(
      ':memory:',
      responders: _memoryResponders,
    );
    opened.add(db);
    return db;
  }

  @override
  void ensureInitialised() => initialisedCount++;
}
