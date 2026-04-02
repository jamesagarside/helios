import 'dart:typed_data';

import 'msp_frame.dart';

/// Internal parser state-machine states.
enum _ParseState {
  idle,
  dollar,
  m,
  direction,
  length,
  code,
  payload,
  checksum,
}

/// MSP v1 frame parser.
///
/// Feed raw bytes from the transport with [feed] or [feedByte].  After each
/// batch call [takeFrames] to retrieve any complete frames that have
/// accumulated.  Frames with incorrect checksums are silently dropped;
/// [parseErrors] is incremented for each such event.
///
/// Wire format:
/// ```
///   '$'  'M'  ('>' | '<')  <length: uint8>  <code: uint8>
///   [payload: length bytes]  <checksum: uint8>
/// ```
/// Checksum = XOR of `length`, `code`, and every payload byte.
class MspParser {
  _ParseState _state = _ParseState.idle;

  MspDirection _direction = MspDirection.response;
  int _length = 0;
  int _code = 0;
  int _crcAccumulator = 0;

  final List<int> _payloadBuffer = [];
  int _payloadBytesRead = 0;

  final List<MspFrame> _completeFrames = [];

  /// Number of frames discarded due to checksum mismatch.
  int parseErrors = 0;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Feed a chunk of raw bytes into the parser.
  void feed(Uint8List data) {
    for (final byte in data) {
      feedByte(byte);
    }
  }

  /// Feed a single byte into the parser.
  void feedByte(int byte) {
    switch (_state) {
      case _ParseState.idle:
        if (byte == 0x24 /* '$' */) {
          _state = _ParseState.dollar;
        }

      case _ParseState.dollar:
        if (byte == 0x4D /* 'M' */) {
          _state = _ParseState.m;
        } else {
          // Not an 'M' — if this byte is '$', stay here; otherwise reset.
          _state = byte == 0x24 ? _ParseState.dollar : _ParseState.idle;
        }

      case _ParseState.m:
        if (byte == 0x3E /* '>' */) {
          _direction = MspDirection.response;
          _state = _ParseState.direction;
        } else if (byte == 0x3C /* '<' */) {
          _direction = MspDirection.request;
          _state = _ParseState.direction;
        } else {
          // Malformed — restart from scratch (handle '$' carry-over).
          _state = byte == 0x24 ? _ParseState.dollar : _ParseState.idle;
        }

      case _ParseState.direction:
        // This state is reached immediately after reading the direction byte;
        // the next byte is the payload length.
        _length = byte & 0xFF;
        _crcAccumulator = _length;
        _payloadBuffer.clear();
        _payloadBytesRead = 0;
        _state = _ParseState.length;

      case _ParseState.length:
        // The byte following length is the command code.
        _code = byte & 0xFF;
        _crcAccumulator ^= _code;
        _state = _length == 0 ? _ParseState.checksum : _ParseState.code;

      case _ParseState.code:
        // We are receiving payload bytes.
        _payloadBuffer.add(byte & 0xFF);
        _crcAccumulator ^= byte;
        _payloadBytesRead++;
        if (_payloadBytesRead >= _length) {
          _state = _ParseState.payload;
        }

      case _ParseState.payload:
        // This byte is the checksum.
        _finaliseFrame(byte & 0xFF);
        _state = _ParseState.idle;

      case _ParseState.checksum:
        // Empty-payload frames skip _ParseState.code/_ParseState.payload and
        // land here for the checksum byte directly.
        _finaliseFrame(byte & 0xFF);
        _state = _ParseState.idle;
    }
  }

  /// Returns all fully-parsed frames accumulated since the last call, then
  /// clears the internal buffer.
  List<MspFrame> takeFrames() {
    if (_completeFrames.isEmpty) return const [];
    final frames = List<MspFrame>.of(_completeFrames);
    _completeFrames.clear();
    return frames;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _finaliseFrame(int receivedCrc) {
    if (receivedCrc != (_crcAccumulator & 0xFF)) {
      parseErrors++;
      return;
    }
    _completeFrames.add(
      MspFrame(
        code: _code,
        payload: List<int>.unmodifiable(List<int>.of(_payloadBuffer)),
        direction: _direction,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // State inspection (primarily for testing)
  // ---------------------------------------------------------------------------

  /// Resets the parser to idle state without clearing accumulated frames.
  void reset() {
    _state = _ParseState.idle;
    _payloadBuffer.clear();
    _payloadBytesRead = 0;
    _crcAccumulator = 0;
    _length = 0;
    _code = 0;
  }
}
