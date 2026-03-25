import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/vehicle_state.dart';

/// Notifier that updates VehicleState from decoded MAVLink messages.
class VehicleStateNotifier extends StateNotifier<VehicleState> {
  VehicleStateNotifier() : super(const VehicleState());

  /// Handle a decoded MAVLink message and update state accordingly.
  void handleMessage(MavlinkMessage msg) {
    switch (msg) {
      case HeartbeatMessage():
        _handleHeartbeat(msg);
      case AttitudeMessage():
        _handleAttitude(msg);
      case GlobalPositionIntMessage():
        _handleGlobalPosition(msg);
      case GpsRawIntMessage():
        _handleGpsRaw(msg);
      case SysStatusMessage():
        _handleSysStatus(msg);
      case VfrHudMessage():
        _handleVfrHud(msg);
      case RcChannelsMessage():
        _handleRcChannels(msg);
      case VibrationMessage():
        break; // Recorded to DuckDB, no UI state update needed
      case StatusTextMessage():
        break; // Handled separately by event log
      case CommandAckMessage():
        break; // Handled by command sender
      default:
        break;
    }
  }

  void _handleHeartbeat(HeartbeatMessage msg) {
    final vehicleType = switch (msg.type) {
      MavType.fixedWing => VehicleType.fixedWing,
      MavType.quadrotor => VehicleType.quadrotor,
      MavType.vtol => VehicleType.vtol,
      MavType.helicopter => VehicleType.helicopter,
      MavType.groundRover => VehicleType.rover,
      MavType.boat => VehicleType.boat,
      _ => VehicleType.unknown,
    };

    final autopilot = switch (msg.autopilot) {
      MavAutopilot.ardupilotmega => AutopilotType.ardupilot,
      MavAutopilot.px4 => AutopilotType.px4,
      _ => AutopilotType.unknown,
    };

    final flightMode = FlightMode(
      'MODE_${msg.customMode}',
      msg.customMode,
    );

    state = state.copyWith(
      systemId: msg.systemId,
      componentId: msg.componentId,
      vehicleType: vehicleType,
      autopilotType: autopilot,
      flightMode: flightMode,
      armed: msg.armed,
      lastHeartbeat: DateTime.now(),
    );
  }

  void _handleAttitude(AttitudeMessage msg) {
    state = state.copyWith(
      roll: msg.roll,
      pitch: msg.pitch,
      yaw: msg.yaw,
      rollSpeed: msg.rollSpeed,
      pitchSpeed: msg.pitchSpeed,
      yawSpeed: msg.yawSpeed,
    );
  }

  void _handleGlobalPosition(GlobalPositionIntMessage msg) {
    state = state.copyWith(
      latitude: msg.latDeg,
      longitude: msg.lonDeg,
      altitudeMsl: msg.altMetres,
      altitudeRel: msg.relAltMetres,
      heading: msg.headingDeg,
    );
  }

  void _handleGpsRaw(GpsRawIntMessage msg) {
    final fix = switch (msg.fixType) {
      0 => GpsFix.none,
      1 => GpsFix.noFix,
      2 => GpsFix.fix2d,
      3 => GpsFix.fix3d,
      4 => GpsFix.dgps,
      5 => GpsFix.rtkFloat,
      6 => GpsFix.rtkFixed,
      _ => GpsFix.none,
    };

    state = state.copyWith(
      gpsFix: fix,
      satellites: msg.satellitesVisible,
      hdop: msg.hdop,
    );
  }

  void _handleSysStatus(SysStatusMessage msg) {
    state = state.copyWith(
      batteryVoltage: msg.voltageVolts,
      batteryCurrent: msg.currentAmps,
      batteryRemaining: msg.batteryRemaining,
    );
  }

  void _handleVfrHud(VfrHudMessage msg) {
    state = state.copyWith(
      airspeed: msg.airspeed,
      groundspeed: msg.groundspeed,
      heading: msg.heading,
      throttle: msg.throttle,
      climbRate: msg.climb,
    );
  }

  void _handleRcChannels(RcChannelsMessage msg) {
    state = state.copyWith(rssi: msg.rssi);
  }

  /// Reset state to defaults (on disconnect).
  void reset() {
    state = const VehicleState();
  }
}
