# Helios GCS — Development Phases & Task Breakdown

**Version**: 1.0.0 | **Status**: Draft | **Date**: 2026-03-24

---

## Phase 1: Foundation (Weeks 1-4)

**Goal**: Connect to a simulated vehicle, display telemetry, record to DuckDB.

**Exit Criteria**: Connect to ArduPlane SITL, see live attitude/GPS/battery, record a 5-minute flight to .duckdb file, all unit tests pass.

### Week 1: Project Scaffold & Transport

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 1.1 Flutter project init with pubspec, analysis_options, directory structure | All | 2 | `flutter run` works, directory matches spec | — |
| 1.2 Helios theme (colours, typography, dark theme) | Presentation | 3 | ThemeData matches spec colour tokens | Widget test: theme applies correctly |
| 1.3 Responsive scaffold (NavigationRail / BottomNav) | Presentation | 4 | Switches at breakpoints | Widget test: 3 breakpoints |
| 1.4 MavlinkTransport abstract interface | Service | 2 | Interface compiles, documented | — |
| 1.5 UdpTransport implementation | Service | 4 | Sends/receives UDP datagrams | Unit test: bind, send, receive |
| 1.6 TcpTransport implementation | Service | 3 | Connects, sends, receives, reconnects | Unit test: connect, reconnect |
| 1.7 Transport reconnection with exponential backoff | Service | 2 | Reconnects with 1s, 2s, 4s... max 30s | Unit test: backoff timing |

### Week 2: MAVLink Parsing & Vehicle State

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 2.1 Vendor dart_mavlink, verify v2 parse/serialize | Data | 4 | Parses HEARTBEAT, ATTITUDE, GPS | Unit test: parse all MVP messages |
| 2.2 MavlinkService: connect, parse, dispatch | Service | 4 | Decodes messages, dispatches to handlers | Unit test: message routing |
| 2.3 HeartbeatWatchdog | Service | 2 | DISCONNECTED → CONNECTED → DEGRADED → LOST | Unit test: all transitions |
| 2.4 VehicleState freezed model | State | 2 | All fields, copyWith, equality | Unit test: model creation |
| 2.5 VehicleStateNotifier + Riverpod provider | State | 4 | Updates from MAVLink messages | Unit test: each message handler |
| 2.6 ConnectionState model + provider | State | 2 | Transport + link state tracking | Unit test: state transitions |
| 2.7 GCS heartbeat sender (1 Hz) | Service | 1 | Sends HEARTBEAT to vehicle | Unit test: periodic sending |

### Week 3: DuckDB & Recording

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 3.1 DuckDB isolate wrapper | Data | 4 | Opens, executes SQL, closes in isolate | Unit test: basic operations |
| 3.2 TelemetryStore: createFlight, schema init | Data | 3 | Creates .duckdb with all tables | Unit test: schema verification |
| 3.3 TelemetryStore: buffer + flush pipeline | Data | 4 | Buffers messages, batch inserts every 1s | Unit test: buffer → flush → query |
| 3.4 RecordingState model + provider | State | 2 | isRecording, file path, stats | Unit test: state transitions |
| 3.5 Auto-record on arm detection | Service | 2 | Starts recording when HEARTBEAT shows armed | Unit test: arm → record start |
| 3.6 Flight close + metadata update | Data | 2 | end_time_utc set, file closed properly | Unit test: close writes metadata |
| 3.7 Crash recovery: detect unclosed flights | Data | 3 | On launch, finds unclosed files, recovers | Unit test: recovery flow |

### Week 4: Fly View MVP

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 4.1 PFD CustomPainter: attitude indicator | Presentation | 6 | Sky/ground split, roll rotation, pitch ladder | Widget test + golden file |
| 4.2 PFD: heading tape | Presentation | 3 | Scrolling compass, cardinal labels | Widget test |
| 4.3 Telemetry strip: battery, GPS, speed, altitude | Presentation | 4 | All cards with colour thresholds | Widget test: each card |
| 4.4 Connection badge widget | Presentation | 2 | Colour matches link state | Widget test: all states |
| 4.5 Fly View composition (map placeholder + PFD + strip) | Presentation | 3 | Responsive layout at all breakpoints | Widget test: layout |
| 4.6 Setup View: connection manager (UDP config) | Presentation | 3 | Address/port input, connect/disconnect buttons | Widget test |
| 4.7 Setup View: recording controls | Presentation | 2 | Start/stop recording, status display | Widget test |
| 4.8 SITL integration test: full pipeline | Integration | 4 | Connect SITL → telemetry flows → record → close | Integration test |

