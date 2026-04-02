# Helios GCS

Open-source ground control station for MAVLink and MSP UAVs. Part of the [Argus Platform](https://github.com/jamesagarside).

Flutter + DuckDB + MAVLink v2 + MSP | GPL-3.0

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
| Status message log overlay | ✅ | ❌ | Scrolling STATUSTEXT feed on Fly View |
| **Fly View Controls** | | | |
| Flight action panel | ✅ | ❌ | ARM/DISARM, mode picker, RTL/LAND/LOITER/AUTO/BRAKE/TAKEOFF |
| Vehicle-type-aware flight modes | ✅ | ❌ | Correct mode names for Copter, Plane, Rover, VTOL |
| Customisable telemetry tiles | ✅ | ✅ | 21 fields; drag-to-reorder, long-press-to-remove |
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
| Connection (UDP / TCP) | ✅ | ✅ | |
| Connection (Serial / USB) | ✅ | ✅ | macOS, Linux, Windows only — not available on iOS/Android |
| Protocol auto-detection | ✅ | ✅ | 5 s probe; first valid frame wins |
| Parameter editor | ✅ | ❌ | MSP has no parameter protocol in Helios |
| Sensor calibration | ✅ | ❌ | ArduPilot/PX4 calibration commands only |
| Stream rate control | ✅ | ❌ | Polling rates are fixed in MSP service |
| **Mission Planning** | | | |
| Waypoint upload / download | ✅ | ❌ | Betaflight has no waypoint mission support |
| DO_ action commands (speed, jump, camera, gimbal, gripper) | ✅ | ❌ | Labelled param editor per command type |
| Multi-select + batch altitude / delete | ✅ | ❌ | Long-press → checkbox mode; Ctrl+A |
| KML / GPX import | ✅ | ❌ | Placemark, LineString, wpt, trkpt |
| Polygon area survey | ✅ | ❌ | Tap polygon vertices → lawnmower grid clipped to shape |
| Geofence | ✅ | ❌ | MAVLink fence protocol only |
| Rally points | ✅ | ❌ | MAVLink only |
| **Simulate (SITL)** | | | |
| One-click SITL launch | ✅ | ❌ | macOS/Linux; native binary auto-download; not iOS/Android/Windows |
| Vehicle + airframe picker | ✅ | ❌ | ArduCopter/Plane/Rover/Sub/Heli + variants |
| Predefined start locations | ✅ | ❌ | CMAC, Duxford, SFO Bay, Sydney + custom lat/lon |
| Wind injection | ✅ | ❌ | SIM_WIND_SPD + SIM_WIND_DIR via MAVLink params |
| Failure injection (GPS, compass, battery) | ✅ | ❌ | Live toggle while SITL running |
| Speed multiplier (1×–8×) | ✅ | ❌ | SIM_SPEEDUP param; test long missions fast |
| SITL log viewer | ✅ | ❌ | Live stdout/stderr stream in Setup tab |
| **Points of Interest** | | | |
| POI markers (pin/star/camera/target/home/flag) | ✅ | ✅ | 6 icons × 6 colours; Plan + Fly View |
| POI details panel (name, notes, coords, altitude) | ✅ | ✅ | Tap to view, long-press to edit |
| Orbit mission generator | ✅ | ❌ | Clockwise circle, configurable radius/laps/speed |
| **No-Fly Zones & Airspace** | | | |
| OpenAIP live airspace fetch | ✅ | ✅ | Free API key required; 7-day local cache |
| GeoJSON airspace file import | ✅ | ✅ | OpenAIP v1/v2 + standard GeoJSON |
| User-drawn NFZ overlays | ✅ | ✅ | Local planning overlays, not sent to FC |
| Waypoint conflict detection | ✅ | ✅ | Highlights wps inside restricted zones |
| **Diagnostic Panels** | | | |
| Servo output viewer (CH1–CH16 PWM bar graphs) | ✅ | ❌ | SERVO_OUTPUT_RAW; traffic-light colour coding |
| RC input viewer (CH1–CH18, RSSI, failsafe) | ✅ | ❌ | RC_CHANNELS; per-channel bars + failsafe badge |
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
flutter run -d <device_id>  # Android/iOS (use `flutter devices` to list)
```

Or build a release:

```bash
flutter build macos --release
flutter build linux --release
flutter build windows --release
flutter build apk --release
flutter build ipa --release   # iOS (requires signing)
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

### ArduPilot SITL (built-in)

For a full autopilot simulation, open the **Setup** tab > **Simulate** panel. Helios downloads official ArduPilot SITL binaries on first use (no Docker required). Pick a vehicle type, airframe, and start location, then click **Launch**.

Available on macOS and Linux. See the [Simulate docs](https://jamesagarside.github.io/helios/docs.html?page=simulate) for details.

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
```

## Tests

```bash
flutter test
```

## Licence

GPL-3.0 — see [LICENSE](LICENSE) for details.
