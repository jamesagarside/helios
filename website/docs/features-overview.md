# Features Overview

Helios is an open-source ground control station for MAVLink and MSP drones. This page provides a summary of every major feature area, organized by application tab.

## Protocol Support

| Capability | MAVLink v2 | MSP (Betaflight/iNav) |
|---|---|---|
| Telemetry | Full (ATTITUDE, GPS, SYS_STATUS, VFR_HUD, EKF, VIBRATION, WIND, etc.) | Attitude, GPS, battery, RC channels |
| Mission Planning | Upload, download, execution monitoring | Not supported |
| Parameter Editor | Full read/write with metadata | Not supported |
| Calibration | Accelerometer, magnetometer, gyro, level | Not supported |
| Firmware Detection | AUTOPILOT_VERSION auto-request | Auto-detected via MSP_API_VERSION |
| Vehicle Types | Fixed-wing, multirotor, VTOL, helicopter, rover, boat | Multirotor, fixed-wing |
| Autopilots | ArduPilot, PX4 | Betaflight, iNav |
| Stream Rate Control | MAV_CMD_SET_MESSAGE_INTERVAL with legacy fallback | Fixed polling interval |
| Geofence | Upload/download/edit | Not supported |
| Rally Points | Upload/download/edit | Not supported |
| Log Download | Dataflash logs over MAVLink | Not supported |
| Guided Commands | Fly-to-here, orbit, altitude change, ROI, pause | Not supported |

---

## Fly View

Real-time flight monitoring and vehicle control.

| Feature | Description |
|---|---|
| Primary Flight Display (PFD) | Compound attitude indicator with speed and altitude tapes, 60fps ticker interpolation |
| Live Map | Vehicle position, heading, flight trail, home marker, mission overlay (flutter_map with OSM tiles) |
| Telemetry Tiles | Configurable grid of live values -- altitude, speed, battery, GPS, heading, distance to home |
| Action Panel | Arm/disarm, takeoff, land, RTL with confirmation dialogs |
| Emergency Panel | Emergency stop, force land, force disarm for critical situations |
| Guided Commands | Fly-to-here, orbit, altitude change, ROI set/clear, pause/continue |
| Flight Mode Strip | Quick-access mode switcher with category grouping (manual, assisted, auto) |
| Preflight Checklist | Pre-arm checks dialog with sensor health and GPS readiness |
| Quick Actions Grid | Common in-flight actions accessible from a single panel |
| EKF Status | Velocity, horizontal position, vertical position, compass, and terrain variance indicators |
| Gimbal Control | Pitch and yaw control for connected gimbal (MOUNT_STATUS) |
| Charts | Real-time scrolling charts for altitude, speed, battery, and other telemetry values |
| Video Overlay | Picture-in-picture RTSP video feed on the map view |
| Map Tools Overlay | Ruler, coordinate readout, zoom controls |

For details, see [Fly View Guide](fly-view.md).

---

## Plan View

Mission planning, geofence editing, and survey pattern generation.

| Feature | Description |
|---|---|
| Waypoint Editor | Add, move, delete, reorder waypoints with drag-and-drop on the map |
| DO_ Commands | Insert MAVLink DO_ commands (delay, set servo, change speed, set ROI, jump, etc.) between navigation waypoints |
| Multi-Select | Select multiple waypoints for bulk altitude change, deletion, or reorder |
| Polygon Survey | Auto-generate lawnmower survey pattern inside a drawn polygon |
| Corridor Scan | Generate parallel scan lines along a polyline centerline for linear features |
| KML/GPX Import | Import waypoints and polygons from KML and GPX files |
| Geofence Editor | Draw inclusion/exclusion polygons and circular fences, upload to FC |
| Rally Points | Place and manage rally (safe-landing) points on the map |
| Points of Interest (POI) | Mark and label reference points for mission context |
| Airspace Overlay | Visualize restricted airspace and no-fly zones on the planning map |
| Terrain Profile | SRTM elevation profile along the planned route with clearance checking |
| Mission Stats Bar | Distance, estimated flight time, waypoint count, and altitude range summary |
| Mission File I/O | Save and load missions as standard MAVLink waypoint files |
| Upload/Download | Upload planned missions to the FC or download the current FC mission |

