import 'dart:math' as math;

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
enum AutopilotType { unknown, ardupilot, px4, betaflight, inav }

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
    this.currentWaypoint = -1,
    this.ekfVelocityVar = 0.0,
    this.ekfPosHorizVar = 0.0,
    this.ekfPosVertVar = 0.0,
    this.ekfCompassVar = 0.0,
    this.ekfTerrainVar = 0.0,
    this.sensorPresent = 0,
    this.sensorEnabled = 0,
    this.sensorHealth = 0,
    // Firmware (AUTOPILOT_VERSION)
    this.firmwareVersionMajor = 0,
    this.firmwareVersionMinor = 0,
    this.firmwareVersionPatch = 0,
    this.boardVersion = 0,
    this.capabilities = 0,
    this.vehicleUid = 0,
    // Gimbal (MOUNT_STATUS)
    this.gimbalPitch = 0.0,
    this.gimbalYaw = 0.0,
    this.gimbalRoll = 0.0,
    this.hasGimbal = false,
    // Servo output channels (SERVO_OUTPUT_RAW — PWM µs, 0 = not used)
    this.servoOutputs = const [],
    // RC channels (RC_CHANNELS)
    this.rcChannels = const [],
    this.rcChannelCount = 0,
    // RC RSSI (0-254, 255 = invalid/not available)
    this.rcRssi = 255,
    // RC failsafe active
    this.rcFailsafe = false,
    // Home position (HOME_POSITION)
    this.homeLatitude = 0.0,
    this.homeLongitude = 0.0,
    this.homeAltitude = 0.0,
    // Wind (WIND msg_id=168)
    this.windSpeed = 0.0,
    this.windDirection = 0.0,
    this.windSpeedZ = 0.0,
    // Vibration (VIBRATION msg_id=241)
    this.vibrationX = 0.0,
    this.vibrationY = 0.0,
    this.vibrationZ = 0.0,
    this.clipping0 = 0,
    this.clipping1 = 0,
    this.clipping2 = 0,
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
  final int currentWaypoint; // -1 = no mission active

  // EKF status (variance: <0.5 good, 0.5-0.8 warn, >0.8 bad)
  final double ekfVelocityVar;
  final double ekfPosHorizVar;
  final double ekfPosVertVar;
  final double ekfCompassVar;
  final double ekfTerrainVar;
  final int sensorPresent; // SYS_STATUS onboardControlSensorsPresent bitmask
  final int sensorEnabled; // SYS_STATUS onboardControlSensorsEnabled bitmask
  final int sensorHealth; // SYS_STATUS onboardControlSensorsHealth bitmask

  // Firmware (AUTOPILOT_VERSION)
  final int firmwareVersionMajor;
  final int firmwareVersionMinor;
  final int firmwareVersionPatch;
  final int boardVersion;
  final int capabilities; // MAV_PROTOCOL_CAPABILITY bitmask
  final int vehicleUid;

  // Gimbal (MOUNT_STATUS)
  final double gimbalPitch; // degrees
  final double gimbalYaw; // degrees
  final double gimbalRoll; // degrees
  final bool hasGimbal;

  // Servo output channels (SERVO_OUTPUT_RAW — PWM µs, 0 = not used)
  final List<int> servoOutputs;

  // RC channels (RC_CHANNELS — PWM values 1000-2000, 0 = not available)
  final List<int> rcChannels;
  final int rcChannelCount;

  // RC RSSI (0-254, 255 = invalid/not available)
  final int rcRssi;

  // RC failsafe active
  final bool rcFailsafe;

  // Home position (HOME_POSITION msg_id=242)
  final double homeLatitude;
  final double homeLongitude;
  final double homeAltitude;

  // Wind (WIND msg_id=168)
  final double windSpeed;      // m/s horizontal
  final double windDirection;  // degrees, direction wind is coming from
  final double windSpeedZ;     // m/s vertical component

  // Vibration (VIBRATION msg_id=241)
  final double vibrationX;     // m/s/s
  final double vibrationY;     // m/s/s
  final double vibrationZ;     // m/s/s
  final int clipping0;         // accelerometer clipping count
  final int clipping1;
  final int clipping2;

  /// Formatted firmware version string (e.g. "4.5.1").
  String get firmwareVersionString {
    if (firmwareVersionMajor == 0 &&
        firmwareVersionMinor == 0 &&
        firmwareVersionPatch == 0) {
      return firmwareVersion.isNotEmpty ? firmwareVersion : '';
    }
    return '$firmwareVersionMajor.$firmwareVersionMinor.$firmwareVersionPatch';
  }

  /// EKF overall health: 0=good, 1=warning, 2=bad
  int get ekfHealth {
    final maxVar = [ekfVelocityVar, ekfPosHorizVar, ekfPosVertVar, ekfCompassVar]
        .reduce((a, b) => a > b ? a : b);
    if (maxVar > 0.8) return 2;
    if (maxVar > 0.5) return 1;
    return 0;
  }

  /// Convenience — whether we have a valid GPS position.
  bool get hasPosition => latitude != 0.0 || longitude != 0.0;

  /// Whether a home position has been set by the FC.
  bool get hasHome => homeLatitude != 0.0 || homeLongitude != 0.0;

  /// Whether a WIND message has been received with valid data.
  bool get hasWind => windSpeed > 0 || windDirection > 0;

  /// Check if a specific sensor bit is present.
  bool isSensorPresent(int bit) => (sensorPresent & bit) != 0;

  /// Check if a specific sensor bit is enabled.
  bool isSensorEnabled(int bit) => (sensorEnabled & bit) != 0;

  /// Check if a specific sensor bit is healthy.
  bool isSensorHealthy(int bit) => (sensorHealth & bit) != 0;

  /// Overall EKF is OK (all variances below warning threshold).
  bool get ekfOk => ekfHealth == 0;

  /// Distance from current position to home in metres (Haversine).
  double get distanceToHome {
    if (!hasHome || !hasPosition) return 0.0;
    const r = 6371000.0;
    final lat1 = latitude * math.pi / 180.0;
    final lat2 = homeLatitude * math.pi / 180.0;
    final dLat = (homeLatitude - latitude) * math.pi / 180.0;
    final dLon = (homeLongitude - longitude) * math.pi / 180.0;
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.pow(math.sin(dLon / 2), 2) * math.cos(lat1) * math.cos(lat2);
    return r * 2.0 * math.asin(math.sqrt(a));
  }

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
    int? currentWaypoint,
    double? ekfVelocityVar,
    double? ekfPosHorizVar,
    double? ekfPosVertVar,
    double? ekfCompassVar,
    double? ekfTerrainVar,
    int? sensorPresent,
    int? sensorEnabled,
    int? sensorHealth,
    int? firmwareVersionMajor,
    int? firmwareVersionMinor,
    int? firmwareVersionPatch,
    int? boardVersion,
    int? capabilities,
    int? vehicleUid,
    double? gimbalPitch,
    double? gimbalYaw,
    double? gimbalRoll,
    bool? hasGimbal,
    List<int>? servoOutputs,
    List<int>? rcChannels,
    int? rcChannelCount,
    int? rcRssi,
    bool? rcFailsafe,
    double? homeLatitude,
    double? homeLongitude,
    double? homeAltitude,
    double? windSpeed,
    double? windDirection,
    double? windSpeedZ,
    double? vibrationX,
    double? vibrationY,
    double? vibrationZ,
    int? clipping0,
    int? clipping1,
    int? clipping2,
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
      currentWaypoint: currentWaypoint ?? this.currentWaypoint,
      ekfVelocityVar: ekfVelocityVar ?? this.ekfVelocityVar,
      ekfPosHorizVar: ekfPosHorizVar ?? this.ekfPosHorizVar,
      ekfPosVertVar: ekfPosVertVar ?? this.ekfPosVertVar,
      ekfCompassVar: ekfCompassVar ?? this.ekfCompassVar,
      ekfTerrainVar: ekfTerrainVar ?? this.ekfTerrainVar,
      sensorPresent: sensorPresent ?? this.sensorPresent,
      sensorEnabled: sensorEnabled ?? this.sensorEnabled,
      sensorHealth: sensorHealth ?? this.sensorHealth,
      firmwareVersionMajor: firmwareVersionMajor ?? this.firmwareVersionMajor,
      firmwareVersionMinor: firmwareVersionMinor ?? this.firmwareVersionMinor,
      firmwareVersionPatch: firmwareVersionPatch ?? this.firmwareVersionPatch,
      boardVersion: boardVersion ?? this.boardVersion,
      capabilities: capabilities ?? this.capabilities,
      vehicleUid: vehicleUid ?? this.vehicleUid,
      gimbalPitch: gimbalPitch ?? this.gimbalPitch,
      gimbalYaw: gimbalYaw ?? this.gimbalYaw,
      gimbalRoll: gimbalRoll ?? this.gimbalRoll,
      hasGimbal: hasGimbal ?? this.hasGimbal,
      servoOutputs: servoOutputs ?? this.servoOutputs,
      rcChannels: rcChannels ?? this.rcChannels,
      rcChannelCount: rcChannelCount ?? this.rcChannelCount,
      rcRssi: rcRssi ?? this.rcRssi,
      rcFailsafe: rcFailsafe ?? this.rcFailsafe,
      homeLatitude: homeLatitude ?? this.homeLatitude,
      homeLongitude: homeLongitude ?? this.homeLongitude,
      homeAltitude: homeAltitude ?? this.homeAltitude,
      windSpeed: windSpeed ?? this.windSpeed,
      windDirection: windDirection ?? this.windDirection,
      windSpeedZ: windSpeedZ ?? this.windSpeedZ,
      vibrationX: vibrationX ?? this.vibrationX,
      vibrationY: vibrationY ?? this.vibrationY,
      vibrationZ: vibrationZ ?? this.vibrationZ,
      clipping0: clipping0 ?? this.clipping0,
      clipping1: clipping1 ?? this.clipping1,
      clipping2: clipping2 ?? this.clipping2,
    );
  }

  @override
  List<Object?> get props => [
        systemId, componentId, vehicleType, autopilotType, firmwareVersion,
        roll, pitch, yaw, rollSpeed, pitchSpeed, yawSpeed,
        latitude, longitude, altitudeMsl, altitudeRel, gpsFix, satellites, hdop,
        airspeed, groundspeed, heading, climbRate, throttle,
        batteryVoltage, batteryCurrent, batteryRemaining, batteryConsumed,
        flightMode, armed, lastHeartbeat, rssi, currentWaypoint,
        ekfVelocityVar, ekfPosHorizVar, ekfPosVertVar, ekfCompassVar,
        ekfTerrainVar, sensorPresent, sensorEnabled, sensorHealth,
        firmwareVersionMajor, firmwareVersionMinor, firmwareVersionPatch,
        boardVersion, capabilities, vehicleUid,
        gimbalPitch, gimbalYaw, gimbalRoll, hasGimbal,
        servoOutputs, rcChannels, rcChannelCount, rcRssi, rcFailsafe,
        homeLatitude, homeLongitude, homeAltitude,
        windSpeed, windDirection, windSpeedZ,
        vibrationX, vibrationY, vibrationZ, clipping0, clipping1, clipping2,
      ];
}
