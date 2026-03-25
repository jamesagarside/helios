# Helios GCS — Argus Integration & Gap Analysis

**Version**: 1.0.0 | **Status**: Draft | **Date**: 2026-03-24

---

## 1. Argus Integration Architecture

### 1.1 Two-Tier Data Pipeline

```
┌──────────────────────────┐     ┌──────────────────────────┐
│      TIER 1: FIELD       │     │      TIER 2: BASE        │
│       (Helios)           │     │       (Argus)            │
│                          │     │                          │
│  Flutter + DuckDB        │     │  Analytics Platform      │
│  Laptop / Tablet         │     │  Server / Cloud          │
│  Fully offline           │     │  Fleet-wide dashboards   │
│                          │     │                          │
│  .duckdb → .parquet ─────┼────→│  Parquet ingestion       │
│                          │     │  ML anomaly detection    │
│  One file per flight     │     │  Cross-mission analysis  │
└──────────────────────────┘     └──────────────────────────┘
         ↕                                ↕
    Field tablet                   Ops centre / cloud
```

### 1.2 Data Transfer Modes

| Mode | Mechanism | Latency | Use Case |
|------|-----------|---------|----------|
| USB sync | Copy Parquet files to USB drive | Manual | Air-gapped environments |
| File drop | Copy to shared folder / NAS | Near-real-time | Base station with LAN |
| HTTP upload | POST to Argus REST endpoint | Minutes | Connected field ops |
| S3 bucket | Upload to S3 / MinIO | Minutes | Cloud deployments |
| Automatic | Background sync on schedule | Configurable | Enterprise fleet ops |

### 1.3 Sync Protocol

```dart
class ArgusSyncAgent {
  /// Configure the Argus endpoint for sync.
  void configure(ArgusEndpoint endpoint);

  /// Queue a flight export for sync.
  Future<void> queueSync(String flightPath);

  /// Process the sync queue.
  /// Retries failed uploads with exponential backoff.
  Future<SyncReport> processQueue();

  /// Get the current sync status.
  SyncStatus get status;

  /// Schedule automatic sync at interval.
  void scheduleAutoSync(Duration interval);

  /// Cancel automatic sync.
  void cancelAutoSync();
}

class SyncStatus {
  final int pendingFlights;
  final int syncedFlights;
  final int failedFlights;
  final DateTime? lastSyncTime;
  final bool isAutoSyncEnabled;
}
```

### 1.4 Schema Contract

Helios and Argus share a schema definition maintained in a separate repository:

```
argus-telemetry-schema/
├── v1/
│   ├── attitude.parquet.schema   # Apache Parquet schema definition
│   ├── gps.parquet.schema
│   ├── battery.parquet.schema
│   ├── ...
│   └── manifest.schema.json      # JSON Schema for manifest.json
├── v2/
│   └── ...                       # Future schema versions
└── README.md
```

Schema evolution rules:
- New columns: allowed (nullable, with defaults)
- Removed columns: deprecated first, removed in next major version
- Type changes: never (create new column instead)
- Table renames: never (create new table, deprecate old)

### 1.5 Authentication

| Method | Use Case | Implementation |
|--------|----------|----------------|
| API Key | Simple deployments | Bearer token in HTTP header |
| mTLS | Defence / high-security | Client certificate + server verification |
| OAuth 2.0 | Enterprise SSO | Authorization code flow with PKCE |

---

## 2. Gaps Identified in Initial Spec

The following gaps were identified in `helios-inital-spec.md` and have been addressed in this specification:

### 2.1 Gaps Filled

| # | Gap | Resolution | Spec Section |
|---|-----|-----------|--------------|
| 1 | No Dart interface definitions | Full typed interfaces for all services | 06-service-interfaces.md |
| 2 | No error handling strategy | Classified errors (transient, recoverable, fatal, user), propagation rules | 06-service-interfaces.md §6 |
| 3 | No isolate architecture | Dedicated isolates for MAVLink I/O and DuckDB worker | 01-vision §2.3 |
| 4 | No state management detail | Full Riverpod provider hierarchy, freezed models, update throttling | 05-state-management.md |
| 5 | No accessibility considerations | WCAG AA contrast, keyboard nav, screen reader labels, colour-blind safety | 01-vision §5.3 |
| 6 | No internationalisation plan | flutter_localizations, ARB files, metric/imperial, coordinate formats | 01-vision §5.4 |
| 7 | No logging strategy | HeliosLogger with levels, structured logging, no print() | 06-service-interfaces.md §6.3 |
| 8 | No performance targets | Concrete targets for latency, FPS, query time, memory | 01-vision §5.1 |
| 9 | No CI/CD pipeline | GitHub Actions for lint, test, build on 3 platforms | 07-testing.md §7 |
| 10 | No coverage requirements | 80% overall, 90%+ for core services | 07-testing.md §7.2 |
| 11 | No crash recovery | Detect unclosed .duckdb files on launch, WAL recovery | 02-data-model.md §1.2 |
| 12 | No Parquet manifest format | manifest.json with table row counts and SHA-256 checksums | 02-data-model.md §5 |
| 13 | DuckDB Dart package unverified | Verified: duckdb_dart by TigerEyeLabs, multi-platform FFI | 01-vision §3 |
| 14 | dart_mavlink unverified | Verified: exists on GitHub, needs vendoring and enhancement | 01-vision §3.1 |
| 15 | No task-level breakdown | 80+ tasks across 5 phases with hours, acceptance criteria, tests | 09-development-phases.md |
| 16 | No theme implementation detail | Full Dart colour tokens, typography, spacing, component tokens | 04-ui-ux.md §1 |
| 17 | No animation spec | Transition durations and rules (telemetry never animates) | 04-ui-ux.md §10 |
| 18 | No keyboard shortcuts | 12 shortcuts for desktop use | 04-ui-ux.md §11 |
| 19 | No Argus sync protocol | SyncAgent class, queue, retry, scheduling | 10-argus.md §1.3 |
| 20 | No schema versioning detail | Schema version in flight_meta, migration scripts, evolution rules | 02-data-model.md §1.3, 10-argus.md §1.4 |
| 21 | GPS table missing fields | Added vdop, vel, cog from GPS_RAW_INT | 02-data-model.md §2.3 |
| 22 | No BATTERY_STATUS support | Added temperature, mapped to battery table | 02-data-model.md §2.4 |
| 23 | No mission_items table | Added for snapshotting uploaded/downloaded missions | 02-data-model.md §2.10 |
| 24 | No params table | Added for vehicle parameter snapshots | 02-data-model.md §2.11 |
| 25 | No data volume estimates | Calculated per-table volumes for 1hr flight | 02-data-model.md §4 |
| 26 | No MAVLink signing detail | HMAC-SHA256, key management via flutter_secure_storage | 03-mavlink.md §8 |
| 27 | No parameter protocol detail | Full fetch + write protocol with retry | 03-mavlink.md §9 |
| 28 | No command retry logic | 3 attempts with 1s timeout, confirmation increment | 03-mavlink.md §4.2 |
| 29 | No flight mode mapping tables | ArduPlane, ArduCopter, PX4 mode numbers and names | 03-mavlink.md §7 |
| 30 | No responsive layout detail | ASCII wireframes for desktop, tablet, mobile at each view | 04-ui-ux.md §3, 4 |

