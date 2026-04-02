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
  ROUND((EPOCH(MAX(ts)) - EPOCH(MIN(ts))), 0) AS duration_sec,
  ROUND(MAX(alt_rel), 1) AS max_alt_m,
  ROUND(AVG(alt_rel), 1) AS avg_alt_m,
  COUNT(*) AS gps_samples
FROM gps''',
        description: 'Flight summary: duration, max/avg altitude, sample count',
      );
    }

    // ── Events / log ─────────────────────────────────────────────────────
    if (_has(t, ['events', 'log', 'messages', 'alerts', 'what happened'])) {
      return const NlQueryResult(
        sql: 'SELECT ts, type, detail FROM events ORDER BY ts',
        description: 'All flight events in chronological order',
      );
    }

    // ── Duration ──────────────────────────────────────────────────────────
    if (_has(t, ['duration', 'how long', 'flight time', 'total time'])) {
      return const NlQueryResult(
        sql: '''
SELECT ROUND((EPOCH(MAX(ts)) - EPOCH(MIN(ts))), 0) AS duration_seconds
FROM gps''',
        description: 'Total flight duration in seconds',
      );
    }

    // ── Location: highest point ────────────────────────────────────────────
    if (_has(t, ['where was i highest', 'highest point location', 'peak altitude location'])) {
      return const NlQueryResult(
        sql: '''
SELECT lat, lon, ROUND(alt_rel, 1) AS alt_rel_m
FROM gps
ORDER BY alt_rel DESC
LIMIT 1''',
        description: 'GPS coordinates at peak altitude',
      );
    }

    // ── Location: fastest point ────────────────────────────────────────────
    if (_has(t, ['where was i fastest', 'fastest location'])) {
      return const NlQueryResult(
        sql: '''
SELECT g.ts, g.lat, g.lon, ROUND(v.groundspeed, 1) AS speed_ms
FROM gps g
JOIN vfr_hud v ON ABS(EPOCH(g.ts) - EPOCH(v.ts)) < 1
ORDER BY v.groundspeed DESC
LIMIT 1''',
        description: 'GPS coordinates at highest groundspeed',
      );
    }

    // ── Flight path ────────────────────────────────────────────────────────
    if (_has(t, ['flight path', 'gps track', 'position over time'])) {
      return const NlQueryResult(
        sql: '''
SELECT ts, lat, lon, ROUND(alt_rel, 1) AS alt_rel_m
FROM gps
ORDER BY ts
LIMIT 500''',
        description: 'GPS track: position and altitude over time',
      );
    }

    // ── Max altitude ──────────────────────────────────────────────────────
    if (_has(t, ['max altitude', 'peak altitude', 'highest altitude', 'how high'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(MAX(alt_rel), 1) AS max_altitude_m FROM gps',
        description: 'Maximum altitude above home',
      );
    }

    // ── Min altitude ──────────────────────────────────────────────────────
    if (_has(t, ['min altitude', 'lowest altitude'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(MIN(alt_rel), 1) AS min_altitude_m FROM gps',
        description: 'Minimum altitude above home',
      );
    }

    // ── Altitude over time ─────────────────────────────────────────────────
    if (_has(t, ['altitude over time', 'altitude vs time', 'show altitude', 'plot altitude'])) {
      return const NlQueryResult(
        sql: '''
SELECT ts, ROUND(alt_rel, 1) AS altitude_m
FROM gps
ORDER BY ts
LIMIT 500''',
        description: 'Altitude above home over time',
      );
    }

    // ── Max airspeed ──────────────────────────────────────────────────────
    if (_has(t, ['max airspeed', 'top airspeed'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(MAX(airspeed), 1) AS max_airspeed_ms FROM vfr_hud',
        description: 'Maximum airspeed',
      );
    }

    // ── Max groundspeed (order matters: check airspeed first) ─────────────
    if (_has(t, ['max speed', 'top speed', 'fastest', 'peak speed', 'maximum speed'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(MAX(groundspeed), 1) AS max_groundspeed_ms FROM vfr_hud',
        description: 'Maximum groundspeed',
      );
    }

    // ── Average speed ─────────────────────────────────────────────────────
    if (_has(t, ['average speed', 'mean speed', 'avg speed'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(AVG(groundspeed), 2) AS avg_groundspeed_ms FROM vfr_hud',
        description: 'Average groundspeed',
      );
    }

    // ── Airspeed over time ────────────────────────────────────────────────
    if (_has(t, ['airspeed over time', 'show airspeed'])) {
      return const NlQueryResult(
        sql: '''
