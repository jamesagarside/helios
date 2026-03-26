import 'package:equatable/equatable.dart';
import 'package:dart_mavlink/dart_mavlink.dart';
import 'mission_item.dart';

/// Fence zone type.
enum FenceZoneType { inclusion, exclusion }

/// Fence shape.
enum FenceShape { polygon, circle }

/// MAV_CMD values for fence items.
abstract final class FenceCmd {
  static const int fenceReturnPoint = 5000;
  static const int fencePolygonVertexInclusion = 5001;
  static const int fencePolygonVertexExclusion = 5002;
  static const int fenceCircleInclusion = 5003;
  static const int fenceCircleExclusion = 5004;
}

/// A single fence zone (polygon or circle).
class FenceZone extends Equatable {
  const FenceZone({
    required this.type,
    required this.shape,
    this.vertices = const [],
    this.radius = 0,
    this.centerLat = 0,
    this.centerLon = 0,
  });

  final FenceZoneType type;
  final FenceShape shape;
  final List<({double lat, double lon})> vertices; // polygon vertices
  final double radius; // circle radius in metres
  final double centerLat; // circle center
  final double centerLon;

  /// Convert to mission items for upload.
  List<MissionItem> toMissionItems(int startSeq) {
    if (shape == FenceShape.circle) {
      final cmd = type == FenceZoneType.inclusion
          ? FenceCmd.fenceCircleInclusion
          : FenceCmd.fenceCircleExclusion;
      return [
        MissionItem(
          seq: startSeq,
          command: cmd,
          frame: MavFrame.global,
          param1: radius,
          latitude: centerLat,
          longitude: centerLon,
        ),
      ];
    }

    // Polygon
    final cmd = type == FenceZoneType.inclusion
        ? FenceCmd.fencePolygonVertexInclusion
        : FenceCmd.fencePolygonVertexExclusion;
    return vertices.asMap().entries.map((e) {
      return MissionItem(
        seq: startSeq + e.key,
        command: cmd,
        frame: MavFrame.global,
        param1: vertices.length.toDouble(), // vertex count in param1
        latitude: e.value.lat,
        longitude: e.value.lon,
      );
    }).toList();
  }

  /// Parse fence items from downloaded mission items.
  static List<FenceZone> fromMissionItems(List<MissionItem> items) {
    final zones = <FenceZone>[];
    var i = 0;

    while (i < items.length) {
      final item = items[i];
      switch (item.command) {
        case FenceCmd.fenceCircleInclusion:
          zones.add(FenceZone(
            type: FenceZoneType.inclusion,
            shape: FenceShape.circle,
            radius: item.param1,
            centerLat: item.latitude,
            centerLon: item.longitude,
          ));
          i++;
        case FenceCmd.fenceCircleExclusion:
          zones.add(FenceZone(
            type: FenceZoneType.exclusion,
            shape: FenceShape.circle,
            radius: item.param1,
            centerLat: item.latitude,
            centerLon: item.longitude,
          ));
          i++;
        case FenceCmd.fencePolygonVertexInclusion:
        case FenceCmd.fencePolygonVertexExclusion:
          final vertexCount = item.param1.toInt();
          final isInclusion = item.command == FenceCmd.fencePolygonVertexInclusion;
          final verts = <({double lat, double lon})>[];
          for (var v = 0; v < vertexCount && (i + v) < items.length; v++) {
            final vi = items[i + v];
            verts.add((lat: vi.latitude, lon: vi.longitude));
          }
          zones.add(FenceZone(
            type: isInclusion ? FenceZoneType.inclusion : FenceZoneType.exclusion,
            shape: FenceShape.polygon,
            vertices: verts,
          ));
          i += vertexCount;
        default:
          i++; // skip return point or unknown
      }
    }
    return zones;
  }

  @override
  List<Object?> get props => [type, shape, vertices, radius, centerLat, centerLon];
}
