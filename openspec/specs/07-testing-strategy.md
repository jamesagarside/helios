# Helios GCS — Testing Strategy Specification

**Version**: 1.0.0 | **Status**: Draft | **Date**: 2026-03-24

---

## 1. Testing Philosophy

- **TDD London School**: Mock-first for service layer. Write test → write implementation → verify.
- **No functionality removed to pass tests**: Tests are the spec. If a test fails, fix the code.
- **Full coverage at boundaries**: 100% coverage for public service interfaces and state transitions.
- **Realistic integration**: SITL tests use real ArduPilot simulator, not mocks.
- **No test skipping**: Every test must pass. No `@Skip`, no commented-out tests.

---

## 2. Test Pyramid

```
         ╱╲
        ╱  ╲        E2E / SITL Integration (5-10 tests)
       ╱    ╲       Real autopilot, real DuckDB, real transport
      ╱──────╲
     ╱        ╲     Widget Tests (50-100 tests)
    ╱          ╲    PFD rendering, telemetry strip, map markers
   ╱────────────╲
  ╱              ╲   Unit Tests (200-400 tests)
 ╱                ╲  State, services, parsing, SQL templates
╱══════════════════╲
```

---

## 3. Unit Tests

### 3.1 MAVLink Parser Tests

```dart
group('MAVLink v2 parser', () {
  test('parses valid HEARTBEAT message', () { ... });
  test('parses valid ATTITUDE message with correct field mapping', () { ... });
  test('rejects frame with invalid CRC', () { ... });
  test('rejects frame with unknown magic byte', () { ... });
  test('handles truncated frame gracefully', () { ... });
  test('parses v1 frame as fallback', () { ... });
  test('correctly unpacks GLOBAL_POSITION_INT lat/lon from int32', () { ... });
  test('increments error counter on parse failure', () { ... });
  test('handles maximum-length payload (255 bytes)', () { ... });
  test('handles zero-length payload', () { ... });
});
```

### 3.2 Vehicle State Tests

```dart
group('VehicleStateNotifier', () {
  test('updates attitude from ATTITUDE message', () { ... });
  test('updates GPS from GLOBAL_POSITION_INT', () { ... });
  test('merges fix_type from GPS_RAW_INT into GPS state', () { ... });
  test('updates battery from SYS_STATUS', () { ... });
  test('extracts flight mode from HEARTBEAT custom_mode', () { ... });
  test('detects arm state from HEARTBEAT base_mode', () { ... });
  test('logs mode change event on flight mode transition', () { ... });
  test('logs arm/disarm event on armed state change', () { ... });
  test('handles unknown vehicle type gracefully', () { ... });
  test('resets state on disconnect', () { ... });
});
```

### 3.3 Heartbeat Watchdog Tests

```dart
group('HeartbeatWatchdog', () {
  test('transitions to connected on first heartbeat', () { ... });
  test('stays connected when heartbeats arrive regularly', () { ... });
  test('transitions to degraded after 2s without heartbeat', () { ... });
  test('transitions to lost after 5s without heartbeat', () { ... });
  test('recovers to connected when heartbeat resumes', () { ... });
  test('fires callback on state transitions', () { ... });
});
```

### 3.4 TelemetryStore Tests

```dart
group('TelemetryStore', () {
  late TelemetryStore store;

  setUp(() async {
    store = TelemetryStore();
    await store.createFlight(
      vehicleSysId: 1,
      vehicleType: VehicleType.fixedWing,
      autopilot: AutopilotType.ardupilot,
    );
  });

  tearDown(() async {
    await store.closeFlight();
    // Delete test database file
  });

  test('creates database with correct schema version', () async {
    final result = await store.query(
      "SELECT value FROM flight_meta WHERE key = 'schema_version'"
    );
    expect(result.rows.first.first, '1');
  });

  test('buffers and flushes attitude data', () async {
    store.buffer(AttitudeMessage(roll: 0.1, pitch: 0.2, yaw: 3.14, ...));
    store.buffer(AttitudeMessage(roll: 0.2, pitch: 0.1, yaw: 3.10, ...));
    final count = await store.flush();
    expect(count, 2);

    final result = await store.query('SELECT COUNT(*) FROM attitude');
    expect(result.rows.first.first, 2);
  });

  test('handles concurrent buffer and flush', () async { ... });

  test('executes vibration analysis template without error', () async {
    // Insert synthetic vibration data
    await _insertSyntheticVibration(store, 100);
    final result = await store.runTemplate(AnalyticsTemplate.vibrationAnalysis);
    expect(result.rowCount, 100);
    expect(result.columnNames, contains('anomaly_x'));
  });

  test('executes battery discharge template without error', () async { ... });
  test('executes GPS quality template without error', () async { ... });
  test('executes altitude profile template without error', () async { ... });
  test('executes anomaly detection template without error', () async { ... });
  test('executes flight summary template without error', () async { ... });
  test('executes mode timeline template without error', () async { ... });

  test('exports to Parquet with correct schema', () async { ... });
  test('exports all tables with manifest', () async { ... });
  test('handles invalid SQL gracefully', () async {
    expect(
      () => store.query('SELECT * FROM nonexistent'),
      throwsA(isA<QueryException>()),
    );
  });

  test('recovers from crash (unclosed database)', () async { ... });
});
```

