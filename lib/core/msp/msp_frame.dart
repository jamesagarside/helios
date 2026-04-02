import 'dart:typed_data';

/// Whether a frame is an outbound request or an inbound response.
enum MspDirection { request, response }

/// An MSP v1 frame, fully decoded.
///
/// The wire format is:
/// ```
///   '$'  'M'  direction  length  code  [payload…]  checksum
/// ```
/// where direction is '<' for requests and '>' for responses.
class MspFrame {
  const MspFrame({
    required this.code,
    required this.payload,
    required this.direction,
  });

  /// MSP command code (see [MspCodes]).
  final int code;

  /// Frame payload bytes (may be empty).
  final List<int> payload;

  /// Whether this frame is a request (outbound) or response (inbound).
  final MspDirection direction;

  // ---------------------------------------------------------------------------
  // Wire encoding helpers
  // ---------------------------------------------------------------------------

  /// Builds a minimal MSP v1 request frame for [code] with no payload.
  ///
  /// Format: `$ M < <length=0> <code> <crc>`
  /// The checksum is `length XOR code XOR payload_bytes…`.  With an empty
  /// payload and length == 0 this simplifies to `0 ^ code == code`.
  static Uint8List buildRequest(int code) {
    // Total frame: 6 bytes — preamble (2) + direction (1) + length (1)
    //              + code (1) + checksum (1)
    final frame = Uint8List(6);
    frame[0] = 0x24; // '$'
    frame[1] = 0x4D; // 'M'
    frame[2] = 0x3C; // '<'
    frame[3] = 0x00; // payload length
    frame[4] = code & 0xFF;
    frame[5] = code & 0xFF; // crc = 0 ^ code = code
    return frame;
  }

  /// Builds an MSP v1 request frame for [code] with a non-empty [payload].
  ///
  /// The checksum is the XOR of `length`, `code`, and every payload byte.
  static Uint8List buildRequestWithPayload(int code, List<int> payload) {
    final length = payload.length;
    // Total: 6 + payload.length bytes
    final frame = Uint8List(6 + length);
    frame[0] = 0x24; // '$'
    frame[1] = 0x4D; // 'M'
    frame[2] = 0x3C; // '<'
    frame[3] = length & 0xFF;
    frame[4] = code & 0xFF;

    var crc = length ^ code;
    for (var i = 0; i < length; i++) {
      frame[5 + i] = payload[i] & 0xFF;
      crc ^= payload[i];
    }
    frame[5 + length] = crc & 0xFF;
    return frame;
  }

  @override
  String toString() =>
      'MspFrame(code: $code, direction: $direction, '
      'payloadLength: ${payload.length})';
}
