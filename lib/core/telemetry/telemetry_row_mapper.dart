import 'package:dart_mavlink/dart_mavlink.dart';

/// Centralised mapping from telemetry messages to table rows.
///
/// Previously every flush built `INSERT INTO <table> VALUES (...)` strings by
/// hand, restating each table's column order inline. Renaming or reordering a
/// column meant editing order-sensitive string interpolation in several
/// places. This mapper owns the row shape for each table in one spot: each
/// `*RowValues` method emits the positional VALUES tuple, and
/// [insertStatement] qualifies it with an explicit column list from
/// `columns.dart`, so a column rename is a single edit the analyzer enforces.
abstract final class TelemetryRowMapper {
  /// Build `INSERT INTO <table> (<cols>) VALUES <tuples>` for [table].
  ///
  /// [columns] is the ordered column list (single source of truth) and each
  /// entry of [tuples] is a pre-rendered `(v0, v1, ...)` matching that order.
  /// The explicit column list makes the statement robust to future schema
  /// additions and self-documenting at the call site.
  static String insertStatement(
    String table,
    List<String> columns,
    List<String> tuples,
  ) {
    final colList = columns.join(', ');
    return 'INSERT INTO $table ($colList) VALUES ${tuples.join(', ')}';
  }

  // ─── VALUES tuple builders (one per table) ────────────────────────────────

  /// `attitude` row from an ATTITUDE message at [ts] (ISO, space-separated).
  static String attitude(String ts, AttitudeMessage m) =>
      "('$ts', ${m.roll}, ${m.pitch}, ${m.yaw}, "
      '${m.rollSpeed}, ${m.pitchSpeed}, ${m.yawSpeed})';

  /// `gps` row: GLOBAL_POSITION_INT position stamped with the latest
  /// GPS_RAW_INT quality. [rawGps] is null until the first GPS_RAW_INT arrives,
  /// in which case the quality columns are written NULL rather than fabricated.
  /// UINT16_MAX (0xFFFF) sentinels in the raw message also map to NULL.
  static String gps(
    String ts,
    GlobalPositionIntMessage pos,
    GpsRawIntMessage? rawGps,
  ) {
    final fixType = rawGps != null ? '${rawGps.fixType}' : 'NULL';
    final sats = rawGps != null ? '${rawGps.satellitesVisible}' : 'NULL';
    final hdop =
        rawGps != null && rawGps.eph != 0xFFFF ? '${rawGps.hdop}' : 'NULL';
    final vdop =
        rawGps != null && rawGps.epv != 0xFFFF ? '${rawGps.vdop}' : 'NULL';
    final vel = rawGps != null && rawGps.vel != 0xFFFF
        ? '${rawGps.vel / 100.0}'
        : 'NULL';
    final cog = rawGps != null && rawGps.cog != 0xFFFF
        ? '${rawGps.cog / 100.0}'
        : 'NULL';
    return "('$ts', ${pos.latDeg}, ${pos.lonDeg}, ${pos.altMetres}, "
        '${pos.relAltMetres}, $fixType, $sats, $hdop, $vdop, $vel, $cog)';
  }

  /// `battery` row from a SYS_STATUS message. consumed_mah is not carried by
  /// SYS_STATUS, so it is recorded as 0.
  static String battery(String ts, SysStatusMessage m) =>
      "('$ts', ${m.voltageVolts}, ${m.currentAmps}, ${m.batteryRemaining}, 0)";

  /// `vfr_hud` row from a VFR_HUD message.
  static String vfrHud(String ts, VfrHudMessage m) =>
      "('$ts', ${m.airspeed}, ${m.groundspeed}, "
      '${m.heading}, ${m.throttle}, ${m.climb})';

  /// `vibration` row from a VIBRATION message.
  static String vibration(String ts, VibrationMessage m) =>
      "('$ts', ${m.vibrationX}, ${m.vibrationY}, ${m.vibrationZ}, "
      '${m.clipping0}, ${m.clipping1}, ${m.clipping2})';

  /// `events` row. [type] and [detail] are escaped for SQL string literals.
  static String event(String ts, String type, String detail, int severity) {
    final t = type.replaceAll("'", "''");
    final d = detail.replaceAll("'", "''");
    return "('$ts', '$t', '$d', $severity)";
  }
}
