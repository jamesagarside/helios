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

  /// Build a LOG_REQUEST_LIST frame (msg_id=117).
  Uint8List buildLogRequestList({
    required int targetSystem,
    required int targetComponent,
    int start = 0,
    int end = 0xFFFF,
  }) {
    final payload = Uint8List(6);
    final data = ByteData.sublistView(payload);
    data.setUint16(0, start, Endian.little);
    data.setUint16(2, end, Endian.little);
    payload[4] = targetSystem;
    payload[5] = targetComponent;
    return buildFrame(messageId: 117, payload: payload);
  }

  /// Build a LOG_REQUEST_DATA frame (msg_id=119).
  Uint8List buildLogRequestData({
    required int targetSystem,
    required int targetComponent,
    required int logId,
    required int offset,
    required int count,
  }) {
    final payload = Uint8List(12);
    final data = ByteData.sublistView(payload);
    data.setUint32(0, offset, Endian.little);
    data.setUint32(4, count, Endian.little);
    data.setUint16(8, logId, Endian.little);
    payload[10] = targetSystem;
    payload[11] = targetComponent;
    return buildFrame(messageId: 119, payload: payload);
  }

  /// Build a LOG_REQUEST_END frame (msg_id=122).
  Uint8List buildLogRequestEnd({
    required int targetSystem,
    required int targetComponent,
  }) {
    final payload = Uint8List(2);
    payload[0] = targetSystem;
    payload[1] = targetComponent;
    return buildFrame(messageId: 122, payload: payload);
  }

  /// Build a PARAM_REQUEST_LIST frame (msg_id=21).
  Uint8List buildParamRequestList({
    required int targetSystem,
    required int targetComponent,
  }) {
    final payload = Uint8List(2);
    payload[0] = targetSystem;
    payload[1] = targetComponent;
    return buildFrame(messageId: 21, payload: payload);
  }

  /// Build a PARAM_SET frame (msg_id=23).
  Uint8List buildParamSet({
    required int targetSystem,
    required int targetComponent,
    required String paramId,
    required double paramValue,
    int paramType = 9, // MAV_PARAM_TYPE_REAL32
  }) {
    final payload = Uint8List(23);
    final data = ByteData.sublistView(payload);
    // Wire order: param_value(float), target_system, target_component, param_id(char[16]), param_type
    data.setFloat32(0, paramValue, Endian.little);
    payload[4] = targetSystem;
    payload[5] = targetComponent;
    // Write param_id (up to 16 chars, null-padded)
    final idBytes = paramId.codeUnits;
    for (var i = 0; i < 16 && i < idBytes.length; i++) {
      payload[6 + i] = idBytes[i];
    }
    payload[22] = paramType;
    return buildFrame(messageId: 23, payload: payload);
  }

  /// Build a REQUEST_DATA_STREAM frame (msg_id=66).
  ///
  /// Used to request specific telemetry streams at a given rate from ArduPilot.
  /// Stream IDs: 0=ALL, 1=RAW_SENSORS, 2=EXTENDED_STATUS, 3=RC_CHANNELS,
  /// 4=RAW_CONTROLLER, 6=POSITION, 10=EXTRA1(attitude), 11=EXTRA2(VFR_HUD), 12=EXTRA3
  Uint8List buildRequestDataStream({
    required int targetSystem,
    required int targetComponent,
    required int streamId,
    required int messageRate,
    int startStop = 1,
  }) {
    final payload = Uint8List(6);
    final data = ByteData.sublistView(payload);
    data.setUint16(0, messageRate, Endian.little);
    payload[2] = targetSystem;
    payload[3] = targetComponent;
    payload[4] = streamId;
    payload[5] = startStop;
    return buildFrame(messageId: 66, payload: payload);
  }

  /// Build a MISSION_REQUEST_LIST frame (msg_id=43).
  Uint8List buildMissionRequestList({
    required int targetSystem,
    required int targetComponent,
    int missionType = 0,
  }) {
    final payload = Uint8List(3);
    payload[0] = targetSystem;
    payload[1] = targetComponent;
    payload[2] = missionType;
    return buildFrame(messageId: 43, payload: payload);
  }

  /// Build a MISSION_COUNT frame (msg_id=44).
  Uint8List buildMissionCount({
    required int targetSystem,
    required int targetComponent,
    required int count,
    int missionType = 0,
  }) {
    final payload = Uint8List(5);
    final data = ByteData.sublistView(payload);
    data.setUint16(0, count, Endian.little);
    payload[2] = targetSystem;
    payload[3] = targetComponent;
    payload[4] = missionType;
    return buildFrame(messageId: 44, payload: payload);
  }

  /// Build a MISSION_ACK frame (msg_id=47).
  Uint8List buildMissionAck({
    required int targetSystem,
    required int targetComponent,
    required int type,
    int missionType = 0,
  }) {
    final payload = Uint8List(4);
    payload[0] = targetSystem;
    payload[1] = targetComponent;
    payload[2] = type;
    payload[3] = missionType;
    return buildFrame(messageId: 47, payload: payload);
  }

  /// Build a MISSION_REQUEST_INT frame (msg_id=51).
  Uint8List buildMissionRequestInt({
    required int targetSystem,
    required int targetComponent,
    required int seq,
    int missionType = 0,
  }) {
    final payload = Uint8List(5);
    final data = ByteData.sublistView(payload);
    data.setUint16(0, seq, Endian.little);
    payload[2] = targetSystem;
    payload[3] = targetComponent;
    payload[4] = missionType;
    return buildFrame(messageId: 51, payload: payload);
  }

  /// Build a MISSION_ITEM_INT frame (msg_id=73).
  Uint8List buildMissionItemInt({
    required int targetSystem,
    required int targetComponent,
    required int seq,
    required int frame,
    required int command,
    required int current,
    required int autocontinue,
    required double param1,
    required double param2,
    required double param3,
    required double param4,
    required int x,
    required int y,
    required double z,
    int missionType = 0,
  }) {
    final payload = Uint8List(38);
    final data = ByteData.sublistView(payload);
    data.setFloat32(0, param1, Endian.little);
    data.setFloat32(4, param2, Endian.little);
    data.setFloat32(8, param3, Endian.little);
    data.setFloat32(12, param4, Endian.little);
    data.setInt32(16, x, Endian.little);
    data.setInt32(20, y, Endian.little);
    data.setFloat32(24, z, Endian.little);
    data.setUint16(28, seq, Endian.little);
    data.setUint16(30, command, Endian.little);
    payload[32] = targetSystem;
    payload[33] = targetComponent;
    payload[34] = frame;
    payload[35] = current;
    payload[36] = autocontinue;
    payload[37] = missionType;
    return buildFrame(messageId: 73, payload: payload);
  }

  /// Build a SET_POSITION_TARGET_GLOBAL_INT frame (msg_id=86).
  ///
  /// Sends an absolute position target in the global frame.
  /// [coordinateFrame] 6 = MAV_FRAME_GLOBAL_RELATIVE_ALT_INT (alt AGL).
  /// [typeMask] 0x0DF8 = position-only (ignore velocity, accel, yaw).
  Uint8List buildSetPositionTargetGlobalInt({
    required int targetSystem,
    required int targetComponent,
    required int latInt,
    required int lonInt,
    required double altM,
    int coordinateFrame = 6,
    int typeMask = 0x0DF8,
  }) {
    final payload = Uint8List(53);
    final data = ByteData.sublistView(payload);
    data.setUint32(0, 0, Endian.little);         // time_boot_ms
    data.setInt32(4, latInt, Endian.little);      // lat_int (1e7 deg)
    data.setInt32(8, lonInt, Endian.little);      // lon_int (1e7 deg)
    data.setFloat32(12, altM, Endian.little);     // alt (m)
    data.setFloat32(16, 0, Endian.little);        // vx
    data.setFloat32(20, 0, Endian.little);        // vy
    data.setFloat32(24, 0, Endian.little);        // vz
    data.setFloat32(28, 0, Endian.little);        // afx
    data.setFloat32(32, 0, Endian.little);        // afy
    data.setFloat32(36, 0, Endian.little);        // afz
    data.setFloat32(40, 0, Endian.little);        // yaw
    data.setFloat32(44, 0, Endian.little);        // yaw_rate
    data.setUint16(48, typeMask, Endian.little);  // type_mask
    payload[50] = targetSystem;
    payload[51] = targetComponent;
    payload[52] = coordinateFrame;
    return buildFrame(messageId: 86, payload: payload);
  }

  /// Build a RC_CHANNELS_OVERRIDE frame (msg_id=70, CRC=124).
  ///
  /// Channel values in microseconds (1000–2000 µs, center 1500).
  /// Pass 0 for channels that should not override (uses UINT16_MAX=65535 in wire format).
  /// [ch1] Roll, [ch2] Pitch, [ch3] Throttle, [ch4] Yaw.
  Uint8List buildRcChannelsOverride({
    required int targetSystem,
    required int targetComponent,
    int ch1 = 0,
    int ch2 = 0,
    int ch3 = 0,
    int ch4 = 0,
    int ch5 = 0,
    int ch6 = 0,
    int ch7 = 0,
    int ch8 = 0,
  }) {
    int toWire(int v) => v == 0 ? 65535 : v.clamp(1000, 2000);
    final payload = Uint8List(18);
    final data = ByteData.sublistView(payload);
    data.setUint16(0,  toWire(ch1), Endian.little);
    data.setUint16(2,  toWire(ch2), Endian.little);
    data.setUint16(4,  toWire(ch3), Endian.little);
    data.setUint16(6,  toWire(ch4), Endian.little);
    data.setUint16(8,  toWire(ch5), Endian.little);
    data.setUint16(10, toWire(ch6), Endian.little);
    data.setUint16(12, toWire(ch7), Endian.little);
    data.setUint16(14, toWire(ch8), Endian.little);
    payload[16] = targetSystem;
    payload[17] = targetComponent;
    return buildFrame(messageId: 70, payload: payload);
  }
}
