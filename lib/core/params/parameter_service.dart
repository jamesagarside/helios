import 'dart:async';
import 'dart:io';
import 'package:dart_mavlink/dart_mavlink.dart';
import '../mavlink/mavlink_service.dart';

/// A single flight controller parameter.
class Parameter {
  Parameter({
    required this.id,
    required this.value,
    required this.type,
    required this.index,
    this.defaultValue,
  });

  final String id;
  double value;
  final int type; // MAV_PARAM_TYPE
  final int index;
  double? defaultValue;

  /// The group prefix (e.g. "ARMING" from "ARMING_CHECK").
  String get group {
    final sep = id.indexOf('_');
    return sep > 0 ? id.substring(0, sep) : 'OTHER';
  }

  /// Whether this looks like an integer parameter.
  bool get isInteger =>
      type != 9 && type != 10; // not REAL32 or REAL64

  Parameter copyWith({double? value}) =>
      Parameter(id: id, value: value ?? this.value, type: type, index: index, defaultValue: defaultValue);
}

/// Transfer progress during parameter fetch.
class ParamFetchProgress {
  const ParamFetchProgress({this.received = 0, this.total = 0, this.done = false, this.error});
  final int received;
  final int total;
  final bool done;
  final String? error;

  double get progress => total > 0 ? received / total : 0;
}

/// Service for fetching and setting flight controller parameters.
///
/// Protocol:
///   Fetch: GCS sends PARAM_REQUEST_LIST → FC streams PARAM_VALUE for each param
///   Set:   GCS sends PARAM_SET → FC echoes PARAM_VALUE with new value
class ParameterService {
  ParameterService(this._mavlink);

  final MavlinkService _mavlink;
  final Map<String, Parameter> _params = {};
  StreamSubscription<MavlinkMessage>? _sub;

  Map<String, Parameter> get params => Map.unmodifiable(_params);
  int get count => _params.length;

  final _progressController = StreamController<ParamFetchProgress>.broadcast();
  Stream<ParamFetchProgress> get progressStream => _progressController.stream;

  /// Fetch all parameters from the vehicle.
  Future<Map<String, Parameter>> fetchAll({
    required int targetSystem,
    required int targetComponent,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _params.clear();
    final completer = Completer<Map<String, Parameter>>();
    int expectedCount = -1;
    Timer? timeoutTimer;
    Timer? gapTimer;

    void cleanup() {
      _sub?.cancel();
      _sub = null;
      timeoutTimer?.cancel();
      gapTimer?.cancel();
    }

    void checkComplete() {
      if (expectedCount > 0 && _params.length >= expectedCount) {
        cleanup();
        _progressController.add(ParamFetchProgress(
          received: _params.length, total: expectedCount, done: true,
        ));
        if (!completer.isCompleted) completer.complete(Map.from(_params));
      }
    }

    _sub = _mavlink.messagesOf<ParamValueMessage>().listen((msg) {
      expectedCount = msg.paramCount;
      _params[msg.paramId] = Parameter(
        id: msg.paramId,
        value: msg.paramValue,
        type: msg.paramType,
        index: msg.paramIndex,
      );

      _progressController.add(ParamFetchProgress(
        received: _params.length, total: expectedCount,
      ));

      // Reset gap timer — if no new params for 2s, assume done
      gapTimer?.cancel();
      gapTimer = Timer(const Duration(seconds: 2), () {
        cleanup();
        _progressController.add(ParamFetchProgress(
          received: _params.length, total: expectedCount, done: true,
        ));
        if (!completer.isCompleted) completer.complete(Map.from(_params));
      });

      checkComplete();
    });

    // Send request
    final frame = _mavlink.frameBuilder.buildParamRequestList(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
    );
    await _mavlink.sendRaw(frame);

    // Absolute timeout
    timeoutTimer = Timer(timeout, () {
      cleanup();
      if (!completer.isCompleted) {
        if (_params.isEmpty) {
          _progressController.add(const ParamFetchProgress(
            done: true, error: 'Timeout: no parameters received',
          ));
          completer.completeError(
            ParameterException('Timeout: no parameters received'),
          );
        } else {
          // Partial — return what we got
          _progressController.add(ParamFetchProgress(
            received: _params.length, total: expectedCount, done: true,
          ));
          completer.complete(Map.from(_params));
        }
      }
    });

    return completer.future;
  }

  /// Set a single parameter on the vehicle.
  /// Returns the confirmed value (or throws on timeout).
  Future<double> setParam({
    required int targetSystem,
    required int targetComponent,
    required String paramId,
    required double value,
    int paramType = 9,
    Duration timeout = const Duration(seconds: 3),
    int maxRetries = 3,
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      final frame = _mavlink.frameBuilder.buildParamSet(
        targetSystem: targetSystem,
        targetComponent: targetComponent,
        paramId: paramId,
        paramValue: value,
        paramType: paramType,
      );
      await _mavlink.sendRaw(frame);

      try {
        final echo = await _mavlink.messagesOf<ParamValueMessage>()
            .where((msg) => msg.paramId == paramId)
            .first
            .timeout(timeout);

        // Update local cache
        if (_params.containsKey(paramId)) {
          _params[paramId]!.value = echo.paramValue;
        }
        return echo.paramValue;
      } on TimeoutException {
        if (attempt >= maxRetries) {
          throw ParameterException('Timeout setting $paramId after $maxRetries retries');
        }
      }
    }
    throw ParameterException('Failed to set $paramId');
  }

  /// Export parameters to Mission Planner .param format.
  /// Format: PARAM_NAME,VALUE
  String exportToParamFile() {
    final sorted = _params.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return sorted.map((p) => '${p.id},${p.value}').join('\n');
  }

  /// Import parameters from a .param file.
  /// Returns list of (name, value) pairs.
  static List<(String, double)> parseParamFile(String content) {
    final results = <(String, double)>[];
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final parts = trimmed.split(',');
      if (parts.length >= 2) {
        final name = parts[0].trim();
        final value = double.tryParse(parts[1].trim());
        if (name.isNotEmpty && value != null) {
          results.add((name, value));
        }
      }
    }
    return results;
  }

  /// Save parameters to a file.
  Future<void> saveToFile(String path) async {
    await File(path).writeAsString(exportToParamFile());
  }

  /// Load parameters from a file and return the parsed entries.
  static Future<List<(String, double)>> loadFromFile(String path) async {
    final content = await File(path).readAsString();
    return parseParamFile(content);
  }

  /// Get all unique group prefixes.
  List<String> get groups {
    final g = _params.values.map((p) => p.group).toSet().toList()..sort();
    return g;
  }

  void cancel() {
    _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    cancel();
    _progressController.close();
  }
}

class ParameterException implements Exception {
  ParameterException(this.message);
  final String message;

  @override
  String toString() => 'ParameterException: $message';
}