### 2.2 Decisions Made

| # | Decision | Resolution | Rationale |
|---|----------|-----------|-----------|
| 1 | Repository hosting | GitHub | Discoverability, community, Actions CI |
| 2 | CI/CD pipeline | GitHub Actions | Flutter official actions available |
| 3 | Mobile priority | Android-first | Field tablets, no App Store delays |
| 4 | SITL for dev | Docker Compose | Reproducible dev environment |
| 5 | Licence | Apache 2.0 | Permissive, patent grant, defence compatible |
| 6 | Argus data contract | Parquet with shared schema | DuckDB native export, versioned schema repo |
| 7 | Map tile provider | OSM default | Free, no API key, MapTiler optional premium |
| 8 | DuckDB Dart package | duckdb_dart (TigerEyeLabs) | Actively maintained, multi-platform FFI, official DuckDB docs page |
| 9 | MAVLink Dart package | Code-generated from MAVLink XML | No mature pub.dev package exists. Code generation is how all mature MAVLink impls work. |
| 10 | Serial library (desktop) | flutter_libserialport (LGPL-3.0) | FFI to libserialport. LGPL OK via dynamic linking. |
| 11 | Serial library (Android) | usb_serial (BSD-3) | Android USB Host API for field tablets |
| 12 | Tile caching | Custom (NOT flutter_map_tile_caching) | FMTC is GPL-3.0 — incompatible with Apache 2.0. Custom SQLite cache. |
| 13 | Video streaming | media_kit (MIT + LGPL deps) | libmpv backend for RTSP. Best cross-platform option. |
| 14 | Real-time charts strategy | fl_chart + CustomPainter | fl_chart for post-flight Analyse View. CustomPainter for real-time in-flight. |

### 2.3 Remaining Open Items

| # | Item | Status | Owner | Decision Needed By |
|---|------|--------|-------|-------------------|
| 1 | Plugin architecture (P2) | Deferred | — | Phase 5 |
| 2 | Multi-vehicle support (P2) | Deferred | — | Post-v1.0 |
| 3 | Calibration wizards (P2) | Deferred | — | Post-v1.0 |
| 4 | Firmware flash (P2) | Deferred | — | Post-v1.0 |
| 5 | Audio alerts (P2) | Deferred | — | Post-v1.0 |
| 6 | KML/KMZ import (P2) | Deferred | — | Post-v1.0 |
| 7 | Rally points (P2) | Deferred | — | Post-v1.0 |
| 8 | Flight comparison (P2) | Deferred | — | Phase 5 |
| 9 | Composable widget layouts | Deferred | — | Post-v1.0 |
| 10 | Web platform support | Deferred | — | Post-v1.0 (WebSocket-only transport) |

---

## 3. Competitive Advantage Summary

| Capability | QGC | Mission Planner | DJI FlightHub | **Helios** |
|-----------|-----|----------------|---------------|-----------|
| Open source | Yes | Yes | No | **Yes (Apache 2.0)** |
| Cross-platform (desktop+mobile) | Yes (Qt) | No (Windows) | No (Web+DJI) | **Yes (Flutter)** |
| Embedded SQL analytics | No | No | No | **Yes (DuckDB)** |
| Offline-first | Yes | Yes | No | **Yes** |
| Parquet export | No | No | No | **Yes** |
| Platform integration | None | None | DJI only | **Argus** |
| Modern UI framework | Qt (2005) | .NET (2002) | Web | **Flutter (2018)** |
| Per-flight queryable DB | No | No | No | **Yes** |
| Pre-built analytics templates | No | No | Partial | **Yes (7 templates)** |
| Statistical anomaly detection | No | No | No | **Yes (z-score)** |
