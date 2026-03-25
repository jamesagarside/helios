# Helios GCS — Security & Deployment Specification

**Version**: 1.0.0 | **Status**: Draft | **Date**: 2026-03-24

---

## 1. Security Architecture

### 1.1 Threat Model

| Threat | Vector | Mitigation | Priority |
|--------|--------|-----------|----------|
| MAVLink command injection | Rogue GCS on network | MAVLink v2 signing (HMAC-SHA256) | P1 |
| Flight data exfiltration | Physical device theft | OS-level disk encryption recommendation | P1 |
| Parquet export interception | Network transfer | TLS 1.3 for Argus sync, AES-256-GCM for file | P1 |
| Malicious MAVLink frames | Crafted packets | Strict parser, bounds checking, no buffer overflows | P0 |
| Supply chain attack | Compromised pub.dev package | Pinned versions, `dart pub audit`, vendored forks | P0 |
| Denial of service | Message flood | Rate limiting per message type, max buffer sizes | P1 |
| Parameter tampering | Unauthorised param write | Command confirmation dialogs, audit logging | P0 |

### 1.2 Data at Rest

| Data | Location | Protection |
|------|----------|-----------|
| Flight databases (.duckdb) | App data directory | OS-level encryption (recommended) |
| Parquet exports | User-specified directory | AES-256-GCM before transfer (P1) |
| Map tile cache | App cache directory | None (non-sensitive) |
| Settings | shared_preferences | OS-level protection |
| MAVLink signing keys | OS keychain | flutter_secure_storage |
| Connection history | shared_preferences | No secrets stored |

### 1.3 Data in Transit

| Channel | Protection | Min Version |
|---------|-----------|-------------|
| MAVLink (UDP/TCP/Serial) | MAVLink v2 signing (optional) | — |
| Argus sync | HTTPS TLS 1.3 | P2 |
| Argus sync (defence) | Mutual TLS (mTLS) | P2 |
| Map tile download | HTTPS | — |

### 1.4 Input Validation

Every system boundary validates input:

```dart
// MAVLink: validate frame before processing
class MavlinkValidator {
  static bool isValidFrame(Uint8List data) {
    if (data.isEmpty) return false;
    if (data[0] != 0xFD && data[0] != 0xFE) return false; // v2 or v1 magic
    if (data.length < 12) return false; // minimum v2 frame
    // CRC check handled by parser
    return true;
  }
}

// SQL: parameterised queries for any user input
// (DuckDB templates use static SQL, but user queries run in isolated context)

// File paths: sanitise to prevent directory traversal
class PathValidator {
  static String sanitise(String path) {
    // Reject paths with .. components
    if (path.contains('..')) throw ArgumentError('Invalid path: $path');
    // Resolve to canonical path
    return p.canonicalize(path);
  }
}
```

### 1.5 Licence Compliance

Helios is Apache 2.0. All dependencies must be compatible.

| Dependency | Licence | Compatible? | Notes |
|-----------|---------|-------------|-------|
| Flutter / Dart | BSD-3 | Yes | — |
| flutter_riverpod | MIT | Yes | — |
| duckdb_dart | MIT | Yes | DuckDB engine itself is MIT |
| flutter_map | BSD-3 | Yes | — |
| fl_chart | MIT | Yes | — |
| flutter_libserialport | LGPL-3.0 | Yes (dynamic linking) | FFI = separate binary. Legal review recommended. |
| media_kit | MIT | Yes | — |
| libmpv (media_kit dep) | LGPL-2.1+ | Yes (dynamic linking) | Bundled as .so/.dylib. Legal review recommended. |
| sqflite | BSD-2 | Yes | — |
| usb_serial | BSD-3 | Yes | — |
| **flutter_map_tile_caching** | **GPL-3.0** | **NO — BLOCKED** | **Must NOT be used. Custom tile cache instead.** |

**Action**: Run `dart pub audit` on every CI build. Pin all dependency versions. Vendor `dart_mavlink` as a local package.

### 1.6 Audit Log

Every command sent to the vehicle is recorded in the `events` table:

```sql
INSERT INTO events (ts, type, detail, severity)
VALUES (NOW(), 'command', '{"cmd": "ARM", "result": "ACCEPTED"}', 6);
```

---

## 2. Deployment

### 2.1 Desktop Builds

