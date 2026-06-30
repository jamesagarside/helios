import 'dart:typed_data';

import 'msp_codes.dart';
import 'msp_frame.dart';
import 'msp_message.dart';

/// Pure, firmware-agnostic MSP decoder: turns one inbound [MspFrame] into one
/// typed [MspMessage], or `null` for frames we don't model.
///
/// It only translates bytes → raw typed fields. It performs **no** firmware
/// interpretation (no Betaflight-vs-iNav mode-bit semantics, no unit scaling
/// into vehicle state) — that belongs to MSP State convergence
/// (`MspMessageRouter`). Keeping this step pure makes it directly unit-testable
/// (frame in → typed message out) and is the MSP analogue of the typed
/// `MavlinkMessage`s the MAVLink parser already emits. See ADR 0002.
abstract final class MspDecoder {
  /// Decode a single inbound response [frame] into a typed [MspMessage].
  ///
  /// Returns `null` when:
  /// - the frame is a request echo rather than a response,
  /// - the command code is not modelled, or
  /// - the payload is too short to decode safely.
  static MspMessage? decode(MspFrame frame) {
    // Only responses carry decodable telemetry; ignore request echo-backs.
    if (frame.direction != MspDirection.response) return null;

    switch (frame.code) {
      case MspCodes.fcVariant:
        return _fcVariant(frame.payload);
      case MspCodes.fcVersion:
        return _fcVersion(frame.payload);
      case MspCodes.status:
      case MspCodes.statusEx:
        return _status(frame.payload);
      case MspCodes.attitude:
        return _attitude(frame.payload);
      case MspCodes.rawGps:
        return _rawGps(frame.payload);
      case MspCodes.altitude:
        return _altitude(frame.payload);
      case MspCodes.analog:
        return _analog(frame.payload);
      case MspCodes.batteryState:
        return _batteryState(frame.payload);
      case MspCodes.rc:
        return _rc(frame.payload);
      default:
        return null;
    }
  }

  static ByteData _bd(List<int> payload) =>
      ByteData.sublistView(Uint8List.fromList(payload));

  static MspMessage? _fcVariant(List<int> payload) {
    if (payload.length < 4) return null;
    return MspFcVariant(String.fromCharCodes(payload.take(4)));
  }

  static MspMessage? _fcVersion(List<int> payload) {
    if (payload.length < 3) return null;
    return MspFcVersion(
      major: payload[0],
      minor: payload[1],
      patch: payload[2],
    );
  }

  static MspMessage? _status(List<int> payload) {
    // Bytes 0-1: cycleTime, 2-3: i2cErrors, 4-5: sensors bitmask,
    // 6-9: flight-mode flags (uint32 LE), 10: active profile.
    if (payload.length < 11) return null;
    final bd = _bd(payload);
    return MspStatus(
      sensorBitmask: bd.getUint16(4, Endian.little),
      flightModeFlags: bd.getUint32(6, Endian.little),
    );
  }

  static MspMessage? _attitude(List<int> payload) {
    // roll  int16 LE  degrees * 10
    // pitch int16 LE  degrees * 10
    // yaw   int16 LE  degrees (heading)
    if (payload.length < 6) return null;
    final bd = _bd(payload);
    return MspAttitude(
      rollDecideg: bd.getInt16(0, Endian.little),
      pitchDecideg: bd.getInt16(2, Endian.little),
      yawDeg: bd.getInt16(4, Endian.little),
    );
  }

  static MspMessage? _rawGps(List<int> payload) {
    // fixType uint8, numSat uint8, lat int32 LE, lon int32 LE,
    // altitude uint16 LE, speed uint16 LE, groundCourse uint16 LE,
    // [hdop uint16 LE — BF 3.3+]
    if (payload.length < 16) return null;
    final bd = _bd(payload);
    return MspRawGps(
      fixType: payload[0],
      numSat: payload[1],
      latRaw: bd.getInt32(2, Endian.little),
      lonRaw: bd.getInt32(6, Endian.little),
      altMeters: bd.getUint16(10, Endian.little),
      speedCmS: bd.getUint16(12, Endian.little),
      courseDecideg: bd.getUint16(14, Endian.little),
      hdopRaw:
          payload.length >= 18 ? bd.getUint16(16, Endian.little) : null,
    );
  }

  static MspMessage? _altitude(List<int> payload) {
    // estimatedAltitude int32 LE cm, vario int16 LE cm/s
    if (payload.length < 6) return null;
    final bd = _bd(payload);
    return MspAltitude(
      altCm: bd.getInt32(0, Endian.little),
      varioCmS: bd.getInt16(4, Endian.little),
    );
  }

  static MspMessage? _analog(List<int> payload) {
    // vbat uint8 (0.1 V), mAh consumed uint16 LE, rssi uint16 LE (0-1023),
    // amperage int16 LE (0.01 A)
    if (payload.length < 7) return null;
    final bd = _bd(payload);
    return MspAnalog(
      vbatDecivolt: payload[0],
      mAhConsumed: bd.getUint16(1, Endian.little),
      rssiRaw: bd.getUint16(3, Endian.little),
      amperageCentiamp: bd.getInt16(5, Endian.little),
    );
  }

  static MspMessage? _batteryState(List<int> payload) {
    // Betaflight 3.1+ MSP_BATTERY_STATE (classic layout):
    // cellCount uint8, capacity uint16 LE, voltage uint8 (0.1 V),
    // mAhDrawn uint16 LE, current uint16 LE (0.01 A), remaining uint8 (percent)
    if (payload.length < 9) return null;
    final bd = _bd(payload);
    return MspBatteryState(
      voltageDecivolt: payload[3],
      mAhDrawn: bd.getUint16(4, Endian.little),
      currentCentiamp: bd.getUint16(6, Endian.little),
      remainingPercent: payload[8],
    );
  }

  static MspMessage? _rc(List<int> payload) {
    // Pairs of uint16 LE — up to 16 channels.
    if (payload.length < 2) return null;
    final bd = _bd(payload);
    final channelCount = (payload.length ~/ 2).clamp(0, 16);
    final channels = <int>[
      for (var i = 0; i < channelCount; i++) bd.getUint16(i * 2, Endian.little),
    ];
    return MspRc(channels);
  }
}