SELECT ts, ROUND(airspeed, 2) AS airspeed_ms
FROM vfr_hud
ORDER BY ts
LIMIT 500''',
        description: 'Airspeed over time',
      );
    }

    // ── Speed over time ────────────────────────────────────────────────────
    if (_has(t, ['speed over time', 'groundspeed over time', 'speed vs time', 'show speed'])) {
      return const NlQueryResult(
        sql: '''
SELECT ts, ROUND(groundspeed, 2) AS groundspeed_ms
FROM vfr_hud
ORDER BY ts
LIMIT 500''',
        description: 'Groundspeed over time',
      );
    }

    // ── Max climb ─────────────────────────────────────────────────────────
    if (_has(t, ['max climb', 'peak climb rate'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(MAX(climb), 2) AS max_climb_ms FROM vfr_hud',
        description: 'Maximum climb rate',
      );
    }

    // ── Max descent ───────────────────────────────────────────────────────
    if (_has(t, ['max descent', 'peak descent'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(MIN(climb), 2) AS max_descent_ms FROM vfr_hud',
        description: 'Maximum descent rate (most negative climb value)',
      );
    }

    // ── Climb rate over time ───────────────────────────────────────────────
    if (_has(t, ['climb rate over time', 'show climb'])) {
      return const NlQueryResult(
        sql: '''
SELECT ts, ROUND(climb, 2) AS climb_ms
FROM vfr_hud
ORDER BY ts
LIMIT 500''',
        description: 'Climb rate over time',
      );
    }

    // ── Max throttle ──────────────────────────────────────────────────────
    if (_has(t, ['max throttle', 'full throttle'])) {
      return const NlQueryResult(
        sql: 'SELECT MAX(throttle) AS max_throttle_pct FROM vfr_hud',
        description: 'Maximum throttle percentage',
      );
    }

    // ── Throttle over time ────────────────────────────────────────────────
    if (_has(t, ['throttle over time', 'show throttle'])) {
      return const NlQueryResult(
        sql: '''
SELECT ts, throttle AS throttle_pct
FROM vfr_hud
ORDER BY ts
LIMIT 500''',
        description: 'Throttle percentage over time',
      );
    }

    // ── Battery: starting voltage ──────────────────────────────────────────
    if (_has(t, ['battery start', 'initial battery', 'starting voltage'])) {
      return const NlQueryResult(
        sql: '''
SELECT ROUND(voltage, 2) AS start_voltage_v
FROM battery
ORDER BY ts
LIMIT 1''',
        description: 'Battery voltage at start of flight',
      );
    }

    // ── Battery: min/final voltage ─────────────────────────────────────────
    if (_has(t, ['battery end', 'final battery', 'ending voltage', 'min voltage', 'lowest voltage'])) {
      return const NlQueryResult(
        sql: 'SELECT ROUND(MIN(voltage), 2) AS min_voltage_v FROM battery',
        description: 'Minimum battery voltage recorded',
      );
    }

    // ── Battery consumed ──────────────────────────────────────────────────
    if (_has(t, ['battery used', 'consumed', 'mah'])) {
      return const NlQueryResult(
        sql: '''
SELECT ROUND(MAX(consumed_mah) - MIN(consumed_mah), 1) AS consumed_mah
FROM battery''',
        description: 'Battery capacity consumed (mAh)',
      );
    }

    // ── Battery over time ─────────────────────────────────────────────────
    if (_has(t, ['battery over time', 'voltage over time', 'show battery', 'show voltage'])) {
      return const NlQueryResult(
        sql: '''