**Phase 1 Total**: ~80 hours (4 weeks at 20hrs/week)

---

## Phase 2: Map & Analytics (Weeks 5-8)

**Goal**: Spatial awareness and the analytics differentiator.

**Exit Criteria**: Fly a SITL mission, see vehicle on map, open recorded flight in Analyse view, run all templates, export Parquet.

### Week 5: Map Integration

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 5.1 flutter_map setup with OSM tiles | Presentation | 3 | Map renders, zoom/pan works | Widget test |
| 5.2 Vehicle marker (rotated to heading) | Presentation | 3 | SVG marker at GPS position, rotated | Widget test |
| 5.3 Vehicle trail (last 300 points) | Presentation | 3 | Gradient polyline, fades with age | Widget test |
| 5.4 Home position marker with range ring | Presentation | 2 | Displays at first GPS fix location | Widget test |
| 5.5 Map auto-centre on vehicle | Presentation | 2 | Follows vehicle, manual pan disables follow | Widget test |

### Week 6: Offline Tiles & Map Polish

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 6.1 flutter_map_tile_caching integration | Service | 4 | Tiles load from cache when offline | Unit test: cache hit |
| 6.2 Tile download UI (region selector) | Presentation | 4 | Select region + zoom levels, progress bar | Widget test |
| 6.3 Tile cache management (list, delete, size) | Service | 3 | List regions, delete, show total size | Unit test |
| 6.4 Active mission overlay on map (waypoint path) | Presentation | 3 | Polyline + numbered markers from mission | Widget test |
| 6.5 Fly View map composition (replace placeholder) | Presentation | 2 | Map fills main area with PFD overlay | Widget test |

### Week 7: Analyse View — Core

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 7.1 Flight browser (list .duckdb files) | Presentation | 3 | Lists files with date, duration, size | Widget test |
| 7.2 Flight open + close lifecycle | Service | 2 | Open flight DB, close previous | Unit test |
| 7.3 SQL editor with syntax highlighting | Presentation | 4 | Highlights keywords, strings, numbers | Widget test |
| 7.4 Query execution + results table | Presentation | 4 | Execute SQL, display columns + rows | Widget test |
| 7.5 Error display for invalid SQL | Presentation | 2 | Shows DuckDB error message inline | Widget test |
| 7.6 Query history (last 50 queries) | Service | 2 | Persists across sessions | Unit test |

### Week 8: Analytics Templates & Export

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 8.1 Analytics template engine | Service | 3 | Enum of templates, SQL lookup, execution | Unit test: all templates |
| 8.2 Template gallery UI (one-click buttons) | Presentation | 3 | Button per template, fills editor + executes | Widget test |
| 8.3 Vibration, battery, GPS, altitude, anomaly templates | Data | 4 | All 7 templates run without error on synthetic data | Unit test: each template |
| 8.4 Parquet export (single table) | Service | 3 | DuckDB COPY TO, correct Parquet output | Unit test: file valid |
| 8.5 Parquet export all tables + manifest.json | Service | 3 | All tables exported, checksums in manifest | Unit test: manifest |
| 8.6 Analyse View composition | Presentation | 2 | Browser + editor + results + templates | Widget test |
| 8.7 SITL integration: record → analyse → export | Integration | 4 | Full round-trip test | Integration test |

**Phase 2 Total**: ~68 hours

---

## Phase 3: Mission Planning (Weeks 9-12)

**Goal**: Plan and fly autonomous missions.

**Exit Criteria**: Plan a multi-waypoint mission, upload to SITL, fly autonomously, see progress on Fly view map, analyse in Analyse view.

### Week 9: Mission Protocol

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 9.1 MissionService: download protocol | Service | 4 | Downloads from SITL correctly | Unit + integration test |
| 9.2 MissionService: upload protocol | Service | 4 | Uploads to SITL, ACK received | Unit + integration test |
| 9.3 MissionItem model + serialisation | Data | 2 | lat/lon int32 conversion correct | Unit test |
| 9.4 MissionState provider | State | 2 | items, transferState, currentWaypoint | Unit test |
| 9.5 Command sender: mode change, arm/disarm | Service | 3 | Commands with retry logic | Unit test |
| 9.6 Confirmation dialogs for critical commands | Presentation | 2 | Arm, disarm, AUTO mode confirmed | Widget test |

