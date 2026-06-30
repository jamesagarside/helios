import 'columns.dart';

/// Result of a natural-language-to-SQL translation.
class NlQueryResult {
  const NlQueryResult({required this.sql, required this.description});

  final String sql;
  final String description;
}

/// Pattern-based NL→SQL translator for Helios flight telemetry.
///
/// No external API required — all translation is done via keyword matching
/// against the known Helios DuckDB schema.
///
/// Usage:
/// ```dart
/// const service = NlQueryService();
/// final result = service.translate('max altitude');
/// if (result != null) {
///   print(result.sql);         // SELECT ROUND(MAX(alt_rel), 1) …
///   print(result.description); // Maximum altitude above home
/// }
/// ```
class NlQueryService {
  const NlQueryService();

  /// Translates a natural-language flight query into a DuckDB SQL statement.
  ///
  /// Returns `null` when no pattern matches the input.
  NlQueryResult? translate(String input) {
    final t = input.toLowerCase().trim();
    if (t.isEmpty) return null;

    // ── Summary / overview ────────────────────────────────────────────────
    if (_has(t, ['summary', 'statistics', 'stats', 'overview'])) {
      return const NlQueryResult(
        sql: '''
SELECT
  ROUND((EPOCH(MAX(${GpsColumns.ts})) - EPOCH(MIN(${GpsColumns.ts}))), 0) AS duration_sec,
  ROUND(MAX(${GpsColumns.altRel}), 1) AS max_alt_m,
  ROUND(AVG(${GpsColumns.altRel}), 1) AS avg_alt_m,
  COUNT(*) AS gps_samples
FROM ${GpsColumns.table}''',
        description: 'Flight summary: duration, max/avg altitude, sample count',
      );
    }

    // ── Events / log ─────────────────────────────────────────────────────
    if (_has(t, ['events', 'log', 'messages', 'alerts', 'what happened'])) {
      return const NlQueryResult(
        sql: 'SELECT ${EventsColumns.ts}, ${EventsColumns.type}, '
            '${EventsColumns.detail} FROM ${EventsColumns.table} '
            'ORDER BY ${EventsColumns.ts}',
        description: 'All flight events in chronological order',
      );
    }

    // ── Duration ──────────────────────────────────────────────────────────
    if (_has(t, ['duration', 'how long', 'flight time', 'total time'])) {
      return const NlQueryResult(
        sql: '''
SELECT ROUND((EPOCH(MAX(${GpsColumns.ts})) - EPOCH(MIN(${GpsColumns.ts}))), 0) AS duration_seconds
FROM ${GpsColumns.table}''',
        description: 'Total flight duration in seconds',
      );
    }

    // ── Location: highest point ────────────────────────────────────────────
    if (_has(t, ['where was i highest', 'highest point location', 'peak altitude location'])) {
      return const NlQueryResult(
        sql: '''
SELECT ${GpsColumns.lat}, ${GpsColumns.lon}, ROUND(${GpsColumns.altRel}, 1) AS alt_rel_m
FROM ${GpsColumns.table}
ORDER BY ${GpsColumns.altRel} DESC
LIMIT 1''',
        description: 'GPS coordinates at peak altitude',
      );
    }

    // ── Location: fastest point ────────────────────────────────────────────
    if (_has(t, ['where was i fastest', 'fastest location'])) {
      return const NlQueryResult(
        sql: '''
SELECT g.${GpsColumns.ts}, g.${GpsColumns.lat}, g.${GpsColumns.lon}, ROUND(v.${VfrHudColumns.groundspeed}, 1) AS speed_ms
FROM ${GpsColumns.table} g
JOIN ${VfrHudColumns.table} v ON ABS(EPOCH(g.${GpsColumns.ts}) - EPOCH(v.${VfrHudColumns.ts})) < 1
ORDER BY v.${VfrHudColumns.groundspeed} DESC
LIMIT 1''',
        description: 'GPS coordinates at highest groundspeed',
      );
    }

    // ── Flight path ────────────────────────────────────────────────────────
    if (_has(t, ['flight path', 'gps track', 'position over time'])) {
      return const NlQueryResult(
        sql: '''
SELECT ${GpsColumns.ts}, ${GpsColumns.lat}, ${GpsColumns.lon}, ROUND(${GpsColumns.altRel}, 1) AS alt_rel_m
FROM ${GpsColumns.table}
ORDER BY ${GpsColumns.ts}
LIMIT 500''',
        description: 'GPS track: position and altitude over time',
      );
    }

    // ── Max altitude ──────────────────────────────────────────────────────
    if (_has(t, ['max altitude', 'peak altitude', 'highest altitude', 'how high'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(MAX(${GpsColumns.altRel}), 1) AS max_altitude_m '
            'FROM ${GpsColumns.table}',
        description: 'Maximum altitude above home',
      );
    }

    // ── Min altitude ──────────────────────────────────────────────────────
    if (_has(t, ['min altitude', 'lowest altitude'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(MIN(${GpsColumns.altRel}), 1) AS min_altitude_m '
            'FROM ${GpsColumns.table}',
        description: 'Minimum altitude above home',
      );
    }

    // ── Altitude over time ─────────────────────────────────────────────────
    if (_has(t, ['altitude over time', 'altitude vs time', 'show altitude', 'plot altitude'])) {
      return const NlQueryResult(
        sql: '''
SELECT ${GpsColumns.ts}, ROUND(${GpsColumns.altRel}, 1) AS altitude_m
FROM ${GpsColumns.table}
ORDER BY ${GpsColumns.ts}
LIMIT 500''',
        description: 'Altitude above home over time',
      );
    }

    // ── Max airspeed ──────────────────────────────────────────────────────
    if (_has(t, ['max airspeed', 'top airspeed'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(MAX(${VfrHudColumns.airspeed}), 1) AS max_airspeed_ms '
            'FROM ${VfrHudColumns.table}',
        description: 'Maximum airspeed',
      );
    }

    // ── Max groundspeed (order matters: check airspeed first) ─────────────
    if (_has(t, ['max speed', 'top speed', 'fastest', 'peak speed', 'maximum speed'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(MAX(${VfrHudColumns.groundspeed}), 1) AS max_groundspeed_ms '
            'FROM ${VfrHudColumns.table}',
        description: 'Maximum groundspeed',
      );
    }

    // ── Average speed ─────────────────────────────────────────────────────
    if (_has(t, ['average speed', 'mean speed', 'avg speed'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(AVG(${VfrHudColumns.groundspeed}), 2) AS avg_groundspeed_ms '
            'FROM ${VfrHudColumns.table}',
        description: 'Average groundspeed',
      );
    }

    // ── Airspeed over time ────────────────────────────────────────────────
    if (_has(t, ['airspeed over time', 'show airspeed'])) {
      return const NlQueryResult(
        sql: '''
SELECT ${VfrHudColumns.ts}, ROUND(${VfrHudColumns.airspeed}, 2) AS airspeed_ms
FROM ${VfrHudColumns.table}
ORDER BY ${VfrHudColumns.ts}
LIMIT 500''',
        description: 'Airspeed over time',
      );
    }

    // ── Speed over time ────────────────────────────────────────────────────
    if (_has(t, ['speed over time', 'groundspeed over time', 'speed vs time', 'show speed'])) {
      return const NlQueryResult(
        sql: '''
SELECT ${VfrHudColumns.ts}, ROUND(${VfrHudColumns.groundspeed}, 2) AS groundspeed_ms
FROM ${VfrHudColumns.table}
ORDER BY ${VfrHudColumns.ts}
LIMIT 500''',
        description: 'Groundspeed over time',
      );
    }

    // ── Max climb ─────────────────────────────────────────────────────────
    if (_has(t, ['max climb', 'peak climb rate'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(MAX(${VfrHudColumns.climb}), 2) AS max_climb_ms '
            'FROM ${VfrHudColumns.table}',
        description: 'Maximum climb rate',
      );
    }

    // ── Max descent ───────────────────────────────────────────────────────
    if (_has(t, ['max descent', 'peak descent'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(MIN(${VfrHudColumns.climb}), 2) AS max_descent_ms '
            'FROM ${VfrHudColumns.table}',
        description: 'Maximum descent rate (most negative climb value)',
      );
    }

    // ── Climb rate over time ───────────────────────────────────────────────
    if (_has(t, ['climb rate over time', 'show climb'])) {
      return const NlQueryResult(
        sql: '''
SELECT ${VfrHudColumns.ts}, ROUND(${VfrHudColumns.climb}, 2) AS climb_ms
FROM ${VfrHudColumns.table}
ORDER BY ${VfrHudColumns.ts}
LIMIT 500''',
        description: 'Climb rate over time',
      );
    }

    // ── Max throttle ──────────────────────────────────────────────────────
    if (_has(t, ['max throttle', 'full throttle'])) {
      return const NlQueryResult(
        sql: 'SELECT MAX(${VfrHudColumns.throttle}) AS max_throttle_pct '
            'FROM ${VfrHudColumns.table}',
        description: 'Maximum throttle percentage',
      );
    }

    // ── Throttle over time ────────────────────────────────────────────────
    if (_has(t, ['throttle over time', 'show throttle'])) {
      return const NlQueryResult(
        sql: '''
SELECT ${VfrHudColumns.ts}, ${VfrHudColumns.throttle} AS throttle_pct
FROM ${VfrHudColumns.table}
ORDER BY ${VfrHudColumns.ts}
LIMIT 500''',
        description: 'Throttle percentage over time',
      );
    }

    // ── Battery: starting voltage ──────────────────────────────────────────
    if (_has(t, ['battery start', 'initial battery', 'starting voltage'])) {
      return const NlQueryResult(
        sql: '''
SELECT ROUND(${BatteryColumns.voltage}, 2) AS start_voltage_v
FROM ${BatteryColumns.table}
ORDER BY ${BatteryColumns.ts}
LIMIT 1''',
        description: 'Battery voltage at start of flight',
      );
    }

    // ── Battery: min/final voltage ─────────────────────────────────────────
    if (_has(t, ['battery end', 'final battery', 'ending voltage', 'min voltage', 'lowest voltage'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(MIN(${BatteryColumns.voltage}), 2) AS min_voltage_v '
            'FROM ${BatteryColumns.table}',
        description: 'Minimum battery voltage recorded',
      );
    }

    // ── Battery consumed ──────────────────────────────────────────────────
    if (_has(t, ['battery used', 'consumed', 'mah'])) {
      return const NlQueryResult(
        sql: '''
SELECT ROUND(MAX(${BatteryColumns.consumedMah}) - MIN(${BatteryColumns.consumedMah}), 1) AS consumed_mah
FROM ${BatteryColumns.table}''',
        description: 'Battery capacity consumed (mAh)',
      );
    }

    // ── Battery over time ─────────────────────────────────────────────────
    if (_has(t, ['battery over time', 'voltage over time', 'show battery', 'show voltage'])) {
      return const NlQueryResult(
        sql: '''
SELECT ${BatteryColumns.ts}, ROUND(${BatteryColumns.voltage}, 2) AS voltage_v, ${BatteryColumns.remainingPct}
FROM ${BatteryColumns.table}
ORDER BY ${BatteryColumns.ts}
LIMIT 500''',
        description: 'Battery voltage and remaining percentage over time',
      );
    }

    // ── Max roll ──────────────────────────────────────────────────────────
    if (_has(t, ['max roll', 'peak roll'])) {
      return const NlQueryResult(
        sql: '''
SELECT ROUND(MAX(ABS(${AttitudeColumns.roll} * 180.0 / 3.14159)), 1) AS max_roll_deg
FROM ${AttitudeColumns.table}''',
        description: 'Maximum roll angle (degrees)',
      );
    }

    // ── Roll over time ────────────────────────────────────────────────────
    if (_has(t, ['roll over time', 'show roll', 'roll vs time'])) {
      return const NlQueryResult(
        sql: '''
SELECT ${AttitudeColumns.ts}, ROUND(${AttitudeColumns.roll} * 180.0 / 3.14159, 1) AS roll_deg
FROM ${AttitudeColumns.table}
ORDER BY ${AttitudeColumns.ts}
LIMIT 500''',
        description: 'Roll angle over time',
      );
    }

    // ── Max pitch ─────────────────────────────────────────────────────────
    if (_has(t, ['max pitch', 'peak pitch'])) {
      return const NlQueryResult(
        sql: '''
SELECT ROUND(MAX(ABS(${AttitudeColumns.pitch} * 180.0 / 3.14159)), 1) AS max_pitch_deg
FROM ${AttitudeColumns.table}''',
        description: 'Maximum pitch angle (degrees)',
      );
    }

    // ── Pitch over time ───────────────────────────────────────────────────
    if (_has(t, ['pitch over time', 'show pitch', 'pitch vs time'])) {
      return const NlQueryResult(
        sql: '''
SELECT ${AttitudeColumns.ts}, ROUND(${AttitudeColumns.pitch} * 180.0 / 3.14159, 1) AS pitch_deg
FROM ${AttitudeColumns.table}
ORDER BY ${AttitudeColumns.ts}
LIMIT 500''',
        description: 'Pitch angle over time',
      );
    }

    // ── Yaw / heading over time ───────────────────────────────────────────
    if (_has(t, ['yaw over time', 'show yaw', 'yaw vs time', 'heading over time'])) {
      return const NlQueryResult(
        sql: '''
SELECT ${AttitudeColumns.ts}, ROUND(${AttitudeColumns.yaw} * 180.0 / 3.14159, 1) AS yaw_deg
FROM ${AttitudeColumns.table}
ORDER BY ${AttitudeColumns.ts}
LIMIT 500''',
        description: 'Yaw angle over time',
      );
    }

    // ── Max vibration ─────────────────────────────────────────────────────
    if (_has(t, ['max vibration', 'vibration peak'])) {
      return const NlQueryResult(
        sql: '''
SELECT ROUND(MAX(GREATEST(${VibrationColumns.vibeX}, ${VibrationColumns.vibeY}, ${VibrationColumns.vibeZ})), 2) AS max_vibration
FROM ${VibrationColumns.table}''',
        description: 'Peak vibration across all axes',
      );
    }

    // ── Vibration over time ───────────────────────────────────────────────
    if (_has(t, ['vibration over time', 'show vibration'])) {
      return const NlQueryResult(
        sql: '''
SELECT ${VibrationColumns.ts}, ROUND(${VibrationColumns.vibeX}, 2) AS x, ROUND(${VibrationColumns.vibeY}, 2) AS y, ROUND(${VibrationColumns.vibeZ}, 2) AS z
FROM ${VibrationColumns.table}
ORDER BY ${VibrationColumns.ts}
LIMIT 500''',
        description: 'Vibration on X/Y/Z axes over time',
      );
    }

    // ── Satellites / GPS quality ──────────────────────────────────────────
    if (_has(t, ['satellites', 'gps satellites'])) {
      return const NlQueryResult(
        sql: '''
SELECT
  ROUND(AVG(${GpsColumns.satellites}), 0) AS avg_satellites,
  MIN(${GpsColumns.satellites}) AS min_satellites
FROM ${GpsColumns.table}''',
        description: 'Average and minimum GPS satellite count',
      );
    }

    // ── RC channels ───────────────────────────────────────────────────────
    if (_has(t, ['rc channels', 'show rc', 'channel input'])) {
      return const NlQueryResult(
        sql: '''
SELECT ${RcChannelsColumns.ts}, ch1, ch2, ch3, ch4
FROM ${RcChannelsColumns.table}
ORDER BY ${RcChannelsColumns.ts}
LIMIT 500''',
        description: 'RC input channels 1–4 over time',
      );
    }

    return null;
  }

  /// Returns `true` if [text] contains at least one of the given [words].
  static bool _has(String text, List<String> words) =>
      words.any((w) => text.contains(w));
}
