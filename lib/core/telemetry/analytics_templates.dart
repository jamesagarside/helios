/// Pre-built SQL analytics templates for the Analyse View.
///
/// Each template runs against a flight DuckDB file.
enum AnalyticsTemplate {
  vibrationAnalysis(
    name: 'Vibration Analysis',
    description: 'Vibration levels with rolling average and anomaly flagging',
    sql: '''
SELECT
  ts, vibe_x, vibe_y, vibe_z, clip_0, clip_1, clip_2,
  AVG(vibe_x) OVER w AS avg_x,
  AVG(vibe_y) OVER w AS avg_y,
  AVG(vibe_z) OVER w AS avg_z
FROM vibration
WINDOW w AS (ORDER BY ts ROWS BETWEEN 30 PRECEDING AND CURRENT ROW)
ORDER BY ts
''',
  ),

  batteryDischarge(
    name: 'Battery Discharge',
    description: 'Voltage, current, and remaining capacity over time',
    sql: '''
SELECT ts, voltage, current_a, remaining_pct, consumed_mah
FROM battery
ORDER BY ts
''',
  ),

  gpsQuality(
    name: 'GPS Quality',
    description: 'Fix type, satellite count, and HDOP over time',
    sql: '''
SELECT
  ts, fix_type, satellites, hdop,
  CASE
    WHEN fix_type < 3 THEN 'NO_FIX'
    WHEN hdop > 2.0 THEN 'POOR'
    WHEN hdop > 1.5 THEN 'FAIR'
    ELSE 'GOOD'
  END AS quality
FROM gps
ORDER BY ts
''',
  ),

  altitudeProfile(
    name: 'Altitude Profile',
    description: 'Altitude (MSL and relative) with climb rate',
    sql: '''
SELECT
  g.ts, g.alt_msl, g.alt_rel,
  v.climb, v.airspeed, v.groundspeed
FROM gps g
ASOF JOIN vfr_hud v ON g.ts >= v.ts
ORDER BY g.ts
''',
  ),

  anomalyDetection(
    name: 'Anomaly Detection',
    description: 'Z-score anomaly detection on vibration data',
    sql: '''
WITH stats AS (
  SELECT
    AVG(vibe_x) AS mean_vx, STDDEV(vibe_x) AS std_vx,
    AVG(vibe_y) AS mean_vy, STDDEV(vibe_y) AS std_vy,
    AVG(vibe_z) AS mean_vz, STDDEV(vibe_z) AS std_vz
  FROM vibration
)
SELECT
  v.ts, v.vibe_x, v.vibe_y, v.vibe_z,
  (v.vibe_x - s.mean_vx) / NULLIF(s.std_vx, 0) AS zscore_x,
  (v.vibe_y - s.mean_vy) / NULLIF(s.std_vy, 0) AS zscore_y,
  (v.vibe_z - s.mean_vz) / NULLIF(s.std_vz, 0) AS zscore_z
FROM vibration v, stats s
ORDER BY v.ts
''',
  ),

  flightSummary(
    name: 'Flight Summary',
    description: 'Single-row summary statistics for the entire flight',
    sql: '''
SELECT
  (SELECT MIN(ts) FROM gps) AS start_time,
  (SELECT MAX(ts) FROM gps) AS end_time,
  (SELECT MAX(alt_rel) FROM gps) AS max_alt_m,
  (SELECT MAX(airspeed) FROM vfr_hud) AS max_ias_ms,
  (SELECT AVG(groundspeed) FROM vfr_hud) AS avg_gs_ms,
  (SELECT MIN(voltage) FROM battery) AS min_voltage,
  (SELECT MIN(remaining_pct) FROM battery) AS min_bat_pct,
  (SELECT COUNT(*) FROM events WHERE type = 'mode_change') AS mode_changes
''',
  ),

  modeTimeline(
    name: 'Mode Timeline',
    description: 'Flight mode transitions with duration',
    sql: '''
SELECT
  ts AS start_ts,
  detail AS mode,
  LEAD(ts) OVER (ORDER BY ts) AS end_ts,
  EXTRACT(EPOCH FROM LEAD(ts) OVER (ORDER BY ts) - ts) AS duration_sec
FROM events
WHERE type = 'mode_change'
ORDER BY ts
''',
  );

  const AnalyticsTemplate({
    required this.name,
    required this.description,
    required this.sql,
  });

  final String name;
  final String description;
  final String sql;
}
