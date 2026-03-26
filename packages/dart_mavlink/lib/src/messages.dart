import 'dart:typed_data';
import 'mavlink_types.dart';

/// HEARTBEAT (msg_id=0) — vehicle type, autopilot, mode, arm state.
class HeartbeatMessage extends MavlinkMessage {
  HeartbeatMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.type,
    required this.autopilot,
    required this.baseMode,
    required this.customMode,
    required this.systemStatus,
    required this.mavlinkVersion,
  });

  @override
  final int messageId = 0;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int type;
  final int autopilot;
  final int baseMode;
  final int customMode;
  final int systemStatus;
  final int mavlinkVersion;

  bool get armed => (baseMode & MavModeFlag.safetyArmed) != 0;

  factory HeartbeatMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    return HeartbeatMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      customMode: data.getUint32(0, Endian.little),
      type: data.getUint8(4),
      autopilot: data.getUint8(5),
      baseMode: data.getUint8(6),
      systemStatus: data.getUint8(7),
      mavlinkVersion: data.getUint8(8),
    );
  }
}

/// ATTITUDE (msg_id=30) — roll, pitch, yaw and angular rates.
class AttitudeMessage extends MavlinkMessage {
  AttitudeMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.timeBootMs,
    required this.roll,
    required this.pitch,
    required this.yaw,
    required this.rollSpeed,
    required this.pitchSpeed,
    required this.yawSpeed,
  });

  @override
  final int messageId = 30;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int timeBootMs;
  final double roll;
  final double pitch;
  final double yaw;
  final double rollSpeed;
  final double pitchSpeed;
  final double yawSpeed;

  factory AttitudeMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    return AttitudeMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      timeBootMs: data.getUint32(0, Endian.little),
      roll: data.getFloat32(4, Endian.little),
      pitch: data.getFloat32(8, Endian.little),
      yaw: data.getFloat32(12, Endian.little),
      rollSpeed: data.getFloat32(16, Endian.little),
      pitchSpeed: data.getFloat32(20, Endian.little),
      yawSpeed: data.getFloat32(24, Endian.little),
    );
  }
}

/// GLOBAL_POSITION_INT (msg_id=33) — lat/lon/alt.
class GlobalPositionIntMessage extends MavlinkMessage {
  GlobalPositionIntMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.timeBootMs,
    required this.lat,
    required this.lon,
    required this.alt,
    required this.relativeAlt,
    required this.vx,
    required this.vy,
    required this.vz,
    required this.hdg,
  });

  @override
  final int messageId = 33;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int timeBootMs;
  final int lat;   // degE7
  final int lon;   // degE7
  final int alt;   // mm MSL
  final int relativeAlt; // mm above home
  final int vx;    // cm/s
  final int vy;
  final int vz;
  final int hdg;   // cdeg (0-35999)

  /// Latitude in degrees.
  double get latDeg => lat / 1e7;

  /// Longitude in degrees.
  double get lonDeg => lon / 1e7;

  /// Altitude MSL in metres.
  double get altMetres => alt / 1000.0;

  /// Relative altitude in metres.
  double get relAltMetres => relativeAlt / 1000.0;

  /// Heading in degrees (0-359).
  int get headingDeg => hdg ~/ 100;

  factory GlobalPositionIntMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    return GlobalPositionIntMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      timeBootMs: data.getUint32(0, Endian.little),
      lat: data.getInt32(4, Endian.little),
      lon: data.getInt32(8, Endian.little),
      alt: data.getInt32(12, Endian.little),
      relativeAlt: data.getInt32(16, Endian.little),
      vx: data.getInt16(20, Endian.little),
      vy: data.getInt16(22, Endian.little),
      vz: data.getInt16(24, Endian.little),
      hdg: data.getUint16(26, Endian.little),
    );
  }
}

