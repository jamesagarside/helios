/// DuckDB schema definitions for flight telemetry recording.
///
/// Each flight creates a fresh .duckdb file with these tables.
abstract final class HeliosSchema {
  static const int version = 1;

  static const createFlightMeta = '''
    CREATE TABLE IF NOT EXISTS flight_meta (
      key   VARCHAR PRIMARY KEY,
      value VARCHAR NOT NULL
    );
  ''';

  static const createAttitude = '''
    CREATE TABLE IF NOT EXISTS attitude (
      ts         TIMESTAMP NOT NULL,
      roll       DOUBLE NOT NULL,
      pitch      DOUBLE NOT NULL,
      yaw        DOUBLE NOT NULL,
      roll_spd   DOUBLE,
      pitch_spd  DOUBLE,
      yaw_spd    DOUBLE
    );
  ''';

  static const createGps = '''
    CREATE TABLE IF NOT EXISTS gps (
      ts         TIMESTAMP NOT NULL,
      lat        DOUBLE NOT NULL,
      lon        DOUBLE NOT NULL,
      alt_msl    DOUBLE NOT NULL,
      alt_rel    DOUBLE NOT NULL,
      fix_type   TINYINT NOT NULL,
      satellites TINYINT NOT NULL,
      hdop       DOUBLE NOT NULL,
      vdop       DOUBLE,
      vel        DOUBLE,
      cog        DOUBLE
    );
  ''';

  static const createBattery = '''
    CREATE TABLE IF NOT EXISTS battery (
      ts              TIMESTAMP NOT NULL,
      voltage         DOUBLE NOT NULL,
      current_a       DOUBLE,
      remaining_pct   TINYINT,
      consumed_mah    DOUBLE
    );
  ''';

  static const createVfrHud = '''
    CREATE TABLE IF NOT EXISTS vfr_hud (
      ts           TIMESTAMP NOT NULL,
      airspeed     DOUBLE NOT NULL,
      groundspeed  DOUBLE NOT NULL,
      heading      SMALLINT NOT NULL,
      throttle     SMALLINT NOT NULL,
      climb        DOUBLE NOT NULL
    );
  ''';

  static const createVibration = '''
    CREATE TABLE IF NOT EXISTS vibration (
      ts      TIMESTAMP NOT NULL,
      vibe_x  DOUBLE NOT NULL,
      vibe_y  DOUBLE NOT NULL,
      vibe_z  DOUBLE NOT NULL,
      clip_0  INTEGER NOT NULL,
      clip_1  INTEGER NOT NULL,
      clip_2  INTEGER NOT NULL
    );
  ''';

  static const createEvents = '''
    CREATE TABLE IF NOT EXISTS events (
      ts       TIMESTAMP NOT NULL,
      type     VARCHAR NOT NULL,
      detail   VARCHAR NOT NULL,
      severity TINYINT DEFAULT 6
    );
  ''';

  static const createRcChannels = '''
    CREATE TABLE IF NOT EXISTS rc_channels (
      ts    TIMESTAMP NOT NULL,
      ch1   SMALLINT, ch2   SMALLINT, ch3   SMALLINT, ch4   SMALLINT,
      ch5   SMALLINT, ch6   SMALLINT, ch7   SMALLINT, ch8   SMALLINT,
      ch9   SMALLINT, ch10  SMALLINT, ch11  SMALLINT, ch12  SMALLINT,
      ch13  SMALLINT, ch14  SMALLINT, ch15  SMALLINT, ch16  SMALLINT,
      rssi  TINYINT
    );
  ''';

  static const createServoOutput = '''
    CREATE TABLE IF NOT EXISTS servo_output (
      ts    TIMESTAMP NOT NULL,
      srv1  SMALLINT, srv2  SMALLINT, srv3  SMALLINT, srv4  SMALLINT,
      srv5  SMALLINT, srv6  SMALLINT, srv7  SMALLINT, srv8  SMALLINT
    );
  ''';

