# Simulate (SITL Launcher)

The Simulate tab lets you launch an ArduPilot Software-In-The-Loop (SITL) simulation directly from within Helios - no terminal, no Docker, no manual setup required. SITL binaries are downloaded on-demand the first time you select a vehicle type, then cached locally for instant startup.

**Platform**: macOS, Linux
**Not available on**: iOS, Android, Windows (planned)

---

## How It Works

Helios downloads pre-built ArduPilot SITL binaries from the official firmware server (`firmware.ardupilot.org`) and runs them as native processes. Only the vehicle types you actually use are downloaded, keeping disk usage minimal (~30 MB per vehicle).

Cached binaries are stored in your application support directory:

```
~/Library/Application Support/helios_gcs/sitl_binaries/
  ArduCopter/stable/arducopter
  ArduPlane/stable/arduplane
  ...
```

---

## Launching SITL

1. Open the **Setup** tab and select **Simulate**.
2. Choose a **Vehicle** (ArduCopter, ArduPlane, ArduRover, ArduSub, ArduHeli).
3. Choose an **Airframe** variant (e.g. quad, hex, plane, rover).
4. Set **Start Altitude** (metres AGL, default 0).
5. Choose a **Start Location** from the presets, or select **Custom** and enter lat/lon/heading.
6. Tap **Launch** (or **Download & Launch** if the binary hasn't been downloaded yet).

On first launch for a vehicle type, Helios downloads the binary and shows a progress bar. Subsequent launches start instantly. After a few seconds the simulator is ready, and Helios auto-connects on **TCP 127.0.0.1:5760**.

### Predefined locations

| Location | Coordinates |
|---|---|
| CMAC (Canberra, AU) | -35.3632, 149.1652 |
| Duxford (UK) | 52.0908, 0.1319 |
| San Francisco Bay | 37.4137, -122.0160 |
| Sydney Airport | -33.9399, 151.1753 |
| Custom | Enter any lat/lon/heading |

---

## Simulation Controls

Available while SITL is running:

### Speed multiplier

Run SITL faster than real-time to test long missions quickly.

| Setting | Effect |
|---|---|
| 1x | Real-time |
| 2x | 2x speed (sets `SIM_SPEEDUP=2`) |
| 4x | 4x speed |
| 8x | 8x speed |

### Wind

- **Speed**: 0-20 m/s (sets `SIM_WIND_SPD`)
- **Direction**: 0-360 degrees (sets `SIM_WIND_DIR`)

Wind affects ArduPlane more significantly than Copter. Set to 0 m/s to disable.

### Failure injection

| Failure | Parameter | Effect |
|---|---|---|
| GPS Failed | `SIM_GPS_DISABLE=1` | GPS loss - tests EKF fallback |
| Compass Failed | `SIM_MAG1_FAIL=1` | Compass failure |
| Battery (voltage slider) | `SIM_BATT_VOLTAGE` | Simulates battery drain |

Restore by toggling back to Normal / moving the slider.

---

## Stopping SITL

Tap **Stop** to terminate the SITL process. The TCP connection to Helios will drop and the status will show **Stopped**.

---

## Managing Cached Binaries

Cached SITL binaries persist between sessions. You can see which vehicles are downloaded in the status panel. To free disk space, delete cached binaries from the application support directory.

---

## Architecture

```
SitlLauncher
  ├── downloadBinary()     Download from firmware.ardupilot.org
  ├── isCached()           Check if binary exists locally
  ├── cachedVehicles()     List cached vehicles + sizes
  ├── deleteCached()       Remove a cached binary
  ├── launch()             Download (if needed) + run binary
  └── stop()               Terminate the SITL process

SitlInjector
  ├── setWind()            Wind speed + direction
  ├── setGpsFailure()      Toggle GPS failure
  ├── setCompassFailure()  Toggle compass failure
  ├── setBatteryVoltage()  Override battery voltage
  └── setSpeedMultiplier() SITL speed (1x-8x)
```

---

## Platform Notes

| Feature | macOS | Linux | Windows | iOS | Android |
|---|:---:|:---:|:---:|:---:|:---:|
| SITL launch (native) | Yes | Yes | Planned | No | No |
| Wind injection | Yes | Yes | Planned | No | No |
| Failure injection | Yes | Yes | Planned | No | No |
| Speed multiplier | Yes | Yes | Planned | No | No |

## Future: Built-in Practice Mode

A pure Dart flight dynamics simulator is planned for a future release. This will provide basic flight simulation on all platforms - including iOS and Android - without requiring any external binaries. It will support RC controller input via USB gamepad or WiFi for a realistic practice experience.
