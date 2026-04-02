# Getting Started

Helios is an open-source ground control station (GCS) for MAVLink and MSP drones, built with Flutter as part of the Argus Platform. It connects to flight controllers over USB, UDP, or TCP and provides real-time telemetry, mission planning, flight recording, and post-flight analytics.

**What makes Helios different:** Every flight is automatically recorded into a DuckDB database. Post-flight analysis is as powerful as the live display -- you can query, chart, and compare any flight with SQL. No other GCS treats telemetry as queryable data.

---

## Supported Platforms

| Platform | Status | Notes |
|---|---|---|
| macOS | Full support | Primary development platform. Requires macOS 13+ and Xcode 15+. |
| Linux | Full support | Requires clang, cmake, ninja-build, and GTK3 dev headers. |
| Windows | Full support | Requires Visual Studio 2022 with C++ Desktop workload. |
| iOS | Limited | Serial USB not available. No SITL launcher (Docker not supported). |
| Android | Limited | Serial USB not available. No SITL launcher (Docker not supported). |

---

## Supported Flight Controllers

| Protocol | Firmware | Notes |
|---|---|---|
| MAVLink v2 | ArduPilot | Full support -- telemetry, missions, parameters, calibration, geofence, rally points. |
| MAVLink v2 | PX4 | Telemetry and mission support. Some parameter metadata differences from ArduPilot. |
| MSP | iNav | Telemetry only. Mission and parameter support planned. |
| MSP | Betaflight | Telemetry only. |
| MSP | Cleanflight | Telemetry only. |

MAVLink-based controllers receive the richest feature set. MSP support covers telemetry display but does not yet include mission upload, parameter editing, or calibration.

---

## System Requirements

| Requirement | Minimum |
|---|---|
| macOS | 13+ with Xcode 15+ |
| Linux | x64 with GTK3 |
| Windows | 10+ with Visual C++ Redistributable |
| DuckDB native library | Required for flight recording (see [Installation](installation.md)) |

---

## Quick Install

Download the latest release for your platform from the [GitHub Releases page](https://github.com/jamesagarside/helios/releases):

| Platform | Package |
|---|---|
| macOS | `helios-gcs-macos.dmg` -- open and drag to Applications |
| Linux | `helios-gcs-linux-x64.tar.gz` -- extract and run |
| Windows | `helios-gcs-windows-x64.zip` -- extract and run |

See the [Installation guide](installation.md) for detailed platform-specific setup, DuckDB configuration, and troubleshooting. To build from source, see [Building from Source](building-from-source.md).

---

## First Connection

1. Open the **Setup** tab.
2. Select a transport:

| Transport | When to use | Address format |
|---|---|---|
| UDP | SITL or network-connected vehicles | `0.0.0.0:14550` (listen) or `host:port` |
| TCP | SITL or companion computers | `127.0.0.1:5760` |
| Serial | USB-connected flight controllers | Select port from dropdown, baud 115200 |

3. Tap **Connect**. Helios sends a heartbeat and waits for the vehicle to respond.
4. Once connected, the status bar turns green and telemetry begins streaming.

Serial connections auto-detect available USB ports. The default baud rate of 115200 works for most ArduPilot and PX4 configurations.

---

## Quick SITL Testing

If you have Docker installed, you can launch an ArduPilot SITL simulation without leaving Helios:

```bash
make sitl
```

This pulls the `ardupilot/ardupilot-sitl:latest` Docker image (on first run) and starts ArduCopter. Then connect via **TCP 127.0.0.1:5760** in the Setup tab.

Alternatively, use the built-in **Simulate** tab in Helios to launch SITL with configurable vehicle type, airframe, start location, wind, and failure injection. See the [Simulate documentation](simulate.md) for details.

---

## Next Steps

| Topic | Link |
|---|---|
| Download and install prebuilt packages | [Installation](installation.md) |
| Build from source | [Building from Source](building-from-source.md) |
| Real-time flight operations | [Fly View](fly_view.md) |
| Mission planning and survey generation | [Mission Planning](mission_planning.md) |
| SITL simulation launcher | [Simulate](simulate.md) |
| Diagnostic panels and sensor data | [Diagnostic Panels](diagnostic_panels.md) |
| No-fly zone management | [No-Fly Zones](no_fly_zones.md) |
| Points of interest | [Points of Interest](points_of_interest.md) |
