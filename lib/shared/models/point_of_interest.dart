import 'package:flutter/foundation.dart';

/// Colour category for a point of interest.
enum PoiColour { red, orange, yellow, green, blue, purple }

/// Icon style for a point of interest.
enum PoiIcon { pin, star, camera, target, home, flag }

/// An immutable user-defined point of interest on the map.
///
/// Platform: All
@immutable
class PointOfInterest {
  const PointOfInterest({
    required this.id,
    required this.name,
    this.notes = '',
    required this.latitude,
    required this.longitude,
    this.altitudeM = 0.0,
    this.colour = PoiColour.blue,
    this.icon = PoiIcon.pin,
  });

  /// Unique identifier (microseconds since epoch as string).
  final String id;

  /// Display name shown on the map and in detail panels.
  final String name;

  /// Optional freeform notes for this point.
  final String notes;

  final double latitude;
  final double longitude;

  /// Altitude above ground level in metres (default 0).
  final double altitudeM;

  /// Colour category for map rendering.
  final PoiColour colour;

  /// Icon style for map rendering.
  final PoiIcon icon;

  // ─── Serialisation ────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notes': notes,
        'lat': latitude,
        'lon': longitude,
        'altM': altitudeM,
        'colour': colour.name,
        'icon': icon.name,
      };

  factory PointOfInterest.fromJson(Map<String, dynamic> json) {
    return PointOfInterest(
      id: json['id'] as String,
      name: json['name'] as String,
      notes: (json['notes'] as String?) ?? '',
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lon'] as num).toDouble(),
      altitudeM: (json['altM'] as num?)?.toDouble() ?? 0.0,
      colour: _parseColour(json['colour'] as String?),
      icon: _parseIcon(json['icon'] as String?),
    );
  }

  static PoiColour _parseColour(String? value) {
    if (value == null) return PoiColour.blue;
    return PoiColour.values.firstWhere(
      (c) => c.name == value,
      orElse: () => PoiColour.blue,
    );
  }

  static PoiIcon _parseIcon(String? value) {
    if (value == null) return PoiIcon.pin;
    return PoiIcon.values.firstWhere(
      (i) => i.name == value,
      orElse: () => PoiIcon.pin,
    );
  }

  // ─── copyWith ─────────────────────────────────────────────────────────────

  PointOfInterest copyWith({
    String? id,
    String? name,
    String? notes,
    double? latitude,
    double? longitude,
    double? altitudeM,
    PoiColour? colour,
    PoiIcon? icon,
  }) {
    return PointOfInterest(
      id: id ?? this.id,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitudeM: altitudeM ?? this.altitudeM,
      colour: colour ?? this.colour,
      icon: icon ?? this.icon,
    );
  }

  // ─── Equality ─────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PointOfInterest &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          notes == other.notes &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          altitudeM == other.altitudeM &&
          colour == other.colour &&
          icon == other.icon;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        notes,
        latitude,
        longitude,
        altitudeM,
        colour,
        icon,
      );
}
