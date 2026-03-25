# Helios GCS — MAVLink Integration Specification

**Version**: 1.0.0 | **Status**: Draft | **Date**: 2026-03-24

---

## 1. MAVLink Protocol Overview

Helios implements MAVLink v2 as the sole vehicle communication protocol. MAVLink v1 frames are accepted but v2 is preferred for signing support.

### 1.1 System Identity

| Parameter | Value | Notes |
|-----------|-------|-------|
| System ID | 255 | GCS convention |
| Component ID | 190 | MAV_COMP_ID_MISSIONPLANNER |
| MAVLink version | 2 | With v1 fallback for legacy vehicles |

### 1.2 Heartbeat

Helios sends HEARTBEAT at 1 Hz:

```
type:        MAV_TYPE_GCS (6)
autopilot:   MAV_AUTOPILOT_INVALID (8)
base_mode:   0
custom_mode: 0
system_status: MAV_STATE_ACTIVE (4)
mavlink_version: 3
```

---

## 2. Transport Layer

### 2.1 Transport Abstraction

```dart
/// Base transport interface. All transports implement this.
abstract class MavlinkTransport {
  /// Connect to the transport. Returns when connected or throws.
  Future<void> connect();

  /// Disconnect and release resources.
  Future<void> disconnect();

  /// Stream of raw bytes from the vehicle.
  Stream<Uint8List> get dataStream;

  /// Send raw bytes to the vehicle.
  Future<void> send(Uint8List data);

  /// Current connection state.
  ValueNotifier<TransportState> get state;

  /// Transport type identifier.
  TransportType get type;
}

enum TransportType { udp, tcp, serial }

enum TransportState { disconnected, connecting, connected, error }
```

### 2.2 UDP Transport (Default)

```dart
class UdpTransport implements MavlinkTransport {
  final String bindAddress;   // default: '0.0.0.0'
  final int bindPort;         // default: 14550

  // UDP is connectionless. "Connected" means we've received at least
  // one packet from a vehicle (establishing the remote endpoint).
  // Outgoing packets are sent to the last-seen remote endpoint.
}
```

- **Bind**: `0.0.0.0:14550` — standard for ArduPilot SITL and telemetry radios in AP mode.
- **Remote discovery**: First received packet establishes the remote endpoint. Subsequent sends go to that endpoint.
- **Multi-vehicle**: Different system IDs from different endpoints are tracked separately.

### 2.3 TCP Transport

```dart
class TcpTransport implements MavlinkTransport {
  final String host;   // e.g., '127.0.0.1'
  final int port;      // default: 5760

  // TCP client connecting to the vehicle/companion.
  // Reconnects with exponential backoff on disconnect.
}
```

### 2.4 Serial Transport

```dart
class SerialTransport implements MavlinkTransport {
  final String portName;    // e.g., '/dev/ttyUSB0', 'COM3'
  final int baudRate;       // default: 57600
  final int dataBits;       // default: 8
  final int stopBits;       // default: 1
  final String parity;      // default: 'none'

  // Uses flutter_libserialport for cross-platform serial access.
  // Common radios: SiK (57600), RFD900 (57600), Holybro (57600)
}
```

### 2.5 Transport Reconnection

All transports implement automatic reconnection with exponential backoff:

```
Attempt 1: immediate
Attempt 2: 1 second
Attempt 3: 2 seconds
Attempt 4: 4 seconds
...
Max: 30 seconds
Reset backoff on successful connection.
```

---

## 3. Message Parsing Pipeline

### 3.1 Parser State Machine

```
IDLE → MAGIC_RECEIVED → HEADER_PARSED → PAYLOAD_RECEIVED → CRC_VALIDATED → DISPATCHED
  ↑                                                              │
  └──────────────── (CRC fail → drop, increment error counter) ──┘
```

### 3.2 Inbound Message Processing

```dart
/// Processes a validated MAVLink message.
/// Routes to the appropriate handler based on message ID.
void _handleMessage(MavlinkMessage msg) {
  // 1. Update heartbeat watchdog (any message resets timer)
  _heartbeatWatchdog.reset();

  // 2. Route to real-time state update (UI path)
  _routeToState(msg);

  // 3. Route to telemetry recording (analytics path)
  if (_isRecording) {
    _telemetryStore.buffer(msg);
  }

  // 4. Route to specific handlers (mission protocol, params, etc.)
  _routeToHandler(msg);
}
```

### 3.3 Message Routing Table