| Platform | Build Command | Output | Distribution |
|----------|-------------|--------|-------------|
| Linux | `flutter build linux --release` | AppImage | GitHub Releases |
| macOS | `flutter build macos --release` | .app bundle (signed) | GitHub Releases, Homebrew |
| Windows | `flutter build windows --release` | .exe + DLLs | GitHub Releases, MSIX |

### 2.2 Mobile Builds

| Platform | Build Command | Output | Distribution |
|----------|-------------|--------|-------------|
| Android | `flutter build apk --release` | .apk / .aab | GitHub Releases, F-Droid |
| iOS | `flutter build ios --release` | .ipa | TestFlight → App Store |

### 2.3 DuckDB Native Library

The DuckDB native library must be bundled with each platform build:

| Platform | Library | Size (~) | Location |
|----------|---------|----------|----------|
| Linux x64 | `libduckdb.so` | ~30 MB | `lib/` |
| macOS arm64 | `libduckdb.dylib` | ~30 MB | `Frameworks/` |
| macOS x64 | `libduckdb.dylib` | ~30 MB | `Frameworks/` |
| Windows x64 | `duckdb.dll` | ~30 MB | `data/flutter_assets/` |
| Android arm64 | `libduckdb.so` | ~25 MB | `jniLibs/arm64-v8a/` |
| iOS arm64 | `libduckdb.dylib` | ~25 MB | `Frameworks/` |

Total app size with DuckDB: approximately 60-80 MB depending on platform.

### 2.4 Release Process

```
1. Version bump in pubspec.yaml
2. Update CHANGELOG.md
3. Create Git tag: v{major}.{minor}.{patch}
4. GitHub Actions builds all platforms
5. Artefacts uploaded to GitHub Releases
6. Linux AppImage signed with GPG
7. macOS .app signed and notarised with Apple Developer ID
8. Windows MSIX signed
```

### 2.5 Auto-Update (P2)

Desktop builds check for updates on launch:

```dart
class UpdateChecker {
  /// Check GitHub Releases API for newer version.
  Future<UpdateInfo?> checkForUpdate();

  /// Download and apply update (platform-specific).
  Future<void> applyUpdate(UpdateInfo update);
}
```

---

## 3. Development Environment

### 3.1 Prerequisites

```bash
# Flutter SDK (latest stable)
flutter --version  # 3.x required

# Dart SDK (bundled with Flutter)
dart --version  # 3.x required

# Platform-specific:
# Linux: clang, cmake, ninja-build, pkg-config, libgtk-3-dev
# macOS: Xcode 15+, CocoaPods
# Windows: Visual Studio 2022 with C++ workload
```

### 3.2 Getting Started

```bash
git clone https://github.com/argus-platform/helios-gcs.git
cd helios-gcs
flutter pub get
flutter run -d linux  # or macos, windows
```

### 3.3 SITL Development

```bash
# Start ArduPilot SITL in Docker
docker compose -f docker/docker-compose.sitl.yaml up -d

# Or install ArduPilot locally:
# https://ardupilot.org/dev/docs/building-setup-linux.html
sim_vehicle.py --vehicle ArduPlane --frame plane --out=udp:127.0.0.1:14550
```

### 3.4 Code Style

- `dart analyze --fatal-infos` must pass (zero warnings)
- `dart format` must match (enforced in CI)
- No `print()` statements (use HeliosLogger)
- All public APIs have dartdoc comments
- Prefer `final` and `const` everywhere
- Use `freezed` for all immutable data classes
- Use `sealed` classes for exhaustive pattern matching

### 3.5 Dependency Management

```yaml
# pubspec.yaml version pinning strategy:
# - Major + minor pinned, patch flexible
# - Example: flutter_riverpod: ^2.5.0
# - Vendored packages: path dependency

dependencies:
  flutter:
    sdk: flutter

  # State management
  flutter_riverpod: ^2.5.0
  riverpod_annotation: ^2.3.0
  freezed_annotation: ^2.4.0

  # Database
  duckdb_dart: ^1.0.0

  # Maps
  flutter_map: ^7.0.0
  # NOTE: flutter_map_tile_caching is GPL-3.0 — NOT USED.
  # Custom tile caching implemented in lib/core/tiles/
  sqflite: ^2.3.0          # SQLite for tile cache storage
  latlong2: ^0.9.0

  # Charts
  fl_chart: ^0.69.0

  # Serial (desktop — LGPL-3.0, OK via dynamic linking)
  flutter_libserialport: ^0.4.0
  # Serial (Android — BSD-3)
  usb_serial: ^0.4.0

  # Video (P1 — media_kit uses LGPL libmpv via dynamic linking)
  media_kit: ^1.0.0
  media_kit_video: ^1.0.0
  media_kit_libs_linux: ^1.0.0
  media_kit_libs_macos_video: ^1.0.0
  media_kit_libs_windows_video: ^1.0.0

  # Storage
  shared_preferences: ^2.3.0
  flutter_secure_storage: ^9.2.0
  path_provider: ^2.1.0
  path: ^1.9.0

  # Utilities
  uuid: ^4.4.0
  intl: ^0.19.0
  collection: ^1.18.0

  # MAVLink (vendored)
  dart_mavlink:
    path: packages/dart_mavlink

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.0
  freezed: ^2.5.0
  riverpod_generator: ^2.4.0
  flutter_lints: ^4.0.0
  mockito: ^5.4.0
  build_runner: ^2.4.0
```

