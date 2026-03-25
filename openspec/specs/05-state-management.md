# Helios GCS — State Management Specification

**Version**: 1.0.0 | **Status**: Draft | **Date**: 2026-03-24

---

## 1. State Architecture

All application state is managed through Riverpod providers. No global mutable state. No singletons. Every provider is overridable for testing.

### 1.1 Provider Hierarchy

```
Configuration Providers (settings, theme)
    ↓
Service Providers (MavlinkService, TelemetryStore, MissionService)
    ↓
State Providers (VehicleState, ConnectionState, RecordingState)
    ↓
Derived Providers (computed values, formatted strings, threshold checks)
    ↓
UI Providers (view-specific state like selected flight, SQL query text)
```

---

## 2. Core State Models

### 2.1 VehicleState

```dart
@freezed
class VehicleState with _$VehicleState {
  const factory VehicleState({
    // Identity
    @Default(0) int systemId,
    @Default(0) int componentId,
    @Default(VehicleType.unknown) VehicleType vehicleType,
    @Default(AutopilotType.unknown) AutopilotType autopilotType,
    @Default('') String firmwareVersion,

    // Attitude
    @Default(0.0) double roll,       // radians
    @Default(0.0) double pitch,      // radians
    @Default(0.0) double yaw,        // radians
    @Default(0.0) double rollSpeed,  // rad/s
    @Default(0.0) double pitchSpeed, // rad/s
    @Default(0.0) double yawSpeed,   // rad/s

    // Position
    @Default(0.0) double latitude,   // degrees
    @Default(0.0) double longitude,  // degrees
    @Default(0.0) double altitudeMsl, // metres
    @Default(0.0) double altitudeRel, // metres
    @Default(GpsFix.none) GpsFix gpsFix,
    @Default(0) int satellites,
    @Default(99.99) double hdop,

    // Speed
    @Default(0.0) double airspeed,      // m/s
    @Default(0.0) double groundspeed,   // m/s
    @Default(0) int heading,            // degrees
    @Default(0.0) double climbRate,     // m/s
    @Default(0) int throttle,           // percent

    // Battery
    @Default(0.0) double batteryVoltage, // volts
    @Default(0.0) double batteryCurrent, // amps
    @Default(-1) int batteryRemaining,   // percent, -1 = unknown
    @Default(0.0) double batteryConsumed, // mAh

    // Status
    @Default(FlightMode.unknown) FlightMode flightMode,
    @Default(false) bool armed,
    @Default(DateTime) DateTime lastHeartbeat,

    // RC
    @Default(0) int rssi,
  }) = _VehicleState;
}

enum VehicleType { unknown, fixedWing, quadrotor, vtol, helicopter, rover, boat }
enum AutopilotType { unknown, ardupilot, px4 }
enum GpsFix { none, noFix, fix2d, fix3d, dgps, rtkFloat, rtkFixed }
```

### 2.2 ConnectionState

```dart
@freezed
class ConnectionConfig with _$ConnectionConfig {
  const factory ConnectionConfig.udp({
    @Default('0.0.0.0') String bindAddress,
    @Default(14550) int port,
  }) = UdpConnectionConfig;

  const factory ConnectionConfig.tcp({
    required String host,
    @Default(5760) int port,
  }) = TcpConnectionConfig;

  const factory ConnectionConfig.serial({
    required String portName,
    @Default(57600) int baudRate,
  }) = SerialConnectionConfig;
}

@freezed
class ConnectionStatus with _$ConnectionStatus {
  const factory ConnectionStatus({
    @Default(TransportState.disconnected) TransportState transportState,
    @Default(LinkState.disconnected) LinkState linkState,
    @Default(null) ConnectionConfig? activeConfig,
    @Default(null) DateTime? connectedSince,
    @Default(0) int messagesReceived,
    @Default(0) int messagesSent,
    @Default(0.0) double messageRate,
  }) = _ConnectionStatus;
}

enum TransportState { disconnected, connecting, connected, error }
enum LinkState { disconnected, connected, degraded, lost }
```

