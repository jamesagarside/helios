# Analyse View

The Analyse View is Helios's post-flight data analysis screen. Every flight is automatically recorded into a per-flight DuckDB file, making post-flight analysis as powerful as the live display. The view combines a flight browser, visual charts, a full SQL query editor, cross-flight forensics, automated scoring, fleet-wide statistics, photo geotagging, and flight replay.

**Protocol**: MAVLink and MSP
**Platform**: All (macOS, Linux, Windows, iOS, Android)

---

## Flight Browser

The left-hand panel lists all recorded flights, sorted newest-first. Each entry shows the flight date and, if assigned, a custom name.

### Interactions

| Action | Effect |
|---|---|
| Tap flight | Opens the flight for analysis |
| Rename | Opens a dialog to assign a custom name |
| Notes | Opens a multi-line text editor for flight notes |
| Delete | Permanently removes the flight file (with confirmation) |
| Replay | Loads the flight into the replay engine and switches to Fly View |
| Refresh | Re-scans the flights directory |

A green indicator marks the currently recording flight. Selecting the live flight shows real-time charts that auto-refresh every two seconds.

---

## Mode Tabs

The top toolbar switches between six analysis modes:

| Mode | Description |
|---|---|
| **Charts** | Visual flight charts with synced timeline (default) |
| **SQL** | DuckDB SQL editor with templates and natural language input |
| **Compare** | Cross-flight forensics and comparison |
| **Score** | Automated flight health scorecard |
| **Fleet** | Aggregate statistics across all flights |
| **Geotag** | Match photos to GPS track and write EXIF coordinates |

---

## Flight Charts

The default mode displays a set of pre-built charts queried from the flight's DuckDB file. All charts share a synchronised crosshair and timeline.

### Available charts

| Chart | Data source | Fields |
|---|---|---|
| Altitude | `gps` | `alt_rel` (AGL), `alt_msl` |
| Speed | `vfr_hud` | `airspeed`, `groundspeed` |
| Climb Rate | `vfr_hud` | `climb` |
| Battery | `battery` | `voltage`, `remaining_pct` |
| GPS Quality | `gps` | `satellites`, `hdop` |
| Attitude | `attitude` | `roll`, `pitch` |
| Vibration | `vibration` | `vibe_x`, `vibe_y`, `vibe_z` |

### Synced timeline scrubbing

A scrub bar at the top of the chart area controls the visible time window. All charts respond to the same controls:

- **Drag the scrub bar** to pan through the flight.
- **Scroll to zoom** to narrow or widen the visible range.
- **Hover any chart** to display a synchronised crosshair across all charts at the same timestamp.

### Live mode

When the currently recording flight is selected, charts auto-refresh every two seconds. The view range stays pinned to the latest data.

### Replay map

A miniature map at the top of the charts view shows the GPS ground track. The crosshair position on the charts is mirrored as a marker on the map.

### Event markers

Key flight events (arm, disarm, mode changes, warnings) are overlaid as vertical markers on each chart for context.

---

## SQL Query Editor

Switch to **SQL** mode for direct DuckDB access. The editor supports standard DuckDB SQL syntax including window functions, CTEs, ASOF JOINs, and aggregations.

### Query templates

A template bar across the top provides one-click pre-built queries:

| Template | Description |
|---|---|
| Vibration Analysis | Rolling average and anomaly flagging on vibration data |
| Battery Discharge | Voltage, current, and capacity over time |
| GPS Quality | Fix type, satellite count, HDOP with quality classification |
| Altitude Profile | Altitude with climb rate via ASOF JOIN to VFR HUD |
| Anomaly Detection | Z-score analysis on vibration axes |

Clicking a template inserts the SQL and immediately executes it.

### Results table

Query results are displayed in a scrollable data table. A status bar at the bottom shows the row count and execution time in milliseconds.

### DuckDB schema reference

Each flight creates a `.duckdb` file with the following tables:

**attitude**

| Column | Type |
|---|---|
| `ts` | TIMESTAMP |
| `roll` | DOUBLE |
| `pitch` | DOUBLE |
| `yaw` | DOUBLE |
| `roll_spd` | DOUBLE |
| `pitch_spd` | DOUBLE |
| `yaw_spd` | DOUBLE |

**gps**

| Column | Type |
|---|---|
| `ts` | TIMESTAMP |
| `lat` | DOUBLE |
| `lon` | DOUBLE |
| `alt_msl` | DOUBLE |
| `alt_rel` | DOUBLE |
| `fix_type` | TINYINT |
| `satellites` | TINYINT |
| `hdop` | DOUBLE |
| `vdop` | DOUBLE |
| `vel` | DOUBLE |
| `cog` | DOUBLE |

**battery**

| Column | Type |
|---|---|
| `ts` | TIMESTAMP |
| `voltage` | DOUBLE |
| `current_a` | DOUBLE |
| `remaining_pct` | TINYINT |
| `consumed_mah` | DOUBLE |

**vfr_hud**

| Column | Type |
|---|---|
| `ts` | TIMESTAMP |
| `airspeed` | DOUBLE |
| `groundspeed` | DOUBLE |
| `heading` | SMALLINT |
| `throttle` | SMALLINT |
| `climb` | DOUBLE |

**vibration**

| Column | Type |
|---|---|
| `ts` | TIMESTAMP |
| `vibe_x` | DOUBLE |
| `vibe_y` | DOUBLE |
| `vibe_z` | DOUBLE |
| `clip_0` | INTEGER |
| `clip_1` | INTEGER |
| `clip_2` | INTEGER |

**events**

| Column | Type |
|---|---|
| `ts` | TIMESTAMP |
| `type` | VARCHAR |
| `detail` | VARCHAR |
| `severity` | TINYINT |

**rc_channels**

