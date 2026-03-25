# Helios GCS — Architecture & Product Specification

**Part of the Argus Platform**

_Helios sees from the sky. Argus sees from the ground._

Version 0.1 — March 2026 | DRAFT — For Planning Purposes

Flutter · DuckDB · MAVLink · Apache 2.0

---

## 1. Vision & Purpose

Helios GCS is an open-source ground control station for MAVLink-enabled fixed-wing and VTOL unmanned aircraft. It is designed to replace the ageing desktop-first GCS tools that dominate the drone market with a modern, cross-platform application built on Flutter and DuckDB.

The core thesis: drone telemetry is a data problem, not just a display problem. Every existing GCS shows you telemetry in real time but throws it away when the flight ends. Helios records every message into an embedded analytical database, making post-flight analysis as powerful as the in-flight display.

Helios is part of the Argus platform — an open-source alternative to Palantir for data fusion and analytics. Helios is the sky-facing sensor layer: it gathers, records, and forwards aerial telemetry. Argus is the ground-facing analytics layer: it ingests, correlates, and visualises data at scale. Together they form a complete pipeline from airborne sensor to operational dashboard.

### 1.1 Problem Statement

The current drone GCS landscape is fragmented and dated:

- **QGroundControl:** Open-source Qt/C++ monolith. Functional but difficult to extend, limited analytics, and a mobile experience that feels like a desktop app shrunk to fit.
- **Mission Planner:** ArduPilot community workhorse. Windows-first via .NET/Mono. Poor cross-platform experience, no embedded analytics.
- **Auterion Mission Control:** Commercial QGC fork locked to the Auterion/Skynode hardware ecosystem, pivoted heavily into defence.
- **DJI FlightHub 2:** Powerful fleet management but vendor-locked to DJI hardware.
- **FlytBase:** Enterprise autonomy platform, cloud-dependent, not a field-deployable GCS.
- **Cockpit (Blue Robotics):** Most modern architecture (Vue/TypeScript, web-based) but focused on marine vehicles with limited aerial support.

None of these treat flight data as a first-class queryable dataset. Post-flight analysis requires downloading .bin log files and opening them in separate tools. None integrate into a broader data fusion platform.

### 1.2 Value Proposition

- **Embedded analytics:** Every flight is a DuckDB database. SQL-queryable telemetry with pre-built templates for vibration analysis, battery degradation, GPS quality, and anomaly detection.
- **True cross-platform:** One Flutter codebase producing native apps for Linux, macOS, Windows, Android, and iOS. Desktop-quality UX on field tablets.
- **Argus integration:** Parquet export feeds directly into the Argus analytics platform. Fleet-wide dashboards, ML anomaly detection, and cross-mission correlation.
- **Open data, open code:** Apache 2.0 licensed. Parquet export for interoperability with Elasticsearch, Spark, Pandas, or any modern data stack. No vendor lock-in.
- **Offline-first:** Works fully disconnected in the field. No cloud dependency. Optional sync when connected.

---

## 2. Competitive Landscape

| Platform        | Open Source          | Cross-Platform    | Embedded Analytics | Offline | Extensible       |
| --------------- | -------------------- | ----------------- | ------------------ | ------- | ---------------- |
| QGroundControl  | Yes (Apache/GPL)     | Yes (Qt)          | No                 | Yes     | Limited (C++)    |
| Mission Planner | Yes (GPL)            | Windows-first     | No                 | Yes     | No               |
| Auterion AMC    | No (QGC fork)        | Limited           | No                 | Partial | App store        |
| DJI FlightHub 2 | No                   | Web + DJI only    | No                 | No      | No               |
| FlytBase        | No                   | Web/cloud         | Partial            | No      | API only         |
| Cockpit         | Yes (GPL)            | Web/Electron      | No                 | Partial | Vue widgets      |
| **Helios GCS**  | **Yes (Apache 2.0)** | **Yes (Flutter)** | **Yes (DuckDB)**   | **Yes** | **Dart plugins** |

The satellite ground station market is projected to reach $82.7bn by 2030 at 15.1% CAGR. The commercial and defence small UAS segment is the fastest-growing subsector, driven by constellation-scale operations and increasing regulatory maturity for BVLOS flights.

---

## 3. Feature Specification