/// GPS_RAW_INT (msg_id=24) — fix type, satellite count, HDOP.
class GpsRawIntMessage extends MavlinkMessage {
  GpsRawIntMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.timeUsec,
    required this.fixType,
    required this.lat,
    required this.lon,
    required this.alt,
    required this.eph,
    required this.epv,
    required this.vel,
    required this.cog,
    required this.satellitesVisible,
  });

  @override
  final int messageId = 24;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int timeUsec;
  final int fixType;
  final int lat;  // degE7
  final int lon;  // degE7
  final int alt;  // mm MSL
  final int eph;  // HDOP * 100
  final int epv;  // VDOP * 100
  final int vel;  // cm/s
  final int cog;  // cdeg
  final int satellitesVisible;

  double get hdop => eph / 100.0;
  double get vdop => epv / 100.0;

  factory GpsRawIntMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    return GpsRawIntMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      timeUsec: data.getUint64(0, Endian.little),
      lat: data.getInt32(8, Endian.little),
      lon: data.getInt32(12, Endian.little),
      alt: data.getInt32(16, Endian.little),
      eph: data.getUint16(20, Endian.little),
      epv: data.getUint16(22, Endian.little),
      vel: data.getUint16(24, Endian.little),
      cog: data.getUint16(26, Endian.little),
      fixType: data.getUint8(28),
      satellitesVisible: data.getUint8(29),
    );
  }
}

/// SYS_STATUS (msg_id=1) — battery voltage, current, remaining.
class SysStatusMessage extends MavlinkMessage {
  SysStatusMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.voltageBattery,
    required this.currentBattery,
    required this.batteryRemaining,
  });

  @override
  final int messageId = 1;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int voltageBattery;   // mV
  final int currentBattery;   // cA (10 * mA)
  final int batteryRemaining; // %, -1 = unknown

  double get voltageVolts => voltageBattery / 1000.0;
  double get currentAmps => currentBattery / 100.0;

  factory SysStatusMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    return SysStatusMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      voltageBattery: data.getUint16(14, Endian.little),
      currentBattery: data.getInt16(16, Endian.little),
      batteryRemaining: data.getInt8(30),
    );
  }
}

/// VFR_HUD (msg_id=74) — airspeed, groundspeed, heading, throttle, climb.
class VfrHudMessage extends MavlinkMessage {
  VfrHudMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.airspeed,
    required this.groundspeed,
    required this.heading,
    required this.throttle,
    required this.alt,
    required this.climb,
  });

  @override
  final int messageId = 74;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final double airspeed;    // m/s
  final double groundspeed; // m/s
  final int heading;        // degrees 0-359
  final int throttle;       // percent 0-100
  final double alt;         // metres MSL
  final double climb;       // m/s

  factory VfrHudMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    return VfrHudMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      airspeed: data.getFloat32(0, Endian.little),
      groundspeed: data.getFloat32(4, Endian.little),
      alt: data.getFloat32(8, Endian.little),
      climb: data.getFloat32(12, Endian.little),
      heading: data.getInt16(16, Endian.little),
      throttle: data.getUint16(18, Endian.little),
    );
  }
}

/// VIBRATION (msg_id=241) — vibration levels and clipping.
class VibrationMessage extends MavlinkMessage {
  VibrationMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.timeUsec,
    required this.vibrationX,
    required this.vibrationY,
    required this.vibrationZ,
    required this.clipping0,
    required this.clipping1,
    required this.clipping2,
  });

  @override
  final int messageId = 241;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int timeUsec;
  final double vibrationX;
  final double vibrationY;
  final double vibrationZ;
  final int clipping0;
  final int clipping1;
  final int clipping2;

  factory VibrationMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    return VibrationMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      timeUsec: data.getUint64(0, Endian.little),
      vibrationX: data.getFloat32(8, Endian.little),
      vibrationY: data.getFloat32(12, Endian.little),
      vibrationZ: data.getFloat32(16, Endian.little),
      clipping0: data.getUint32(20, Endian.little),
      clipping1: data.getUint32(24, Endian.little),
      clipping2: data.getUint32(28, Endian.little),
    );
  }
}

