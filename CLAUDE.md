# Helios GCS — Claude Code Configuration

## What Is Helios?

Helios is an open-source ground control station (GCS) for MAVLink UAVs, part of the Argus Platform. It connects to flight controllers (ArduPilot, PX4) over USB, UDP, or TCP and provides real-time telemetry, mission planning, flight recording, and post-flight analytics.

**Key differentiator:** Every flight is automatically recorded into a DuckDB database, making post-flight analysis as powerful as the live display. No other GCS treats telemetry as queryable data.

**Tagline:** _"Helios sees from the sky. Argus sees from the ground."_

## Architecture

```
lib/
├── core/                    # Business logic (no UI)
│   ├── mavlink/             # MAVLink parser, transports (UDP/TCP/Serial)
│   ├── mission/             # Mission download/upload protocol
│   ├── params/              # Parameter fetch/set/export
│   ├── calibration/         # Sensor calibration service
│   ├── fence/               # Geofence upload/download
│   ├── logs/                # Dataflash log download
│   ├── telemetry/           # DuckDB recording + schema + analytics
│   └── map/                 # Offline tile caching
├── features/                # UI views (one directory per tab)
│   ├── fly/                 # Real-time PFD, map, charts
│   ├── plan/                # Mission + geofence + rally planning
│   ├── analyse/             # SQL editor, charts, flight browser
│   ├── video/               # RTSP video streaming
│   └── setup/               # Connection, params, calibration, settings
├── shared/                  # Cross-feature code
│   ├── models/              # Immutable Equatable models
│   ├── providers/           # Riverpod state management
│   ├── widgets/             # Shared widgets (status bar, etc.)
│   └── theme/               # Colors, typography tokens
packages/
├── dart_mavlink/            # Vendored MAVLink v2 parser + frame builder
└── duckdb_dart_patched/     # DuckDB FFI bindings (patched for macOS)
scripts/
├── generate_crc_extras.dart # Generate CRC extras from MAVLink XML
├── sim_telemetry.dart       # Telemetry simulator for dev without SITL
└── mavlink_xml/             # MAVLink XML definitions (common + ardupilot)
```

**Stack:** Flutter 3.38, Dart 3.10, Riverpod, DuckDB, flutter_map, media_kit, flutter_libserialport

**4-Layer Pattern:** Presentation → State (Riverpod) → Service → Data

## Build & Test

```bash
make check          # Analyze + test (run before every commit)
make run            # Run on macOS
make run-linux      # Run on Linux
make build-macos    # Release build
make package-macos  # Create .dmg installer
make sitl           # Start ArduPilot SITL in Docker
make gen-crc        # Regenerate MAVLink CRC extras from XML
```

Or without Make:
```bash
dart analyze --fatal-warnings lib/ test/ packages/dart_mavlink/
flutter test
flutter run -d macos
```

## Testing Rules

- ALWAYS run `make check` (analyze + test) before committing
- ALWAYS write tests for new models, services, and state notifiers
- ALWAYS verify the macOS build succeeds after significant changes
- Test with real hardware via USB serial when available
- Test with SITL via `make sitl` + TCP 127.0.0.1:5760 for protocol testing
- Tests live in `test/` mirroring the `lib/` directory structure
- Use `flutter test test/path/to/specific_test.dart` for focused testing
- Current: 124 tests covering models, providers, parser, watchdog, widgets

## Ways of Working

### Before writing code:
1. Read the files you're about to change
2. Understand the existing patterns in neighbouring code
3. Check if there's an existing service/model you should extend rather than create new

### When adding MAVLink features:
1. Check the message definition in `scripts/mavlink_xml/common.xml` or `ardupilotmega.xml`
2. Add the message class to `packages/dart_mavlink/lib/src/messages.dart`
3. Add the deserializer case to `packages/dart_mavlink/lib/src/mavlink_parser.dart`
4. Add frame builder if we need to send this message type
5. Run `make gen-crc` if you added a new XML or suspect CRC issues
6. The CRC extras are auto-generated — never hand-edit `generated_crc_extras.dart`

### When adding UI features:
1. Create the service/model in `lib/core/` or `lib/shared/models/`
2. Wire it through Riverpod in `lib/shared/providers/`
3. Build the UI in `lib/features/<tab>/`
4. Follow existing widget patterns (ConsumerWidget/ConsumerStatefulWidget)

### When modifying VehicleState:
1. Add field with default value to `VehicleState` constructor
2. Add to `copyWith()` method
3. Add to `props` list (Equatable)
4. Handle the message in `VehicleStateNotifier` (writes to `_pending`, sets `_dirty = true`)
5. State is batched at 30Hz — don't call `state =` directly, use the pending buffer