Features are grouped by view and priority tier: P0 (MVP), P1 (v1.0), P2 (future).

### 3.1 Fly View — Real-Time Operations

The primary in-flight screen displaying vehicle state, map position, and live telemetry.

| Feature                | Pri | Description                                                                              | Value                                       |
| ---------------------- | --- | ---------------------------------------------------------------------------------------- | ------------------------------------------- |
| Primary Flight Display | P0  | Attitude indicator, roll/pitch/yaw. CustomPainter at 60fps.                              | Core situational awareness.                 |
| Moving map             | P0  | flutter_map with OSM tiles. Vehicle position, heading, trail, waypoint overlay.          | Spatial awareness of vehicle and mission.   |
| Offline map tiles      | P0  | Pre-cached tile sets via flutter_map_tile_caching.                                       | Field ops often lack connectivity.          |
| Telemetry strip        | P0  | Sidebar with battery, GPS, mode, arm state, airspeed, altitude. Colour-coded thresholds. | At-a-glance vehicle health.                 |
| Connection badge       | P0  | Heartbeat watchdog (5s timeout). Visual link state indicator.                            | Immediate lost-link awareness.              |
| Speed/altitude tapes   | P1  | Vertical tape instruments for IAS, GS, altitude, vertical speed.                         | Precision instrument flying.                |
| Video stream           | P1  | RTSP/WebRTC video from onboard camera. PiP mode over map.                                | Payload monitoring for inspection missions. |
| HUD overlay            | P1  | Transparent overlay on video: attitude, speed, altitude.                                 | Pilot-focused combined view.                |
| Audio alerts           | P2  | Voice/tone alerts for battery low, GPS loss, geofence breach.                            | Eyes-free critical event awareness.         |
| Multi-vehicle          | P2  | Display and switch between multiple connected vehicles.                                  | Swarm and multi-asset operations.           |

### 3.2 Plan View — Mission Planning

Pre-flight mission creation and upload.

| Feature                 | Pri | Description                                                                             | Value                                           |
| ----------------------- | --- | --------------------------------------------------------------------------------------- | ----------------------------------------------- |
| Waypoint editor         | P0  | Tap-to-place waypoints. Drag to reorder. Per-waypoint altitude, speed, loiter radius.   | Core autonomous flight planning.                |
| Mission upload/download | P0  | Upload to vehicle via MAVLink mission protocol. Download for editing.                   | Transfer between GCS and autopilot.             |
| Survey planner          | P1  | Polygon area with auto-generated lawnmower/crosshatch pattern. Camera trigger interval. | Structured coverage for mapping.                |
| Terrain-aware altitude  | P1  | SRTM/DEM data for AGL altitude planning on hilly terrain.                               | Fixed-wing ops in varied terrain.               |
| Geofence editor         | P1  | Inclusion/exclusion zones. Upload as MAVLink geofence.                                  | Safety boundary enforcement.                    |
| Rally points            | P2  | Alternate landing locations for emergency RTL.                                          | Fixed-wing safety with limited landing options. |
| KML/KMZ import          | P2  | Import boundaries and waypoints from Google Earth files.                                | Interop with existing planning workflows.       |

### 3.3 Analyse View — DuckDB Analytics (Differentiator)

Post-flight and in-flight analytics powered by embedded DuckDB. This is the feature no other GCS offers.

| Feature             | Pri | Description                                                                                                    | Value                                    |
| ------------------- | --- | -------------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| Flight browser      | P0  | List all recorded flights (.duckdb files). Date, duration, file size.                                          | Navigate the flight archive.             |
| SQL query editor    | P0  | Syntax-highlighted editor. Run arbitrary SQL. Results as data table.                                           | Ad-hoc exploration for advanced users.   |
| Pre-built templates | P0  | One-click templates: vibration, battery discharge, GPS quality, altitude profile, anomaly detection (z-score). | Instant insights without writing SQL.    |
| Telemetry charts    | P1  | fl_chart time-series plots. Any column vs time. Multi-series overlay.                                          | Visual pattern recognition.              |
| Anomaly detection   | P1  | Statistical z-score and rolling deviation on vibration, battery, GPS.                                          | Predictive maintenance.                  |
| Flight comparison   | P2  | Two flights side-by-side. Overlay telemetry curves. Detect degradation.                                        | Fleet health and regression detection.   |
| Parquet export      | P0  | Export tables/queries to Parquet via DuckDB COPY TO.                                                           | Sync to Argus/ES/S3. Zero lock-in.       |
| Argus sync agent    | P2  | Push Parquet files to Argus platform endpoint. Configurable schedule.                                          | Automated fleet-wide analytics pipeline. |

