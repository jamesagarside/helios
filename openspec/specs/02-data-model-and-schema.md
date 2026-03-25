# Helios GCS — Data Model & DuckDB Schema Specification

**Version**: 1.0.0 | **Status**: Draft | **Date**: 2026-03-24

---

## 1. Database Lifecycle

### 1.1 File Naming Convention

```
helios_YYYYMMDD_HHmmss_{vehicle_sysid}.duckdb
```

Example: `helios_20260324_143022_1.duckdb`

### 1.2 Database Lifecycle States

```
Created → Recording → Closed → Archived
  │                      │
  └──── (crash) ────────→ Recovery
```

- **Created**: Schema initialised, flight_meta populated, recording not yet started.
- **Recording**: Active telemetry being written. File locked.
- **Closed**: Recording stopped. File available for analysis and export.
- **Archived**: Exported to Parquet and/or synced to Argus. May be compressed or moved.
- **Recovery**: App crashed during recording. On next launch, detect unclosed files and attempt WAL recovery.

### 1.3 Schema Versioning

The `flight_meta` table includes a `schema_version` key. Schema migrations are handled at open time:

```sql
-- Check schema version on open
SELECT value FROM flight_meta WHERE key = 'schema_version';
```

Migration scripts are bundled in the app and run sequentially from current version to latest.

---

## 2. Core Schema

### 2.1 flight_meta

Key-value metadata about the flight. Created at recording start, updated at recording end.

```sql
CREATE TABLE flight_meta (
  key   VARCHAR PRIMARY KEY,
  value VARCHAR NOT NULL
);

-- Required keys:
-- schema_version    '1'
-- flight_id         UUID v4
-- vehicle_sysid     '1'
-- vehicle_compid    '1'
-- vehicle_type      'FIXED_WING' | 'VTOL' | 'QUADROTOR' | ...
-- autopilot         'ARDUPILOT' | 'PX4' | 'UNKNOWN'
-- firmware_version  '4.5.1' or 'UNKNOWN'
-- start_time_utc    ISO 8601 timestamp
-- end_time_utc      ISO 8601 timestamp (set on close)
-- start_lat         Decimal degrees
-- start_lon         Decimal degrees
-- helios_version    '1.0.0'
-- recording_reason  'manual' | 'auto_arm' | 'auto_connect'
```

### 2.2 attitude

High-frequency attitude data from the autopilot.

```sql
CREATE TABLE attitude (
  ts         TIMESTAMP NOT NULL,  -- UTC, microsecond precision
  roll       DOUBLE NOT NULL,     -- radians
  pitch      DOUBLE NOT NULL,     -- radians
  yaw        DOUBLE NOT NULL,     -- radians
  roll_spd   DOUBLE,              -- rad/s
  pitch_spd  DOUBLE,              -- rad/s
  yaw_spd    DOUBLE               -- rad/s
);

-- Optimisation: ordered by ts for range scans
-- Source: ATTITUDE (msg_id 30), 20-50 Hz
```

### 2.3 gps

GPS position data.

```sql
CREATE TABLE gps (
  ts         TIMESTAMP NOT NULL,
  lat        DOUBLE NOT NULL,     -- degrees, WGS84
  lon        DOUBLE NOT NULL,     -- degrees, WGS84
  alt_msl    DOUBLE NOT NULL,     -- metres above mean sea level
  alt_rel    DOUBLE NOT NULL,     -- metres above home
  fix_type   TINYINT NOT NULL,    -- 0=none, 2=2D, 3=3D, 4=DGPS, 5=RTK
  satellites TINYINT NOT NULL,
  hdop       DOUBLE NOT NULL,     -- horizontal dilution of precision (cm)
  vdop       DOUBLE,              -- vertical dilution of precision (cm)
  vel        DOUBLE,              -- ground speed (cm/s)
  cog        DOUBLE               -- course over ground (cdeg)
);

-- Source: GLOBAL_POSITION_INT (33) for lat/lon/alt, GPS_RAW_INT (24) for fix/sats/hdop
-- Rate: 5-10 Hz
```

### 2.4 battery

Battery state.