---

## 4. Project Directory Structure

```
helios-gcs/
├── lib/
│   ├── main.dart                           # Entry point, ProviderScope
│   ├── app.dart                            # MaterialApp, routing, theme
│   ├── core/
│   │   ├── mavlink/
│   │   │   ├── mavlink_service.dart        # Connection + MAVLink parsing
│   │   │   ├── command_sender.dart         # Outbound command builder
│   │   │   ├── heartbeat_watchdog.dart     # Link state monitor
│   │   │   ├── transports/
│   │   │   │   ├── transport.dart          # Abstract transport interface
│   │   │   │   ├── udp_transport.dart      # UDP implementation
│   │   │   │   ├── tcp_transport.dart      # TCP implementation
│   │   │   │   └── serial_transport.dart   # Serial implementation
│   │   │   └── messages/
│   │   │       └── flight_mode.dart        # Mode mapping tables
│   │   ├── telemetry/
│   │   │   ├── telemetry_store.dart        # DuckDB engine
│   │   │   ├── schema.dart                 # SQL schema definitions
│   │   │   ├── analytics_templates.dart    # Pre-built SQL templates
│   │   │   └── export_service.dart         # Parquet export + Argus sync
│   │   └── mission/
│   │       └── mission_service.dart        # Mission protocol handler
│   ├── features/
│   │   ├── fly/
│   │   │   ├── fly_view.dart               # In-flight screen
│   │   │   ├── widgets/
│   │   │   │   ├── pfd_widget.dart         # Primary flight display
│   │   │   │   ├── pfd_painter.dart        # CustomPainter for PFD
│   │   │   │   ├── telemetry_strip.dart    # Telemetry data cards
│   │   │   │   ├── telemetry_card.dart     # Single data card
│   │   │   │   ├── connection_badge.dart   # Link state indicator
│   │   │   │   ├── vehicle_marker.dart     # Map vehicle icon
│   │   │   │   └── vehicle_trail.dart      # GPS trail polyline
│   │   │   └── providers/
│   │   │       └── fly_view_providers.dart # View-specific state
│   │   ├── plan/
│   │   │   ├── plan_view.dart              # Mission planning screen
│   │   │   ├── widgets/
│   │   │   │   ├── waypoint_editor.dart    # Waypoint property editor
│   │   │   │   ├── waypoint_list.dart      # Ordered waypoint list
│   │   │   │   ├── waypoint_marker.dart    # Map waypoint marker
│   │   │   │   └── mission_path.dart       # Polyline between waypoints
│   │   │   └── providers/
│   │   │       └── plan_view_providers.dart
│   │   ├── analyse/
│   │   │   ├── analyse_view.dart           # Analytics screen
│   │   │   ├── widgets/
│   │   │   │   ├── flight_browser.dart     # Flight file list
│   │   │   │   ├── sql_editor.dart         # SQL query editor
│   │   │   │   ├── results_table.dart      # Query results display
│   │   │   │   ├── template_gallery.dart   # Pre-built template buttons
│   │   │   │   └── telemetry_chart.dart    # fl_chart time-series
│   │   │   └── providers/
│   │   │       └── analyse_providers.dart
│   │   └── setup/
│   │       ├── setup_view.dart             # Configuration screen
│   │       ├── widgets/
│   │       │   ├── connection_manager.dart  # Transport config UI
│   │       │   ├── recording_controls.dart  # Start/stop recording
│   │       │   ├── serial_port_picker.dart  # Serial port selection
│   │       │   └── parameter_editor.dart    # Param table (P1)
│   │       └── providers/
│   │           └── setup_providers.dart
│   └── shared/
│       ├── models/
│       │   ├── vehicle_state.dart           # VehicleState + enums
│       │   ├── connection_state.dart        # ConnectionConfig/Status
│       │   ├── recording_state.dart         # RecordingState
│       │   ├── mission_state.dart           # MissionState + MissionItem
│       │   └── telemetry_stats.dart         # TelemetryStats
│       ├── providers/
│       │   ├── service_providers.dart       # Service-level providers
│       │   ├── state_providers.dart         # StateNotifier providers
│       │   └── derived_providers.dart       # Computed values
│       ├── theme/
│       │   ├── helios_theme.dart            # ThemeData definition
│       │   ├── helios_colors.dart           # Colour tokens
│       │   └── helios_typography.dart       # Text styles
│       ├── widgets/
│       │   ├── responsive_scaffold.dart     # NavigationRail/BottomNav switch
│       │   ├── error_boundary.dart          # Error catching widget
│       │   ├── status_bar.dart              # Bottom status bar
│       │   └── confirmation_dialog.dart     # Critical command confirmation
│       └── utils/
│           ├── logger.dart                  # HeliosLogger
│           ├── units.dart                   # Unit conversion (metric/imperial)
│           ├── coordinates.dart             # Coordinate format conversion
│           └── validators.dart              # Input validation helpers
├── packages/
│   └── dart_mavlink/                        # Vendored MAVLink library
│       ├── lib/
│       ├── test/
│       └── pubspec.yaml
├── test/
│   ├── core/
│   │   ├── mavlink/
│   │   │   ├── mavlink_service_test.dart
│   │   │   ├── command_sender_test.dart
│   │   │   ├── heartbeat_watchdog_test.dart
│   │   │   └── transports/
│   │   │       ├── udp_transport_test.dart
│   │   │       └── tcp_transport_test.dart
│   │   ├── telemetry/
│   │   │   ├── telemetry_store_test.dart
│   │   │   ├── analytics_templates_test.dart
│   │   │   └── export_service_test.dart
│   │   └── mission/
│   │       └── mission_service_test.dart
│   ├── features/
│   │   ├── fly/
│   │   │   ├── pfd_widget_test.dart
│   │   │   ├── telemetry_strip_test.dart
│   │   │   └── connection_badge_test.dart
│   │   ├── plan/
│   │   │   ├── waypoint_editor_test.dart
│   │   │   └── mission_upload_test.dart
│   │   ├── analyse/
│   │   │   ├── sql_editor_test.dart
│   │   │   └── flight_browser_test.dart
│   │   └── setup/
│   │       └── connection_manager_test.dart
│   ├── shared/
│   │   └── models/
│   │       ├── vehicle_state_test.dart
│   │       └── mission_state_test.dart
│   ├── integration/
│   │   ├── sitl_connection_test.dart
│   │   ├── sitl_mission_test.dart
│   │   └── duckdb_roundtrip_test.dart
│   └── performance/
│       ├── pfd_paint_benchmark.dart
│       ├── duckdb_insert_benchmark.dart
│       └── duckdb_query_benchmark.dart
├── docker/
│   ├── docker-compose.sitl.yaml             # ArduPilot SITL for dev/CI
│   └── Dockerfile.sitl                      # Custom SITL image if needed
├── assets/
│   ├── icons/
│   │   ├── helios_logo.svg
│   │   └── vehicle_marker.svg
│   └── fonts/
│       └── JetBrainsMono/                   # Monospace font for telemetry
├── .github/
│   └── workflows/
│       ├── ci.yaml                          # Lint, test, build
│       └── release.yaml                     # Build and publish releases
├── pubspec.yaml
├── analysis_options.yaml
├── LICENCE                                  # Apache 2.0
├── CHANGELOG.md
└── CONTRIBUTING.md
```

---

## 5. Versioning

Semantic versioning: `MAJOR.MINOR.PATCH`

| Version | Meaning |
|---------|---------|
| 0.1.0 | Phase 1 complete (connect, display, record) |
| 0.2.0 | Phase 2 complete (map, analytics) |
| 0.3.0 | Phase 3 complete (mission planning) |
| 0.4.0 | Phase 4 complete (polish, hardware) |
| 1.0.0 | Phase 5 complete (Argus integration, production-ready) |

Schema version increments independently when DuckDB schema changes.