### 3.4 Setup View — Configuration

| Feature             | Pri | Description                                             | Value                                   |
| ------------------- | --- | ------------------------------------------------------- | --------------------------------------- |
| Connection manager  | P0  | UDP, TCP, serial. Address, port, baud rate config.      | Connect to any MAVLink vehicle.         |
| Recording controls  | P0  | Start/stop recording. Auto-record on arm.               | Capture every flight.                   |
| Parameter editor    | P1  | Read/write ArduPilot/PX4 params. Search, group, modify. | On-field configuration.                 |
| Calibration wizards | P2  | Accelerometer, compass, radio calibration flows.        | Complete setup without switching tools. |
| Firmware flash      | P2  | Flash ArduPilot/PX4 firmware to flight controller.      | Reduce toolchain dependencies.          |

---

## 4. Technical Architecture

### 4.1 Layered Architecture

Helios follows a four-layer architecture separating presentation, state, services, and data.

- **Presentation layer:** Flutter widgets organised by feature (Fly, Plan, Analyse, Setup). Responsive layouts for desktop, tablet, and mobile. CustomPainter for performance-critical instruments (PFD, HUD).
- **State layer:** Riverpod providers as the single source of truth. StateNotifier for vehicle state, connection state, recording state. All widgets consume state reactively — no manual rebuild management.
- **Service layer:** MavlinkService (connection, parsing, command dispatch), TelemetryStore (DuckDB operations), MissionService (waypoint management). Business logic lives here, fully testable without UI.
- **Data layer:** DuckDB embedded database. One .duckdb file per flight. Parquet export for interoperability. File system for map tile cache and configuration.

### 4.2 Dual Data Path

The core architectural innovation is the dual data path, enabling real-time display and analytical queries simultaneously.

#### Real-time path (< 100ms latency)

MAVLink bytes arrive on the transport (UDP/TCP/serial). MavlinkService parses frames via dart_mavlink. Each decoded message updates the corresponding Riverpod StateNotifier. Flutter widgets rebuild reactively via ConsumerWidget/StreamBuilder. This path has zero database involvement — pure in-memory Dart streams.

#### Analytics path (1-second batch cadence)

The same decoded messages are also buffered in memory lists within TelemetryStore. A periodic timer (1s) flushes buffers to DuckDB via multi-row INSERT statements. DuckDB's columnar engine handles batch inserts efficiently. The Analyse view queries DuckDB via standard SQL.

#### Export path (on-demand)

DuckDB's native COPY TO command exports tables or query results as Apache Parquet. Parquet files sync to the Argus platform, Elasticsearch, S3, or any tool in the modern data stack.

### 4.3 DuckDB Schema

Each flight creates a fresh .duckdb file under the app data directory. Schema is flat and wide — optimised for columnar analytics.

| Table        | Key Columns                                                | Source / Rate                                      |
| ------------ | ---------------------------------------------------------- | -------------------------------------------------- |
| attitude     | ts, roll, pitch, yaw, roll_spd, pitch_spd, yaw_spd         | ATTITUDE msg, 20–50 Hz                             |
| gps          | ts, lat, lon, alt_msl, alt_rel, fix_type, satellites, hdop | GLOBAL_POSITION_INT, 5–10 Hz                       |
| battery      | ts, voltage, current_a, remaining_pct, consumed_mah        | SYS_STATUS, 1 Hz                                   |
| vfr_hud      | ts, airspeed, groundspeed, heading, throttle, climb        | VFR_HUD, 5–10 Hz                                   |
| rc_channels  | ts, ch1…ch16                                               | RC_CHANNELS, 10 Hz                                 |
| servo_output | ts, srv1…srv16                                             | SERVO_OUTPUT_RAW, 10 Hz                            |
| vibration    | ts, vibe_x, vibe_y, vibe_z, clip_0, clip_1, clip_2         | VIBRATION, 1 Hz                                    |
| events       | ts, type, detail                                           | Mode changes, arm/disarm, failsafes, annotations   |
| flight_meta  | key, value                                                 | Flight ID, vehicle, firmware, start/end timestamps |

