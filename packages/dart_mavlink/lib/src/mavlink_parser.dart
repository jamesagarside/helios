import 'dart:typed_data';
import 'crc.dart';
import 'mavlink_types.dart';
import 'messages.dart';

/// MAVLink v2 frame parser.
///
/// Feed raw bytes via [parse], retrieve decoded messages via [takeMessages].
/// Handles frame synchronisation, CRC validation, and message dispatch.
class MavlinkParser {
  final List<MavlinkMessage> _pending = [];
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  /// Parse errors (invalid magic, malformed frames).
  int parseErrors = 0;

  /// CRC validation failures.
  int crcErrors = 0;

  /// Unknown message IDs (still parsed as UnknownMessage).
  int unknownMessages = 0;

  /// Total messages successfully decoded.
  int messagesDecoded = 0;

  /// Feed raw bytes from the transport layer.
  void parse(Uint8List data) {
    _buffer.add(data);
    final bytes = _buffer.toBytes();
    _buffer.clear();

    var offset = 0;

    while (offset < bytes.length) {
      // Scan for magic byte
      if (bytes[offset] == mavlinkV2Magic) {
        final result = _tryParseV2(bytes, offset);
        if (result > 0) {
          offset += result;
          continue;
        } else if (result == 0) {
          // Not enough data — save remainder and return
          _buffer.add(Uint8List.sublistView(bytes, offset));
          return;
        } else {
          // Parse error — skip this byte
          parseErrors++;
          offset++;
          continue;
        }
      } else if (bytes[offset] == mavlinkV1Magic) {
        final result = _tryParseV1(bytes, offset);
        if (result > 0) {
          offset += result;
          continue;
        } else if (result == 0) {
          _buffer.add(Uint8List.sublistView(bytes, offset));
          return;
        } else {
          parseErrors++;
          offset++;
          continue;
        }
      } else {
        // Not a magic byte — skip
        offset++;
      }
    }
  }

  /// Try to parse a MAVLink v2 frame starting at [offset].
  /// Returns bytes consumed (>0), 0 if incomplete, -1 if invalid.
  int _tryParseV2(Uint8List bytes, int offset) {
    final remaining = bytes.length - offset;

    // Need at least header (10 bytes)
    if (remaining < mavlinkV2HeaderSize) return 0;

    final payloadLen = bytes[offset + 1];
    final incompatFlags = bytes[offset + 2];
    // final compatFlags = bytes[offset + 3]; // unused for now

    final isSigned = (incompatFlags & mavlinkIflagSigned) != 0;
    final frameSize = mavlinkV2HeaderSize +
        payloadLen +
        mavlinkCrcSize +
        (isSigned ? mavlinkV2SignatureSize : 0);

    if (remaining < frameSize) return 0; // Incomplete frame

    final seq = bytes[offset + 4];
    final sysId = bytes[offset + 5];
    final compId = bytes[offset + 6];
    final msgId = bytes[offset + 7] |
        (bytes[offset + 8] << 8) |
        (bytes[offset + 9] << 16);

    // Extract header and payload for CRC
    final header = Uint8List.sublistView(bytes, offset, offset + mavlinkV2HeaderSize);
    final payload = Uint8List.sublistView(
      bytes,
      offset + mavlinkV2HeaderSize,
      offset + mavlinkV2HeaderSize + payloadLen,
    );

    // CRC validation
    final crcExtra = mavlinkCrcExtras[msgId];
    if (crcExtra == null) {
      // Unknown message ID — still accept but mark as unknown
      unknownMessages++;
      _pending.add(UnknownMessage(
        messageId: msgId,
        systemId: sysId,
        componentId: compId,
        sequence: seq,
        payload: Uint8List.fromList(payload),
      ));
      messagesDecoded++;
      return frameSize;
    }

    final expectedCrc = MavlinkCrc.computeFrameCrc(
      header: header,
      payload: payload,
      crcExtra: crcExtra,
    );

    final crcOffset = offset + mavlinkV2HeaderSize + payloadLen;
    final receivedCrc = bytes[crcOffset] | (bytes[crcOffset + 1] << 8);

    if (expectedCrc != receivedCrc) {
      crcErrors++;
      return -1; // CRC mismatch
    }

    // Dispatch to message-specific deserializer
    final message = _deserialize(msgId, payload, sysId, compId, seq);
    _pending.add(message);
    messagesDecoded++;
    return frameSize;
  }

