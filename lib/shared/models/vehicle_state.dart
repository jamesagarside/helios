import 'package:equatable/equatable.dart';

/// Vehicle type enumeration from MAVLink MAV_TYPE.
enum VehicleType {
  unknown,
  fixedWing,
  quadrotor,
  vtol,
  helicopter,
  rover,
  boat,
}

/// Autopilot firmware type.
enum AutopilotType { unknown, ardupilot, px4 }

/// GPS fix quality.
enum GpsFix { none, noFix, fix2d, fix3d, dgps, rtkFloat, rtkFixed }

/// Flight mode — generic wrapper, actual mode names depend on autopilot.
class FlightMode extends Equatable {
  const FlightMode(this.name, this.number, {this.category = 'unknown'});

  static const unknown = FlightMode('UNKNOWN', -1);

  final String name;
  final int number;
  final String category;

  @override
  List<Object?> get props => [name, number];
}

/// MAVLink link quality state.
enum LinkState { disconnected, connected, degraded, lost }

/// Transport connection state.
enum TransportState { disconnected, connecting, connected, error }

/// Immutable vehicle state — updated from MAVLink messages.
class VehicleState extends Equatable {
  const VehicleState({
    this.systemId = 0,
    this.componentId = 0,
    this.vehicleType = VehicleType.unknown,
    this.autopilotType = AutopilotType.unknown,
    this.firmwareVersion = '',
    // Attitude
    this.roll = 0.0,
    this.pitch = 0.0,
    this.yaw = 0.0,
    this.rollSpeed = 0.0,
    this.pitchSpeed = 0.0,
    this.yawSpeed = 0.0,
    // Position
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.altitudeMsl = 0.0,
    this.altitudeRel = 0.0,
    this.gpsFix = GpsFix.none,
    this.satellites = 0,
    this.hdop = 99.99,
    // Speed
    this.airspeed = 0.0,
    this.groundspeed = 0.0,
    this.heading = 0,
    this.climbRate = 0.0,
    this.throttle = 0,
    // Battery
    this.batteryVoltage = 0.0,
    this.batteryCurrent = 0.0,
    this.batteryRemaining = -1,
    this.batteryConsumed = 0.0,
    // Status
    this.flightMode = FlightMode.unknown,
    this.armed = false,
    this.lastHeartbeat,
    this.rssi = 0,
  });

  // Identity
  final int systemId;
  final int componentId;
  final VehicleType vehicleType;
  final AutopilotType autopilotType;
  final String firmwareVersion;

  // Attitude (radians)
  final double roll;
  final double pitch;
  final double yaw;
  final double rollSpeed;
  final double pitchSpeed;
  final double yawSpeed;

  // Position
  final double latitude;
  final double longitude;
  final double altitudeMsl;
  final double altitudeRel;
  final GpsFix gpsFix;
  final int satellites;
  final double hdop;

  // Speed
  final double airspeed;
  final double groundspeed;
  final int heading;
  final double climbRate;
  final int throttle;

  // Battery
  final double batteryVoltage;
  final double batteryCurrent;
  final int batteryRemaining;
  final double batteryConsumed;

  // Status
  final FlightMode flightMode;
  final bool armed;
  final DateTime? lastHeartbeat;
  final int rssi;

  /// Convenience — whether we have a valid GPS position.
  bool get hasPosition => latitude != 0.0 || longitude != 0.0;

  /// Create a copy with modified fields.
  VehicleState copyWith({
    int? systemId,
    int? componentId,
    VehicleType? vehicleType,
    AutopilotType? autopilotType,
    String? firmwareVersion,
    double? roll,
    double? pitch,
    double? yaw,
    double? rollSpeed,
    double? pitchSpeed,
    double? yawSpeed,
    double? latitude,
    double? longitude,
    double? altitudeMsl,
    double? altitudeRel,
    GpsFix? gpsFix,
    int? satellites,
    double? hdop,
    double? airspeed,
    double? groundspeed,
    int? heading,
    double? climbRate,
    int? throttle,
    double? batteryVoltage,
    double? batteryCurrent,
    int? batteryRemaining,
    double? batteryConsumed,
    FlightMode? flightMode,
    bool? armed,
    DateTime? lastHeartbeat,
    int? rssi,
  }) {
    return VehicleState(
      systemId: systemId ?? this.systemId,
      componentId: componentId ?? this.componentId,
      vehicleType: vehicleType ?? this.vehicleType,
      autopilotType: autopilotType ?? this.autopilotType,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      roll: roll ?? this.roll,
      pitch: pitch ?? this.pitch,
      yaw: yaw ?? this.yaw,
      rollSpeed: rollSpeed ?? this.rollSpeed,
      pitchSpeed: pitchSpeed ?? this.pitchSpeed,
      yawSpeed: yawSpeed ?? this.yawSpeed,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitudeMsl: altitudeMsl ?? this.altitudeMsl,
      altitudeRel: altitudeRel ?? this.altitudeRel,
      gpsFix: gpsFix ?? this.gpsFix,
      satellites: satellites ?? this.satellites,
      hdop: hdop ?? this.hdop,
      airspeed: airspeed ?? this.airspeed,
      groundspeed: groundspeed ?? this.groundspeed,
      heading: heading ?? this.heading,
      climbRate: climbRate ?? this.climbRate,
      throttle: throttle ?? this.throttle,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      batteryCurrent: batteryCurrent ?? this.batteryCurrent,
      batteryRemaining: batteryRemaining ?? this.batteryRemaining,
      batteryConsumed: batteryConsumed ?? this.batteryConsumed,
      flightMode: flightMode ?? this.flightMode,
      armed: armed ?? this.armed,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
      rssi: rssi ?? this.rssi,
    );
  }

  @override
  List<Object?> get props => [
        systemId, componentId, vehicleType, autopilotType, firmwareVersion,
        roll, pitch, yaw, rollSpeed, pitchSpeed, yawSpeed,
        latitude, longitude, altitudeMsl, altitudeRel, gpsFix, satellites, hdop,
        airspeed, groundspeed, heading, climbRate, throttle,
        batteryVoltage, batteryCurrent, batteryRemaining, batteryConsumed,
        flightMode, armed, lastHeartbeat, rssi,
      ];
}