Estimated volume: a 1-hour flight at typical MAVLink rates produces ~50–100 MB of DuckDB data. Parquet export compresses to ~10–20 MB.

### 4.4 Argus Integration Architecture

Helios and Argus form a two-tier data pipeline:

- **Tier 1 — Field (Helios):** Flutter app + DuckDB in-process on laptop/tablet. Fully offline. One .duckdb file per flight. All analytics available locally.
- **Tier 2 — Base (Argus):** Central analytics platform. Ingests Parquet files from Helios. Fleet-wide dashboards, ML anomaly detection, cross-mission correlation, long-term trend analysis.
- **Data bridge:** Parquet is the interchange format. DuckDB exports it natively. Argus ingests it via configurable connectors (file drop, S3 bucket, HTTP upload, USB sync).
- **Schema alignment:** Helios and Argus share a common telemetry schema definition. Changes are versioned. Argus can ingest data from any Helios version via schema evolution.

---

## 5. Technology Stack

Every choice is justified by the project's constraints: cross-platform, offline-first, embeddable, and open source.

| Layer        | Technology                  | Licence    | Justification                                                                                                  |
| ------------ | --------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------- |
| UI framework | Flutter 3.x                 | BSD-3      | Single codebase for desktop + mobile + web. Native compilation. Widget system ideal for composable dashboards. |
| Language     | Dart 3.x                    | BSD-3      | Flutter's language. Strong typing, async/await, streams, good FFI for native bindings.                         |
| State        | Riverpod 2.x                | MIT        | Compile-safe, testable, no boilerplate. StateNotifier for reactive updates across all widgets.                 |
| Database     | DuckDB 1.x (dart_duckdb)    | MIT        | In-process columnar OLAP. Zero external deps. Native Dart bindings. Parquet export built in.                   |
| Protocol     | MAVLink v2 (dart_mavlink)   | MIT        | Industry standard for PX4 + ArduPilot. Dart parser/serialiser available.                                       |
| Maps         | flutter_map 7.x             | BSD-3      | OSM-based, no API key. Offline tiles via flutter_map_tile_caching.                                             |
| Charts       | fl_chart 0.69+              | MIT        | Lightweight charting for time-series telemetry visualisation.                                                  |
| Serial       | serial_port_flutter         | MIT        | Platform channel for USB-serial telemetry radios.                                                              |
| Export       | Apache Parquet (via DuckDB) | Apache 2.0 | Universal columnar interchange. Readable by Argus, ES, Spark, Pandas, Polars.                                  |

### 5.1 Why Flutter

- **vs Qt (QGC):** Qt demands C++ expertise, has complex build systems, and delivers subpar mobile UX. Flutter is more productive and produces truly native mobile apps.
- **vs Electron (Cockpit):** Electron bundles Chromium (~150 MB overhead). Flutter compiles native with smaller binaries and better performance on field hardware.
- **vs pure Web:** Cannot access serial ports natively, limited offline capability, cannot embed DuckDB in-process. Flutter desktop gives full native access while sharing code with mobile.

### 5.2 Why DuckDB

- **vs Elasticsearch:** ES requires a JVM, 30–60s startup, 2–4 GB heap minimum. DuckDB is in-process and instant. ES is right for the Argus tier, not the field tier.
- **vs SQLite:** Row-oriented OLTP engine. Analytical queries (time-window aggregations, statistical functions) are orders of magnitude slower than DuckDB on the same data.
- **vs QuestDB:** Excellent TSDB but it's a server process, not embeddable. No Dart bindings. DuckDB's dart_duckdb provides true in-process embedding.

---

## 6. UI/UX Design Guidelines

### 6.1 Design Principles

- **Dark-first:** Outdoor tablet use demands high contrast. Dark backgrounds, bright accent colours. Optimised for sunlight readability.
- **Information density:** Operators need many data points visible simultaneously. Optimise for data-per-pixel, not whitespace aesthetics.
- **Responsive:** One layout system flexing from 1920px desktop to 375px phone. NavigationRail on desktop, BottomNav on mobile.
- **Composable:** Future: drag-and-drop widget layouts saved per mission profile. MVP: well-considered fixed layouts.
- **Immediate feedback:** Every action produces visual feedback within 200ms. Optimistic UI where safe.