For details, see [Plan View Guide](plan-view.md) and [Corridor Scan](corridor-scan.md) and [Terrain Planning](terrain-planning.md).

---

## Data View (Analyse)

Post-flight analytics powered by DuckDB columnar storage.

| Feature | Description |
|---|---|
| Flight Browser | Browse recorded flights by date, duration, vehicle, and summary stats |
| Charts | Interactive time-series charts for any recorded telemetry channel |
| SQL Editor | Write arbitrary SQL queries against DuckDB flight databases |
| Flight Forensics | Cross-flight comparative analysis for anomaly detection |
| Fleet Dashboard | Aggregated statistics across all vehicles and flights |
| Natural Language Queries | Grammar-based SQL generation from plain English questions |
| Geotagging | Match camera trigger timestamps to GPS coordinates for image geotagging |
| Flight Replay | Play back a recorded flight through the Fly View PFD and map |
| Export | Export flight data as Parquet, CSV, or JSON for external analysis |
| Telemetry Recording | Every flight is automatically recorded into a per-flight DuckDB database |

For details, see [Data View Guide](data-view.md).

---

## Setup

Connection management, vehicle configuration, and application settings.

| Feature | Description |
|---|---|
| Connection (UDP) | Bind to 0.0.0.0 on port 14550 with automatic remote endpoint discovery |
| Connection (TCP) | Connect to a specified host and port (typical SITL: 127.0.0.1:5760) |
| Connection (Serial) | Select serial port and baud rate for USB or radio telemetry links |
| Protocol Auto-Detection | 5-second probe determines MAVLink vs MSP on any transport |
| Auto-Connect | Monitor for new serial ports and connect automatically (toggle in Setup) |
| Quick Connection Bar | Top-of-screen bar showing current connection, one-click reconnect |
| Connection Persistence | Last-used connection configuration saved and restored on launch |
| Parameter Editor | Full parameter list with search, descriptions, enums, group filtering, and metadata |
| Calibration | Accelerometer, magnetometer, gyro, and level calibration wizards |
| Stream Rates | Configure per-message telemetry rates (ATTITUDE, GPS, SYS_STATUS, etc.) |
| Video Settings | RTSP URL configuration for live video feed |
| Display Settings | Theme mode, unit preferences, layout profile selection |
| Offline Maps | Download and manage map tile regions for offline/air-gapped use |
| Log Download | Browse and download Dataflash logs stored on the flight controller |
| Failsafe Panel | Configure failsafe actions (RC loss, battery, GCS loss) |
| Frame Type Panel | View and set vehicle frame class and type |
| Motor Test | Spin individual motors at specified throttle for verification |
| Pre-Arm Panel | Review pre-arm check status and sensor health |
| Simulate (SITL) | Launch ArduPilot SITL in Docker with wind and failure injection |

For details, see [Connection Guide](connection-guide.md) and [Setup Guide](setup-guide.md).

---

## Inspect

Low-level MAVLink diagnostics.

| Feature | Description |
|---|---|
| Packet Inspector | Real-time scrolling log of all decoded MAVLink packets with message ID, name, system/component ID, timestamp, and payload size (10,000 packet ring buffer at 5Hz UI refresh) |
| MAVLink Terminal | Send raw MAVLink commands and view responses |
| Message Filtering | Filter the packet stream by message name or ID |
| Pause/Resume | Freeze the inspector display for analysis without losing buffered data |

---

## Video

Live video streaming and recording.

| Feature | Description |
|---|---|
| RTSP Streaming | Connect to any RTSP video source (onboard camera, IP camera) via media_kit |
| HUD Overlay | Heads-up display overlay with attitude, altitude, and speed on the video feed |
| Recording | Record the video stream to a local file |

---

## Simulate

Development and testing tools for use without hardware.

| Feature | Description |
|---|---|
| SITL Docker Launcher | Start ArduPilot SITL instances in Docker containers from the Setup tab |
| Wind Injection | Configure simulated wind speed and direction during SITL flights |
| Failure Injection | Trigger simulated component failures (GPS, battery, motor) |
| Speed Multiplier | Run the simulation faster or slower than real time |

For details, see [Simulation Guide](simulation-guide.md).