/// STATUSTEXT (msg_id=253) — autopilot text messages.
class StatusTextMessage extends MavlinkMessage {
  StatusTextMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.severity,
    required this.text,
  });

  @override
  final int messageId = 253;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int severity;
  final String text;

  factory StatusTextMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final severity = payload[0];
    // Text is null-terminated, up to 50 chars
    final textBytes = payload.sublist(1);
    final nullIndex = textBytes.indexOf(0);
    final text = String.fromCharCodes(
      nullIndex >= 0 ? textBytes.sublist(0, nullIndex) : textBytes,
    );
    return StatusTextMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      severity: severity,
      text: text,
    );
  }
}

/// COMMAND_ACK (msg_id=77) — command acknowledgement.
class CommandAckMessage extends MavlinkMessage {
  CommandAckMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.command,
    required this.result,
  });

  @override
  final int messageId = 77;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int command;
  final int result;

  bool get accepted => result == 0; // MAV_RESULT_ACCEPTED

  factory CommandAckMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    return CommandAckMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      command: data.getUint16(0, Endian.little),
      result: data.getUint8(2),
    );
  }
}

/// RC_CHANNELS (msg_id=65) — RC input channels.
class RcChannelsMessage extends MavlinkMessage {
  RcChannelsMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.timeBootMs,
    required this.channelCount,
    required this.channels,
    required this.rssi,
  });

  @override
  final int messageId = 65;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int timeBootMs;
  final int channelCount;
  final List<int> channels; // up to 18 channels
  final int rssi;

  factory RcChannelsMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    final channels = <int>[];
    for (var i = 0; i < 18; i++) {
      channels.add(data.getUint16(4 + i * 2, Endian.little));
    }
    return RcChannelsMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      timeBootMs: data.getUint32(0, Endian.little),
      channelCount: data.getUint8(40),
      channels: channels,
      rssi: data.getUint8(41),
    );
  }
}

/// SERVO_OUTPUT_RAW (msg_id=36) — servo/motor outputs.
class ServoOutputRawMessage extends MavlinkMessage {
  ServoOutputRawMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.timeUsec,
    required this.port,
    required this.servos,
  });

  @override
  final int messageId = 36;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int timeUsec;
  final int port;
  final List<int> servos; // up to 16 servos

  factory ServoOutputRawMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    final servos = <int>[];
    // First 8 servos at fixed offsets
    for (var i = 0; i < 8; i++) {
      servos.add(data.getUint16(4 + i * 2, Endian.little));
    }
    // Servos 9-16 if payload is long enough (extended message)
    if (payload.length >= 38) {
      for (var i = 0; i < 8; i++) {
        servos.add(data.getUint16(22 + i * 2, Endian.little));
      }
    }
    return ServoOutputRawMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      timeUsec: data.getUint32(0, Endian.little),
      port: data.getUint8(20),
      servos: servos,
    );
  }
}

/// LOG_ENTRY (msg_id=118) — onboard log metadata.
class LogEntryMessage extends MavlinkMessage {
  LogEntryMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.id,
    required this.numLogs,
    required this.lastLogNum,
    required this.timeUtc,
    required this.size,
  });

  @override
  final int messageId = 118;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int id;
  final int numLogs;
  final int lastLogNum;
  final int timeUtc; // seconds since epoch, 0 if unavailable
  final int size; // bytes

  DateTime? get dateTime =>
      timeUtc > 0 ? DateTime.fromMillisecondsSinceEpoch(timeUtc * 1000, isUtc: true) : null;

  factory LogEntryMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    return LogEntryMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      timeUtc: data.getUint32(0, Endian.little),
      size: data.getUint32(4, Endian.little),
      id: data.getUint16(8, Endian.little),
      numLogs: data.getUint16(10, Endian.little),
      lastLogNum: data.getUint16(12, Endian.little),
    );
  }
}