### 3.5 Command Sender Tests

```dart
group('CommandSender', () {
  test('sends arm command and receives ACK', () async { ... });
  test('retries command on timeout (max 3)', () async { ... });
  test('returns timeout after 3 failed attempts', () async { ... });
  test('returns denied when ACK has MAV_RESULT_DENIED', () async { ... });
  test('sends correct flight mode value for ArduPlane', () async { ... });
  test('sends correct flight mode value for ArduCopter', () async { ... });
});
```

### 3.6 Mission Protocol Tests

```dart
group('MissionService', () {
  test('downloads mission with correct handshake sequence', () async { ... });
  test('uploads mission with correct handshake sequence', () async { ... });
  test('handles mission download timeout', () async { ... });
  test('handles mission upload rejection', () async { ... });
  test('retries individual items on request-resend', () async { ... });
  test('correctly converts lat/lon to/from int32 format', () async { ... });
  test('clears mission on vehicle', () async { ... });
});
```

### 3.7 Analytics Template Validation

Every SQL template must be tested against synthetic data:

```dart
group('Analytics Templates', () {
  late TelemetryStore store;

  setUp(() async {
    store = TelemetryStore();
    await store.createFlight(...);
    await _insertSyntheticData(store, durationMinutes: 10);
  });

  for (final template in AnalyticsTemplate.values) {
    test('template "${template.name}" executes without error', () async {
      final result = await store.runTemplate(template);
      expect(result.rowCount, greaterThan(0));
    });
  }
});
```

---

## 4. Widget Tests

### 4.1 PFD Widget Tests

```dart
group('PrimaryFlightDisplay', () {
  test('renders at level attitude', () async { ... });
  test('renders at extreme roll (±90°)', () async { ... });
  test('renders at extreme pitch (±45°)', () async { ... });
  test('renders heading tape with cardinal directions', () async { ... });
  test('renders aircraft symbol at center', () async { ... });
  test('matches golden file for level flight', () async { ... });
  test('matches golden file for banked turn', () async { ... });
});
```

### 4.2 Telemetry Strip Tests

```dart
group('TelemetryStrip', () {
  test('displays battery voltage with correct format', () async { ... });
  test('shows green for battery > 30%', () async { ... });
  test('shows yellow for battery 15-30%', () async { ... });
  test('shows red for battery < 15%', () async { ... });
  test('displays satellite count', () async { ... });
  test('shows red for GPS no fix', () async { ... });
  test('displays flight mode name', () async { ... });
  test('shows ARMED indicator in red', () async { ... });
  test('shows DISARMED indicator in green', () async { ... });
  test('handles 0% battery without crash', () async { ... });
  test('handles 0 satellites without crash', () async { ... });
  test('handles unknown flight mode gracefully', () async { ... });
});
```

### 4.3 Connection Badge Tests

```dart
group('ConnectionBadge', () {
  test('shows grey when disconnected', () async { ... });
  test('shows green when connected', () async { ... });
  test('shows yellow when link degraded', () async { ... });
  test('shows red when link lost', () async { ... });
  test('displays vehicle type when connected', () async { ... });
});
```

### 4.4 Layout Responsiveness Tests

```dart
group('Responsive layouts', () {
  test('shows NavigationRail at desktop width (1400px)', () async { ... });
  test('shows NavigationRail at tablet width (900px)', () async { ... });
  test('shows BottomNavigationBar at mobile width (375px)', () async { ... });
  test('Fly View uses column layout on desktop', () async { ... });
  test('Fly View stacks vertically on tablet', () async { ... });
  test('Fly View uses overlay PFD on mobile', () async { ... });
});
```

