# Helios GCS — Vision & Architecture Specification

**Version**: 1.0.0 | **Status**: Draft | **Date**: 2026-03-24
**Part of**: Argus Platform | **Licence**: Apache 2.0

---

## 1. Vision

Helios GCS is an open-source ground control station for MAVLink-enabled fixed-wing and VTOL unmanned aircraft. It replaces ageing desktop-first GCS tools with a modern, cross-platform Flutter application backed by DuckDB embedded analytics.

**Core thesis**: Drone telemetry is a data problem, not just a display problem. Helios records every message into an embedded analytical database, making post-flight analysis as powerful as the in-flight display.

**Tagline**: _Helios sees from the sky. Argus sees from the ground._

### 1.1 Strategic Position

- **Helios** = sky-facing sensor layer (field-deployed, embedded, offline-first)
- **Argus** = ground-facing analytics layer (central, fleet-wide, ML-powered)
- **Data bridge** = Apache Parquet interchange format

### 1.2 Target Users

| Persona | Role | Primary View | Key Need |
|---------|------|-------------|----------|
| Pilot | Remote pilot in command | Fly View | Real-time SA, low-latency controls |
| Mission Planner | Pre-flight ops | Plan View | Waypoint editing, coverage planning |
| Flight Analyst | Post-flight review | Analyse View | SQL queries, trend detection |
| Fleet Manager | Multi-vehicle ops | Analyse + Argus | Cross-mission correlation |
| Developer | Extending Helios | All views | Clean APIs, plugin architecture |

### 1.3 Design Principles

1. **Offline-first**: Full functionality without connectivity. No cloud dependency.
2. **Data-native**: Every flight is a queryable database. SQL is a first-class citizen.
3. **Dark-first**: High contrast for outdoor tablet use. Sunlight readable.
4. **Information-dense**: Maximise data-per-pixel. Operators need many readouts visible simultaneously.
5. **Progressive disclosure**: Simple by default, powerful on demand.
6. **Platform-native**: Flutter compiles native. No Electron bloat. No web runtime.

---

## 2. System Architecture

### 2.1 Layered Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   PRESENTATION LAYER                     │
│  Flutter Widgets (Fly, Plan, Analyse, Setup)            │
│  CustomPainter (PFD, HUD, gauges) │ Responsive layouts  │
├─────────────────────────────────────────────────────────┤
│                      STATE LAYER                         │
│  Riverpod Providers                                      │
│  VehicleState │ ConnectionState │ RecordingState         │
│  MissionState │ AnalyticsState                           │
├─────────────────────────────────────────────────────────┤
│                     SERVICE LAYER                        │
│  MavlinkService │ TelemetryStore │ MissionService       │
│  ExportService  │ MapTileService │ VideoService          │
├─────────────────────────────────────────────────────────┤
│                      DATA LAYER                          │
│  DuckDB (one .duckdb per flight)                        │
│  File system (tile cache, config, exports)              │
│  MAVLink transport (UDP/TCP/Serial)                     │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Dual Data Path

The core architectural innovation enabling real-time display and analytical queries simultaneously.

#### Real-Time Path (< 100ms latency)

```
MAVLink bytes → Transport (UDP/TCP/Serial)
  → MavlinkService.parse()
  → Decoded MAVLink message
  → Riverpod StateNotifier.update()
  → Flutter widget rebuild (ConsumerWidget)
```

- Zero database involvement — pure in-memory Dart streams
- Target: < 50ms from wire to pixel for attitude data
- StreamController broadcasts to multiple consumers

#### Analytics Path (1-second batch cadence)

```
Decoded MAVLink message → TelemetryStore.buffer()
  → Periodic timer (1s) → batch INSERT
  → DuckDB columnar storage
  → SQL queries from Analyse View
```

- Buffered writes prevent I/O blocking the UI thread
- DuckDB runs in a dedicated Dart isolate
- Batch INSERT of 20-50 rows per table per second

#### Export Path (on-demand)

```
DuckDB COPY TO → Parquet file
  → File system / USB / HTTP upload
  → Argus platform ingestion
```

### 2.3 Isolate Architecture

Flutter is single-threaded by default. Helios uses Dart isolates to prevent blocking the UI:

