import 'package:flutter/foundation.dart';

/// Metadata for a single ArduPilot parameter from apm.pdef.xml.
@immutable
class ParamMeta {
  const ParamMeta({
    required this.name,
    this.displayName = '',
    this.description = '',
    this.group = '',
    this.units = '',
    this.rangeMin,
    this.rangeMax,
    this.increment,
    this.values = const {},
    this.bitmaskBits = const {},
    this.userLevel = 'Advanced',
  });

  factory ParamMeta.fromJson(Map<String, dynamic> json) {
    Map<int, String> parseMap(dynamic raw) {
      if (raw == null) return const {};
      final m = raw as Map<String, dynamic>;
      return {
        for (final e in m.entries) int.parse(e.key): e.value as String,
      };
    }

    return ParamMeta(
      name: json['name'] as String,
      displayName: (json['displayName'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      group: (json['group'] as String?) ?? '',
      units: (json['units'] as String?) ?? '',
      rangeMin: (json['rangeMin'] as num?)?.toDouble(),
      rangeMax: (json['rangeMax'] as num?)?.toDouble(),
      increment: (json['increment'] as num?)?.toDouble(),
      values: parseMap(json['values']),
      bitmaskBits: parseMap(json['bitmaskBits']),
      userLevel: (json['userLevel'] as String?) ?? 'Advanced',
    );
  }

  // ── Fields ──────────────────────────────────────────────────────────────────

  /// The canonical parameter name (e.g. "ARMING_CHECK").
  final String name;

  /// Human-readable display name from humanName attribute.
  final String displayName;

  /// Documentation string from documentation attribute.
  final String description;

  /// Logical group (e.g. "Arming" or "ARMING" from prefix).
  final String group;

  /// Physical units (e.g. "m/s", "deg").
  final String units;

  /// Minimum allowed value, if a Range field was present.
  final double? rangeMin;

  /// Maximum allowed value, if a Range field was present.
  final double? rangeMax;

  /// Recommended step size, if an Increment field was present.
  final double? increment;

  /// Enum mapping: integer code to label, populated from values elements.
  final Map<int, String> values;

  /// Bitmask mapping: bit index to label, populated from a Bitmask field.
  final Map<int, String> bitmaskBits;

  /// ArduPilot user level: 'Standard' or 'Advanced'.
  final String userLevel;

  // ── Derived ─────────────────────────────────────────────────────────────────

  /// True when this parameter has discrete enum choices.
  bool get hasEnumValues => values.isNotEmpty;

  /// True when this parameter is a bitmask (multiple bits are independently
  /// meaningful).
  bool get isBitmask => bitmaskBits.isNotEmpty;

  /// True when ArduPilot marks this as a Standard (beginner-friendly) param.
  bool get isStandard => userLevel == 'Standard';

  // ── Serialisation ────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'name': name,
        'displayName': displayName,
        'description': description,
        'group': group,
        'units': units,
        if (rangeMin != null) 'rangeMin': rangeMin,
        if (rangeMax != null) 'rangeMax': rangeMax,
        if (increment != null) 'increment': increment,
        'values': {for (final e in values.entries) '${e.key}': e.value},
        'bitmaskBits': {
          for (final e in bitmaskBits.entries) '${e.key}': e.value
        },
        'userLevel': userLevel,
      };
}