### 2.3 RecordingState

```dart
@freezed
class RecordingState with _$RecordingState {
  const factory RecordingState({
    @Default(false) bool isRecording,
    @Default(null) String? currentFilePath,
    @Default(null) DateTime? recordingStarted,
    @Default(0) int rowsWritten,
    @Default(0) int bytesWritten,
    @Default(true) bool autoRecordOnArm,
  }) = _RecordingState;
}
```

### 2.4 MissionState

```dart
@freezed
class MissionState with _$MissionState {
  const factory MissionState({
    @Default([]) List<MissionItem> items,
    @Default(MissionTransferState.idle) MissionTransferState transferState,
    @Default(0) int transferProgress,  // 0-100
    @Default(0) int transferTotal,
    @Default(-1) int currentWaypointSeq, // active waypoint during flight
    @Default(false) bool modified,       // unsaved changes
  }) = _MissionState;
}

enum MissionTransferState { idle, uploading, downloading, error }
```

---

## 3. Provider Definitions

### 3.1 Service Providers

```dart
// Transport layer
final transportProvider = Provider<MavlinkTransport>((ref) {
  final config = ref.watch(connectionConfigProvider);
  return switch (config) {
    UdpConnectionConfig() => UdpTransport(config.bindAddress, config.port),
    TcpConnectionConfig() => TcpTransport(config.host, config.port),
    SerialConnectionConfig() => SerialTransport(config.portName, config.baudRate),
  };
});

// MAVLink service (depends on transport)
final mavlinkServiceProvider = Provider<MavlinkService>((ref) {
  final transport = ref.watch(transportProvider);
  return MavlinkService(transport);
});

// Telemetry store (DuckDB operations)
final telemetryStoreProvider = Provider<TelemetryStore>((ref) {
  return TelemetryStore();
});

// Mission service (depends on MAVLink)
final missionServiceProvider = Provider<MissionService>((ref) {
  final mavlink = ref.watch(mavlinkServiceProvider);
  return MissionService(mavlink);
});

// Export service (depends on telemetry store)
final exportServiceProvider = Provider<ExportService>((ref) {
  final store = ref.watch(telemetryStoreProvider);
  return ExportService(store);
});
```

### 3.2 State Notifier Providers

```dart
// Vehicle state — updated by MAVLink message handlers
final vehicleStateProvider = StateNotifierProvider<VehicleStateNotifier, VehicleState>((ref) {
  final mavlink = ref.watch(mavlinkServiceProvider);
  return VehicleStateNotifier(mavlink);
});

// Connection status
final connectionStatusProvider = StateNotifierProvider<ConnectionStatusNotifier, ConnectionStatus>((ref) {
  final transport = ref.watch(transportProvider);
  return ConnectionStatusNotifier(transport);
});

// Recording state
final recordingStateProvider = StateNotifierProvider<RecordingStateNotifier, RecordingState>((ref) {
  final store = ref.watch(telemetryStoreProvider);
  return RecordingStateNotifier(store);
});

// Mission state
final missionStateProvider = StateNotifierProvider<MissionStateNotifier, MissionState>((ref) {
  final missionService = ref.watch(missionServiceProvider);
  return MissionStateNotifier(missionService);
});
```

### 3.3 Derived Providers