### 6.2 Colour Palette

| Token          | Hex       | Usage                                  |
| -------------- | --------- | -------------------------------------- |
| Background     | `#0D1117` | Primary app background                 |
| Surface        | `#161B22` | Cards, panels, sidebars                |
| Surface Light  | `#21262D` | Hover states, alternating rows         |
| Border         | `#30363D` | Dividers, card edges                   |
| Text Primary   | `#E6EDF3` | Headings, primary readouts             |
| Text Secondary | `#8B949E` | Labels, descriptions                   |
| Accent         | `#58A6FF` | Selected items, links, primary actions |
| Success        | `#3FB950` | Connected, GPS fix, healthy state      |
| Warning        | `#D29922` | Battery medium, HDOP high, degraded    |
| Danger         | `#F85149` | Disconnected, no GPS, critical battery |

### 6.3 Typography

- **UI text:** System sans-serif (SF Pro, Roboto, Segoe UI). No custom font assets to bundle.
- **Telemetry values:** Monospace (SF Mono, JetBrains Mono). Bold for primary readouts.
- **SQL editor:** Monospace, 13px. Keyword highlighting in accent, strings in success, numbers in warning.

### 6.4 Layout Breakpoints

| Breakpoint | Width      | Navigation            | Fly View                                   |
| ---------- | ---------- | --------------------- | ------------------------------------------ |
| Desktop    | > 1200px   | NavigationRail (left) | Map + PFD cols, telemetry strip right      |
| Tablet     | 768–1200px | NavigationRail (left) | Map top, PFD bottom, strip collapsed       |
| Mobile     | < 768px    | BottomNavigationBar   | Map fullscreen, PFD overlay, pull-up sheet |

### 6.5 Iconography & Branding

The Helios logo should evoke a stylised sun with radiating sight lines — connecting the sun god's all-seeing gaze with the drone's aerial perspective. Colour: the accent blue (`#58A6FF`) on dark background. The logo should work at 16px (favicon) and 512px (splash screen).

When shown alongside Argus branding, Helios should appear as a peer product within the same family. Shared typography and colour tokens, differentiated by icon/mark.

---

## 7. MAVLink Integration

### 7.1 Core Messages (MVP)

| Message             | ID  | Dir    | Usage                                           |
| ------------------- | --- | ------ | ----------------------------------------------- |
| HEARTBEAT           | 0   | In/Out | Keepalive, vehicle type, flight mode, arm state |
| ATTITUDE            | 30  | In     | Roll, pitch, yaw + angular rates for PFD        |
| GLOBAL_POSITION_INT | 33  | In     | GPS lat/lon/alt for map and altitude            |
| GPS_RAW_INT         | 24  | In     | Fix type, satellite count, HDOP                 |
| SYS_STATUS          | 1   | In     | Battery voltage, current, remaining %           |
| VFR_HUD             | 74  | In     | Airspeed, groundspeed, heading, throttle, climb |
| RC_CHANNELS         | 65  | In     | RC input channels                               |
| SERVO_OUTPUT_RAW    | 36  | In     | Servo/motor outputs                             |
| VIBRATION           | 241 | In     | Vibration levels, clipping counts               |
| STATUSTEXT          | 253 | In     | Autopilot text messages                         |
| COMMAND_LONG        | 76  | Out    | Arm/disarm, mode change, reboot                 |
| MISSION_ITEM_INT    | 73  | In/Out | Waypoint upload/download                        |
| PARAM_VALUE         | 22  | In/Out | Parameter read/write                            |

### 7.2 Transport Layer

- **UDP (default):** Bind 0.0.0.0:14550. Standard for SITL and telemetry radios in AP mode.
- **TCP:** Connect to host:5760. Companion computers and mavlink-router.
- **Serial:** USB-serial radios (SiK, RFD900) via serial_port_flutter. Default 57600 baud.

### 7.3 Autopilot Compatibility

