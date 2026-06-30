import 'columns.dart';

/// Pre-built SQL analytics templates for the Analyse View.
///
/// Each template runs against a flight DuckDB file. Table and column names are
/// interpolated from `columns.dart` so a schema rename updates the templates.
enum AnalyticsTemplate {
  vibrationAnalysis(
    name: 'Vibration Analysis',
    description: 'Vibration levels with rolling average and anomaly flagging',
    sql: '''
SELECT
  ${VibrationColumns.ts}, ${VibrationColumns.vibeX}, ${VibrationColumns.vibeY}, ${VibrationColumns.vibeZ}, ${VibrationColumns.clip0}, ${VibrationColumns.clip1}, ${VibrationColumns.clip2},
  AVG(${VibrationColumns.vibeX}) OVER w AS avg_x,
  AVG(${VibrationColumns.vibeY}) OVER w AS avg_y,
  AVG(${VibrationColumns.vibeZ}) OVER w AS avg_z
FROM ${VibrationColumns.table}
WINDOW w AS (ORDER BY ${VibrationColumns.ts} ROWS BETWEEN 30 PRECEDING AND CURRENT ROW)
ORDER BY ${VibrationColumns.ts}
''',
  ),

  batteryDischarge(
    name: 'Battery Discharge',
    description: 'Voltage, current, and remaining capacity over time',
    sql: '''
SELECT ${BatteryColumns.ts}, ${BatteryColumns.voltage}, ${BatteryColumns.currentA}, ${BatteryColumns.remainingPct}, ${BatteryColumns.consumedMah}
FROM ${BatteryColumns.table}
ORDER BY ${BatteryColumns.ts}
''',
  ),

  gpsQuality(
    name: 'GPS Quality',
    description: 'Fix type, satellite count, and HDOP over time',
    sql: '''
SELECT
  ${GpsColumns.ts}, ${GpsColumns.fixType}, ${GpsColumns.satellites}, ${GpsColumns.hdop},
  CASE
    WHEN ${GpsColumns.fixType} IS NULL AND ${GpsColumns.hdop} IS NULL THEN 'UNKNOWN'
    WHEN ${GpsColumns.fixType} < 3 THEN 'NO_FIX'
    WHEN ${GpsColumns.hdop} > 2.0 THEN 'POOR'
    WHEN ${GpsColumns.hdop} > 1.5 THEN 'FAIR'
    WHEN ${GpsColumns.hdop} IS NULL THEN 'UNKNOWN'
    ELSE 'GOOD'
  END AS quality
FROM ${GpsColumns.table}
ORDER BY ${GpsColumns.ts}
''',
  ),

  altitudeProfile(
    name: 'Altitude Profile',
    description: 'Altitude (MSL and relative) with climb rate',
    sql: '''
SELECT
  g.${GpsColumns.ts}, g.${GpsColumns.altMsl}, g.${GpsColumns.altRel},
  v.${VfrHudColumns.climb}, v.${VfrHudColumns.airspeed}, v.${VfrHudColumns.groundspeed}
FROM ${GpsColumns.table} g
ASOF JOIN ${VfrHudColumns.table} v ON g.${GpsColumns.ts} >= v.${VfrHudColumns.ts}
ORDER BY g.${GpsColumns.ts}
''',
  ),

  anomalyDetection(
    name: 'Anomaly Detection',
    description: 'Z-score anomaly detection on vibration data',
    sql: '''
WITH stats AS (
  SELECT
    AVG(${VibrationColumns.vibeX}) AS mean_vx, STDDEV(${VibrationColumns.vibeX}) AS std_vx,
    AVG(${VibrationColumns.vibeY}) AS mean_vy, STDDEV(${VibrationColumns.vibeY}) AS std_vy,
    AVG(${VibrationColumns.vibeZ}) AS mean_vz, STDDEV(${VibrationColumns.vibeZ}) AS std_vz
  FROM ${VibrationColumns.table}
)
SELECT
  v.${VibrationColumns.ts}, v.${VibrationColumns.vibeX}, v.${VibrationColumns.vibeY}, v.${VibrationColumns.vibeZ},
  (v.${VibrationColumns.vibeX} - s.mean_vx) / NULLIF(s.std_vx, 0) AS zscore_x,
  (v.${VibrationColumns.vibeY} - s.mean_vy) / NULLIF(s.std_vy, 0) AS zscore_y,
  (v.${VibrationColumns.vibeZ} - s.mean_vz) / NULLIF(s.std_vz, 0) AS zscore_z
FROM ${VibrationColumns.table} v, stats s
ORDER BY v.${VibrationColumns.ts}
''',
  ),

  flightSummary(
    name: 'Flight Summary',
    description: 'Single-row summary statistics for the entire flight',
    sql: '''
SELECT
  (SELECT MIN(${GpsColumns.ts}) FROM ${GpsColumns.table}) AS start_time,
  (SELECT MAX(${GpsColumns.ts}) FROM ${GpsColumns.table}) AS end_time,
  (SELECT MAX(${GpsColumns.altRel}) FROM ${GpsColumns.table}) AS max_alt_m,
  (SELECT MAX(${VfrHudColumns.airspeed}) FROM ${VfrHudColumns.table}) AS max_ias_ms,
  (SELECT AVG(${VfrHudColumns.groundspeed}) FROM ${VfrHudColumns.table}) AS avg_gs_ms,
  (SELECT MIN(${BatteryColumns.voltage}) FROM ${BatteryColumns.table}) AS min_voltage,
  (SELECT MIN(${BatteryColumns.remainingPct}) FROM ${BatteryColumns.table}) AS min_bat_pct,
  (SELECT COUNT(*) FROM ${EventsColumns.table} WHERE ${EventsColumns.type} = 'mode_change') AS mode_changes
''',
  ),

  modeTimeline(
    name: 'Mode Timeline',
    description: 'Flight mode transitions with duration',
    sql: '''
SELECT
  ${EventsColumns.ts} AS start_ts,
  ${EventsColumns.detail} AS mode,
  LEAD(${EventsColumns.ts}) OVER (ORDER BY ${EventsColumns.ts}) AS end_ts,
  EXTRACT(EPOCH FROM LEAD(${EventsColumns.ts}) OVER (ORDER BY ${EventsColumns.ts}) - ${EventsColumns.ts}) AS duration_sec
FROM ${EventsColumns.table}
WHERE ${EventsColumns.type} = 'mode_change'
ORDER BY ${EventsColumns.ts}
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
