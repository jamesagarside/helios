import '../params/parameter_service.dart';

/// Difference between two parameter sets.
class ParamDiff {
  const ParamDiff({
    this.changed = const {},
    this.added = const {},
    this.removed = const {},
  });

  /// Parameters present in both sets but with different values.
  /// Key = param name, value = (old, new).
  final Map<String, (double, double)> changed;

  /// Parameters only in the new set.
  final Map<String, double> added;

  /// Parameters only in the old set.
  final Map<String, double> removed;

  bool get isEmpty => changed.isEmpty && added.isEmpty && removed.isEmpty;
  int get totalChanges => changed.length + added.length + removed.length;
}

/// Service for saving, loading, and comparing parameter files.
///
/// Supports:
/// - ArduPilot `.param` format: `PARAM_NAME,VALUE`
/// - Mission Planner `.param` format (same as above)
/// - QGC `.params` format: `COMPONENT_ID SYSTEM_ID PARAM_NAME VALUE TYPE`
class ParamFileService {
  // ─── Save ────────────────────────────────────────────────────────────────

  /// Save parameters to ArduPilot .param format.
  ///
  /// Format: `PARAM_NAME,VALUE` (one per line).
  String saveArduPilot(Map<String, Parameter> params) {
    final buf = StringBuffer();
    final sorted = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in sorted) {
      buf.writeln('${entry.key},${_formatValue(entry.value)}');
    }
    return buf.toString();
  }

  /// Save parameters to QGC .params format.
  ///
  /// Format: `COMPONENT_ID SYSTEM_ID PARAM_NAME VALUE PARAM_TYPE`
  String saveQgc(
    Map<String, Parameter> params, {
    int systemId = 1,
    int componentId = 1,
  }) {
    final buf = StringBuffer();
    buf.writeln('# Helios GCS Parameters');
    buf.writeln('# Vehicle: $systemId Component: $componentId');
    buf.writeln();
    final sorted = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in sorted) {
      buf.writeln(
        '$componentId\t$systemId\t${entry.key}\t'
        '${_formatValue(entry.value)}\t${entry.value.type}',
      );
    }
    return buf.toString();
  }

  /// Save only parameters that differ from their default values.
  String saveModifiedOnly(Map<String, Parameter> params) {
    final modified = Map.fromEntries(
      params.entries.where((e) {
        final def = e.value.defaultValue;
        return def == null || (e.value.value - def).abs() > 1e-7;
      }),
    );
    return saveArduPilot(modified);
  }

  // ─── Load ────────────────────────────────────────────────────────────────

  /// Load parameters from a file string. Auto-detects format.
  Map<String, double> load(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty) return {};

    // Check for QGC format by looking for tab-separated lines with 5 fields
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length >= 5 && int.tryParse(parts[0]) != null) {
        return _loadQgc(content);
      }
      break;
    }

    return _loadArduPilot(content);
  }

  /// Parse ArduPilot/Mission Planner .param format.
  Map<String, double> _loadArduPilot(String content) {
    final result = <String, double>{};
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      // Format: PARAM_NAME,VALUE or PARAM_NAME VALUE
      final parts = trimmed.contains(',')
          ? trimmed.split(',')
          : trimmed.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;

      final name = parts[0].trim();
      final value = double.tryParse(parts[1].trim());
      if (name.isNotEmpty && value != null) {
        result[name] = value;
      }
    }
    return result;
  }

  /// Parse QGC .params format.
  Map<String, double> _loadQgc(String content) {
    final result = <String, double>{};
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 4) continue;

      // Format: COMPONENT_ID SYSTEM_ID PARAM_NAME VALUE [TYPE]
      final name = parts[2].trim();
      final value = double.tryParse(parts[3].trim());
      if (name.isNotEmpty && value != null) {
        result[name] = value;
      }
    }
    return result;
  }

  // ─── Compare ─────────────────────────────────────────────────────────────

  /// Compare two parameter sets and return the differences.
  ///
  /// [oldParams] is the baseline (e.g. current vehicle params).
  /// [newParams] is the comparison set (e.g. loaded from file).
  ParamDiff compare(
      Map<String, double> oldParams, Map<String, double> newParams) {
    final changed = <String, (double, double)>{};
    final added = <String, double>{};
    final removed = <String, double>{};

    for (final entry in newParams.entries) {
      final oldValue = oldParams[entry.key];
      if (oldValue == null) {
        added[entry.key] = entry.value;
      } else if ((oldValue - entry.value).abs() > 1e-7) {
        changed[entry.key] = (oldValue, entry.value);
      }
    }

    for (final entry in oldParams.entries) {
      if (!newParams.containsKey(entry.key)) {
        removed[entry.key] = entry.value;
      }
    }

    return ParamDiff(changed: changed, added: added, removed: removed);
  }

  /// Compare a parameter cache against loaded values.
  ParamDiff compareWithCache(
    Map<String, Parameter> cache,
    Map<String, double> fileParams,
  ) {
    final cacheValues = cache.map((k, v) => MapEntry(k, v.value));
    return compare(cacheValues, fileParams);
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  String _formatValue(Parameter param) {
    if (param.isInteger) {
      return param.value.toInt().toString();
    }
    // Remove trailing zeros but keep at least one decimal place for floats
    final s = param.value.toStringAsFixed(6);
    final dot = s.indexOf('.');
    if (dot < 0) return s;
    var end = s.length;
    while (end > dot + 2 && s[end - 1] == '0') {
      end--;
    }
    return s.substring(0, end);
  }
}