SELECT ts, ROUND(voltage, 2) AS voltage_v, remaining_pct
FROM battery
ORDER BY ts
LIMIT 500''',
        description: 'Battery voltage and remaining percentage over time',
      );
    }

    // ── Max roll ──────────────────────────────────────────────────────────
    if (_has(t, ['max roll', 'peak roll'])) {
      return const NlQueryResult(
        sql: '''
SELECT ROUND(MAX(ABS(roll * 180.0 / 3.14159)), 1) AS max_roll_deg
FROM attitude''',
        description: 'Maximum roll angle (degrees)',
      );
    }

    // ── Roll over time ────────────────────────────────────────────────────
    if (_has(t, ['roll over time', 'show roll', 'roll vs time'])) {
      return const NlQueryResult(
        sql: '''
SELECT ts, ROUND(roll * 180.0 / 3.14159, 1) AS roll_deg
FROM attitude
ORDER BY ts
LIMIT 500''',
        description: 'Roll angle over time',
      );
    }

    // ── Max pitch ─────────────────────────────────────────────────────────
    if (_has(t, ['max pitch', 'peak pitch'])) {
      return const NlQueryResult(
        sql: '''
SELECT ROUND(MAX(ABS(pitch * 180.0 / 3.14159)), 1) AS max_pitch_deg
FROM attitude''',
        description: 'Maximum pitch angle (degrees)',
      );
    }

    // ── Pitch over time ───────────────────────────────────────────────────
    if (_has(t, ['pitch over time', 'show pitch', 'pitch vs time'])) {
      return const NlQueryResult(
        sql: '''
SELECT ts, ROUND(pitch * 180.0 / 3.14159, 1) AS pitch_deg
FROM attitude
ORDER BY ts
LIMIT 500''',
        description: 'Pitch angle over time',
      );
    }

    // ── Yaw / heading over time ───────────────────────────────────────────
    if (_has(t, ['yaw over time', 'show yaw', 'yaw vs time', 'heading over time'])) {
      return const NlQueryResult(
        sql: '''
SELECT ts, ROUND(yaw * 180.0 / 3.14159, 1) AS yaw_deg
FROM attitude
ORDER BY ts
LIMIT 500''',
        description: 'Yaw angle over time',
      );
    }

    // ── Max vibration ─────────────────────────────────────────────────────
    if (_has(t, ['max vibration', 'vibration peak'])) {
      return const NlQueryResult(
        sql: '''
SELECT ROUND(MAX(GREATEST(vibe_x, vibe_y, vibe_z)), 2) AS max_vibration
FROM vibration''',
        description: 'Peak vibration across all axes',
      );
    }

    // ── Vibration over time ───────────────────────────────────────────────
    if (_has(t, ['vibration over time', 'show vibration'])) {
      return const NlQueryResult(
        sql: '''
SELECT ts, ROUND(vibe_x, 2) AS x, ROUND(vibe_y, 2) AS y, ROUND(vibe_z, 2) AS z
FROM vibration
ORDER BY ts
LIMIT 500''',
        description: 'Vibration on X/Y/Z axes over time',
      );
    }

    // ── Satellites / GPS quality ──────────────────────────────────────────
    if (_has(t, ['satellites', 'gps satellites'])) {
      return const NlQueryResult(
        sql: '''
SELECT
  ROUND(AVG(satellites), 0) AS avg_satellites,
  MIN(satellites) AS min_satellites
FROM gps''',
        description: 'Average and minimum GPS satellite count',
      );
    }

    // ── RC channels ───────────────────────────────────────────────────────
    if (_has(t, ['rc channels', 'show rc', 'channel input'])) {
      return const NlQueryResult(
        sql: '''
SELECT ts, ch1, ch2, ch3, ch4
FROM rc_channels
ORDER BY ts
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
