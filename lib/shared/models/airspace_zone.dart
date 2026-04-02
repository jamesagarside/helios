import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

enum AirspaceType {
  prohibited,   // P - no fly
  restricted,   // R - restricted
  danger,       // D - danger area
  ctr,          // CTR / control zone
  tma,          // TMA / terminal area
  classA,
  classB,
  classC,
  classD,
  classE,
  classF,
  classG,
  other,
}

/// A no-fly or restricted airspace zone loaded from a GeoJSON file.
class AirspaceZone extends Equatable {
  const AirspaceZone({
    required this.id,
    required this.name,
    required this.type,
    required this.polygon,
    this.lowerLimitFt = 0,
    this.upperLimitFt = 99999,
    this.description = '',
  });

  final String id;
  final String name;
  final AirspaceType type;
  final List<LatLng> polygon;
  final int lowerLimitFt;
  final int upperLimitFt;
  final String description;

  bool get isProhibited =>
      type == AirspaceType.prohibited || type == AirspaceType.restricted;

  /// Returns true if [point] is inside this zone using the ray-casting algorithm.
  bool contains(LatLng point) {
    final lat = point.latitude;
    final lon = point.longitude;
    final n = polygon.length;
    if (n < 3) return false;

    var inside = false;
    var j = n - 1;
    for (var i = 0; i < n; i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;
      if (((yi > lat) != (yj > lat)) &&
          (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  @override
  List<Object?> get props => [id, name, type, polygon, lowerLimitFt, upperLimitFt];
}