```sql
CREATE TABLE battery (
  ts              TIMESTAMP NOT NULL,
  voltage         DOUBLE NOT NULL,     -- volts (from mV)
  current_a       DOUBLE,              -- amps (from cA), NULL if not available
  remaining_pct   TINYINT,             -- 0-100, -1 if unknown
  consumed_mah    DOUBLE,              -- mAh consumed
  temperature     DOUBLE               -- celsius, NULL if not available
);

-- Source: SYS_STATUS (1) for voltage/current/remaining, BATTERY_STATUS (147) for detail
-- Rate: 1 Hz
```

### 2.5 vfr_hud

Primary flight instruments data.

```sql
CREATE TABLE vfr_hud (
  ts           TIMESTAMP NOT NULL,
  airspeed     DOUBLE NOT NULL,     -- m/s indicated airspeed
  groundspeed  DOUBLE NOT NULL,     -- m/s
  heading      SMALLINT NOT NULL,   -- degrees 0-359
  throttle     SMALLINT NOT NULL,   -- percent 0-100
  climb        DOUBLE NOT NULL      -- m/s climb rate
);

-- Source: VFR_HUD (74), 5-10 Hz
```

### 2.6 rc_channels

RC input channels.

```sql
CREATE TABLE rc_channels (
  ts    TIMESTAMP NOT NULL,
  ch1   SMALLINT, ch2   SMALLINT, ch3   SMALLINT, ch4   SMALLINT,
  ch5   SMALLINT, ch6   SMALLINT, ch7   SMALLINT, ch8   SMALLINT,
  ch9   SMALLINT, ch10  SMALLINT, ch11  SMALLINT, ch12  SMALLINT,
  ch13  SMALLINT, ch14  SMALLINT, ch15  SMALLINT, ch16  SMALLINT,
  rssi  TINYINT   -- signal strength 0-254, 255=unknown
);

-- Source: RC_CHANNELS (65), 10 Hz
-- Values: PWM microseconds (typically 1000-2000)
```

### 2.7 servo_output

Servo/motor output channels.

```sql
CREATE TABLE servo_output (
  ts    TIMESTAMP NOT NULL,
  srv1  SMALLINT, srv2  SMALLINT, srv3  SMALLINT, srv4  SMALLINT,
  srv5  SMALLINT, srv6  SMALLINT, srv7  SMALLINT, srv8  SMALLINT,
  srv9  SMALLINT, srv10 SMALLINT, srv11 SMALLINT, srv12 SMALLINT,
  srv13 SMALLINT, srv14 SMALLINT, srv15 SMALLINT, srv16 SMALLINT
);

-- Source: SERVO_OUTPUT_RAW (36), 10 Hz
-- Values: PWM microseconds
```

### 2.8 vibration

Vibration data for maintenance and anomaly detection.

```sql
CREATE TABLE vibration (
  ts      TIMESTAMP NOT NULL,
  vibe_x  DOUBLE NOT NULL,   -- m/s² RMS
  vibe_y  DOUBLE NOT NULL,
  vibe_z  DOUBLE NOT NULL,
  clip_0  INTEGER NOT NULL,  -- accelerometer 0 clipping count
  clip_1  INTEGER NOT NULL,
  clip_2  INTEGER NOT NULL
);

-- Source: VIBRATION (241), 1 Hz
```

### 2.9 events

Discrete events during the flight. Not periodic — triggered by state changes.

```sql
CREATE TABLE events (
  ts      TIMESTAMP NOT NULL,
  type    VARCHAR NOT NULL,    -- 'mode_change', 'arm', 'disarm', 'failsafe',
                               -- 'geofence', 'statustext', 'annotation', 'error'
  detail  VARCHAR NOT NULL,    -- JSON or plain text detail
  severity TINYINT DEFAULT 6   -- MAVLink severity: 0=EMERGENCY ... 7=DEBUG
);

-- Sources: HEARTBEAT mode changes, COMMAND_ACK, STATUSTEXT (253), user annotations
-- Rate: event-driven (not periodic)
```

### 2.10 mission_items

Snapshot of the mission uploaded/downloaded during this flight.

```sql
CREATE TABLE mission_items (
  seq       SMALLINT NOT NULL,    -- waypoint sequence number
  frame     TINYINT NOT NULL,     -- MAV_FRAME
  command   SMALLINT NOT NULL,    -- MAV_CMD
  current   TINYINT NOT NULL,     -- 1 = current target
  autocont  TINYINT NOT NULL,     -- auto-continue
  param1    DOUBLE,
  param2    DOUBLE,
  param3    DOUBLE,
  param4    DOUBLE,
  lat       DOUBLE,               -- degrees (x 1e7 in MAVLink, converted)
  lon       DOUBLE,
  alt       DOUBLE,               -- metres
  mission_type TINYINT DEFAULT 0  -- 0=mission, 1=fence, 2=rally
);

-- Source: MISSION_ITEM_INT (73) during upload/download
-- Captured once per mission transfer
```