### Week 10: Plan View

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 10.1 Plan View map with tap-to-place waypoints | Presentation | 4 | Tap adds waypoint at position | Widget test |
| 10.2 Waypoint markers on map (numbered, draggable) | Presentation | 4 | Drag to move, numbered display | Widget test |
| 10.3 Mission path polyline with direction arrows | Presentation | 3 | Lines between waypoints, arrows show direction | Widget test |
| 10.4 Waypoint list panel (reorderable) | Presentation | 3 | Drag to reorder, displays all fields | Widget test |
| 10.5 Waypoint editor (altitude, speed, command, hold) | Presentation | 4 | Edit all fields with validation | Widget test |

### Week 11: Mission Execution & Monitoring

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 11.1 Upload button + progress indicator | Presentation | 2 | Progress bar during upload | Widget test |
| 11.2 Download button + progress indicator | Presentation | 2 | Progress bar during download | Widget test |
| 11.3 Current waypoint tracking on map | Presentation | 3 | Highlights active waypoint during AUTO | Widget test |
| 11.4 Mission items saved to DuckDB | Data | 2 | Snapshot saved on upload/download | Unit test |
| 11.5 Undo/redo for waypoint editing | State | 4 | Ctrl+Z / Ctrl+Shift+Z works | Unit test |
| 11.6 Clear mission (local + vehicle) | Service | 2 | Clears both sides | Unit + widget test |

### Week 12: Charts & Polish

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 12.1 fl_chart time-series line chart | Presentation | 4 | Timestamp X, numeric Y, multi-series | Widget test |
| 12.2 Chart controls (zoom, pan, series selection) | Presentation | 3 | Mouse wheel zoom, drag pan | Widget test |
| 12.3 Chart integration in Analyse view | Presentation | 2 | Toggle between table and chart view | Widget test |
| 12.4 Status bar (bottom: mode, arm, flight time, msg/s) | Presentation | 2 | Updates reactively | Widget test |
| 12.5 Keyboard shortcuts | Presentation | 2 | All shortcuts from spec working | Widget test |
| 12.6 SITL integration: plan → upload → fly → analyse | Integration | 4 | Full autonomous flight test | Integration test |

**Phase 3 Total**: ~66 hours

---

## Phase 4: Polish & Hardware (Weeks 13-16)

**Goal**: Field-ready with real hardware.

**Exit Criteria**: Complete a real-world flight with a physical ArduPlane, recording full telemetry.

### Week 13: Serial Transport & Video

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 13.1 SerialTransport implementation | Service | 4 | Connect to SiK radio via USB | Unit test |
| 13.2 Serial port discovery + picker UI | Presentation | 3 | Lists available ports, auto-detect | Widget test |
| 13.3 RTSP video player widget | Presentation | 4 | Plays RTSP stream in PiP | Widget test |
| 13.4 Video overlay toggle (PiP on/off) | Presentation | 2 | Toggle video overlay on Fly View | Widget test |

### Week 14: Instruments & Survey

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 14.1 Speed tape (IAS vertical) | Presentation | 4 | Scrolling tape, numeric readout | Widget test + golden |
| 14.2 Altitude tape (vertical) | Presentation | 4 | Scrolling tape, MSL + REL | Widget test + golden |
| 14.3 Survey planner: polygon area definition | Presentation | 3 | Tap to define polygon on map | Widget test |
| 14.4 Survey planner: lawnmower pattern generator | Service | 4 | Generates waypoints from polygon | Unit test |

### Week 15: Parameter Editor & Mobile

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 15.1 Parameter fetch (full list) | Service | 3 | Fetches all ~1000 params | Integration test |
| 15.2 Parameter editor UI (search, filter, edit) | Presentation | 4 | Searchable table, edit + save | Widget test |
| 15.3 Mobile layout (BottomNav, overlay PFD) | Presentation | 4 | Correct at < 768px | Widget test |
| 15.4 Pull-up sheet for mobile telemetry | Presentation | 3 | Swipe up for detailed telemetry | Widget test |