---

## 5. Integration Tests

### 5.1 SITL Test Environment

ArduPilot SITL (Software In The Loop) provides a complete autopilot simulation.

```yaml
# docker-compose.sitl.yaml
services:
  ardupilot-sitl:
    image: ardupilot/sitl:latest
    command: >
      sim_vehicle.py
        --vehicle ArduPlane
        --frame plane
        --out=udp:host.docker.internal:14550
        --speedup 5
    ports:
      - "5760:5760"    # TCP MAVLink
      - "14550:14550/udp"  # UDP MAVLink
```

### 5.2 SITL Integration Tests

```dart
@Tags(['integration', 'sitl'])
group('SITL Integration', () {
  late MavlinkService mavlink;

  setUpAll(() async {
    // Start SITL container (or connect to running instance)
    mavlink = MavlinkService(UdpTransport('127.0.0.1', 14550));
    await mavlink.connect(const UdpConnectionConfig());
    // Wait for heartbeat
    await mavlink.messagesOf<HeartbeatMessage>().first.timeout(
      const Duration(seconds: 10),
    );
  });

  test('receives heartbeat from SITL', () async {
    expect(mavlink.linkState, LinkState.connected);
  });

  test('receives attitude data at expected rate', () async {
    final attitudes = await mavlink.messagesOf<AttitudeMessage>()
      .take(50)
      .toList();
    expect(attitudes.length, 50);
  });

  test('receives GPS data with 3D fix', () async {
    final gps = await mavlink.messagesOf<GpsRawIntMessage>().first;
    expect(gps.fixType, greaterThanOrEqualTo(3));
  });

  test('arms and disarms vehicle', () async {
    final result = await mavlink.commands.setArmed(true);
    expect(result, CommandResult.accepted);
    // Verify armed via heartbeat
    final hb = await mavlink.messagesOf<HeartbeatMessage>().first;
    expect(hb.baseMode & 128, isNonZero); // MAV_MODE_FLAG_SAFETY_ARMED

    final disarmResult = await mavlink.commands.setArmed(false);
    expect(disarmResult, CommandResult.accepted);
  });

  test('uploads and downloads mission', () async {
    final mission = [
      MissionItem(seq: 0, command: MavCmd.navTakeoff, altitude: 50, ...),
      MissionItem(seq: 1, command: MavCmd.navWaypoint, latitude: -35.362, longitude: 149.165, altitude: 100),
      MissionItem(seq: 2, command: MavCmd.navReturnToLaunch),
    ];

    await missionService.uploadMission(mission);
    final downloaded = await missionService.downloadMission();

    expect(downloaded.length, 3);
    expect(downloaded[1].latitude, closeTo(-35.362, 0.001));
  });

  test('records full flight to DuckDB and exports Parquet', () async {
    final store = TelemetryStore();
    final flightPath = await store.createFlight(
      vehicleSysId: 1,
      vehicleType: VehicleType.fixedWing,
      autopilot: AutopilotType.ardupilot,
    );

    // Record for 30 seconds at 5x speed = 150 seconds sim time
    mavlink.messageStream.listen(store.buffer);
    await Future.delayed(const Duration(seconds: 30));
    await store.flush();
    await store.closeFlight();

    // Verify data was recorded
    await store.openFlight(flightPath);
    final attitudeCount = await store.query('SELECT COUNT(*) FROM attitude');
    expect(attitudeCount.rows.first.first, greaterThan(100));

    // Run all analytics templates
    for (final template in AnalyticsTemplate.values) {
      final result = await store.runTemplate(template);
      expect(result.rowCount, greaterThan(0),
        reason: 'Template ${template.name} returned no rows');
    }

    // Export to Parquet
    final manifest = await store.exportAllParquet('/tmp/helios_test_export');
    expect(manifest.tables.length, greaterThan(5));
    expect(File('${manifest.directory}/attitude.parquet').existsSync(), isTrue);

    await store.closeFlight();
  });
});
```

### 5.3 DuckDB Round-Trip Test

