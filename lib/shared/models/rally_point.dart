import 'package:equatable/equatable.dart';
import 'package:dart_mavlink/dart_mavlink.dart';
import 'mission_item.dart';

/// A rally point (alternate landing site).
class RallyPoint extends Equatable {
  const RallyPoint({
    required this.seq,
    required this.latitude,
    required this.longitude,
    this.altitude = 50.0,
  });

  final int seq;
  final double latitude;
  final double longitude;
  final double altitude;

  /// Convert to a mission item for upload via rally protocol.
  MissionItem toMissionItem() => MissionItem(
    seq: seq,
    command: MavCmd.navLoiterUnlim, // Rally uses NAV_LOITER_UNLIM
    frame: MavFrame.globalRelativeAlt,
    latitude: latitude,
    longitude: longitude,
    altitude: altitude,
  );

  /// Create from a downloaded mission item.
  factory RallyPoint.fromMissionItem(MissionItem item) => RallyPoint(
    seq: item.seq,
    latitude: item.latitude,
    longitude: item.longitude,
    altitude: item.altitude,
  );

  RallyPoint copyWith({int? seq, double? latitude, double? longitude, double? altitude}) =>
    RallyPoint(
      seq: seq ?? this.seq,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
    );

  @override
  List<Object?> get props => [seq, latitude, longitude, altitude];
}