/// LOG_DATA (msg_id=120) — chunk of log data.
class LogDataMessage extends MavlinkMessage {
  LogDataMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.id,
    required this.ofs,
    required this.count,
    required this.data,
  });

  @override
  final int messageId = 120;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int id;
  final int ofs;
  final int count; // 0 = end of log
  final Uint8List data; // up to 90 bytes

  factory LogDataMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final bd = ByteData.sublistView(payload);
    final ofs = bd.getUint32(0, Endian.little);
    final id = bd.getUint16(4, Endian.little);
    final count = payload[6];
    final logData = count > 0 ? Uint8List.fromList(payload.sublist(7, 7 + count)) : Uint8List(0);

    return LogDataMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      id: id,
      ofs: ofs,
      count: count,
      data: logData,
    );
  }
}

/// MAG_CAL_PROGRESS (msg_id=191) — compass calibration progress.
class MagCalProgressMessage extends MavlinkMessage {
  MagCalProgressMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.compassId,
    required this.calStatus,
    required this.attempt,
    required this.completionPct,
    required this.directionX,
    required this.directionY,
    required this.directionZ,
  });

  @override
  final int messageId = 191;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int compassId;
  final int calStatus;
  final int attempt;
  final int completionPct;
  final double directionX;
  final double directionY;
  final double directionZ;

  factory MagCalProgressMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    return MagCalProgressMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      directionX: data.getFloat32(0, Endian.little),
      directionY: data.getFloat32(4, Endian.little),
      directionZ: data.getFloat32(8, Endian.little),
      compassId: payload[12],
      calStatus: payload[14],
      attempt: payload[15],
      completionPct: payload[16],
    );
  }
}

/// MAG_CAL_REPORT (msg_id=192) — compass calibration result.
class MagCalReportMessage extends MavlinkMessage {
  MagCalReportMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.compassId,
    required this.calStatus,
    required this.autosaved,
    required this.fitness,
  });

  @override
  final int messageId = 192;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int compassId;
  final int calStatus;
  final int autosaved;
  final double fitness; // RMS milligauss residuals

  bool get success => calStatus == 4; // MAG_CAL_SUCCESS
  bool get failed => calStatus == 5;  // MAG_CAL_FAILED

  factory MagCalReportMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    return MagCalReportMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      fitness: data.getFloat32(0, Endian.little),
      compassId: payload[32],
      calStatus: payload[34],
      autosaved: payload[35],
    );
  }
}

/// EKF_STATUS_REPORT (msg_id=193) — EKF health variances.
class EkfStatusReportMessage extends MavlinkMessage {
  EkfStatusReportMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.flags,
    required this.velocityVariance,
    required this.posHorizVariance,
    required this.posVertVariance,
    required this.compassVariance,
    required this.terrainAltVariance,
  });

  @override
  final int messageId = 193;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int flags;
  final double velocityVariance;
  final double posHorizVariance;
  final double posVertVariance;
  final double compassVariance;
  final double terrainAltVariance;

  /// Variance health: <0.5 good, 0.5-0.8 warning, >0.8 bad.
  int healthLevel(double variance) =>
      variance < 0.5 ? 0 : variance < 0.8 ? 1 : 2;

  factory EkfStatusReportMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    return EkfStatusReportMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      velocityVariance: data.getFloat32(0, Endian.little),
      posHorizVariance: data.getFloat32(4, Endian.little),
      posVertVariance: data.getFloat32(8, Endian.little),
      compassVariance: data.getFloat32(12, Endian.little),
      terrainAltVariance: data.getFloat32(16, Endian.little),
      flags: data.getUint16(20, Endian.little),
    );
  }
}

/// PARAM_REQUEST_LIST (msg_id=21) — request all parameters.
class ParamRequestListMessage extends MavlinkMessage {
  ParamRequestListMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.targetSystem,
    required this.targetComponent,
  });

  @override
  final int messageId = 21;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int targetSystem;
  final int targetComponent;

  factory ParamRequestListMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    return ParamRequestListMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      targetSystem: payload[0],
      targetComponent: payload[1],
    );
  }
}

