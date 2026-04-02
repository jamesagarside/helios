# Setup View

The Setup View configures connections, telemetry, video, display, maps, and system settings. On desktop it uses a sidebar navigation; on smaller screens it switches to a scrollable tab bar.

**Platform**: All (macOS, Linux, Windows, iOS, Android)

---

## Connection Tab

Configure how Helios connects to a flight controller.

### Protocol selection

| Protocol | Description |
|---|---|
| **Auto** | Probes MAVLink and MSP simultaneously. Picks whichever responds first (5-second timeout). |
| **MAVLink** | ArduPilot, PX4, iNav (with MAVLink enabled). Full feature set. |
| **MSP** | Betaflight and iNav. Mission planning is not available. |

### Transport types

#### UDP

| Field | Default | Description |
|---|---|---|
| Bind Address | `0.0.0.0` | Address to listen on. Use `0.0.0.0` to accept from any source. |
| Port | `14550` | Standard MAVLink GCS port. |

UDP is the recommended transport for SITL testing and WiFi telemetry radios. Helios binds to the specified address and port and waits for incoming packets.

#### TCP

| Field | Default | Description |
|---|---|---|
| Host | `127.0.0.1` | Flight controller or SITL host address. |
| Port | `5760` | Standard SITL TCP port. |

TCP is a client connection -- Helios connects to the flight controller. Use this for SITL (`127.0.0.1:5760`) or network-attached autopilots.

#### Serial

| Field | Default | Description |
|---|---|---|
| Port | (auto-detected) | Dropdown of available serial ports. Tap refresh to re-scan. |
| Baud Rate | `115200` | Supported rates: 9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600. |

Serial transport connects via USB. Port names include the device description when available.

**Platform note**: Serial/USB is not supported on iOS. A warning is shown directing users to connect via UDP or TCP through a WiFi telemetry radio.

### Auto-connect

A toggle next to the Connect button enables auto-connect. When enabled, Helios automatically reconnects using the last saved connection settings on launch.

### Link status

Once connected, the Link Status section shows:

| Field | Description |
|---|---|
| State | Disconnected, Connecting, Connected, Error |
| Link | Healthy, Degraded, Lost |
| Vehicle | Type and system ID (e.g. "Copter (SysID 1)") |
| Autopilot | ArduPilot, PX4, or other autopilot type |
| Firmware | Firmware version string (when reported) |
| Board | Board version number |
| UID | Unique vehicle identifier (hex) |
| Messages/s | Current message receive rate |
| Total msgs | Cumulative message count |

---

## Telemetry Tab

### Stream rate control

**Protocol**: MAVLink only

Controls how frequently the flight controller sends each telemetry stream. Helios uses `MAV_CMD_SET_MESSAGE_INTERVAL` for per-message rate control.

#### Presets

| Preset | Description |
|---|---|
| Normal | Balanced for flight monitoring (default) |
| High Rate | For vibration analysis and tuning |
| Low Bandwidth | For radio telemetry links |
| Custom | User-defined rates |

#### Configurable streams

| Stream | Default (Hz) | Description |
|---|---|---|
| Attitude | 10 | Roll, pitch, yaw |
| Position | 5 | GPS coordinates, altitude |
| VFR HUD | 5 | Airspeed, groundspeed, climb rate |
| Status | 2 | System status, battery, mode |
| RC Channels | 2 | RC input values |

An estimated DuckDB rows-per-minute count is shown based on the current rates.

### Recording status

Telemetry recording is automatic. It starts when a vehicle connects and stops on disconnect. Each flight is saved as a separate DuckDB file. The recording indicator shows the current state (RECORDING or IDLE) and a live row count.

---

## Video Tab

### RTSP URL

Enter the RTSP stream URL for your camera. The URL is persisted across sessions.

| Field | Example |
|---|---|
| RTSP URL | `rtsp://192.168.0.10:8554/main` |

### Options

