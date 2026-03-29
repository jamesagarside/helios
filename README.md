# Helios GCS

Open-source ground control station for MAVLink and MSP UAVs. Part of the [Argus Platform](https://github.com/jamesagarside).

Flutter + DuckDB + MAVLink v2 + MSP | Apache 2.0

## Protocol & Feature Support

Helios supports both MAVLink (ArduPilot, PX4, iNav with MAVLink) and MSP (Betaflight, iNav with Cleanflight protocol). Protocol is auto-detected on connect, or you can force a specific protocol in Setup.

### Flight Controller Compatibility

| Flight Controller | Protocol | Status |
|---|---|---|
| ArduPilot (Plane, Copter, Rover, Sub) | MAVLink v2 | Full support |
| PX4 | MAVLink v2 | Full support |
| iNav (MAVLink mode) | MAVLink v2 | Full support |
| Betaflight | MSP | Full support |
| iNav (MSP mode) | MSP | Full support |
| Cleanflight | MSP | Full support |

### Feature Matrix

| Feature | MAVLink | MSP | Notes |
|---|:---:|:---:|---|
| **Live Telemetry** | | | |
| Attitude (roll, pitch, yaw) | ✅ | ✅ | |
| GPS position & fix | ✅ | ✅ | |
| Altitude (relative to home) | ✅ | ✅ | |
| Altitude (MSL) | ✅ | ✅ | |
| Groundspeed | ✅ | ✅ | |
| Airspeed | ✅ | ❌ | MSP does not expose airspeed sensor data |
| Climb rate | ✅ | ✅ | |
| Battery voltage | ✅ | ✅ | |
| Battery current | ✅ | ✅ | |
| Battery remaining % | ✅ | ✅ | |
| Flight mode | ✅ | ✅ | |
| Armed state | ✅ | ✅ | |
| GPS satellite count | ✅ | ✅ | |
| HDOP (GPS accuracy) | ✅ | ❌ | MSP_RAW_GPS does not include HDOP |
| Vibration (X/Y/Z) | ✅ | ❌ | MSP has no vibration reporting; use Blackbox |
| RSSI | ✅ | ✅ | |
| Status messages / alerts | ✅ | ❌ | No MSP equivalent to STATUSTEXT |
| **Recording & Analytics** | | | |
| DuckDB flight recording | ✅ | ✅ | MSP uses separate `msp_*` table prefix |
| Altitude chart | ✅ | ✅ | |
| Speed chart | ✅ | ✅ (GS only) | Groundspeed only for MSP; no airspeed |
| Climb rate chart | ✅ | ✅ | |
| Battery chart | ✅ | ✅ | |
| GPS quality chart | ✅ | ✅ (sats only) | Satellite count only; no HDOP for MSP |
| Attitude chart | ✅ | ✅ | |
| Vibration chart | ✅ | ❌ | Not available via MSP |
| SQL query editor | ✅ | ✅ | MAVLink and MSP tables available in same DB |
| Parquet export | ✅ | ✅ | |
| Predictive maintenance | ✅ | ⚠️ Partial | Vibration analysis unavailable without IMU data |
| Flight Forensics | ✅ | ✅ | Cross-flight DuckDB analytics |
| **Setup & Configuration** | | | |
| Connection (UDP / TCP / Serial) | ✅ | ✅ | |
| Protocol auto-detection | ✅ | ✅ | 5 s probe; first valid frame wins |
| Parameter editor | ✅ | ❌ | MSP has no parameter protocol in Helios |
| Sensor calibration | ✅ | ❌ | ArduPilot/PX4 calibration commands only |
| Stream rate control | ✅ | ❌ | Polling rates are fixed in MSP service |
| **Mission Planning** | | | |
| Waypoint upload / download | ✅ | ❌ | Betaflight has no waypoint mission support |
| Geofence | ✅ | ❌ | MAVLink fence protocol only |
| Rally points | ✅ | ❌ | MAVLink only |
| **Other** | | | |
| Dataflash log download | ✅ | ❌ | Use Betaflight Configurator for Blackbox |
| Video streaming (RTSP) | ✅ | ✅ | Transport-independent |
| Dark / light mode | ✅ | ✅ | |
| Offline map tiles | ✅ | ✅ | |

## Quick Start

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.x (stable channel)
- Platform toolchain for your OS:
  - **macOS**: Xcode 15+
  - **Linux**: clang, cmake, ninja-build, pkg-config, libgtk-3-dev
  - **Windows**: Visual Studio 2022 with C++ workload
  - **Android**: Android SDK, Android Studio or cmdline-tools
  - **iOS**: Xcode 15+, CocoaPods

### Install & Run

```bash
git clone https://github.com/jamesagarside/helios.git
cd helios
flutter pub get
```

Run on your platform:

```bash
flutter run -d macos       # macOS
flutter run -d linux       # Linux
flutter run -d windows     # Windows
flutter run -d chrome       # Web
flutter run -d <device_id>  # Android/iOS (use `flutter devices` to list)
```

Or build a release:

```bash
flutter build macos --release
flutter build linux --release
flutter build windows --release
flutter build web
flutter build apk --release
```

### Connect to a Vehicle

1. Open the app and go to **Setup** (4th tab or press `4`)
2. Select transport: **UDP** (default), **TCP**, or **Serial**
3. Set address/port (defaults: UDP `0.0.0.0:14550`, TCP `127.0.0.1:5760`)
4. Click **Connect**
5. Switch to **Fly** view (press `1`) to see live telemetry

### Telemetry Simulator (no drone needed)

For development and testing without a real vehicle:

```bash
dart run scripts/sim_telemetry.dart
```

This sends simulated ArduPlane telemetry (circular flight over Canberra) to `localhost:14550`. Connect Helios with UDP and you'll see live attitude, GPS, battery, and speed data.

### ArduPilot SITL (Docker)

For a full autopilot simulation:

```bash
./scripts/start-sitl.sh            # ArduPlane (default)
./scripts/start-sitl.sh copter      # ArduCopter
./scripts/start-sitl.sh plane 5     # 5x speed
```

Requires Docker. Connect Helios via TCP `127.0.0.1:5760`.

## Recording & Analysis

1. **Setup** > click **Start Recording** while connected
2. Telemetry is written to a DuckDB file in real time
3. Click **Stop** when done
4. Switch to **Data** view > select the flight > run SQL queries or use template buttons

Every flight is a `.duckdb` file. Query it with SQL, export to Parquet.

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `1` | Fly View |
| `2` | Plan View |
| `3` | Data View |
| `4` | Setup View |

## Project Structure

```
lib/
  core/mavlink/        MAVLink parser, transports, heartbeat watchdog
  core/telemetry/      DuckDB store, schema, analytics templates
  features/fly/        Fly View (map, PFD, telemetry strip)
  features/plan/       Plan View (mission planning)
  features/analyse/    Data View (SQL editor, flight browser)
  features/setup/      Setup View (connection, recording)
  shared/              Models, providers, theme, widgets
packages/dart_mavlink/ MAVLink v2 parser (pure Dart)
openspec/specs/        Full project specification (10 documents)
```

## Tests

```bash
flutter test
```

## Licence

Apache 2.0