### Week 16: Hardware Testing & Bug Fixes

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 16.1 Hardware test: Pixhawk USB connection | All | 4 | Connect, receive telemetry, send commands | Manual test |
| 16.2 Hardware test: SiK telemetry radio | All | 4 | 57600 baud, stable data | Manual test |
| 16.3 Performance profiling + optimisation | All | 4 | Meet all performance targets from spec | Performance tests |
| 16.4 Bug fixes from Phase 1-3 testing | All | 6 | All known bugs resolved | Regression tests |
| 16.5 Accessibility audit (contrast, keyboard, labels) | Presentation | 2 | WCAG AA compliance | Manual audit |

**Phase 4 Total**: ~62 hours

---

## Phase 5: Argus Integration (Weeks 17-20)

**Goal**: Close the loop with the Argus analytics platform.

**Exit Criteria**: Multiple flights from multiple devices sync to Argus. Fleet dashboard showing cross-mission analytics.

### Week 17: Argus Sync

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 17.1 Argus endpoint configuration UI | Presentation | 3 | URL, API key, mTLS toggle | Widget test |
| 17.2 HTTP Parquet upload client | Service | 4 | Uploads Parquet files to endpoint | Unit test |
| 17.3 Sync queue with retry | Service | 4 | Queues exports, retries on failure | Unit test |
| 17.4 Sync status indicator | Presentation | 2 | Shows pending/syncing/synced/error | Widget test |

### Week 18: Security Hardening

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 18.1 MAVLink signing implementation | Service | 4 | HMAC-SHA256, reject unsigned when enabled | Unit test |
| 18.2 Signing key management (flutter_secure_storage) | Service | 3 | Store/retrieve keys from OS keychain | Unit test |
| 18.3 Signing configuration UI | Presentation | 2 | Enable/disable, key management | Widget test |
| 18.4 Security audit: input validation review | All | 4 | All boundaries validated | Unit tests added |

### Week 19: Geofence & Multi-User

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 19.1 Geofence editor: draw inclusion/exclusion zones | Presentation | 4 | Polygon drawing on map | Widget test |
| 19.2 Geofence upload via MAVLink | Service | 3 | Upload FENCE_POINT / MISSION fence items | Unit + integration test |
| 19.3 Geofence display on Fly View map | Presentation | 2 | Shows fence boundaries | Widget test |
| 19.4 Role-based access control model (P2) | Service | 4 | Pilot/Observer/Analyst roles | Unit test |

### Week 20: Release Preparation

| Task | Layer | Hours | Acceptance Criteria | Tests |
|------|-------|-------|-------------------|-------|
| 20.1 Release builds for Linux, macOS, Windows | DevOps | 4 | All platforms build successfully | CI |
| 20.2 Android release build | DevOps | 3 | APK generates, installs on tablet | Manual test |
| 20.3 GitHub Actions release pipeline | DevOps | 4 | Tag → build → upload to Releases | CI test |
| 20.4 Full regression test pass | All | 4 | All tests green, 80%+ coverage | CI |
| 20.5 Documentation: CONTRIBUTING.md, CHANGELOG.md | Docs | 3 | Complete contributor guide | — |

**Phase 5 Total**: ~58 hours

---

## Total Estimated Effort

| Phase | Weeks | Hours | Key Deliverable |
|-------|-------|-------|----------------|
| 1. Foundation | 1-4 | ~80 | Connect, display, record |
| 2. Map & Analytics | 5-8 | ~68 | Map, SQL analytics, Parquet export |
| 3. Mission Planning | 9-12 | ~66 | Waypoint planning, autonomous flight |
| 4. Polish & Hardware | 13-16 | ~62 | Serial, video, instruments, hardware test |
| 5. Argus Integration | 17-20 | ~58 | Sync, security, geofence, release |
| **Total** | **20 weeks** | **~334 hours** | **Production v1.0.0** |

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| dart_mavlink too immature | Medium | High | Fork and enhance. Fallback: code-generate from MAVLink XML. |
| DuckDB Dart bindings unstable | Low | High | duckdb_dart actively maintained. Fallback: SQLite with manual columnar optimisation. |
| Flutter CustomPainter too slow for PFD at 60fps | Low | Medium | Profile early (Week 4). Fallback: reduce to 30fps, simplify drawing. |
| Serial port access inconsistent cross-platform | Medium | Medium | Test on all platforms Week 13. Fallback: USB→WiFi bridge. |
| ArduPilot SITL Docker image breaks | Low | Low | Pin SITL version. Maintain custom Dockerfile. |
| DuckDB file corruption on crash | Low | High | WAL mode + recovery logic (Task 3.7). |
| Map tile provider rate limiting | Low | Low | Tile caching + multiple provider fallback. |
