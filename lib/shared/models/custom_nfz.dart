import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// A user-drawn no-fly zone stored locally on-device.
@immutable
class CustomNfz {
  const CustomNfz({
    required this.id,
    required this.name,
    required this.polygon,
    this.colour = 'orange',
  });

  factory CustomNfz.fromJson(Map<String, dynamic> json) {
    final rawPolygon = json['polygon'] as List<dynamic>? ?? [];
    final polygon = rawPolygon
        .cast<Map<String, dynamic>>()
        .map((p) => LatLng(
              (p['lat'] as num).toDouble(),
              (p['lon'] as num).toDouble(),
            ))
        .toList();
    return CustomNfz(
      id: json['id'] as String,
      name: json['name'] as String,
      polygon: polygon,
      colour: json['colour'] as String? ?? 'orange',
    );
  }

  final String id;
  final String name;
  final List<LatLng> polygon;

  /// One of 'red', 'orange', 'yellow'.
  final String colour;

  CustomNfz copyWith({
    String? id,
    String? name,
    List<LatLng>? polygon,
    String? colour,
  }) =>
      CustomNfz(
        id: id ?? this.id,
        name: name ?? this.name,
        polygon: polygon ?? this.polygon,
        colour: colour ?? this.colour,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colour': colour,
        'polygon': polygon
            .map((p) => {'lat': p.latitude, 'lon': p.longitude})
            .toList(),
      };

  @override
  bool operator ==(Object other) =>
      other is CustomNfz &&
      other.id == id &&
      other.name == name &&
      other.colour == colour &&
      _polygonEquals(other.polygon, polygon);

  @override
  int get hashCode => Object.hash(id, name, colour, Object.hashAll(polygon));

  static bool _polygonEquals(List<LatLng> a, List<LatLng> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude) {
        return false;
      }
    }
    return true;
  }
}