| Message | ID | Handler | State Update | Recorded |
|---------|----|---------|--------------|---------|
| HEARTBEAT | 0 | `_handleHeartbeat()` | vehicleType, flightMode, armState | events (mode changes) |
| ATTITUDE | 30 | `_handleAttitude()` | roll, pitch, yaw, rates | attitude table |
| GLOBAL_POSITION_INT | 33 | `_handleGlobalPos()` | lat, lon, altMsl, altRel | gps table |
| GPS_RAW_INT | 24 | `_handleGpsRaw()` | fixType, satellites, hdop | gps table (merged) |
| SYS_STATUS | 1 | `_handleSysStatus()` | voltage, current, batteryPct | battery table |
| VFR_HUD | 74 | `_handleVfrHud()` | airspeed, groundspeed, heading | vfr_hud table |
| RC_CHANNELS | 65 | `_handleRcChannels()` | ch1-16, rssi | rc_channels table |
| SERVO_OUTPUT_RAW | 36 | `_handleServoOutput()` | srv1-16 | servo_output table |
| VIBRATION | 241 | `_handleVibration()` | vibeX/Y/Z, clipping | vibration table |
| STATUSTEXT | 253 | `_handleStatusText()` | — | events table |
| COMMAND_ACK | 77 | `_handleCommandAck()` | pending command result | events table |
| MISSION_ITEM_INT | 73 | `_handleMissionItem()` | mission items list | mission_items table |
| MISSION_COUNT | 44 | `_handleMissionCount()` | mission download state | — |
| MISSION_REQUEST_INT | 51 | `_handleMissionRequest()` | mission upload state | — |
| MISSION_ACK | 47 | `_handleMissionAck()` | mission transfer result | events table |
| PARAM_VALUE | 22 | `_handleParamValue()` | parameter list | params table |
| BATTERY_STATUS | 147 | `_handleBatteryStatus()` | detailed battery info | battery table |

---

## 4. Outbound Commands

### 4.1 Command Interface

```dart
/// Sends MAVLink commands to the vehicle.
class CommandSender {
  /// Arm or disarm the vehicle.
  /// Returns true if ACK received with MAV_RESULT_ACCEPTED.
  Future<CommandResult> setArmed(bool armed);

  /// Change flight mode.
  Future<CommandResult> setFlightMode(FlightMode mode);

  /// Trigger return-to-launch.
  Future<CommandResult> returnToLaunch();

  /// Send a COMMAND_LONG with retry logic.
  Future<CommandResult> sendCommand({
    required int command,
    int confirmation = 0,
    double param1 = 0, double param2 = 0,
    double param3 = 0, double param4 = 0,
    double param5 = 0, double param6 = 0,
    double param7 = 0,
  });
}

enum CommandResult { accepted, denied, failed, unsupported, timeout }
```

### 4.2 Command Retry Logic

Commands use COMMAND_LONG with automatic retry:

```
Send COMMAND_LONG (confirmation=0)
Wait 1 second for COMMAND_ACK
  → Received: return result
  → Timeout: resend with confirmation=1
Wait 1 second
  → Received: return result
  → Timeout: resend with confirmation=2
Wait 1 second
  → Received: return result
  → Timeout: return CommandResult.timeout
Max 3 attempts.
```

### 4.3 Critical Commands — Confirmation Required

The following commands require explicit user confirmation before sending:

| Command | Confirmation UI |
|---------|----------------|
| ARM (component_arm_disarm param1=1) | "Arm vehicle?" dialog |
| DISARM (component_arm_disarm param1=0) | "Disarm vehicle?" dialog |
| Mode change to AUTO | "Start autonomous mission?" dialog |
| Reboot (preflight_reboot_shutdown) | "Reboot flight controller?" dialog |

---

## 5. Heartbeat Watchdog

### 5.1 State Machine

```
DISCONNECTED → CONNECTED → LINK_DEGRADED → LINK_LOST
     ↑              │              │             │
     └──────────────┴──────────────┴─────────────┘
                  (heartbeat received)
```

| State | Condition | UI Indicator |
|-------|-----------|-------------|
| DISCONNECTED | No heartbeat ever received | Grey badge |
| CONNECTED | Heartbeat within last 2s | Green badge |
| LINK_DEGRADED | No heartbeat for 2-5s | Yellow badge + warning |
| LINK_LOST | No heartbeat for 5s+ | Red badge + alarm + event log |

### 5.2 Implementation

```dart
class HeartbeatWatchdog {
  static const Duration degradedThreshold = Duration(seconds: 2);
  static const Duration lostThreshold = Duration(seconds: 5);

  Timer? _timer;
  DateTime? _lastHeartbeat;

  void onHeartbeatReceived() {
    _lastHeartbeat = DateTime.now();
    _updateState(LinkState.connected);
    _resetTimer();
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final elapsed = DateTime.now().difference(_lastHeartbeat!);
      if (elapsed >= lostThreshold) {
        _updateState(LinkState.lost);
      } else if (elapsed >= degradedThreshold) {
        _updateState(LinkState.degraded);
      }
    });
  }
}
```

---

## 6. Mission Protocol

### 6.1 Mission Download

```
GCS → Vehicle: MISSION_REQUEST_LIST
Vehicle → GCS: MISSION_COUNT (count=N)
for i in 0..N-1:
  GCS → Vehicle: MISSION_REQUEST_INT (seq=i)
  Vehicle → GCS: MISSION_ITEM_INT (seq=i)
GCS → Vehicle: MISSION_ACK (MAV_MISSION_ACCEPTED)
```

### 6.2 Mission Upload

```
GCS → Vehicle: MISSION_COUNT (count=N)
for i in 0..N-1:
  Vehicle → GCS: MISSION_REQUEST_INT (seq=i)
  GCS → Vehicle: MISSION_ITEM_INT (seq=i)
Vehicle → GCS: MISSION_ACK (MAV_MISSION_ACCEPTED)
```