| Column | Type |
|---|---|
| `ts` | TIMESTAMP |
| `ch1`..`ch16` | SMALLINT |
| `rssi` | TINYINT |

**servo_output**

| Column | Type |
|---|---|
| `ts` | TIMESTAMP |
| `srv1`..`srv8` | SMALLINT |

**missions**

| Column | Type |
|---|---|
| `ts` | TIMESTAMP |
| `direction` | VARCHAR |
| `seq` | SMALLINT |
| `frame` | TINYINT |
| `command` | SMALLINT |
| `param1`..`param4` | DOUBLE |
| `lat`, `lon`, `alt` | DOUBLE |
| `autocont` | TINYINT |

**flight_meta**

| Column | Type |
|---|---|
| `key` | VARCHAR (PK) |
| `value` | VARCHAR |

---

## Export Formats

From the SQL editor, export query results or full tables to disk.

| Format | Extension | Notes |
|---|---|---|
| Parquet | `.parquet` | Columnar format, best for further analytics tooling |
| CSV | `.csv` | Query result rows exported as comma-separated values |
| JSON | `.json` | Query result rows exported as JSON array |

Export files are written to a directory alongside the flight `.duckdb` file, named `<flight>_export/`.

---

## Natural Language Queries

A natural language input bar sits above the SQL editor. Type a plain-English question and Helios translates it into DuckDB SQL using pattern-based keyword matching. No external API or network connection is required.

### Example queries

| Input | Generated SQL description |
|---|---|
| `max altitude` | Maximum altitude above home |
| `battery chart` | Voltage, current, and capacity over time |
| `summary` | Duration, max/avg altitude, sample count |
| `events` | All flight events in chronological order |
| `how long` | Total flight duration in seconds |
| `where was I highest` | GPS coordinates at peak altitude |
| `where was I fastest` | GPS coordinates at peak speed |

If no pattern matches, the input is ignored and the SQL field remains unchanged. The generated SQL is editable before execution.

---

## Flight Score

The **Score** mode runs four independent queries (GPS quality, battery health, vibration levels, attitude stability) against the selected flight and produces an automated health scorecard from 0 to 100.

### Scoring categories

| Category | What it measures |
|---|---|
| GPS | Satellite count, HDOP, fix quality |
| Battery | Voltage stability, capacity usage |
| Vibration | Vibration magnitude, clipping events |
| Attitude | Roll/pitch stability, angular rate smoothness |

Each category produces a sub-score. The overall score is a weighted average. Colour coding indicates the result: green for healthy, amber for marginal, red for concerning.

---

## Flight Forensics (Compare)

The **Compare** mode enables cross-flight analysis. Select two or more flights from the browser and run comparison templates or custom SQL against all selected files.

### Built-in templates

The forensics service provides pre-built comparison templates (for example, flight duration, max altitude, battery consumption across flights). Results are displayed in a comparison table with one column per flight.

### Custom SQL

Toggle the custom SQL editor to write your own cross-flight queries. Each query runs independently against every selected flight, and results are merged into a single comparison table.

---

## Fleet Dashboard

The **Fleet** mode aggregates statistics across all recorded flights. It opens each `.duckdb` file, queries key metrics, and displays:

- **Summary header**: total flights, total flight time, average duration, combined distance.
- **Per-flight table**: one row per flight sorted by date, showing duration, max altitude, max speed, battery usage, and GPS quality.

This view is read-only and refreshes automatically when the flight list changes.

---

## Photo Geotagging

The **Geotag** mode matches photos to the GPS track of the selected flight and writes GPS coordinates into the image EXIF data.

### How it works

1. Select a flight in the browser (it provides the GPS track).
2. Switch to the **Geotag** tab and select one or more JPEG images.
3. Helios reads the EXIF `DateTimeOriginal` from each image.
4. It queries the DuckDB `gps` table for the nearest timestamp within 5 seconds.
5. If a match is found, `GPSLatitude`, `GPSLongitude`, and `GPSAltitude` are written back into the JPEG.

### Options

| Option | Description |
|---|---|
| Time offset (seconds) | Compensate for camera clock drift. Positive values shift photo timestamps forward. |

### Results

A results list shows each image with its matched coordinates or an error reason (no EXIF date, no GPS match within threshold, unsupported format).

---

## Flight Replay

From the flight browser, tap the **Replay** button on any flight to load it into the replay engine. Helios pre-loads all telemetry from the DuckDB file into memory, then switches to the Fly View and plays back the flight as if it were live.

### Playback controls

| Control | Effect |
|---|---|
| Play / Pause | Start or pause playback |
| Speed | 0.5x, 1x, 2x, 4x, 8x |
| Scrub | Seek to any point in the flight |

The PFD, map, charts, and telemetry sidebar all update in real time during replay. The replay marker on the map traces the ground track.

---

## Platform Notes

| Feature | macOS | Linux | Windows | iOS | Android |
|---|:---:|:---:|:---:|:---:|:---:|
| Flight browser | Yes | Yes | Yes | Yes | Yes |
| Flight charts | Yes | Yes | Yes | Yes | Yes |
| SQL query editor | Yes | Yes | Yes | Yes | Yes |
| Parquet/CSV/JSON export | Yes | Yes | Yes | Yes | Yes |
| Natural language queries | Yes | Yes | Yes | Yes | Yes |
| Flight Score | Yes | Yes | Yes | Yes | Yes |
| Flight Forensics | Yes | Yes | Yes | Yes | Yes |
| Fleet Dashboard | Yes | Yes | Yes | Yes | Yes |
| Photo Geotagging | Yes | Yes | Yes | -- | -- |
| Flight Replay | Yes | Yes | Yes | Yes | Yes |

Photo geotagging requires filesystem access to JPEG files, which may be restricted on mobile platforms.