| Autopilot              | Support | Notes                                                            |
| ---------------------- | ------- | ---------------------------------------------------------------- |
| ArduPilot (ArduPlane)  | Full    | Primary target. Fixed-wing + VTOL modes.                         |
| ArduPilot (ArduCopter) | Partial | Multirotor features not prioritised initially.                   |
| PX4                    | Partial | Shared MAVLink common dialect. PX4-specific commands may differ. |

### 7.4 MAVLink Signing

MAVLink v2 supports message signing (HMAC-SHA256) to prevent command injection. Helios should implement signing with a configurable key, rejecting unsigned commands in signed mode. Critical for defence and commercial deployments.

---

## 8. Security Considerations

### 8.1 Data at Rest

- **Flight databases:** DuckDB files are unencrypted by default. Sensitive deployments should use OS-level disk encryption (LUKS, FileVault, BitLocker).
- **Parquet exports:** Encrypt before transmission. AES-256-GCM at file level.
- **Map tile cache:** Cached tiles may reveal operational areas. Cache directory should be on encrypted storage for sensitive ops.

### 8.2 Data in Transit

- **Argus sync:** HTTPS/TLS 1.3 minimum. Mutual TLS for defence. API key or certificate authentication.
- **MAVLink link:** MAVLink signing (see 7.4). Consider encrypted transports (e.g. WireGuard tunnel) for long-range 4G links.

### 8.3 Access Control

MVP is single-user desktop. Future multi-user support should include:

- **Roles:** Pilot (full control), Observer (read-only telemetry), Mission Commander (plan + monitor, no direct control), Analyst (Analyse view only).
- **Authentication:** Local accounts for field use. LDAP/OIDC integration for enterprise.
- **Audit log:** Every command sent to the vehicle recorded in the events table with operator identity.

### 8.4 Supply Chain

All dependencies must be from trusted registries (pub.dev, npm). Pin versions in pubspec.yaml. Run `dart pub audit` regularly. The DuckDB native binary is fetched at build time from the official DuckDB releases.

---

## 9. Testing Strategy

### 9.1 Unit Tests

- **Vehicle state:** Test all state transitions (arm/disarm, mode changes, GPS fix gain/loss).
- **TelemetryStore:** Test schema creation, buffering, flush, query, Parquet export.
- **MavlinkService:** Test message parsing, heartbeat watchdog, transport switching.
- **Analytics templates:** Verify each SQL template executes without error on synthetic data.

### 9.2 Widget Tests

Test PFD rendering at extreme attitudes, telemetry strip at boundary values (0% battery, 0 satellites), and layout responsiveness at each breakpoint.

### 9.3 Integration Tests

- **SITL loop:** Connect to ArduPilot SITL (sim_vehicle.py). Verify heartbeat, telemetry flow, mission upload/download, arm/disarm commands.
- **DuckDB round-trip:** Record a SITL flight, stop, reopen in Analyse view, run all templates, export Parquet, verify schema.

### 9.4 Hardware-in-the-Loop

Test with physical flight controllers (Pixhawk 6C, Cube Orange) connected via USB and telemetry radio. Verify serial transport, parameter read/write, firmware version detection.

---

## 10. Development Phases

### Phase 1: Foundation (Weeks 1–4)

**Goal:** Connect to a simulated vehicle, display telemetry, record to DuckDB.

- Flutter project scaffold with NavigationRail shell.
- MavlinkService: UDP transport, dart_mavlink parser, heartbeat watchdog.
- Riverpod vehicle state: attitude, GPS, battery, status providers.
- TelemetryStore: DuckDB init, schema creation, buffered inserts, flush timer.
- Fly View: basic PFD (CustomPainter), telemetry strip, connection badge.
- Setup View: connection config (UDP address/port), connect/disconnect, start/stop recording.

**Exit criteria:** Connect to ArduPlane SITL, see live attitude/GPS/battery, record a 5-minute flight to .duckdb file.

### Phase 2: Map & Analytics (Weeks 5–8)

**Goal:** Spatial awareness and the analytics differentiator.

- flutter_map integration with OSM tiles and vehicle position marker.
- Offline tile caching (flutter_map_tile_caching) for field use.
- Vehicle trail drawing on map.
- Analyse View: flight browser, SQL query editor, results table.
- Pre-built query templates (vibration, battery, GPS, altitude, anomaly detection).
- Parquet export from Analyse view.

