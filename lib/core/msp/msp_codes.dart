/// MSP (MultiWii Serial Protocol) command codes.
///
/// Covers identification, telemetry reads, and outbound commands for
/// Betaflight / iNav flight controllers.
abstract final class MspCodes {
  // ---------------------------------------------------------------------------
  // Identification
  // ---------------------------------------------------------------------------

  /// MSP_API_VERSION — protocol API version tuple.
  static const int apiVersion = 1;

  /// MSP_FC_VARIANT — 4-byte ASCII FC identifier ("BTFL", "INAV", …).
  static const int fcVariant = 2;

  /// MSP_FC_VERSION — major / minor / patch version bytes.
  static const int fcVersion = 3;

  /// MSP_BOARD_INFO — board identifier and hardware revision.
  static const int boardInfo = 4;

  /// MSP_BUILD_INFO — build date / time / git revision ASCII strings.
  static const int buildInfo = 5;

  // ---------------------------------------------------------------------------
  // Telemetry reads
  // ---------------------------------------------------------------------------

  /// MSP_STATUS — armed flags, active flight-mode bitmask, sensor health.
  static const int status = 101;

  /// MSP_RAW_IMU — raw accelerometer, gyro, and magnetometer readings.
  static const int rawImu = 102;

  /// MSP_RC — RC channel values, up to 16 × uint16 LE.
  static const int rc = 105;

  /// MSP_RAW_GPS — fix type, satellite count, lat/lon/alt/speed/course.
  static const int rawGps = 106;

  /// MSP_ATTITUDE — roll (int16 × 10 = deg), pitch (int16 × 10 = deg),
  /// heading (int16 = deg).
  static const int attitude = 108;

  /// MSP_ALTITUDE — estimated altitude in cm (int32 LE), vario in cm/s
  /// (int16 LE).
  static const int altitude = 109;

  /// MSP_ANALOG — vbat in 0.1 V units (uint8), mAh consumed (uint16 LE),
  /// RSSI 0-1023 (uint16 LE), amperage in 0.01 A units (int16 LE).
  static const int analog = 110;

  /// MSP_BOX_NAMES — flight-mode box names, semicolon-delimited ASCII.
  static const int boxNames = 116;

  /// MSP_BOX_IDS — box permanent-ID mapping (parallel array to boxNames).
  static const int boxIds = 119;

  /// MSP_BATTERY_STATE — Betaflight 3.1+ extended battery info:
  /// cell count, capacity, voltage, mAh drawn, current, remaining %.
  static const int batteryState = 130;

  /// MSP_STATUS_EX — extended status (includes CPU load, task count).
  static const int statusEx = 150;

  // ---------------------------------------------------------------------------
  // Commands (outbound)
  // ---------------------------------------------------------------------------

  /// MSP_SET_RAW_RC — write raw RC channel overrides (16 × uint16 LE).
  static const int setRawRc = 200;
}