| Isolate | Responsibility | Communication |
|---------|---------------|---------------|
| Main (UI) | Widget rendering, user input, state management | — |
| MAVLink I/O | Socket/serial read/write, message parsing | SendPort/ReceivePort |
| DuckDB Worker | All database operations (insert, query, export) | SendPort/ReceivePort |
| Video Decoder | RTSP frame decoding (P1) | Texture bridge |

**Rule**: No database call or network I/O ever runs on the main isolate.

### 2.4 Dependency Injection

All services are provided via Riverpod. No service locator pattern. No singletons.

```dart
// Service providers (overridable for testing)
final mavlinkServiceProvider = Provider<MavlinkService>((ref) => ...);
final telemetryStoreProvider = Provider<TelemetryStore>((ref) => ...);
final missionServiceProvider = Provider<MissionService>((ref) => ...);
final exportServiceProvider = Provider<ExportService>((ref) => ...);
```

### 2.5 Error Boundaries

Every view has an error boundary widget that catches and displays errors gracefully without crashing the app. Critical errors (lost vehicle link) trigger global alerts regardless of active view.

---

## 3. Technology Stack — Validated

| Layer | Technology | Version | Licence | Status |
|-------|-----------|---------|---------|--------|
| UI Framework | Flutter | 3.x (latest stable) | BSD-3 | Stable, production-ready |
| Language | Dart | 3.x | BSD-3 | Stable |
| State | flutter_riverpod | 2.x | MIT | Stable, widely adopted |
| Database | DuckDB via `duckdb_dart` | 1.x | MIT | Stable — TigerEyeLabs FFI bindings, multi-platform. Official DuckDB Dart client docs at duckdb.org. |
| Protocol | MAVLink v2 via code-generated Dart bindings | custom | MIT | Generated from MAVLink XML definitions. Vendored in `packages/dart_mavlink/`. See §3.1. |
| Maps | flutter_map | 7.x | BSD-3 | Stable, OSM-based, no API key |
| Offline Tiles | Custom tile caching (NOT flutter_map_tile_caching) | custom | Apache 2.0 | FMTC is GPL-3.0 — incompatible with Apache 2.0. Custom SQLite-backed cache. See §3.3. |
| Charts | fl_chart | 0.69+ | MIT | Stable. Use for Analyse View. For real-time, throttle to 2-4 Hz or use CustomPainter. |
| Serial (desktop) | flutter_libserialport | 0.4.x | LGPL-3.0 | FFI to libserialport. LGPL via dynamic linking is Apache-2.0 compatible. Legal review recommended. |
| Serial (Android) | usb_serial | 0.4.x | BSD-3 | Android USB Host API for field tablets with USB OTG radios. |
| Video (P1) | media_kit | 1.x | MIT (LGPL deps) | libmpv backend for RTSP. LGPL via dynamic linking — legal review recommended. |
| Export | Apache Parquet via DuckDB | — | Apache 2.0 | Native DuckDB COPY TO |
| Networking | dart:io (Socket, RawDatagramSocket) | built-in | BSD-3 | Native UDP/TCP |

### 3.1 MAVLink Dart Strategy

No mature, production-quality MAVLink Dart library exists. The recommended approach (consistent with how every mature MAVLink implementation works) is **code generation from MAVLink XML definitions**:

1. **MAVLink XML definitions** — Source from `github.com/mavlink/mavlink` (`common.xml`, `ardupilotmega.xml`).
2. **Code generator** — Extend `mavgen` (Python/Jinja2, part of pymavlink) to output Dart, OR write a standalone Dart generator. Produces:
   - Typed Dart class per message (e.g., `AttitudeMessage`, `HeartbeatMessage`)
   - Serialise/deserialise methods with correct CRC-extra
   - MAVLink v2 packet framing, CRC-16/MCRF4XX, optional signing
3. **Runtime library** — Small pure-Dart library (~500 lines) for packet framing, parser state machine, and transport abstraction.
4. **Vendored in `packages/dart_mavlink/`** — Local package dependency, not pub.dev.

Fallback: Fork `github.com/nus/dart_mavlink` (existing v1/v2 parser) and extend with missing messages. This is faster to start but harder to maintain long-term.

### 3.2 DuckDB Dart Bindings

`duckdb_dart` by TigerEyeLabs provides FFI bindings to DuckDB's C API:
- Official documentation at `duckdb.org/docs/stable/clients/dart`
- Supports: macOS, iOS, Android, Linux, Windows, Web (via DuckDB WASM)
- Dedicated background isolates per connection for zero-copy query results
- Production-suitable per DuckDB team