**Exit criteria:** Fly a SITL mission, see vehicle on map, open recorded flight in Analyse view, run all templates, export Parquet.

### Phase 3: Mission Planning (Weeks 9–12)

**Goal:** Plan and fly autonomous missions.

- Plan View: tap-to-place waypoints on map.
- Waypoint editing (altitude, speed, loiter radius).
- Mission upload/download via MAVLink mission protocol.
- Active mission overlay on Fly View map.
- fl_chart integration in Analyse view for telemetry time-series plots.

**Exit criteria:** Plan a multi-waypoint mission in Plan view, upload to SITL, fly autonomously, see progress on Fly view map, analyse flight in Analyse view.

### Phase 4: Polish & Hardware (Weeks 13–16)

**Goal:** Field-ready with real hardware.

- Serial transport for USB telemetry radios.
- Parameter editor in Setup view.
- Video stream widget (RTSP).
- Speed/altitude tape instruments on PFD.
- Survey planner in Plan view.
- Terrain-aware altitude (SRTM data).
- Mobile layout (BottomNavigationBar, responsive Fly view).
- First hardware flight test.

**Exit criteria:** Complete a real-world flight with a physical ArduPlane/VTOL, recording full telemetry, with mission planned and monitored in Helios.

### Phase 5: Argus Integration (Weeks 17–20)

**Goal:** Close the loop with the Argus analytics platform.

- Argus Parquet ingestion connector.
- Fleet-wide dashboards in Argus.
- Automated sync agent (configurable endpoint, schedule).
- Schema versioning between Helios and Argus.
- Geofence editor.
- MAVLink signing implementation.
- Multi-user RBAC (if Argus requires it).

**Exit criteria:** Multiple flights from multiple devices sync to Argus. Fleet dashboard showing cross-mission analytics.

---

## 11. Project Structure

```
lib/
├── main.dart                          Entry point, Riverpod setup
├── core/
│   ├── mavlink/
│   │   ├── mavlink_service.dart       Connection + MAVLink parsing
│   │   └── command_sender.dart        Outbound command builder
│   ├── telemetry/
│   │   ├── telemetry_store.dart       DuckDB engine
│   │   └── export_service.dart        Parquet export + Argus sync
│   └── mission/
│       └── mission_service.dart       Mission protocol handler
├── features/
│   ├── fly_view.dart                  In-flight screen
│   ├── plan_view.dart                 Mission planning
│   ├── analyse_view.dart              DuckDB analytics
│   └── setup_view.dart                Config + connections
└── shared/
    ├── models/
    │   └── vehicle_state.dart         Vehicle state + providers
    ├── theme/
    │   └── helios_theme.dart          Dark theme tokens
    └── widgets/                       PFD, gauges, badges, etc.

test/                                  Mirrors lib/ structure
assets/                                Icons, default tile cache
docs/                                  This spec + API docs
```

---

## 12. Open Questions & Decisions

| #   | Question                 | Options                                    | Recommendation                                                                |
| --- | ------------------------ | ------------------------------------------ | ----------------------------------------------------------------------------- |
| 1   | Repository hosting       | GitHub / GitLab / self-hosted              | GitHub under the Argus org for discoverability and community.                 |
| 2   | CI/CD pipeline           | GitHub Actions / GitLab CI                 | GitHub Actions. Flutter has official actions for build/test.                  |
| 3   | Plugin architecture (P2) | Dart packages / FFI / gRPC sidecar         | Dart packages distributed via pub.dev. Lowest friction for contributors.      |
| 4   | Mobile priority          | iOS-first / Android-first / both           | Android-first (tablet in field, no App Store review delays). iOS fast-follow. |
| 5   | SITL integration for dev | Local ArduPilot / Docker SITL / Cloud SITL | Docker Compose with ArduPilot SITL for reproducible dev environment.          |
| 6   | Licence                  | Apache 2.0 / MIT / GPL                     | Apache 2.0. Permissive, patent grant, compatible with defence procurement.    |
| 7   | Argus data contract      | Parquet schema / protobuf / JSON           | Parquet with shared schema definition in a separate repo.                     |
| 8   | Map tile provider        | OSM / MapTiler / Mapbox                    | OSM default (free, no API key). MapTiler as optional premium layer.           |

---

_Helios GCS — Part of the Argus Platform_
