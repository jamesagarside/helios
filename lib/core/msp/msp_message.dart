/// Typed MSP **Protocol messages** — single decoded facts off the MSP wire.
///
/// Each case carries the *raw* fields decoded straight from the frame payload,
/// before any firmware interpretation. The decoder ([MspDecoder]) is therefore
/// firmware-agnostic: Betaflight-vs-iNav semantics (e.g. which mode bit means
/// what) live one level up, in MSP State convergence (`MspMessageRouter`).
///
/// This mirrors the MAVLink side of the seam, where typed `MavlinkMessage`s
/// flow inbound and convergence happens per-protocol. See ADR 0002 and the
/// *Protocol message* / *Protocol-vs-firmware* entries in `CONTEXT.md`.
library;

/// Base of the typed MSP message family carried through the protocol seam.
sealed class MspMessage {
  const MspMessage();
}

/// MSP_FC_VARIANT — the 4-byte ASCII flight-controller identifier
/// (e.g. "BTFL", "INAV"). Convergence maps this to an `AutopilotType` so it
/// always knows which firmware is speaking MSP.
class MspFcVariant extends MspMessage {
  const MspFcVariant(this.identifier);

  /// Raw 4-character variant string as sent by the FC.
  final String identifier;
}

/// MSP_FC_VERSION — firmware version triple.
class MspFcVersion extends MspMessage {
  const MspFcVersion({
    required this.major,
    required this.minor,
    required this.patch,
  });

  final int major;
  final int minor;
  final int patch;
}

/// MSP_STATUS / MSP_STATUS_EX — armed/flight-mode flags and sensor health.
///
/// [flightModeFlags] is the raw uint32 mode bitmask exactly as sent; the
/// meaning of individual bits is firmware-specific and is resolved during
/// convergence, never here.
class MspStatus extends MspMessage {
  const MspStatus({
    required this.flightModeFlags,
    required this.sensorBitmask,
  });

  /// Raw mode-flags uint32 (bytes 6-9 of the payload).
  final int flightModeFlags;

  /// Raw sensors-present bitmask (bytes 4-5 of the payload).
  final int sensorBitmask;
}

/// MSP_ATTITUDE — roll/pitch in tenths-of-degrees, heading in whole degrees,
/// all as raw signed integers straight off the wire.
class MspAttitude extends MspMessage {
  const MspAttitude({
    required this.rollDecideg,
    required this.pitchDecideg,
    required this.yawDeg,
  });

  /// Roll in tenths of a degree (int16).
  final int rollDecideg;

  /// Pitch in tenths of a degree (int16).
  final int pitchDecideg;

  /// Heading in whole degrees (int16).
  final int yawDeg;
}

/// MSP_RAW_GPS — fix/satellite/position/velocity facts as raw integers.
class MspRawGps extends MspMessage {
  const MspRawGps({
    required this.fixType,
    required this.numSat,
    required this.latRaw,
    required this.lonRaw,
    required this.altMeters,
    required this.speedCmS,
    required this.courseDecideg,
    this.hdopRaw,
  });

  /// Raw fix type byte (0 = none/no-fix, 1 = 2D, 2 = 3D).
  final int fixType;
  final int numSat;

  /// Latitude in degrees × 1e7 (int32).
  final int latRaw;

  /// Longitude in degrees × 1e7 (int32).
  final int lonRaw;

  /// Altitude in metres (uint16).
  final int altMeters;

  /// Ground speed in cm/s (uint16).
  final int speedCmS;

  /// Ground course in tenths of a degree (uint16).
  final int courseDecideg;

  /// Raw HDOP value if present (BF 3.3+); null when the frame omits it.
  final int? hdopRaw;
}

/// MSP_ALTITUDE — estimated altitude and vertical speed as raw integers.
class MspAltitude extends MspMessage {
  const MspAltitude({
    required this.altCm,
    required this.varioCmS,
  });

  /// Estimated altitude in cm (int32).
  final int altCm;

  /// Vertical speed in cm/s (int16).
  final int varioCmS;
}

/// MSP_ANALOG — voltage/current/RSSI/consumption as raw integers.
class MspAnalog extends MspMessage {
  const MspAnalog({
    required this.vbatDecivolt,
    required this.mAhConsumed,
    required this.rssiRaw,
    required this.amperageCentiamp,
  });

  /// Battery voltage in 0.1 V units (uint8).
  final int vbatDecivolt;

  /// Consumed capacity in mAh (uint16).
  final int mAhConsumed;

  /// RSSI on the raw 0-1023 scale (uint16).
  final int rssiRaw;

  /// Current in 0.01 A units (int16).
  final int amperageCentiamp;
}

/// MSP_BATTERY_STATE — Betaflight 3.1+ extended battery facts (raw integers).
class MspBatteryState extends MspMessage {
  const MspBatteryState({
    required this.voltageDecivolt,
    required this.mAhDrawn,
    required this.currentCentiamp,
    required this.remainingPercent,
  });

  /// Battery voltage in 0.1 V units (uint8, classic layout).
  final int voltageDecivolt;

  /// Drawn capacity in mAh (uint16).
  final int mAhDrawn;

  /// Current in 0.01 A units (uint16).
  final int currentCentiamp;

  /// Remaining capacity percent (uint8).
  final int remainingPercent;
}

/// MSP_RC — raw RC channel values (each uint16), up to 16 channels.
class MspRc extends MspMessage {
  const MspRc(this.channels);

  /// Raw channel values in wire order.
  final List<int> channels;
}