### 2.11 params (P1)

Snapshot of vehicle parameters at recording start.

```sql
CREATE TABLE params (
  name  VARCHAR PRIMARY KEY,
  value DOUBLE NOT NULL,
  type  TINYINT NOT NULL     -- MAV_PARAM_TYPE
);

-- Source: PARAM_VALUE (22) during param fetch
-- Captured once at recording start (full param list ~800-1500 params)
```

---

## 3. Pre-Built Analytics Templates

SQL templates that run against the DuckDB file. Each template has a name, description, SQL, and expected column schema.

### 3.1 Vibration Analysis

```sql
-- Template: vibration_analysis
-- Description: Vibration levels over time with anomaly flagging
SELECT
  ts,
  vibe_x, vibe_y, vibe_z,
  clip_0, clip_1, clip_2,
  AVG(vibe_x) OVER w AS avg_x,
  AVG(vibe_y) OVER w AS avg_y,
  AVG(vibe_z) OVER w AS avg_z,
  CASE WHEN vibe_x > AVG(vibe_x) OVER w + 2 * STDDEV(vibe_x) OVER w
       THEN true ELSE false END AS anomaly_x,
  CASE WHEN vibe_y > AVG(vibe_y) OVER w + 2 * STDDEV(vibe_y) OVER w
       THEN true ELSE false END AS anomaly_y,
  CASE WHEN vibe_z > AVG(vibe_z) OVER w + 2 * STDDEV(vibe_z) OVER w
       THEN true ELSE false END AS anomaly_z
FROM vibration
WINDOW w AS (ORDER BY ts ROWS BETWEEN 30 PRECEDING AND CURRENT ROW)
ORDER BY ts;
```

### 3.2 Battery Discharge Curve

```sql
-- Template: battery_discharge
-- Description: Battery voltage and current over time with estimated endurance
SELECT
  ts,
  voltage,
  current_a,
  remaining_pct,
  consumed_mah,
  CASE WHEN current_a > 0 AND remaining_pct > 0
    THEN (remaining_pct / 100.0 * consumed_mah / (remaining_pct / 100.0)) / current_a * 60
    ELSE NULL
  END AS est_remaining_min
FROM battery
ORDER BY ts;
```

### 3.3 GPS Quality

```sql
-- Template: gps_quality
-- Description: GPS fix quality, satellite count, and HDOP over time
SELECT
  ts,
  fix_type,
  satellites,
  hdop / 100.0 AS hdop,
  CASE
    WHEN fix_type < 3 THEN 'NO_FIX'
    WHEN hdop > 200 THEN 'POOR'
    WHEN hdop > 150 THEN 'FAIR'
    ELSE 'GOOD'
  END AS quality_label
FROM gps
ORDER BY ts;
```

### 3.4 Altitude Profile

```sql
-- Template: altitude_profile
-- Description: Altitude (MSL and relative), climb rate, and terrain clearance
SELECT
  g.ts,
  g.alt_msl,
  g.alt_rel,
  v.climb,
  v.airspeed,
  v.groundspeed
FROM gps g
ASOF JOIN vfr_hud v ON g.ts >= v.ts
ORDER BY g.ts;
```

### 3.5 Anomaly Detection (Z-Score)

```sql
-- Template: anomaly_detection
-- Description: Multi-parameter z-score anomaly detection
WITH stats AS (
  SELECT
    AVG(vibe_x) AS mean_vx, STDDEV(vibe_x) AS std_vx,
    AVG(vibe_y) AS mean_vy, STDDEV(vibe_y) AS std_vy,
    AVG(vibe_z) AS mean_vz, STDDEV(vibe_z) AS std_vz
  FROM vibration
)
SELECT
  v.ts,
  v.vibe_x, v.vibe_y, v.vibe_z,
  (v.vibe_x - s.mean_vx) / NULLIF(s.std_vx, 0) AS zscore_x,
  (v.vibe_y - s.mean_vy) / NULLIF(s.std_vy, 0) AS zscore_y,
  (v.vibe_z - s.mean_vz) / NULLIF(s.std_vz, 0) AS zscore_z,
  CASE WHEN ABS((v.vibe_x - s.mean_vx) / NULLIF(s.std_vx, 0)) > 3
         OR ABS((v.vibe_y - s.mean_vy) / NULLIF(s.std_vy, 0)) > 3
         OR ABS((v.vibe_z - s.mean_vz) / NULLIF(s.std_vz, 0)) > 3
    THEN true ELSE false
  END AS is_anomaly
FROM vibration v, stats s
ORDER BY v.ts;
```