If `duckdb_dart` proves insufficient, the fallback is generating raw FFI bindings from `duckdb.h` using `package:ffigen`.

### 3.3 Tile Caching Strategy (Licence-Safe)

`flutter_map_tile_caching` (FMTC) is **GPL-3.0** — incompatible with Helios's Apache 2.0 licence.

Custom tile caching implementation required (~300-500 lines):
- Intercept tile requests via a custom `TileProvider` for `flutter_map`
- Store tiles in SQLite (via `sqflite`) or filesystem, keyed by `z/x/y`
- Serve from cache when offline
- Bulk download: HTTP fetch tiles for a given bounds + zoom levels, store locally
- Cache management: list regions, delete, size tracking, LRU eviction

This gives full control over cache behaviour for field conditions and avoids GPL dependency.

### 3.2 Technology Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| DuckDB over SQLite | DuckDB | Columnar OLAP engine. 10-100x faster for analytical queries (time-window aggregations, statistical functions). Native Parquet export. |
| Flutter over Qt | Flutter | Single codebase for 6 platforms. Faster development. Better mobile UX. Hot reload. |
| Flutter over Electron | Flutter | Native compilation. No Chromium overhead (~150MB). Better performance on field hardware. |
| Riverpod over BLoC | Riverpod | Compile-safe, less boilerplate, better testability with ProviderScope overrides. |
| flutter_map over Google Maps | flutter_map | No API key required. OSM tiles free. True offline support. |
| Isolates over compute() | Dedicated isolates | Long-lived workers for MAVLink I/O and DuckDB. `compute()` is for one-shot tasks. |

---

## 4. Platform Support Matrix

| Platform | Priority | Transport | Notes |
|----------|----------|-----------|-------|
| Linux (x64) | P0 | UDP, TCP, Serial | Primary dev platform. SITL testing. |
| macOS (arm64/x64) | P0 | UDP, TCP, Serial | Dev machines. |
| Windows (x64) | P0 | UDP, TCP, Serial | Mission Planner replacement target. |
| Android (arm64) | P1 | UDP, TCP, USB OTG | Field tablets. Android-first mobile. |
| iOS (arm64) | P2 | UDP, TCP | No serial without MFi. App Store constraints. |
| Web | P2 | WebSocket only | No raw UDP/TCP. Limited use case. |

---

## 5. Non-Functional Requirements

### 5.1 Performance Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| Attitude display latency | < 50ms wire-to-pixel | Oscilloscope + camera frame analysis |
| Map marker update rate | 10 Hz (100ms) | Frame timing |
| PFD frame rate | 60 fps sustained | Flutter DevTools |
| DuckDB batch insert | < 10ms for 50-row batch | Stopwatch in isolate |
| DuckDB query (1hr flight) | < 500ms for aggregation | SQL EXPLAIN ANALYZE |
| Parquet export (1hr flight) | < 5s | Wall clock |
| App cold start | < 3s to interactive | Timeline trace |
| Memory usage (1hr recording) | < 500MB RSS | Process monitor |

### 5.2 Reliability

- App must not crash on MAVLink parse errors (malformed packets silently dropped with counter)
- Lost-link detection within 5 seconds (heartbeat watchdog)
- DuckDB write failures must not block the real-time path
- Graceful degradation: if DuckDB isolate crashes, real-time display continues
- Auto-recovery: reconnect transport on transient failures with exponential backoff

### 5.3 Accessibility

- Minimum contrast ratio 4.5:1 for all text (WCAG AA)
- Keyboard navigation for all desktop views
- Screen reader labels on all interactive elements
- Colour-blind safe: never encode information solely in colour (use shape/text)
- Configurable font size scaling (0.8x - 1.5x)

### 5.4 Internationalisation (P2)

- All user-facing strings via `flutter_localizations` and ARB files
- Initial locale: en-GB, en-US
- Future: de, fr, ja, zh-CN (community contributed)
- Telemetry units: metric (default) / imperial (configurable)
- Coordinate formats: decimal degrees (default), DMS, UTM

### 5.5 Data Integrity

- Every DuckDB file is self-contained (no external references)
- Flight metadata table includes schema version for forward compatibility
- Checksums on Parquet exports for integrity verification
- Atomic flush: partial writes on crash should not corrupt the database (DuckDB WAL)