  static const createMissions = '''
    CREATE TABLE IF NOT EXISTS missions (
      ts          TIMESTAMP NOT NULL,
      direction   VARCHAR NOT NULL,
      seq         SMALLINT NOT NULL,
      frame       TINYINT NOT NULL,
      command     SMALLINT NOT NULL,
      param1      DOUBLE,
      param2      DOUBLE,
      param3      DOUBLE,
      param4      DOUBLE,
      lat         DOUBLE NOT NULL,
      lon         DOUBLE NOT NULL,
      alt         DOUBLE NOT NULL,
      autocont    TINYINT NOT NULL
    );
  ''';

  static const allTables = [
    createFlightMeta,
    createAttitude,
    createGps,
    createBattery,
    createVfrHud,
    createVibration,
    createEvents,
    createRcChannels,
    createServoOutput,
    createMissions,
  ];
}

/// DuckDB schema definitions for MSP (Multiwii Serial Protocol) telemetry.
///
/// MSP is used by Betaflight/Cleanflight flight controllers. These tables
/// are created alongside the MAVLink tables in every flight database so that
/// a single .duckdb file can hold data from either protocol (or both).
abstract final class HeliosMspSchema {
  static const createMspAttitude = '''
    CREATE TABLE IF NOT EXISTS msp_attitude (
      ts      TIMESTAMP NOT NULL,
      roll    DOUBLE NOT NULL,    -- degrees (raw from MSP, not radians)
      pitch   DOUBLE NOT NULL,    -- degrees
      heading SMALLINT NOT NULL   -- degrees
    );
  ''';

  static const createMspGps = '''
    CREATE TABLE IF NOT EXISTS msp_gps (
      ts         TIMESTAMP NOT NULL,
      fix_type   TINYINT NOT NULL,   -- 0=none, 1=2D, 2=3D
      num_sat    TINYINT NOT NULL,
      lat        DOUBLE NOT NULL,
      lon        DOUBLE NOT NULL,
      altitude_m DOUBLE NOT NULL,
      speed_ms   DOUBLE NOT NULL,    -- m/s
      course_deg DOUBLE NOT NULL     -- degrees
    );
  ''';

  static const createMspAnalog = '''
    CREATE TABLE IF NOT EXISTS msp_analog (
      ts              TIMESTAMP NOT NULL,
      voltage_v       DOUBLE NOT NULL,
      current_a       DOUBLE,
      consumed_mah    DOUBLE,
      remaining_pct   TINYINT,
      rssi            SMALLINT        -- 0-255
    );
  ''';

  static const createMspStatus = '''
    CREATE TABLE IF NOT EXISTS msp_status (
      ts                 TIMESTAMP NOT NULL,
      armed              BOOLEAN NOT NULL,
      flight_mode_flags  INTEGER NOT NULL,
      flight_mode_name   VARCHAR,
      sensors_ok         BOOLEAN NOT NULL,
      cycle_time_us      INTEGER
    );
  ''';

  static const createMspAltitude = '''
    CREATE TABLE IF NOT EXISTS msp_altitude (
      ts              TIMESTAMP NOT NULL,
      altitude_rel_m  DOUBLE NOT NULL,   -- metres above home
      climb_ms        DOUBLE NOT NULL    -- m/s (positive = climbing)
    );
  ''';

  static const createMspRc = '''
    CREATE TABLE IF NOT EXISTS msp_rc (
      ts    TIMESTAMP NOT NULL,
      ch1   SMALLINT, ch2   SMALLINT, ch3   SMALLINT, ch4   SMALLINT,
      ch5   SMALLINT, ch6   SMALLINT, ch7   SMALLINT, ch8   SMALLINT,
      ch9   SMALLINT, ch10  SMALLINT, ch11  SMALLINT, ch12  SMALLINT,
      ch13  SMALLINT, ch14  SMALLINT, ch15  SMALLINT, ch16  SMALLINT
    );
  ''';

  static const allTables = [
    createMspAttitude,
    createMspGps,
    createMspAnalog,
    createMspStatus,
    createMspAltitude,
    createMspRc,
  ];
}
