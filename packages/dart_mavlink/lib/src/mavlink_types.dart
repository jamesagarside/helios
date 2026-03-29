/// MAVLink v2 protocol constants and base types.

// CRC extras are auto-generated from MAVLink XML.
// Run: dart run scripts/generate_crc_extras.dart
export 'generated_crc_extras.dart';

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

/// MAV_MISSION_RESULT enumeration.
abstract final class MavMissionResult {
  static const int accepted = 0;
  static const int error = 1;
  static const int unsupportedFrame = 2;
  static const int unsupported = 3;
  static const int noSpace = 4;
  static const int invalid = 5;
  static const int invalidParam1 = 6;
  static const int invalidParam2 = 7;
  static const int invalidParam3 = 8;
  static const int invalidParam4 = 9;
  static const int invalidParam5X = 10;
  static const int invalidParam6Y = 11;
  static const int invalidParam7 = 12;
  static const int invalidSequence = 13;
  static const int denied = 14;
  static const int operationCancelled = 15;
}

/// MAV_MISSION_TYPE enumeration.
abstract final class MavMissionType {
  static const int mission = 0;
  static const int fence = 1;
  static const int rally = 2;
  static const int all = 255;
}

/// MAV_FRAME enumeration (subset).
abstract final class MavFrame {
  static const int global = 0;
  static const int localNed = 1;
  static const int mission = 2;
  static const int globalRelativeAlt = 3;
  static const int globalInt = 5;
  static const int globalRelativeAltInt = 6;
  static const int globalTerrainAlt = 10;
  static const int globalTerrainAltInt = 11;
}

/// MAV_CMD enumeration (subset — mission-relevant commands).
abstract final class MavCmd {
  static const int navWaypoint = 16;
  static const int navLoiterUnlim = 17;
  static const int navLoiterTurns = 18;
  static const int navLoiterTime = 19;
  static const int navReturnToLaunch = 20;
  static const int navLand = 21;
  static const int navTakeoff = 22;
  static const int navLoiterToAlt = 31;
  static const int doSetMode = 176;
  static const int doChangeSpeed = 178;
  static const int doSetHome = 179;
  static const int doSetRelay = 181;
  static const int doSetServo = 183;
  static const int doJump = 177;
  static const int doSetRoiNone = 197;
  static const int doSetRoi = 201;
  static const int doDigicamControl = 203;
  static const int doMountConfigure = 204;
  static const int doMountControl = 205;
  static const int doMotorTest = 209;
  static const int missionStart = 300;
  static const int componentArmDisarm = 400;
  static const int requestMessage = 512;
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