/// PARAM_VALUE (msg_id=22) — parameter name, value, type, count, index.
class ParamValueMessage extends MavlinkMessage {
  ParamValueMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.paramId,
    required this.paramValue,
    required this.paramType,
    required this.paramCount,
    required this.paramIndex,
  });

  @override
  final int messageId = 22;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final String paramId;
  final double paramValue;
  final int paramType; // MAV_PARAM_TYPE
  final int paramCount;
  final int paramIndex;

  factory ParamValueMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    // Wire order: param_value(float), param_count(u16), param_index(u16), param_id(char[16]), param_type(u8)
    final paramValue = data.getFloat32(0, Endian.little);
    final paramCount = data.getUint16(4, Endian.little);
    final paramIndex = data.getUint16(6, Endian.little);
    // param_id is 16 bytes starting at offset 8
    final idBytes = payload.sublist(8, 24);
    final nullIdx = idBytes.indexOf(0);
    final paramId = String.fromCharCodes(
      nullIdx >= 0 ? idBytes.sublist(0, nullIdx) : idBytes,
    );
    final paramType = payload[24];

    return ParamValueMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      paramId: paramId,
      paramValue: paramValue,
      paramType: paramType,
      paramCount: paramCount,
      paramIndex: paramIndex,
    );
  }
}

/// PARAM_SET (msg_id=23) — set a parameter value.
class ParamSetMessage extends MavlinkMessage {
  ParamSetMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.targetSystem,
    required this.targetComponent,
    required this.paramId,
    required this.paramValue,
    required this.paramType,
  });

  @override
  final int messageId = 23;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int targetSystem;
  final int targetComponent;
  final String paramId;
  final double paramValue;
  final int paramType;

  factory ParamSetMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    final paramValue = data.getFloat32(0, Endian.little);
    final targetSystem = payload[4];
    final targetComponent = payload[5];
    final idBytes = payload.sublist(6, 22);
    final nullIdx = idBytes.indexOf(0);
    final paramId = String.fromCharCodes(
      nullIdx >= 0 ? idBytes.sublist(0, nullIdx) : idBytes,
    );
    final paramType = payload[22];

    return ParamSetMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      paramId: paramId,
      paramValue: paramValue,
      paramType: paramType,
    );
  }
}

/// MISSION_CURRENT (msg_id=42) — current active mission item sequence.
class MissionCurrentMessage extends MavlinkMessage {
  MissionCurrentMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.seq,
  });

  @override
  final int messageId = 42;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int seq; // Current waypoint sequence number

  factory MissionCurrentMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seqNum,
  ) {
    final data = ByteData.sublistView(payload);
    return MissionCurrentMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seqNum,
      seq: data.getUint16(0, Endian.little),
    );
  }
}

/// MISSION_REQUEST_LIST (msg_id=43) — request mission item count.
class MissionRequestListMessage extends MavlinkMessage {
  MissionRequestListMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.targetSystem,
    required this.targetComponent,
    this.missionType = 0,
  });

  @override
  final int messageId = 43;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int targetSystem;
  final int targetComponent;
  final int missionType;

  factory MissionRequestListMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    return MissionRequestListMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      targetSystem: payload[0],
      targetComponent: payload[1],
      missionType: payload.length > 2 ? payload[2] : 0,
    );
  }
}

/// MISSION_COUNT (msg_id=44) — number of mission items.
class MissionCountMessage extends MavlinkMessage {
  MissionCountMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.targetSystem,
    required this.targetComponent,
    required this.count,
    this.missionType = 0,
  });

  @override
  final int messageId = 44;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int targetSystem;
  final int targetComponent;
  final int count;
  final int missionType;

  factory MissionCountMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    final data = ByteData.sublistView(payload);
    return MissionCountMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      count: data.getUint16(0, Endian.little),
      targetSystem: payload[2],
      targetComponent: payload[3],
      missionType: payload.length > 4 ? payload[4] : 0,
    );
  }
}

