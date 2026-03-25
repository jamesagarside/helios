import 'dart:typed_data';
import 'crc.dart';
import 'mavlink_types.dart';

/// Builds MAVLink v2 frames for transmission.
class MavlinkFrameBuilder {
  int _sequence = 0;
  final int systemId;
  final int componentId;

  MavlinkFrameBuilder({
    this.systemId = gcsSystemId,
    this.componentId = gcsComponentId,
  });

  /// Build a complete MAVLink v2 frame.
  Uint8List buildFrame({
    required int messageId,
    required Uint8List payload,
  }) {
    final payloadLen = payload.length;
    final frameSize = mavlinkV2HeaderSize + payloadLen + mavlinkCrcSize;
    final frame = Uint8List(frameSize);

    // Header
    frame[0] = mavlinkV2Magic;
    frame[1] = payloadLen;
    frame[2] = 0; // incompatibility flags
    frame[3] = 0; // compatibility flags
    frame[4] = _sequence++ & 0xFF;
    frame[5] = systemId;
    frame[6] = componentId;
    frame[7] = messageId & 0xFF;
    frame[8] = (messageId >> 8) & 0xFF;
    frame[9] = (messageId >> 16) & 0xFF;

    // Payload
    frame.setRange(mavlinkV2HeaderSize, mavlinkV2HeaderSize + payloadLen, payload);

    // CRC
    final header = Uint8List.sublistView(frame, 0, mavlinkV2HeaderSize);
    final crcExtra = mavlinkCrcExtras[messageId] ?? 0;
    final crc = MavlinkCrc.computeFrameCrc(
      header: header,
      payload: payload,
      crcExtra: crcExtra,
    );
    frame[frameSize - 2] = crc & 0xFF;
    frame[frameSize - 1] = (crc >> 8) & 0xFF;

    return frame;
  }

  /// Build a GCS HEARTBEAT frame.
  Uint8List buildHeartbeat() {
    final payload = Uint8List(9);
    final data = ByteData.sublistView(payload);
    data.setUint32(0, 0, Endian.little); // custom_mode
    payload[4] = MavType.gcs;             // type
    payload[5] = MavAutopilot.invalid;    // autopilot
    payload[6] = 0;                       // base_mode
    payload[7] = MavState.active;         // system_status
    payload[8] = 3;                       // mavlink_version

    return buildFrame(messageId: 0, payload: payload);
  }

  /// Build a COMMAND_LONG frame.
  Uint8List buildCommandLong({
    required int targetSystem,
    required int targetComponent,
    required int command,
    int confirmation = 0,
    double param1 = 0,
    double param2 = 0,
    double param3 = 0,
    double param4 = 0,
    double param5 = 0,
    double param6 = 0,
    double param7 = 0,
  }) {
    final payload = Uint8List(33);
    final data = ByteData.sublistView(payload);
    data.setFloat32(0, param1, Endian.little);
    data.setFloat32(4, param2, Endian.little);
    data.setFloat32(8, param3, Endian.little);
    data.setFloat32(12, param4, Endian.little);
    data.setFloat32(16, param5, Endian.little);
    data.setFloat32(20, param6, Endian.little);
    data.setFloat32(24, param7, Endian.little);
    data.setUint16(28, command, Endian.little);
    payload[30] = targetSystem;
    payload[31] = targetComponent;
    payload[32] = confirmation;

    return buildFrame(messageId: 76, payload: payload);
  }
}