| Setting | Description |
|---|---|
| Low-latency mode | Minimises the buffer for real-time video. |
| Auto-connect on launch | Automatically starts the video stream when the app opens. |

A **Test Stream** button connects to the configured URL to verify it works. Errors are displayed inline.

See [Video Streaming](video-streaming.md) for full video documentation.

---

## Display Tab

### Theme

Switch between Dark, Light, and Auto (follows system setting) colour schemes using a segmented control.

### Scale

A slider adjusts the global text and widget scale. Range and percentage are shown. A Reset button restores the default.

### Layout profiles

Manage Fly View layout profiles. Each profile saves chart positions, PFD visibility, telemetry tile selection, and sidebar configuration.

Three default profiles ship with Helios:

| Profile | Vehicle type |
|---|---|
| Multirotor | Copter / Helicopter |
| Fixed Wing | Plane / VTOL |
| VTOL | VTOL |

Actions per profile:

| Action | Description |
|---|---|
| Set active | Switch the Fly View to this profile |
| Duplicate | Create a copy with a new name |
| Delete | Remove custom profiles (default profiles cannot be deleted) |
| Reset | Restore a default profile to its factory settings |

---

## Offline Maps Tab

Map tiles from OpenStreetMap are cached locally for offline use. Previously viewed areas remain available without an internet connection.

| Control | Description |
|---|---|
| Cache size | Shows current disk usage of cached tiles |
| Clear Cache | Deletes all cached tiles |

To prepare for field operations, pan and zoom across the mission area while connected to the internet. The tiles will be available offline.

---

## System Tab

### Predictive maintenance

**Protocol**: MAVLink only

Analyses flight history to surface maintenance alerts. Alerts are derived from trends across recorded flights and are categorised by severity:

| Severity | Description |
|---|---|
| Critical | Immediate attention required |
| Warning | Should be addressed before next flight |
| Info | Informational trend or suggestion |

When no concerns are detected, a green status message is shown.

### Reset

Options to reset app settings and clear local data.

---

## Info Tab

Displays read-only application and runtime information:

| Section | Fields |
|---|---|
| Application | Name, version, platform, licence |
| Runtime | Flutter version, Dart version, OS, OS version |
| Key libraries | DuckDB, dart_mavlink, flutter_map, media_kit, flutter_libserialport, Riverpod |
| About | Project description |

---

## Logs Tab

**Protocol**: MAVLink only

Download onboard dataflash logs stored on the flight controller.

### Workflow

1. Connect to a vehicle.
2. Switch to the Logs tab. Helios requests the log list from the flight controller.
3. Each log entry shows its ID, size, and date (when available).
4. Tap a log to download it. Progress is shown during the transfer.
5. Downloaded logs are saved to the app's documents directory.

---

## Simulate Tab

Launch and configure ArduPilot SITL (Software In The Loop) for testing without hardware. See [Simulate](simulate.md) for full documentation.

---

## Platform Notes

| Feature | macOS | Linux | Windows | iOS | Android |
|---|:---:|:---:|:---:|:---:|:---:|
| UDP connection | Yes | Yes | Yes | Yes | Yes |
| TCP connection | Yes | Yes | Yes | Yes | Yes |
| Serial / USB connection | Yes | Yes | Yes | -- | -- |
| Stream rate control | Yes | Yes | Yes | Yes | Yes |
| Video configuration | Yes | Yes | Yes | -- | -- |
| Theme switching | Yes | Yes | Yes | Yes | Yes |
| Offline map caching | Yes | Yes | Yes | Yes | Yes |
| Dataflash log download | Yes | Yes | Yes | Yes | Yes |
| Predictive maintenance | Yes | Yes | Yes | Yes | Yes |
| SITL Simulate | Yes | Yes | Yes | -- | -- |

Serial/USB requires OS-level serial port access (`flutter_libserialport`). Video streaming requires `media_kit` (desktop only). SITL requires Docker.