### 3.6 Flight Summary

```sql
-- Template: flight_summary
-- Description: Single-row summary statistics for the entire flight
SELECT
  MIN(g.ts) AS start_time,
  MAX(g.ts) AS end_time,
  EXTRACT(EPOCH FROM MAX(g.ts) - MIN(g.ts)) / 60.0 AS duration_min,
  MAX(g.alt_rel) AS max_alt_rel_m,
  MAX(v.airspeed) AS max_airspeed_ms,
  MAX(v.groundspeed) AS max_groundspeed_ms,
  AVG(v.groundspeed) AS avg_groundspeed_ms,
  MIN(b.voltage) AS min_voltage,
  MAX(b.consumed_mah) AS total_mah,
  MIN(b.remaining_pct) AS min_battery_pct,
  MAX(vib.vibe_x) AS max_vibe_x,
  MAX(vib.vibe_y) AS max_vibe_y,
  MAX(vib.vibe_z) AS max_vibe_z,
  (SELECT COUNT(*) FROM events WHERE type = 'failsafe') AS failsafe_count,
  (SELECT COUNT(*) FROM events WHERE type = 'mode_change') AS mode_change_count
FROM gps g, vfr_hud v, battery b, vibration vib;
```

### 3.7 Mode Timeline

```sql
-- Template: mode_timeline
-- Description: Flight mode transitions with duration
WITH mode_changes AS (
  SELECT
    ts AS start_ts,
    detail AS mode,
    LEAD(ts) OVER (ORDER BY ts) AS end_ts
  FROM events
  WHERE type = 'mode_change'
)
SELECT
  start_ts,
  end_ts,
  mode,
  EXTRACT(EPOCH FROM COALESCE(end_ts, (SELECT MAX(ts) FROM gps)) - start_ts) AS duration_sec
FROM mode_changes
ORDER BY start_ts;
```

---

## 4. Data Volume Estimates

| Table | Msg Rate (Hz) | Row Size (bytes) | 1hr Volume (rows) | 1hr Volume (MB) |
|-------|---------------|------------------|--------------------|------------------|
| attitude | 30 | ~56 | 108,000 | ~6.0 |
| gps | 10 | ~88 | 36,000 | ~3.2 |
| vfr_hud | 10 | ~40 | 36,000 | ~1.4 |
| rc_channels | 10 | ~40 | 36,000 | ~1.4 |
| servo_output | 10 | ~40 | 36,000 | ~1.4 |
| battery | 1 | ~40 | 3,600 | ~0.1 |
| vibration | 1 | ~48 | 3,600 | ~0.2 |
| events | ~0.01 | ~128 | ~50 | ~0.01 |
| **Total** | | | **~259,250** | **~13.7** |

DuckDB overhead and indexes add ~2-3x → **~30-50 MB per hour of flight**.
Parquet export compresses to ~10-20 MB per hour.

---

## 5. Parquet Export Schema

Export preserves table names as Parquet files:

```
export_20260324_143022/
├── flight_meta.parquet
├── attitude.parquet
├── gps.parquet
├── battery.parquet
├── vfr_hud.parquet
├── rc_channels.parquet
├── servo_output.parquet
├── vibration.parquet
├── events.parquet
├── mission_items.parquet
└── manifest.json          -- export metadata, checksums
```

### manifest.json

```json
{
  "helios_version": "1.0.0",
  "schema_version": 1,
  "flight_id": "uuid-here",
  "export_time_utc": "2026-03-24T14:35:00Z",
  "tables": {
    "attitude": { "rows": 108000, "sha256": "abc..." },
    "gps": { "rows": 36000, "sha256": "def..." }
  }
}
```