```dart
// Battery health assessment
final batteryHealthProvider = Provider<BatteryHealth>((ref) {
  final vehicle = ref.watch(vehicleStateProvider);
  return BatteryHealth.fromVoltageAndPercent(
    vehicle.batteryVoltage,
    vehicle.batteryRemaining,
  );
});

// GPS quality assessment
final gpsQualityProvider = Provider<GpsQuality>((ref) {
  final vehicle = ref.watch(vehicleStateProvider);
  return GpsQuality.fromFixAndHdop(vehicle.gpsFix, vehicle.hdop);
});

// Link quality assessment
final linkQualityProvider = Provider<LinkQuality>((ref) {
  final connection = ref.watch(connectionStatusProvider);
  return LinkQuality.fromState(connection.linkState, connection.messageRate);
});

// Vehicle position as LatLng (for map)
final vehiclePositionProvider = Provider<LatLng?>((ref) {
  final vehicle = ref.watch(vehicleStateProvider);
  if (vehicle.latitude == 0.0 && vehicle.longitude == 0.0) return null;
  return LatLng(vehicle.latitude, vehicle.longitude);
});

// Formatted telemetry strings
final formattedAltitudeProvider = Provider<String>((ref) {
  final vehicle = ref.watch(vehicleStateProvider);
  return '${vehicle.altitudeRel.toStringAsFixed(1)}m';
});
```

---

## 4. State Update Flow

### 4.1 MAVLink → State Update Pipeline

```
1. MavlinkService receives decoded message
2. Calls vehicleStateNotifier.handleMessage(msg)
3. StateNotifier updates immutable state (copyWith)
4. Riverpod notifies all watching providers/widgets
5. ConsumerWidgets rebuild with new state
```

### 4.2 Update Throttling

Some messages arrive faster than the UI can render. Strategy:

| Data | Max UI Update Rate | Method |
|------|--------------------|--------|
| Attitude (PFD) | 60 Hz | AnimationController driven repaint |
| GPS (Map marker) | 10 Hz | State update, natural throttle |
| Battery | 1 Hz | Direct state update |
| Telemetry strip values | 4 Hz | Timer-based batch update |

The PFD uses a dedicated `Ticker` to drive repaint at display refresh rate, interpolating between the two most recent attitude samples for smooth animation.

---

## 5. Persistence

### 5.1 Settings Persistence

User settings persisted via `shared_preferences`:

```dart
@freezed
class AppSettings with _$AppSettings {
  const factory AppSettings({
    // Connection
    @Default(ConnectionConfig.udp()) ConnectionConfig lastConnection,
    @Default(true) bool autoRecordOnArm,

    // Display
    @Default('metric') String unitSystem,      // 'metric' | 'imperial'
    @Default('dd') String coordinateFormat,     // 'dd' | 'dms' | 'utm'
    @Default(1.0) double fontScale,

    // Map
    @Default('osm') String tileProvider,
    @Default(14) int defaultZoom,

    // Analyse
    @Default([]) List<String> recentQueries,
    @Default('') String lastOpenedFlight,
  }) = _AppSettings;
}
```

### 5.2 Flight Database Location

```
// Platform-specific app data directories:
// Linux:   ~/.local/share/helios/flights/
// macOS:   ~/Library/Application Support/helios/flights/
// Windows: %APPDATA%\helios\flights\
// Android: /data/data/com.argus.helios/flights/
// iOS:     <app>/Documents/flights/
```

---

## 6. Testing Strategy for State

### 6.1 Unit Tests

Every StateNotifier has corresponding tests:

```dart
// Example: VehicleStateNotifier test
test('updates roll/pitch/yaw from ATTITUDE message', () {
  final notifier = VehicleStateNotifier(mockMavlink);

  notifier.handleMessage(AttitudeMessage(
    roll: 0.1, pitch: -0.05, yaw: 3.14,
    rollSpeed: 0.01, pitchSpeed: 0.0, yawSpeed: -0.02,
  ));

  expect(notifier.state.roll, closeTo(0.1, 0.001));
  expect(notifier.state.pitch, closeTo(-0.05, 0.001));
  expect(notifier.state.yaw, closeTo(3.14, 0.001));
});
```

### 6.2 Provider Override Testing

```dart
// Widget tests use ProviderScope overrides
testWidgets('telemetry strip shows battery voltage', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vehicleStateProvider.overrideWith(
          (ref) => VehicleStateNotifier.withState(
            const VehicleState(batteryVoltage: 12.4),
          ),
        ),
      ],
      child: const MaterialApp(home: TelemetryStrip()),
    ),
  );

  expect(find.text('12.4V'), findsOneWidget);
});
```
