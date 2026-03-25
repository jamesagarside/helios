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