```dart
@Tags(['integration'])
test('DuckDB: write → close → reopen → query → export round-trip', () async {
  final store = TelemetryStore();

  // Create and populate
  final path = await store.createFlight(...);
  for (var i = 0; i < 1000; i++) {
    store.buffer(_syntheticAttitude(i));
    store.buffer(_syntheticGps(i));
    store.buffer(_syntheticBattery(i));
  }
  await store.flush();
  await store.closeFlight();

  // Reopen and verify
  await store.openFlight(path);
  final attitude = await store.query('SELECT COUNT(*) FROM attitude');
  expect(attitude.rows.first.first, 1000);

  // Query with template
  final summary = await store.runTemplate(AnalyticsTemplate.flightSummary);
  expect(summary.rowCount, 1);

  // Export
  final parquetPath = await store.exportParquet(
    tableName: 'attitude',
    outputPath: '/tmp/test_attitude.parquet',
  );
  expect(File(parquetPath).existsSync(), isTrue);
  expect(File(parquetPath).lengthSync(), greaterThan(0));
});
```

---

## 6. Performance Tests

```dart
@Tags(['performance'])
group('Performance benchmarks', () {
  test('PFD paint completes in < 4ms', () async {
    final painter = PfdPainter(attitude: Attitude(roll: 0.5, pitch: -0.1, yaw: 2.0));
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    final sw = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      painter.paint(canvas, const Size(320, 240));
    }
    sw.stop();

    final avgMs = sw.elapsedMicroseconds / 100 / 1000;
    expect(avgMs, lessThan(4.0), reason: 'PFD paint took ${avgMs}ms average');
  });

  test('DuckDB batch insert of 50 rows completes in < 10ms', () async {
    final store = TelemetryStore();
    await store.createFlight(...);

    final rows = List.generate(50, (i) => _syntheticAttitude(i));
    for (final row in rows) {
      store.buffer(row);
    }

    final sw = Stopwatch()..start();
    await store.flush();
    sw.stop();

    expect(sw.elapsedMilliseconds, lessThan(10),
      reason: 'Flush took ${sw.elapsedMilliseconds}ms');
  });

  test('DuckDB aggregation query on 100k rows completes in < 500ms', () async {
    final store = TelemetryStore();
    await store.createFlight(...);

    // Insert 100k attitude rows
    for (var i = 0; i < 100000; i++) {
      store.buffer(_syntheticAttitude(i));
    }
    await store.flush();

    final sw = Stopwatch()..start();
    await store.query('''
      SELECT
        DATE_TRUNC('minute', ts) AS minute,
        AVG(roll), AVG(pitch), AVG(yaw),
        STDDEV(roll), STDDEV(pitch), STDDEV(yaw)
      FROM attitude
      GROUP BY minute
      ORDER BY minute
    ''');
    sw.stop();

    expect(sw.elapsedMilliseconds, lessThan(500),
      reason: 'Aggregation took ${sw.elapsedMilliseconds}ms');
  });
});
```

---

## 7. CI Pipeline

### 7.1 GitHub Actions

```yaml
# .github/workflows/ci.yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: dart analyze --fatal-infos
      - run: dart format --set-exit-if-changed .

  test-unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter test --coverage --exclude-tags integration,sitl,performance
      - uses: codecov/codecov-action@v4
        with:
          file: coverage/lcov.info

  test-widget:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter test --tags widget

  test-integration:
    runs-on: ubuntu-latest
    services:
      ardupilot-sitl:
        image: ardupilot/sitl:latest
        ports:
          - 14550:14550/udp
          - 5760:5760
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter test --tags integration

  build:
    needs: [analyze, test-unit, test-widget]
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter build linux --release  # or macos / windows
      - uses: actions/upload-artifact@v4
        with:
          name: helios-${{ matrix.os }}
          path: build/
```

### 7.2 Coverage Requirements

| Module | Minimum Coverage |
|--------|-----------------|
| `core/mavlink/` | 90% |
| `core/telemetry/` | 90% |
| `core/mission/` | 85% |
| `shared/models/` | 95% |
| `features/` (widgets) | 70% |
| **Overall** | **80%** |

---

## 8. Hardware-in-the-Loop Tests (P1)

Manual test procedures for physical hardware:

| Test | Hardware | Procedure | Pass Criteria |
|------|----------|-----------|---------------|
| Serial connect | Pixhawk 6C + USB | Connect via USB, verify heartbeat | Heartbeat within 5s |
| Telemetry radio | SiK radio pair | Connect 57600 baud, verify data | Attitude updates at 20+ Hz |
| Parameter read | Any Pixhawk | Fetch full param list | All params received, no gaps |
| Mission upload | SITL + real FC | Upload 10-waypoint mission | Mission ACK received |
| Real flight | ArduPlane VTOL | Full flight with recording | DuckDB file valid, all templates run |
