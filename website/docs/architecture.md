# Architecture

This document describes the internal architecture of Helios GCS, including the layered design, directory structure, technology stack, and key technical decisions.

## 4-Layer Pattern

Helios follows a strict 4-layer architecture. Each layer depends only on the layer below it.

```
Presentation (UI)
      |
   State (Riverpod)
      |
   Service (Business Logic)
      |
   Data (Transport, Storage, Files)
```

| Layer | Responsibility | Location |
|---|---|---|
| Presentation | Flutter widgets, views, user interaction | `lib/features/` |
| State | Riverpod providers and state notifiers | `lib/shared/providers/` |
| Service | Protocol handling, mission logic, recording, calibration | `lib/core/` |
| Data | MAVLink transport (UDP/TCP/Serial), DuckDB storage, file I/O | `lib/core/*/`, `packages/` |

### Rules

- Presentation widgets never call service methods directly. They read state from Riverpod providers and dispatch actions through provider methods.
- State notifiers receive decoded messages from services and maintain the canonical application state.
- Services are plain Dart classes with no Flutter dependency. They can be tested without a widget tree.
- Data layer code handles raw bytes, file operations, and database access.

## Directory Structure

```
lib/
  core/                    Business logic (no UI imports)
    mavlink/               MAVLink parser, transports, heartbeat watchdog, flight modes
    mission/               Mission upload/download protocol, corridor scan, survey
    params/                Parameter fetch/set/export, metadata service
    calibration/           Sensor calibration sequences
    fence/                 Geofence upload/download
    logs/                  Dataflash log download
    telemetry/             DuckDB recording, schema, analytics, replay, export
    map/                   Offline tile caching
    msp/                   MSP protocol service (Betaflight/iNav)
    rally/                 Rally point management
  features/                UI views (one directory per tab)
    fly/                   Fly View -- PFD, map, telemetry tiles, action panels
    plan/                  Plan View -- mission editor, survey dialogs, geofence
    analyse/               Data View -- flight browser, charts, SQL editor
    video/                 Video View -- RTSP streaming, HUD overlay
    setup/                 Setup View -- connection, params, calibration, settings
    config/                FC Config View -- parameter editor
    inspect/               Inspect View -- MAVLink packet inspector
  shared/                  Cross-feature code
    models/                Immutable data classes (Equatable)
    providers/             Riverpod providers and state notifiers
    widgets/               Shared widgets (status bar, notification overlay)
    theme/                 Colour tokens, typography tokens

packages/
  dart_mavlink/            Vendored MAVLink v2 parser and frame builder
  duckdb_dart_patched/     DuckDB FFI bindings (patched for macOS)

scripts/
  generate_crc_extras.dart CRC extras code generation from MAVLink XML
  sim_telemetry.dart       Telemetry simulator for development without SITL
  mavlink_xml/             MAVLink XML definitions (common.xml, ardupilotmega.xml)

test/                      Tests mirroring lib/ structure
```

## Technology Stack

| Component | Technology | Version | Purpose |
|---|---|---|---|
| Framework | Flutter | 3.38 | Cross-platform UI (macOS, Linux, Windows) |
| Language | Dart | 3.10 | Application logic |
| State Management | Riverpod | -- | Reactive state with providers and notifiers |
| Database | DuckDB | -- | Columnar OLAP storage for flight telemetry |
| Maps | flutter_map | -- | OpenStreetMap tile rendering (no API key) |
| Video | media_kit | -- | RTSP streaming with LGPL-compatible dynamic linking |
| Serial | flutter_libserialport | -- | USB and radio telemetry serial port access |
| MAVLink | dart_mavlink (vendored) | v2 | MAVLink protocol parsing and frame building |

## MAVLink Parser

Helios uses a vendored MAVLink v2 parser located in `packages/dart_mavlink/`. The parser is maintained in-tree because no mature MAVLink Dart package exists on pub.dev.

### Parsing Pipeline

1. Raw bytes arrive from the transport (UDP/TCP/Serial).
2. `MavlinkParser` accumulates bytes and scans for MAVLink v2 frame start markers (`0xFD`).
3. When a complete frame is detected, the parser validates the CRC using pre-generated CRC extras.
4. If the CRC passes, the parser deserializes the payload into a typed Dart message class.
5. The decoded `MavlinkMessage` is broadcast on the `MavlinkService.messageStream`.

### CRC Generation

CRC extras are auto-generated from the MAVLink XML definitions at build time. The generation process:

1. Source XML files are stored in `scripts/mavlink_xml/` (common.xml, ardupilotmega.xml).
2. Running `make gen-crc` executes `scripts/generate_crc_extras.dart`.
3. The script parses the XML, computes CRC extras for each message, and writes `packages/dart_mavlink/lib/src/generated_crc_extras.dart`.
4. The generated file contains 305 CRC extras covering all standard and ArduPilot-specific messages.

