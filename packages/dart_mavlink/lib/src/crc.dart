import 'dart:typed_data';

/// MAVLink CRC-16/MCRF4XX (X.25) implementation.
///
/// Used for MAVLink frame integrity checking.
/// Reference: https://mavlink.io/en/guide/serialization.html#crc_extra
class MavlinkCrc {
  static const int _initialValue = 0xFFFF;

  /// Compute CRC-16 over the given bytes.
  static int calculate(Uint8List data) {
    var crc = _initialValue;
    for (final byte in data) {
      crc = accumulate(byte, crc);
    }
    return crc;
  }

  /// Accumulate a single byte into the running CRC.
  static int accumulate(int byte, int crc) {
    var tmp = byte ^ (crc & 0xFF);
    tmp ^= (tmp << 4) & 0xFF;
    return ((crc >> 8) & 0xFF) ^
        (tmp << 8) ^
        (tmp << 3) ^
        ((tmp >> 4) & 0xFF);
  }

  /// Compute CRC for a MAVLink v2 frame.
  ///
  /// Includes header (bytes 1..9), payload, and the CRC extra byte
  /// for the specific message ID.
  static int computeFrameCrc({
    required Uint8List header,
    required Uint8List payload,
    required int crcExtra,
  }) {
    var crc = _initialValue;

    // CRC over header bytes (excluding STX magic byte at index 0)
    for (var i = 1; i < header.length; i++) {
      crc = accumulate(header[i], crc);
    }

    // CRC over payload
    for (final byte in payload) {
      crc = accumulate(byte, crc);
    }

    // CRC extra for message-specific validation
    crc = accumulate(crcExtra, crc);

    return crc;
  }
}