/// MISSION_ACK (msg_id=47) — mission transfer acknowledgement.
class MissionAckMessage extends MavlinkMessage {
  MissionAckMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.targetSystem,
    required this.targetComponent,
    required this.type,
    this.missionType = 0,
  });

  @override
  final int messageId = 47;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int targetSystem;
  final int targetComponent;
  final int type; // MAV_MISSION_RESULT
  final int missionType;

  bool get accepted => type == 0; // MAV_MISSION_RESULT_ACCEPTED

  factory MissionAckMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seq,
  ) {
    return MissionAckMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seq,
      targetSystem: payload[0],
      targetComponent: payload[1],
      type: payload[2],
      missionType: payload.length > 3 ? payload[3] : 0,
    );
  }
}

/// MISSION_REQUEST_INT (msg_id=51) — request a specific mission item.
class MissionRequestIntMessage extends MavlinkMessage {
  MissionRequestIntMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.targetSystem,
    required this.targetComponent,
    required this.seq,
    this.missionType = 0,
  });

  @override
  final int messageId = 51;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int targetSystem;
  final int targetComponent;
  final int seq; // Requested item sequence number
  final int missionType;

  factory MissionRequestIntMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seqNum,
  ) {
    final data = ByteData.sublistView(payload);
    return MissionRequestIntMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seqNum,
      seq: data.getUint16(0, Endian.little),
      targetSystem: payload[2],
      targetComponent: payload[3],
      missionType: payload.length > 4 ? payload[4] : 0,
    );
  }
}

/// MISSION_ITEM_INT (msg_id=73) — mission item with int32 lat/lon.
class MissionItemIntMessage extends MavlinkMessage {
  MissionItemIntMessage({
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.targetSystem,
    required this.targetComponent,
    required this.seq,
    required this.frame,
    required this.command,
    required this.current,
    required this.autocontinue,
    required this.param1,
    required this.param2,
    required this.param3,
    required this.param4,
    required this.x,
    required this.y,
    required this.z,
    this.missionType = 0,
  });

  @override
  final int messageId = 73;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final int targetSystem;
  final int targetComponent;
  final int seq;         // Waypoint sequence number
  final int frame;       // MAV_FRAME
  final int command;     // MAV_CMD
  final int current;     // 0 or 1
  final int autocontinue;
  final double param1;
  final double param2;
  final double param3;
  final double param4;
  final int x;           // Latitude degE7
  final int y;           // Longitude degE7
  final double z;        // Altitude (metres)
  final int missionType;

  double get latDeg => x / 1e7;
  double get lonDeg => y / 1e7;

  factory MissionItemIntMessage.fromPayload(
    Uint8List payload, int sysId, int compId, int seqNum,
  ) {
    final data = ByteData.sublistView(payload);
    return MissionItemIntMessage(
      systemId: sysId,
      componentId: compId,
      sequence: seqNum,
      param1: data.getFloat32(0, Endian.little),
      param2: data.getFloat32(4, Endian.little),
      param3: data.getFloat32(8, Endian.little),
      param4: data.getFloat32(12, Endian.little),
      x: data.getInt32(16, Endian.little),
      y: data.getInt32(20, Endian.little),
      z: data.getFloat32(24, Endian.little),
      seq: data.getUint16(28, Endian.little),
      command: data.getUint16(30, Endian.little),
      targetSystem: payload[32],
      targetComponent: payload[33],
      frame: payload[34],
      current: payload[35],
      autocontinue: payload[36],
      missionType: payload.length > 37 ? payload[37] : 0,
    );
  }
}

/// Unrecognised message — payload preserved for inspection.
class UnknownMessage extends MavlinkMessage {
  UnknownMessage({
    required this.messageId,
    required this.systemId,
    required this.componentId,
    required this.sequence,
    required this.payload,
  });

  @override
  final int messageId;
  @override
  final int systemId;
  @override
  final int componentId;
  @override
  final int sequence;

  final Uint8List payload;
}