The generated CRC extras file must never be hand-edited. Always regenerate from XML.

### Frame Builder

`MavlinkFrameBuilder` constructs outgoing MAVLink v2 frames for sending commands, mission items, parameter requests, and other GCS-to-vehicle messages. It handles sequence numbering, system/component ID assignment, and CRC computation.

## 30Hz State Batching

High-frequency MAVLink messages (ATTITUDE at 25-50Hz, GPS at 5-10Hz, SYS_STATUS at 1-2Hz) arrive at different rates. Updating the Flutter widget tree on every incoming message would cause excessive rebuilds.

`VehicleStateNotifier` solves this with a batched update pattern:

1. Each incoming MAVLink message handler writes fields to a `_pending` VehicleState instance and sets a `_dirty` flag.
2. A persistent timer fires every 33ms (approximately 30Hz).
3. On each timer tick, if `_dirty` is true, the `_pending` state is published as the new `state`, triggering a single widget rebuild.
4. Between timer ticks, multiple messages accumulate into the same `_pending` instance without triggering any rebuilds.

This limits UI updates to 30fps regardless of how many MAVLink messages arrive per second, while ensuring that every message's data is reflected in the next frame.

### PFD Ticker Interpolation

The Primary Flight Display (PFD) attitude indicator renders at 60fps using Flutter's `Ticker`. Between 10Hz telemetry updates, the PFD interpolates roll, pitch, and yaw using angular rates from the ATTITUDE message. This provides smooth visual rotation without requiring 60Hz telemetry data.

## DuckDB Per-Flight Storage

Every flight is recorded into its own DuckDB database file. This design provides several advantages over a single shared database:

| Advantage | Explanation |
|---|---|
| Isolation | Corrupted or incomplete flights do not affect other data |
| Portability | Individual flight files can be copied, shared, or archived |
| Performance | Columnar OLAP queries on a single flight avoid scanning unrelated data |
| Cleanup | Deleting a flight is a simple file deletion |

### Schema

The telemetry schema stores time-series data with microsecond timestamps. Key columns include attitude (roll, pitch, yaw), position (lat, lon, alt), speed, battery, GPS quality, EKF variances, and sensor health bitmasks.

### Analytics

DuckDB's columnar engine enables analytical queries that would be slow in a row-oriented database:

- Aggregate statistics (min/max/avg altitude, total distance, flight duration)
- Time-windowed analysis (battery drain rate over 30-second windows)
- Cross-column correlation (vibration vs altitude, EKF variance over time)
- Export to Parquet for external tools (Python, R, MATLAB)

## Key Design Decisions

| Decision | Rationale |
|---|---|
| DuckDB per flight (not SQLite) | Columnar OLAP engine, 10-100x faster for analytics queries over time-series data |
| Vendored dart_mavlink | No mature MAVLink Dart package on pub.dev; in-tree parser allows full control |
| duckdb_dart patched for macOS | Upstream package only supports Linux and Windows |
| flutter_map (not google_maps) | No API key required, OSM tiles, Apache 2.0 license compatible |
| Custom CachedTileProvider | flutter_map_tile_caching is GPL-3.0, incompatible with Apache 2.0 |
| media_kit for video | LGPL via dynamic linking, cross-platform RTSP support |
| flutter_libserialport | C-based libserialport works on macOS, Linux, and Windows |
| 30Hz state batching | Prevents 50Hz ATTITUDE from triggering 50 widget rebuilds per second |
| PFD Ticker interpolation | 60fps smooth rendering between 10Hz telemetry samples |
| MAV_CMD_SET_MESSAGE_INTERVAL | Modern per-message rate control with legacy REQUEST_DATA_STREAM fallback |
| 305 auto-generated CRC extras | Generated from MAVLink XML at build time, not hand-coded |
| Equatable models | Immutable value objects with structural equality for reliable Riverpod state comparison |
| Protocol auto-detection | 5-second probe supports both MAVLink and MSP without manual protocol selection |

## Build System

Helios uses a Makefile for common development tasks:

| Command | Action |
|---|---|
| `make check` | Run `dart analyze` and `flutter test` (run before every commit) |
| `make run` | Run on macOS |
| `make run-linux` | Run on Linux |
| `make build-macos` | Release build for macOS |
| `make package-macos` | Create .dmg installer |
| `make sitl` | Launch ArduPilot SITL (downloads binary on first run) |
| `make gen-crc` | Regenerate MAVLink CRC extras from XML |

All commands can also be run directly without Make:

```bash
dart analyze --fatal-warnings lib/ test/ packages/dart_mavlink/
flutter test
flutter run -d macos
```