## Key Technical Decisions

| Decision | Rationale |
|----------|-----------|
| DuckDB per flight (not SQLite) | Columnar OLAP, 10-100x faster for analytics queries |
| Vendored dart_mavlink | No mature MAVLink package on pub.dev; we control the parser |
| duckdb_dart patched for macOS | Upstream only supports Linux/Windows |
| flutter_map (not google_maps) | No API key needed, OSM tiles, Apache 2.0 compatible |
| Custom CachedTileProvider | flutter_map_tile_caching is GPL-3.0, incompatible with Apache 2.0 |
| media_kit for video | LGPL via dynamic linking, cross-platform RTSP support |
| flutter_libserialport | C-based libserialport works on macOS/Linux/Windows |
| 30Hz state batching | Prevents 50Hz ATTITUDE from triggering 50 widget rebuilds/sec |
| PFD Ticker interpolation | 60fps smooth rendering between 10Hz telemetry samples |
| MAV_CMD_SET_MESSAGE_INTERVAL | Modern per-message rate control with legacy fallback |
| 305 auto-generated CRC extras | From MAVLink XML at build time, not hand-coded |

## File Organization Rules

- Source code: `lib/`
- Tests: `test/` (mirrors lib/ structure)
- Scripts: `scripts/`
- Documentation: `docs/`
- NEVER save working files to the project root
- NEVER create documentation unless explicitly asked
- Keep files under 500 lines where practical

## Security Rules

- NEVER hardcode API keys, secrets, or credentials
- NEVER commit .env files
- Validate all MAVLink input at the parser boundary
- Sanitize file paths (DuckDB file names, log downloads, param exports)
- Serial port access requires macOS sandbox disabled (already configured)

## Roadmap

### Completed
- Phase 1: MAVLink parser, UDP/TCP/Serial transports, heartbeat watchdog, PFD
- Phase 2: Maps, DuckDB recording, charts, Parquet export, analytics templates
- Phase 3: Mission planning (upload/download/Plan View), execution monitoring
- Phase 4: Compound PFD (speed+alt tapes), serial USB, stream rate control
- Sprint 1 Parity: Calibration, EKF status, geofence, log download, rally points
- Infrastructure: Parameter editor, CI/CD pipelines, CRC generation, connection persistence

### Next: Sprint 2 — Enhanced Monitoring
- Firmware version detection (AUTOPILOT_VERSION)
- Gimbal/camera control
- Multi-vehicle foundation (registry by systemId)

### Sprint 3 — Unique Differentiators
- Flight Forensics Engine (cross-flight DuckDB analytics)
- Predictive Maintenance Alerts (on-device statistical analysis)
- Flight Replay Engine (play back DuckDB through Fly View)
- Fleet Database (aggregated cross-vehicle analytics)
- Natural Language Flight Query (grammar-based SQL generation)

### Sprint 4 — Platform & Compliance
- Regulatory compliance toolkit (FAA Part 107 / EASA reports)
- Remote ID support
- Air-gapped operations (.helios archive bundles)
- Scripting API (JSON-RPC)
- Plugin system

## Useful Paths

| What | Where |
|------|-------|
| MAVLink messages | `packages/dart_mavlink/lib/src/messages.dart` |
| MAVLink parser | `packages/dart_mavlink/lib/src/mavlink_parser.dart` |
| Frame builder | `packages/dart_mavlink/lib/src/frame_builder.dart` |
| CRC extras (generated) | `packages/dart_mavlink/lib/src/generated_crc_extras.dart` |
| Vehicle state model | `lib/shared/models/vehicle_state.dart` |
| State notifier (30Hz) | `lib/shared/providers/vehicle_state_notifier.dart` |
| Connection controller | `lib/shared/providers/providers.dart` |
| DuckDB schema | `lib/core/telemetry/schema.dart` |
| Telemetry store | `lib/core/telemetry/telemetry_store.dart` |
| Typography tokens | `lib/shared/theme/helios_typography.dart` |
| Colour tokens | `lib/shared/theme/helios_colors.dart` |
| App root + navigation | `lib/app.dart` |
| Fly View (PFD + map) | `lib/features/fly/fly_view.dart` |
| Plan View (missions) | `lib/features/plan/plan_view.dart` |
| Setup View | `lib/features/setup/setup_view.dart` |
| MAVLink XML sources | `scripts/mavlink_xml/` |

## DuckDB dylib (macOS)

The DuckDB native library must be at `/usr/local/lib/libduckdb.dylib` on macOS. If missing, copy from `native/macos/libduckdb.dylib`.
