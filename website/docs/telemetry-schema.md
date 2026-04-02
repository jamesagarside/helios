# Telemetry Schema

Helios records every flight into its own DuckDB database file. This page documents the storage model, schema, and how to work with recorded telemetry data.

---

## Storage Model

Each flight is stored as an independent DuckDB file. This provides:

| Advantage | Explanation |
|---|---|
| Isolation | A corrupted or incomplete flight does not affect other recordings |
| Portability | Individual flight files can be copied, shared, or archived independently |
| Performance | Columnar OLAP queries on a single flight avoid scanning unrelated data |
| Cleanup | Deleting a flight is a simple file deletion |

Flight databases are stored in the application's data directory and named by timestamp.

---

## Schema

The telemetry table stores time-series data with microsecond timestamps. Each row represents a telemetry snapshot captured at approximately 30Hz.

### Core Columns

| Column | Type | Source Message | Description |
|---|---|---|---|
| `timestamp_us` | BIGINT | System clock | Microseconds since epoch |
| `roll` | DOUBLE | ATTITUDE | Roll angle in degrees |
| `pitch` | DOUBLE | ATTITUDE | Pitch angle in degrees |
| `yaw` | DOUBLE | ATTITUDE | Yaw/heading in degrees |
| `rollspeed` | DOUBLE | ATTITUDE | Roll rate in rad/s |
| `pitchspeed` | DOUBLE | ATTITUDE | Pitch rate in rad/s |
| `yawspeed` | DOUBLE | ATTITUDE | Yaw rate in rad/s |

### Position

| Column | Type | Source Message | Description |
|---|---|---|---|
| `lat` | DOUBLE | GLOBAL_POSITION_INT | Latitude in degrees |
| `lon` | DOUBLE | GLOBAL_POSITION_INT | Longitude in degrees |
| `alt_msl` | DOUBLE | GLOBAL_POSITION_INT | Altitude MSL in metres |
| `alt_rel` | DOUBLE | GLOBAL_POSITION_INT | Altitude relative to home in metres |
| `hdg` | DOUBLE | GLOBAL_POSITION_INT | Heading in degrees |

### Speed

| Column | Type | Source Message | Description |
|---|---|---|---|
| `groundspeed` | DOUBLE | VFR_HUD | Ground speed in m/s |
| `airspeed` | DOUBLE | VFR_HUD | Indicated airspeed in m/s |
| `climb` | DOUBLE | VFR_HUD | Climb rate in m/s |
| `throttle` | INTEGER | VFR_HUD | Throttle percentage (0-100) |

### Battery

| Column | Type | Source Message | Description |
|---|---|---|---|
| `voltage_v` | DOUBLE | SYS_STATUS | Battery voltage in volts |
| `current_a` | DOUBLE | SYS_STATUS | Battery current in amps |
| `remaining_pct` | INTEGER | SYS_STATUS | Battery remaining percentage |

### GPS

| Column | Type | Source Message | Description |
|---|---|---|---|
| `gps_fix` | INTEGER | GPS_RAW_INT | Fix type (0=no fix, 3=3D fix, etc.) |
| `gps_satellites` | INTEGER | GPS_RAW_INT | Number of visible satellites |
| `gps_hdop` | DOUBLE | GPS_RAW_INT | Horizontal dilution of precision |

### System

| Column | Type | Source Message | Description |
|---|---|---|---|
| `flight_mode` | VARCHAR | HEARTBEAT | Current flight mode name |
| `armed` | BOOLEAN | HEARTBEAT | Whether the vehicle is armed |
| `sensors_health` | BIGINT | SYS_STATUS | Sensor health bitmask |

---

## Querying Flight Data

The **Analyse** view provides a built-in SQL editor for querying flight recordings. Queries run directly against DuckDB using standard SQL.

### Example Queries

**Flight duration and distance:**

```sql
SELECT
  (MAX(timestamp_us) - MIN(timestamp_us)) / 1e6 AS duration_seconds,
  MIN(alt_rel) AS min_alt,
  MAX(alt_rel) AS max_alt,
  AVG(groundspeed) AS avg_speed
FROM telemetry
```

**Battery drain rate over 30-second windows:**

```sql
SELECT
  (timestamp_us / 30000000) * 30 AS window_start_sec,
  MAX(voltage_v) - MIN(voltage_v) AS voltage_drop,
  AVG(current_a) AS avg_current
FROM telemetry
GROUP BY window_start_sec
ORDER BY window_start_sec
```

**GPS quality over time:**

```sql
SELECT
  timestamp_us / 1e6 AS time_sec,
  gps_fix,
  gps_satellites,
  gps_hdop
FROM telemetry
WHERE gps_satellites IS NOT NULL
ORDER BY timestamp_us
```

---

## Export

Recorded flights can be exported to Parquet format for analysis in external tools (Python, R, MATLAB, DuckDB CLI):

1. Open the **Analyse** view.
2. Select a flight from the browser.
3. Use the export option to save as `.parquet`.

Parquet files preserve the full schema and columnar layout, making them efficient for large-scale analysis.