### 6.3 Mission Item Mapping

```dart
class MissionItem {
  final int seq;
  final MavFrame frame;        // MAV_FRAME_GLOBAL_RELATIVE_ALT_INT (default)
  final MavCmd command;        // MAV_CMD_NAV_WAYPOINT, etc.
  final bool current;
  final bool autoContinue;
  final double param1;         // hold time (s) for waypoint
  final double param2;         // acceptance radius (m)
  final double param3;         // pass radius (m), 0 = fly through
  final double param4;         // yaw angle (deg), NaN = unchanged
  final double latitude;       // degrees
  final double longitude;      // degrees
  final double altitude;       // metres (relative to home by default)
}
```

---

## 7. Flight Mode Mapping

### 7.1 ArduPlane Modes

| Mode Number | Name | Category |
|-------------|------|----------|
| 0 | MANUAL | Manual |
| 1 | CIRCLE | Guided |
| 2 | STABILIZE | Assisted |
| 3 | TRAINING | Assisted |
| 5 | FBWA | Assisted |
| 6 | FBWB | Assisted |
| 7 | CRUISE | Assisted |
| 10 | AUTO | Autonomous |
| 11 | RTL | Autonomous |
| 12 | LOITER | Guided |
| 14 | AVOID_ADSB | Safety |
| 15 | GUIDED | Guided |
| 17 | QSTABILIZE | VTOL |
| 18 | QHOVER | VTOL |
| 19 | QLOITER | VTOL |
| 20 | QLAND | VTOL |
| 21 | QRTL | VTOL |

### 7.2 ArduCopter Modes

| Mode Number | Name | Category |
|-------------|------|----------|
| 0 | STABILIZE | Assisted |
| 2 | ALT_HOLD | Assisted |
| 3 | AUTO | Autonomous |
| 4 | GUIDED | Guided |
| 5 | LOITER | Guided |
| 6 | RTL | Autonomous |
| 9 | LAND | Autonomous |
| 16 | POSHOLD | Guided |

### 7.3 PX4 Modes

PX4 uses `custom_main_mode` and `custom_sub_mode` from the HEARTBEAT. Mapping handled via lookup table.

---

## 8. MAVLink Signing (P1)

### 8.1 Signing Protocol

MAVLink v2 signing uses SHA-256 HMAC with a 32-byte key:

```
signature = SHA-256(secret_key + header + payload + CRC + link_id + timestamp)
```

### 8.2 Configuration

```dart
class SigningConfig {
  final Uint8List secretKey;    // 32 bytes
  final int linkId;             // 0-255
  final bool rejectUnsigned;   // reject incoming unsigned messages
  final List<int> allowUnsignedIds; // message IDs allowed unsigned (e.g., RADIO_STATUS)
}
```

### 8.3 Key Management

- Keys stored in OS keychain (flutter_secure_storage)
- Per-vehicle key configuration
- Key generation: `Random.secure()` for 32 bytes
- Key exchange: manual entry or QR code scan

---

## 9. Parameter Protocol (P1)

### 9.1 Full Parameter Fetch

```
GCS → Vehicle: PARAM_REQUEST_LIST
Vehicle → GCS: PARAM_VALUE (index=0, count=N)
Vehicle → GCS: PARAM_VALUE (index=1, count=N)
...
Vehicle → GCS: PARAM_VALUE (index=N-1, count=N)
```

- Fetch timeout: 10 seconds per batch of 100 params
- Retry missing indices individually after full list
- Store in `params` table of current flight DB

### 9.2 Parameter Write

```
GCS → Vehicle: PARAM_SET (param_id, value, type)
Vehicle → GCS: PARAM_VALUE (confirmed value)
```

- Verify returned value matches requested value
- Log parameter changes to events table

---

## 10. Error Handling

### 10.1 Parse Errors

| Error | Action | Counter |
|-------|--------|---------|
| Invalid magic byte | Skip byte, continue scanning | `parse_errors` |
| CRC mismatch | Drop frame, log if verbose | `crc_errors` |
| Unknown message ID | Accept frame, don't route to handler | `unknown_msgs` |
| Truncated frame | Wait for more data | — |
| Invalid system/component ID | Accept but don't process as own vehicle | — |

### 10.2 Transport Errors

| Error | Action |
|-------|--------|
| UDP bind failure | Retry with backoff, surface to UI |
| TCP connection refused | Reconnect with exponential backoff |
| Serial port not found | List available ports, prompt user |
| Serial port permission denied | Surface error with OS-specific fix instructions |
| Data timeout (no bytes for 10s) | Transition to LINK_DEGRADED |

### 10.3 Telemetry Statistics

Exposed via Riverpod provider for the UI status bar:

```dart
class TelemetryStats {
  final int messagesReceived;
  final int messagesSent;
  final int parseErrors;
  final int crcErrors;
  final int unknownMessages;
  final double messageRate;     // messages/second (rolling 5s window)
  final Duration latency;       // estimated one-way latency
}
```
