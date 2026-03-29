import 'dart:async';
import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/vehicle_state.dart';

/// Notifier that updates VehicleState from decoded MAVLink messages.
///
/// Batches incoming messages and emits state at a fixed frame rate (~30Hz).
/// High-frequency messages (ATTITUDE at 25-50Hz) are accumulated into
/// [_pending] and flushed to [state] every 33ms by a persistent timer.
class VehicleStateNotifier extends StateNotifier<VehicleState> {
  VehicleStateNotifier() : super(const VehicleState());

  /// Target UI refresh interval — 33ms ≈ 30 fps.
  static const _frameInterval = Duration(milliseconds: 33);

  Timer? _frameTimer;
  VehicleState _pending = const VehicleState();
  bool _dirty = false;
  bool _active = false;

  /// Handle a decoded MAVLink message and update state accordingly.
  void handleMessage(MavlinkMessage msg) {
    // Start the frame timer on first message
    if (!_active) {
      _active = true;
      _frameTimer = Timer.periodic(_frameInterval, (_) => _flush());
    }

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
      case MissionCurrentMessage():
        _handleMissionCurrent(msg);
      case EkfStatusReportMessage():
        _handleEkfStatus(msg);
      case AutopilotVersionMessage():
        _handleAutopilotVersion(msg);
      case MountStatusMessage():
        _handleMountStatus(msg);
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

  void _flush() {
    if (_dirty) {
      state = _pending;
      _dirty = false;
    }
  }

  /// Force-flush pending state to listeners immediately.
  /// Used by tests and for critical state changes that can't wait.
  void flush() {
    if (_dirty) {
      state = _pending;
      _dirty = false;
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

    _pending = _pending.copyWith(
      systemId: msg.systemId,
      componentId: msg.componentId,
      vehicleType: vehicleType,
      autopilotType: autopilot,
      flightMode: flightMode,
      armed: msg.armed,
      lastHeartbeat: DateTime.now(),
    );
    _dirty = true;
  }

  void _handleAttitude(AttitudeMessage msg) {
    _pending = _pending.copyWith(
      roll: msg.roll,
      pitch: msg.pitch,
      yaw: msg.yaw,
      rollSpeed: msg.rollSpeed,
      pitchSpeed: msg.pitchSpeed,
      yawSpeed: msg.yawSpeed,
    );
    _dirty = true;
  }

  void _handleGlobalPosition(GlobalPositionIntMessage msg) {
    _pending = _pending.copyWith(
      latitude: msg.latDeg,
      longitude: msg.lonDeg,
      altitudeMsl: msg.altMetres,
      altitudeRel: msg.relAltMetres,
      heading: msg.headingDeg,
    );
    _dirty = true;
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

    _pending = _pending.copyWith(
      gpsFix: fix,
      satellites: msg.satellitesVisible,
      hdop: msg.hdop,
    );
    _dirty = true;
  }

  void _handleSysStatus(SysStatusMessage msg) {
    _pending = _pending.copyWith(
      batteryVoltage: msg.voltageVolts,
      batteryCurrent: msg.currentAmps,
      batteryRemaining: msg.batteryRemaining,
    );
    _dirty = true;
  }

  void _handleVfrHud(VfrHudMessage msg) {
    _pending = _pending.copyWith(
      airspeed: msg.airspeed,
      groundspeed: msg.groundspeed,
      heading: msg.heading,
      throttle: msg.throttle,
      climbRate: msg.climb,
    );
    _dirty = true;
  }

  void _handleRcChannels(RcChannelsMessage msg) {
    _pending = _pending.copyWith(
      rssi: msg.rssi,
      rcChannels: msg.channels,
      rcChannelCount: msg.channelCount,
    );
    _dirty = true;
  }

  void _handleMissionCurrent(MissionCurrentMessage msg) {
    _pending = _pending.copyWith(currentWaypoint: msg.seq);
    _dirty = true;
  }

  void _handleEkfStatus(EkfStatusReportMessage msg) {
    _pending = _pending.copyWith(
      ekfVelocityVar: msg.velocityVariance,
      ekfPosHorizVar: msg.posHorizVariance,
      ekfPosVertVar: msg.posVertVariance,
      ekfCompassVar: msg.compassVariance,
      ekfTerrainVar: msg.terrainAltVariance,
    );
    _dirty = true;
  }

  void _handleAutopilotVersion(AutopilotVersionMessage msg) {
    _pending = _pending.copyWith(
      firmwareVersion: msg.versionString,
      firmwareVersionMajor: msg.versionMajor,
      firmwareVersionMinor: msg.versionMinor,
      firmwareVersionPatch: msg.versionPatch,
      boardVersion: msg.boardVersion,
      capabilities: msg.capabilities,
      vehicleUid: msg.uid,
    );
    _dirty = true;
  }

  void _handleMountStatus(MountStatusMessage msg) {
    _pending = _pending.copyWith(
      gimbalPitch: msg.pitchDeg,
      gimbalYaw: msg.yawDeg,
      gimbalRoll: msg.rollDeg,
      hasGimbal: true,
    );
    _dirty = true;
  }

  /// Apply a replay snapshot directly as the current state.
  ///
  /// Bypasses the MAVLink message pipeline and the 30Hz batch buffer.
  void applyReplayState(VehicleState replayState) {
    state = replayState;
  }

  /// Apply a VehicleState update from the MSP service.
  ///
  /// Routes through the 30Hz batch buffer so the Fly View gets the same
  /// smooth update cadence as MAVLink telemetry.
  void applyMspState(VehicleState mspState) {
    if (!_active) {
      _active = true;
      _frameTimer = Timer.periodic(_frameInterval, (_) => _flush());
    }
    _pending = mspState;
    _dirty = true;
  }

  /// Reset state to defaults (on disconnect).
  void reset() {
    _frameTimer?.cancel();
    _frameTimer = null;
    _active = false;
    _dirty = false;
    _pending = const VehicleState();
    state = const VehicleState();
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }
}
