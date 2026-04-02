import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

/// A saved home/launch location for quick map navigation.
///
/// Platform: All
class HomeLocation extends Equatable {
  const HomeLocation({
    required this.name,
    required this.position,
    this.altitude = 0,
    this.isDefault = false,
    this.notes = '',
  });

  factory HomeLocation.fromJson(Map<String, dynamic> json) {
    return HomeLocation(
      name: json['name'] as String,
      position: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lon'] as num).toDouble(),
      ),
      altitude: (json['alt'] as num?)?.toDouble() ?? 0,
      isDefault: json['isDefault'] as bool? ?? false,
      notes: (json['notes'] as String?) ?? '',
    );
  }

  /// Display name for this location.
  final String name;

  /// Geographic coordinates.
  final LatLng position;

  /// Altitude in metres above mean sea level.
  final double altitude;

  /// Whether this is the default home location shown on map startup.
  final bool isDefault;

  /// Optional freeform notes.
  final String notes;

  // ─── Serialisation ──────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'name': name,
        'lat': position.latitude,
        'lon': position.longitude,
        'alt': altitude,
        'isDefault': isDefault,
        'notes': notes,
      };

  // ─── copyWith ───────────────────────────────────────────────────────────

  HomeLocation copyWith({
    String? name,
    LatLng? position,
    double? altitude,
    bool? isDefault,
    String? notes,
  }) {
    return HomeLocation(
      name: name ?? this.name,
      position: position ?? this.position,
      altitude: altitude ?? this.altitude,
      isDefault: isDefault ?? this.isDefault,
      notes: notes ?? this.notes,
    );
  }

  @override
  String toString() =>
      'HomeLocation($name, ${position.latitude.toStringAsFixed(6)}, '
      '${position.longitude.toStringAsFixed(6)}, alt=$altitude)';

  @override
  List<Object?> get props => [name, position, altitude, isDefault, notes];
}
