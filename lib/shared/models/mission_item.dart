import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:dart_mavlink/dart_mavlink.dart';

/// A single mission waypoint/command.
class MissionItem extends Equatable {
  const MissionItem({
    required this.seq,
    this.frame = MavFrame.globalRelativeAlt,
    this.command = MavCmd.navWaypoint,
    this.current = 0,
    this.autocontinue = 1,
    this.param1 = 0.0,
    this.param2 = 0.0,
    this.param3 = 0.0,
    this.param4 = 0.0,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.altitude = 50.0,
  });

  final int seq;
  final int frame;
  final int command;
  final int current;
  final int autocontinue;
  final double param1;   // Hold time (s) for NAV_WAYPOINT
  final double param2;   // Acceptance radius (m)
  final double param3;   // Pass-through (0) or orbit (>0 CW, <0 CCW)
  final double param4;   // Desired yaw angle (deg)
  final double latitude;
  final double longitude;
  final double altitude;  // Relative altitude (m)

  /// Latitude in degE7 for MAVLink protocol.
  int get latE7 => (latitude * 1e7).round();

  /// Longitude in degE7 for MAVLink protocol.
  int get lonE7 => (longitude * 1e7).round();

  /// Human-readable command label.
  String get commandLabel => switch (command) {
    MavCmd.navWaypoint => 'Waypoint',
    MavCmd.navLoiterUnlim => 'Loiter',
    MavCmd.navLoiterTurns => 'Loiter Turns',
    MavCmd.navLoiterTime => 'Loiter Time',
    MavCmd.navReturnToLaunch => 'RTL',
    MavCmd.navLand => 'Land',
    MavCmd.navTakeoff => 'Takeoff',
    MavCmd.navLoiterToAlt => 'Loiter to Alt',
    MavCmd.doChangeSpeed => 'Change Speed',
    MavCmd.doSetHome => 'Set Home',
    MavCmd.doJump => 'Jump',
    _ => 'CMD $command',
  };

  /// Whether this is a navigation command (has lat/lon).
  bool get isNavCommand => command >= 16 && command <= 95;

  /// Create from a decoded MISSION_ITEM_INT message.
  factory MissionItem.fromMessage(MissionItemIntMessage msg) {
    return MissionItem(
      seq: msg.seq,
      frame: msg.frame,
      command: msg.command,
      current: msg.current,
      autocontinue: msg.autocontinue,
      param1: msg.param1,
      param2: msg.param2,
      param3: msg.param3,
      param4: msg.param4,
      latitude: msg.latDeg,
      longitude: msg.lonDeg,
      altitude: msg.z,
    );
  }

  MissionItem copyWith({
    int? seq,
    int? frame,
    int? command,
    int? current,
    int? autocontinue,
    double? param1,
    double? param2,
    double? param3,
    double? param4,
    double? latitude,
    double? longitude,
    double? altitude,
  }) {
    return MissionItem(
      seq: seq ?? this.seq,
      frame: frame ?? this.frame,
      command: command ?? this.command,
      current: current ?? this.current,
      autocontinue: autocontinue ?? this.autocontinue,
      param1: param1 ?? this.param1,
      param2: param2 ?? this.param2,
      param3: param3 ?? this.param3,
      param4: param4 ?? this.param4,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
    );
  }

  @override
  List<Object?> get props => [
        seq, frame, command, current, autocontinue,
        param1, param2, param3, param4,
        latitude, longitude, altitude,
      ];
}

/// Mission transfer state machine.
enum MissionTransferState {
  idle,
  downloading,
  uploading,
  complete,
  error,
}

/// Immutable mission state — the current mission on the vehicle.
class MissionState extends Equatable {
  const MissionState({
    this.items = const [],
    this.transferState = MissionTransferState.idle,
    this.currentWaypoint = 0,
    this.transferProgress = 0.0,
    this.errorMessage,
  });

  final List<MissionItem> items;
  final MissionTransferState transferState;
  final int currentWaypoint;
  final double transferProgress; // 0.0 - 1.0
  final String? errorMessage;

  int get waypointCount => items.length;

  bool get isEmpty => items.isEmpty;
  bool get isTransferring =>
      transferState == MissionTransferState.downloading ||
      transferState == MissionTransferState.uploading;

  /// Total distance in metres between navigation waypoints.
  double get totalDistanceMetres {
    double total = 0;
    final navItems = items.where((i) => i.isNavCommand).toList();
    for (var i = 1; i < navItems.length; i++) {
      total += _haversineMetres(
        navItems[i - 1].latitude,
        navItems[i - 1].longitude,
        navItems[i].latitude,
        navItems[i].longitude,
      );
    }
    return total;
  }

  MissionState copyWith({
    List<MissionItem>? items,
    MissionTransferState? transferState,
    int? currentWaypoint,
    double? transferProgress,
    String? errorMessage,
  }) {
    return MissionState(
      items: items ?? this.items,
      transferState: transferState ?? this.transferState,
      currentWaypoint: currentWaypoint ?? this.currentWaypoint,
      transferProgress: transferProgress ?? this.transferProgress,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        items, transferState, currentWaypoint,
        transferProgress, errorMessage,
      ];
}

/// Haversine formula for distance between two GPS coordinates.
double _haversineMetres(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
      sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return r * c;
}
