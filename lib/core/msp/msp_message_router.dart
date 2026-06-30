import 'dart:math';

import '../../shared/models/vehicle_state.dart';
import 'msp_message.dart';

/// Pure MSP **State convergence**: folds typed [MspMessage]s into the unified
/// [VehicleState].
///
/// This is the one place MSP *and* firmware knowledge legitimately remains
/// after the seam (see ADR 0002 and the *State convergence* /
/// *Protocol-vs-firmware* entries in `CONTEXT.md`). The decoder stays
/// firmware-agnostic; here is where Betaflight-vs-iNav interpretation happens —
/// e.g. which mode bit in the raw `MSP_STATUS` flags means ANGLE/HORIZON.
///
/// It tracks the active [AutopilotType] from `MSP_FC_VARIANT` so it always
/// knows which firmware is speaking, and accumulates an immutable [VehicleState]
/// across messages (each fold is `copyWith` off the previous snapshot). It holds
/// no transports, timers or I/O, so "typed message in → folded state out" is
/// directly unit-testable. The sibling of `MavlinkMessageRouter`.
class MspMessageRouter {
  /// Latest accumulated vehicle state.
  VehicleState get state => _state;
  VehicleState _state = const VehicleState();

  /// The firmware detected from `MSP_FC_VARIANT`, defaulting to unknown until
  /// the FC identifies itself. Convergence consults this for any
  /// firmware-specific interpretation.
  AutopilotType get firmware => _state.autopilotType;

  /// Fold one typed [message] into the accumulated state and return the new
  /// snapshot. The exhaustive switch guarantees every modelled MSP message is
  /// handled.
  VehicleState route(MspMessage message) {
    final VehicleState next = switch (message) {
      MspFcVariant() => _state.copyWith(autopilotType: _variantToType(message)),
      MspFcVersion() => _state.copyWith(
          firmwareVersionMajor: message.major,
          firmwareVersionMinor: message.minor,
          firmwareVersionPatch: message.patch,
          firmwareVersion: '${message.major}.${message.minor}.${message.patch}',
        ),
      MspStatus() => _foldStatus(message),
      MspAttitude() => _foldAttitude(message),
      MspRawGps() => _foldRawGps(message),
      MspAltitude() => _state.copyWith(
          altitudeRel: message.altCm / 100.0,
          climbRate: message.varioCmS / 100.0,
        ),
      MspAnalog() => _foldAnalog(message),
      MspBatteryState() => _state.copyWith(
          batteryVoltage: message.voltageDecivolt / 10.0,
          batteryConsumed: message.mAhDrawn.toDouble(),
          batteryCurrent: message.currentCentiamp / 100.0,
          batteryRemaining: message.remainingPercent.clamp(0, 100),
        ),
      MspRc() => _state.copyWith(
          rcChannels: message.channels,
          rcChannelCount: message.channels.length,
        ),
    };
    _state = next;
    return _state;
  }

  AutopilotType _variantToType(MspFcVariant message) {
    switch (message.identifier) {
      case 'BTFL':
        return AutopilotType.betaflight;
      case 'INAV':
        return AutopilotType.inav;
      default:
        return AutopilotType.unknown;
    }
  }

  VehicleState _foldStatus(MspStatus message) {
    final flags = message.flightModeFlags;
    final isArmed = (flags & (1 << 0)) != 0;
    return _state.copyWith(
      armed: isArmed,
      flightMode: _decodeFlightMode(flags),
      lastHeartbeat: DateTime.now(),
    );
  }

  /// Interpret the raw mode-flags bitmask for the active firmware.
  ///
  /// Betaflight flight-mode flag bits (from bf source, modes.h):
  ///   bit 0 = ARM, bit 1 = ANGLE, bit 2 = HORIZON, bit 21 = AIRMODE.
  /// iNav shares the leading ANGLE/HORIZON/ACRO bits closely enough for display
  /// purposes; this is the firmware-specific seam where the two could diverge.
  FlightMode _decodeFlightMode(int flags) {
    final isAngle = (flags & (1 << 1)) != 0;
    final isHorizon = (flags & (1 << 2)) != 0;
    final isAirMode = (flags & (1 << 21)) != 0;

    if (isAngle) {
      return const FlightMode('ANGLE', 1, category: 'self-level');
    }
    if (isHorizon) {
      return const FlightMode('HORIZON', 2, category: 'self-level');
    }
    if (isAirMode) {
      return const FlightMode('AIR', 21, category: 'acro');
    }
    return const FlightMode('ACRO', 0, category: 'acro');
  }

  VehicleState _foldAttitude(MspAttitude message) {
    const degToRad = pi / 180.0;
    final roll = (message.rollDecideg / 10.0) * degToRad;
    final pitch = (message.pitchDecideg / 10.0) * degToRad;
    final yaw = message.yawDeg.toDouble() * degToRad;
    return _state.copyWith(
      roll: roll,
      pitch: pitch,
      yaw: yaw,
      heading: message.yawDeg < 0 ? (message.yawDeg + 360) : message.yawDeg,
    );
  }

  VehicleState _foldRawGps(MspRawGps message) {
    final GpsFix gpsFix;
    switch (message.fixType) {
      case 0:
        gpsFix = GpsFix.noFix;
      case 1:
        gpsFix = GpsFix.fix2d;
      case 2:
        gpsFix = GpsFix.fix3d;
      default:
        gpsFix = GpsFix.none;
    }

    // Some BF versions encode HDOP as hdop × 100; the most common encoding is
    // × 100 (matching MAVLink GPS_RAW_INT). Keep the previous value when absent.
    final hdop = message.hdopRaw != null ? message.hdopRaw! / 100.0 : _state.hdop;

    return _state.copyWith(
      gpsFix: gpsFix,
      satellites: message.numSat,
      latitude: message.latRaw / 1e7,
      longitude: message.lonRaw / 1e7,
      altitudeMsl: message.altMeters.toDouble(),
      groundspeed: message.speedCmS / 100.0,
      heading: (message.courseDecideg ~/ 10).clamp(0, 359),
      hdop: hdop,
    );
  }

  VehicleState _foldAnalog(MspAnalog message) {
    // Scale RSSI from 0-1023 to 0-255 to match MAVLink convention.
    final rssi = (message.rssiRaw * 255 ~/ 1023).clamp(0, 255);
    return _state.copyWith(
      batteryVoltage: message.vbatDecivolt / 10.0,
      batteryConsumed: message.mAhConsumed.toDouble(),
      rssi: rssi,
      batteryCurrent: message.amperageCentiamp / 100.0,
    );
  }
}