  /// Try to parse a MAVLink v1 frame starting at [offset].
  int _tryParseV1(Uint8List bytes, int offset) {
    final remaining = bytes.length - offset;

    if (remaining < mavlinkV1HeaderSize) return 0;

    final payloadLen = bytes[offset + 1];
    final frameSize = mavlinkV1HeaderSize + payloadLen + mavlinkCrcSize;

    if (remaining < frameSize) return 0;

    final seq = bytes[offset + 2];
    final sysId = bytes[offset + 3];
    final compId = bytes[offset + 4];
    final msgId = bytes[offset + 5];

    final payload = Uint8List.sublistView(
      bytes,
      offset + mavlinkV1HeaderSize,
      offset + mavlinkV1HeaderSize + payloadLen,
    );

    // V1 CRC: over header[1..5] + payload + crc_extra
    final crcExtra = mavlinkCrcExtras[msgId];
    if (crcExtra == null) {
      unknownMessages++;
      _pending.add(UnknownMessage(
        messageId: msgId,
        systemId: sysId,
        componentId: compId,
        sequence: seq,
        payload: Uint8List.fromList(payload),
      ));
      messagesDecoded++;
      return frameSize;
    }

    var crc = 0xFFFF;
    for (var i = 1; i < mavlinkV1HeaderSize; i++) {
      crc = MavlinkCrc.accumulate(bytes[offset + i], crc);
    }
    for (final byte in payload) {
      crc = MavlinkCrc.accumulate(byte, crc);
    }
    crc = MavlinkCrc.accumulate(crcExtra, crc);

    final crcOffset = offset + mavlinkV1HeaderSize + payloadLen;
    final receivedCrc = bytes[crcOffset] | (bytes[crcOffset + 1] << 8);

    if (crc != receivedCrc) {
      crcErrors++;
      return -1;
    }

    // Pad payload to expected size for deserializers that assume v2 layout
    final message = _deserialize(msgId, payload, sysId, compId, seq);
    _pending.add(message);
    messagesDecoded++;
    return frameSize;
  }

  /// Deserialize payload into a typed message.
  MavlinkMessage _deserialize(
    int msgId, Uint8List payload, int sysId, int compId, int seq,
  ) {
    try {
      return switch (msgId) {
        0 => HeartbeatMessage.fromPayload(payload, sysId, compId, seq),
        1 => SysStatusMessage.fromPayload(payload, sysId, compId, seq),
        24 => GpsRawIntMessage.fromPayload(payload, sysId, compId, seq),
        30 => AttitudeMessage.fromPayload(payload, sysId, compId, seq),
        21 => ParamRequestListMessage.fromPayload(payload, sysId, compId, seq),
        22 => ParamValueMessage.fromPayload(payload, sysId, compId, seq),
        23 => ParamSetMessage.fromPayload(payload, sysId, compId, seq),
        33 => GlobalPositionIntMessage.fromPayload(payload, sysId, compId, seq),
        36 => ServoOutputRawMessage.fromPayload(payload, sysId, compId, seq),
        42 => MissionCurrentMessage.fromPayload(payload, sysId, compId, seq),
        43 => MissionRequestListMessage.fromPayload(payload, sysId, compId, seq),
        44 => MissionCountMessage.fromPayload(payload, sysId, compId, seq),
        47 => MissionAckMessage.fromPayload(payload, sysId, compId, seq),
        51 => MissionRequestIntMessage.fromPayload(payload, sysId, compId, seq),
        65 => RcChannelsMessage.fromPayload(payload, sysId, compId, seq),
        73 => MissionItemIntMessage.fromPayload(payload, sysId, compId, seq),
        74 => VfrHudMessage.fromPayload(payload, sysId, compId, seq),
        118 => LogEntryMessage.fromPayload(payload, sysId, compId, seq),
        120 => LogDataMessage.fromPayload(payload, sysId, compId, seq),
        191 => MagCalProgressMessage.fromPayload(payload, sysId, compId, seq),
        192 => MagCalReportMessage.fromPayload(payload, sysId, compId, seq),
        193 => EkfStatusReportMessage.fromPayload(payload, sysId, compId, seq),
        77 => CommandAckMessage.fromPayload(payload, sysId, compId, seq),
        148 => AutopilotVersionMessage.fromPayload(payload, sysId, compId, seq),
        158 => MountStatusMessage.fromPayload(payload, sysId, compId, seq),
        168 => WindMessage.fromPayload(payload, sysId, compId, seq),
        241 => VibrationMessage.fromPayload(payload, sysId, compId, seq),
        242 => HomePositionMessage.fromPayload(payload, sysId, compId, seq),
        246 => AdsbVehicleMessage.fromPayload(payload, sysId, compId, seq),
        253 => StatusTextMessage.fromPayload(payload, sysId, compId, seq),
        _ => UnknownMessage(
            messageId: msgId,
            systemId: sysId,
            componentId: compId,
            sequence: seq,
            payload: Uint8List.fromList(payload),
          ),
      };
    } catch (_) {
      // Malformed payload — wrap as unknown
      parseErrors++;
      return UnknownMessage(
        messageId: msgId,
        systemId: sysId,
        componentId: compId,
        sequence: seq,
        payload: Uint8List.fromList(payload),
      );
    }
  }

  /// Take all pending decoded messages and clear the buffer.
  List<MavlinkMessage> takeMessages() {
    final result = List<MavlinkMessage>.from(_pending);
    _pending.clear();
    return result;
  }
}
