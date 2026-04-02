import 'package:flutter/foundation.dart';

/// Configuration for a single telemetry tile in the fly-view panel.
@immutable
class TelemetryTileConfig {
  const TelemetryTileConfig({
    required this.fieldId,
    this.warnLow,
    this.warnHigh,
  });

  factory TelemetryTileConfig.fromJson(Map<String, dynamic> json) {
    return TelemetryTileConfig(
      fieldId: json['fieldId'] as String,
      warnLow: (json['warnLow'] as num?)?.toDouble(),
      warnHigh: (json['warnHigh'] as num?)?.toDouble(),
    );
  }

  /// Key into [TelemetryFieldRegistry.fields].
  final String fieldId;

  /// Optional threshold: tile highlights amber/red if value < warnLow.
  final double? warnLow;

  /// Optional threshold: tile highlights amber/red if value > warnHigh.
  final double? warnHigh;

  TelemetryTileConfig copyWith({
    String? fieldId,
    double? warnLow,
    double? warnHigh,
  }) {
    return TelemetryTileConfig(
      fieldId: fieldId ?? this.fieldId,
      warnLow: warnLow ?? this.warnLow,
      warnHigh: warnHigh ?? this.warnHigh,
    );
  }

  Map<String, dynamic> toJson() => {
        'fieldId': fieldId,
        if (warnLow != null) 'warnLow': warnLow,
        if (warnHigh != null) 'warnHigh': warnHigh,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TelemetryTileConfig &&
          fieldId == other.fieldId &&
          warnLow == other.warnLow &&
          warnHigh == other.warnHigh;

  @override
  int get hashCode => Object.hash(fieldId, warnLow, warnHigh);
}
