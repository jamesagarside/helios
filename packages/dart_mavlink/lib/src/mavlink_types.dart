/// MAVLink v2 protocol constants and base types.

/// MAVLink v2 start-of-frame marker.
const int mavlinkV2Magic = 0xFD;

/// MAVLink v1 start-of-frame marker (legacy).
const int mavlinkV1Magic = 0xFE;

/// MAVLink v2 header size (STX + 9 header bytes).
const int mavlinkV2HeaderSize = 10;

/// MAVLink v1 header size.
const int mavlinkV1HeaderSize = 6;

/// MAVLink CRC size (2 bytes).
const int mavlinkCrcSize = 2;

/// MAVLink v2 signature size (13 bytes, optional).
const int mavlinkV2SignatureSize = 13;

/// Maximum MAVLink v2 payload size.
const int mavlinkV2MaxPayload = 255;

/// GCS system ID (convention).
const int gcsSystemId = 255;

/// GCS component ID (MAV_COMP_ID_MISSIONPLANNER).
const int gcsComponentId = 190;

/// Incompatibility flag: frame is signed.
const int mavlinkIflagSigned = 0x01;

/// Base class for all decoded MAVLink messages.
abstract class MavlinkMessage {
  /// MAVLink message ID.
  int get messageId;

  /// Source system ID.
  int get systemId;

  /// Source component ID.
  int get componentId;

  /// Sequence number.
  int get sequence;
}

/// CRC extra values for each message ID.
/// These are derived from the message field definitions.
/// Reference: https://mavlink.io/en/guide/serialization.html#crc_extra
const Map<int, int> mavlinkCrcExtras = {
  0: 50,    // HEARTBEAT
  1: 124,   // SYS_STATUS
  24: 24,   // GPS_RAW_INT
  30: 39,   // ATTITUDE
  33: 104,  // GLOBAL_POSITION_INT
  36: 222,  // SERVO_OUTPUT_RAW
  44: 159,  // MISSION_COUNT
  47: 153,  // MISSION_ACK
  51: 196,  // MISSION_REQUEST_INT
  65: 118,  // RC_CHANNELS
  73: 38,   // MISSION_ITEM_INT
  74: 20,   // VFR_HUD
  76: 152,  // COMMAND_LONG
  77: 143,  // COMMAND_ACK
  147: 154, // BATTERY_STATUS
  241: 90,  // VIBRATION
  253: 83,  // STATUSTEXT
};

/// MAV_TYPE enumeration (subset).
abstract final class MavType {
  static const int generic = 0;
  static const int fixedWing = 1;
  static const int quadrotor = 2;
  static const int helicopter = 4;
  static const int groundRover = 10;
  static const int boat = 11;
  static const int vtol = 19;
  static const int gcs = 6;
}

/// MAV_AUTOPILOT enumeration (subset).
abstract final class MavAutopilot {
  static const int generic = 0;
  static const int ardupilotmega = 3;
  static const int px4 = 12;
  static const int invalid = 8;
}

/// MAV_MODE_FLAG bits.
abstract final class MavModeFlag {
  static const int safetyArmed = 128;
  static const int manualInputEnabled = 64;
  static const int guidedEnabled = 8;
  static const int autoEnabled = 4;
}

/// MAV_STATE enumeration.
abstract final class MavState {
  static const int uninit = 0;
  static const int boot = 1;
  static const int calibrating = 2;
  static const int standby = 3;
  static const int active = 4;
  static const int critical = 5;
  static const int emergency = 6;
}

/// MAV_SEVERITY for STATUSTEXT.
abstract final class MavSeverity {
  static const int emergency = 0;
  static const int alert = 1;
  static const int critical = 2;
  static const int error = 3;
  static const int warning = 4;
  static const int notice = 5;
  static const int info = 6;
  static const int debug = 7;
}
