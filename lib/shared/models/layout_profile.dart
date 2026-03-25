import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../features/fly/widgets/chart_toolbar.dart';

/// Position and visibility config for a single widget on the Fly View.
@immutable
class WidgetConfig {
  const WidgetConfig({
    required this.x,
    required this.y,
    this.width,
    this.height,
    this.visible = true,
    this.minimised = false,
  });

  factory WidgetConfig.fromJson(Map<String, dynamic> json) {
    return WidgetConfig(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num?)?.toDouble(),
      height: (json['height'] as num?)?.toDouble(),
      visible: json['visible'] as bool? ?? true,
      minimised: json['minimised'] as bool? ?? false,
    );
  }

  final double x;
  final double y;
  final double? width;
  final double? height;
  final bool visible;
  final bool minimised;

  WidgetConfig copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    bool? visible,
    bool? minimised,
  }) {
    return WidgetConfig(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      visible: visible ?? this.visible,
      minimised: minimised ?? this.minimised,
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        'visible': visible,
        'minimised': minimised,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WidgetConfig &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height &&
          visible == other.visible &&
          minimised == other.minimised;

  @override
  int get hashCode => Object.hash(x, y, width, height, visible, minimised);
}

/// Vehicle type for default layout presets.
enum VehicleType {
  multirotor('Multirotor'),
  fixedWing('Fixed Wing'),
  vtol('VTOL');

  const VehicleType(this.label);
  final String label;
}

/// A named layout profile containing widget configs for the Fly View.
@immutable
class LayoutProfile {
  const LayoutProfile({
    required this.name,
    this.vehicleType = VehicleType.multirotor,
    this.charts = const {},
    this.pfd = const WidgetConfig(x: 16, y: -1, visible: true),
    this.telemetryStrip = const WidgetConfig(x: 0, y: 0, visible: true),
    this.video = const WidgetConfig(x: 16, y: 270, visible: false),
    this.isDefault = false,
  });

  factory LayoutProfile.fromJson(Map<String, dynamic> json) {
    return LayoutProfile(
      name: json['name'] as String,
      vehicleType: VehicleType.values.firstWhere(
        (v) => v.name == json['vehicleType'],
        orElse: () => VehicleType.multirotor,
      ),
      charts: (json['charts'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, WidgetConfig.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      pfd: json['pfd'] != null
          ? WidgetConfig.fromJson(json['pfd'] as Map<String, dynamic>)
          : const WidgetConfig(x: 16, y: -1, visible: true),
      telemetryStrip: json['telemetryStrip'] != null
          ? WidgetConfig.fromJson(json['telemetryStrip'] as Map<String, dynamic>)
          : const WidgetConfig(x: 0, y: 0, visible: true),
      video: json['video'] != null
          ? WidgetConfig.fromJson(json['video'] as Map<String, dynamic>)
          : const WidgetConfig(x: 16, y: 270, visible: false),
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  factory LayoutProfile.decode(String encoded) {
    return LayoutProfile.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
  }

  final String name;
  final VehicleType vehicleType;

  /// Chart widget configs keyed by ChartType name.
  final Map<String, WidgetConfig> charts;

  /// PFD overlay config. y == -1 means bottom-left (default).
  final WidgetConfig pfd;

  /// Telemetry strip sidebar config.
  final WidgetConfig telemetryStrip;

  /// Video PiP config.
  final WidgetConfig video;

  /// Whether this is a built-in default (cannot be deleted).
  final bool isDefault;

  /// Get active chart types (visible charts).
  Set<ChartType> get activeCharts {
    final active = <ChartType>{};
    for (final entry in charts.entries) {
      if (entry.value.visible) {
        final type = ChartType.values.where((t) => t.name == entry.key);
        if (type.isNotEmpty) active.add(type.first);
      }
    }
    return active;
  }

  LayoutProfile copyWith({
    String? name,
    VehicleType? vehicleType,
    Map<String, WidgetConfig>? charts,
    WidgetConfig? pfd,
    WidgetConfig? telemetryStrip,
    WidgetConfig? video,
    bool? isDefault,
  }) {
    return LayoutProfile(
      name: name ?? this.name,
      vehicleType: vehicleType ?? this.vehicleType,
      charts: charts ?? this.charts,
      pfd: pfd ?? this.pfd,
      telemetryStrip: telemetryStrip ?? this.telemetryStrip,
      video: video ?? this.video,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'vehicleType': vehicleType.name,
        'charts': charts.map((k, v) => MapEntry(k, v.toJson())),
        'pfd': pfd.toJson(),
        'telemetryStrip': telemetryStrip.toJson(),
        'video': video.toJson(),
        'isDefault': isDefault,
      };

  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutProfile &&
          name == other.name &&
          vehicleType == other.vehicleType;

  @override
  int get hashCode => Object.hash(name, vehicleType);
}

// ---------------------------------------------------------------------------
// Default profiles
// ---------------------------------------------------------------------------

/// Default multirotor profile — ALT + BAT charts, PFD bottom-left.
LayoutProfile defaultMultirotorProfile() {
  return LayoutProfile(
    name: 'Multirotor',
    vehicleType: VehicleType.multirotor,
    isDefault: true,
    charts: {
      ChartType.altitude.name: const WidgetConfig(x: 350, y: 50, visible: true),
      ChartType.battery.name: const WidgetConfig(x: 350, y: 210, visible: true),
    },
    pfd: const WidgetConfig(x: 16, y: -1, visible: true),
    telemetryStrip: const WidgetConfig(x: 0, y: 0, visible: true),
    video: const WidgetConfig(x: 16, y: 270, visible: false),
  );
}

/// Default fixed-wing profile — ALT + SPD + VS charts.
LayoutProfile defaultFixedWingProfile() {
  return LayoutProfile(
    name: 'Fixed Wing',
    vehicleType: VehicleType.fixedWing,
    isDefault: true,
    charts: {
      ChartType.altitude.name: const WidgetConfig(x: 350, y: 50, visible: true),
      ChartType.speed.name: const WidgetConfig(x: 350, y: 210, visible: true),
      ChartType.climbRate.name: const WidgetConfig(x: 350, y: 370, visible: true),
    },
    pfd: const WidgetConfig(x: 16, y: -1, visible: true),
    telemetryStrip: const WidgetConfig(x: 0, y: 0, visible: true),
    video: const WidgetConfig(x: 16, y: 270, visible: false),
  );
}

/// Default VTOL profile — ALT + SPD + ATT charts.
LayoutProfile defaultVtolProfile() {
  return LayoutProfile(
    name: 'VTOL',
    vehicleType: VehicleType.vtol,
    isDefault: true,
    charts: {
      ChartType.altitude.name: const WidgetConfig(x: 350, y: 50, visible: true),
      ChartType.speed.name: const WidgetConfig(x: 350, y: 210, visible: true),
      ChartType.attitude.name: const WidgetConfig(x: 350, y: 370, visible: true),
    },
    pfd: const WidgetConfig(x: 16, y: -1, visible: true),
    telemetryStrip: const WidgetConfig(x: 0, y: 0, visible: true),
    video: const WidgetConfig(x: 16, y: 270, visible: false),
  );
}
