/// Single source of truth for flight-recording table and column names.
///
/// Every telemetry module (recorder, forensics, replay, analytics templates,
/// NL→SQL) referred to these names as inline string literals, so renaming a
/// column silently broke several call sites. They are now defined once here
/// and the schema `CREATE TABLE` definitions in `schema.dart` are built from
/// the same constants, so a rename is a single edit that the analyzer and the
/// schema-consistency test enforce everywhere.
///
/// Naming convention: one `abstract final class` per table. `table` is the SQL
/// table name; each remaining constant is a column name. The `columns` list is
/// the ordered tuple used for positional `INSERT INTO <table> VALUES (...)`.
library;

/// `flight_meta` — key/value metadata, one row per key.
abstract final class FlightMetaColumns {
  static const table = 'flight_meta';
  static const key = 'key';
  static const value = 'value';
}

/// `attitude` — ATTITUDE messages (radians).
abstract final class AttitudeColumns {
  static const table = 'attitude';
  static const ts = 'ts';
  static const roll = 'roll';
  static const pitch = 'pitch';
  static const yaw = 'yaw';
  static const rollSpd = 'roll_spd';
  static const pitchSpd = 'pitch_spd';
  static const yawSpd = 'yaw_spd';

  static const columns = [ts, roll, pitch, yaw, rollSpd, pitchSpd, yawSpd];
}

/// `gps` — GLOBAL_POSITION_INT position stamped with GPS_RAW_INT quality.
abstract final class GpsColumns {
  static const table = 'gps';
  static const ts = 'ts';
  static const lat = 'lat';
  static const lon = 'lon';
  static const altMsl = 'alt_msl';
  static const altRel = 'alt_rel';
  static const fixType = 'fix_type';
  static const satellites = 'satellites';
  static const hdop = 'hdop';
  static const vdop = 'vdop';
  static const vel = 'vel';
  static const cog = 'cog';

  static const columns = [
    ts,
    lat,
    lon,
    altMsl,
    altRel,
    fixType,
    satellites,
    hdop,
    vdop,
    vel,
    cog,
  ];
}

/// `battery` — SYS_STATUS battery telemetry.
abstract final class BatteryColumns {
  static const table = 'battery';
  static const ts = 'ts';
  static const voltage = 'voltage';
  static const currentA = 'current_a';
  static const remainingPct = 'remaining_pct';
  static const consumedMah = 'consumed_mah';

  static const columns = [ts, voltage, currentA, remainingPct, consumedMah];
}

/// `vfr_hud` — VFR_HUD speeds, heading, throttle, climb.
abstract final class VfrHudColumns {
  static const table = 'vfr_hud';
  static const ts = 'ts';
  static const airspeed = 'airspeed';
  static const groundspeed = 'groundspeed';
  static const heading = 'heading';
  static const throttle = 'throttle';
  static const climb = 'climb';

  static const columns = [ts, airspeed, groundspeed, heading, throttle, climb];
}

/// `vibration` — VIBRATION axes and accelerometer clip counters.
abstract final class VibrationColumns {
  static const table = 'vibration';
  static const ts = 'ts';
  static const vibeX = 'vibe_x';
  static const vibeY = 'vibe_y';
  static const vibeZ = 'vibe_z';
  static const clip0 = 'clip_0';
  static const clip1 = 'clip_1';
  static const clip2 = 'clip_2';

  static const columns = [ts, vibeX, vibeY, vibeZ, clip0, clip1, clip2];
}

/// `events` — discrete events (mode changes, STATUSTEXT, etc.).
abstract final class EventsColumns {
  static const table = 'events';
  static const ts = 'ts';
  static const type = 'type';
  static const detail = 'detail';
  static const severity = 'severity';

  static const columns = [ts, type, detail, severity];
}

/// `rc_channels` — RC_CHANNELS 16 channels + RSSI.
abstract final class RcChannelsColumns {
  static const table = 'rc_channels';
  static const ts = 'ts';
}

/// `servo_output` — SERVO_OUTPUT_RAW 8 servos.
abstract final class ServoOutputColumns {
  static const table = 'servo_output';
  static const ts = 'ts';
}

/// `missions` — mission snapshots (upload/download).
abstract final class MissionsColumns {
  static const table = 'missions';
  static const ts = 'ts';
  static const direction = 'direction';
  static const seq = 'seq';
  static const frame = 'frame';
  static const command = 'command';
  static const param1 = 'param1';
  static const param2 = 'param2';
  static const param3 = 'param3';
  static const param4 = 'param4';
  static const lat = 'lat';
  static const lon = 'lon';
  static const alt = 'alt';
  static const autocont = 'autocont';

  static const columns = [
    ts,
    direction,
    seq,
    frame,
    command,
    param1,
    param2,
    param3,
    param4,
    lat,
    lon,
    alt,
    autocont,
  ];
}
