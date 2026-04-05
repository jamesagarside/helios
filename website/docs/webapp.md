# Web App

Helios GCS runs as a Progressive Web App (PWA) at [app.heliosgcs.com](https://app.heliosgcs.com). This document covers the web architecture, platform abstraction layer, connectivity via the Helios Relay, and deployment.

> **Looking for the user guide?** See the [Web App Guide](docs.html?page=web-app-guide) for setup instructions, browser compatibility, relay installation, and troubleshooting.

## Architecture Overview

The web app is the same Flutter codebase compiled to JavaScript. Platform-specific features (native sockets, DuckDB FFI, serial ports) are handled through compile-time conditional imports that swap in web-compatible implementations.

```
                       Browser (app.heliosgcs.com)
                       ┌──────────────────────────────┐
                       │  Flutter Web App (PWA)        │
                       │  ┌────────┐  ┌─────────────┐ │
                       │  │ UI     │  │ Telemetry   │ │
                       │  │ Views  │  │ Recording   │ │
                       │  └───┬────┘  └──────┬──────┘ │
                       │      │              │        │
                       │  ┌───┴──────────────┴──┐     │
                       │  │  WebSocket Transport │     │
                       │  └───────────┬─────────┘     │
                       └──────────────┼───────────────┘
                                      │ ws://
                                      │
                       ┌──────────────┴───────────────┐
                       │       Helios Relay            │
                       │   WebSocket ↔ TCP bridge      │
                       │   (runs on user's machine)    │
                       └──────────────┬───────────────┘
                                      │ TCP :5760
                                      │
                       ┌──────────────┴───────────────┐
                       │    Flight Controller          │
                       │    (ArduPilot / PX4)          │
                       └──────────────────────────────┘
```

## Platform Abstraction

Helios uses Dart's conditional imports to provide platform-specific implementations behind shared interfaces. The compiler includes only the correct implementation — there is no runtime overhead.

### Database

| Platform | Backend | Storage |
|---|---|---|
| Native (macOS, Linux, Windows) | DuckDB via FFI | File system (`.duckdb` files) |
| Web | sql.js (SQLite compiled to WASM) | IndexedDB |

The database interface (`lib/core/database/database_interface.dart`) defines `HeliosDatabase` and `HeliosDatabaseFactory`. The conditional export in `database.dart` resolves at compile time:

```dart
export 'database_native.dart'
    if (dart.library.js_interop) 'database_web.dart';
```

Web capabilities differ from native — see `HeliosDatabaseCapabilities` for what each backend supports (e.g. web does not support `ATTACH` or `COPY TO` for Parquet export).

### MAVLink Transports

| Transport | Native | Web |
|---|---|---|
| TCP | Raw `dart:io` sockets | Stub (use WebSocket via relay) |
| UDP | Raw `dart:io` datagrams | Stub (use WebSocket via relay) |
| Serial (USB) | `flutter_libserialport` | Stub (Web Serial API planned) |
| WebSocket | `web_socket_channel` | `web_socket_channel` (primary) |

On web, the **WebSocket transport** is the primary connection method. It works on all platforms (including native) and connects through the Helios Relay to reach the flight controller.

### File System

The web file system (`lib/core/platform/file_system_web.dart`) maps flight storage to IndexedDB object stores instead of the native file system.

### Video

RTSP video streaming (`media_kit`) is not available on web. The video tab is hidden on web builds.

## Helios Relay

The relay is a lightweight Dart server that bridges browser WebSocket connections to raw TCP MAVLink connections. It runs on the user's local machine (same network as the flight controller).

### How It Works

1. The relay listens for WebSocket connections on port `8765`
2. For each WebSocket client, it opens a dedicated TCP connection to the flight controller
3. Binary MAVLink frames are forwarded in both directions with zero transformation
4. Multiple browser tabs can connect simultaneously (each gets its own TCP session)

### Installation

**From source (requires Dart SDK):**

```bash
git clone https://github.com/jamesagarside/helios.git
cd helios
dart compile exe scripts/helios_relay.dart -o helios-relay
./helios-relay --fc-host 192.168.4.1
```

**From release binary:**

```bash
curl -fsSL https://heliosgcs.com/relay/install.sh | sh
helios-relay --fc-host 192.168.4.1
```

### Usage

```bash
# Connect to SITL on localhost
helios-relay

# Connect to WiFi flight controller
helios-relay --fc-host 192.168.4.1

# Custom port
helios-relay --fc-host 10.0.0.5 --fc-port 5762

# Custom WebSocket port
helios-relay --ws-port 9000
```

The relay requires no admin access and runs entirely in user space. It serves a status page at `http://localhost:8765` when accessed via a regular HTTP request.

### Relay Status Detection

The web app includes a relay status provider (`lib/shared/providers/relay_status_provider.dart`) that probes the WebSocket endpoint and reports whether the relay is reachable. The UI can use this to show connection guidance.

## Feature Parity

| Feature | Desktop | Web | Notes |
|---|---|---|---|
| Real-time telemetry (PFD, map, charts) | Yes | Yes | Via WebSocket relay |
| Mission planning | Yes | Yes | Full mission editor |
| Flight recording (DuckDB) | Yes | Yes | sql.js on web, IndexedDB persistence |
| Post-flight analytics | Yes | Yes | SQL queries, charts (no Parquet export) |
| Parquet/CSV/JSON export | Yes | No | Hidden on web (requires file system) |
| USB serial connection | Yes | No | Web Serial API planned for Chrome |
| TCP/UDP direct connection | Yes | No | Use WebSocket relay instead |
| RTSP video streaming | Yes | No | media_kit requires native platform |
| SITL simulator tab | Yes | No | Requires local binary execution |
| Geofence editor | Yes | Yes | |
| Parameter editor | Yes | Yes | Via WebSocket relay |
| Rally points | Yes | Yes | |
| Calibration | Yes | Yes | Via WebSocket relay |
| Log download | Yes | No | Hidden on web (requires file system) |
| Offline tile caching | Yes | Yes | Via browser Cache API |
| PWA install (Add to Home Screen) | N/A | Yes | Standalone app experience |

## Deployment

### Hosting

The web app is hosted on GitHub Pages at [app.heliosgcs.com](https://app.heliosgcs.com), deployed from a separate repository (`jamesagarside/helios-app`).

A GitHub Actions workflow in the main Helios repo builds the Flutter web output and pushes it to the deployment repo when a new release is published (or triggered manually via workflow_dispatch).

### DNS Setup

Add a `CNAME` record in your DNS provider:

```
app.heliosgcs.com → jamesagarside.github.io
```

Then enable GitHub Pages on the `helios-app` repo with the custom domain `app.heliosgcs.com`.

### Deploy Key Setup

The deploy workflow pushes to an external repo, so it needs a deploy key:

1. Generate an SSH key pair: `ssh-keygen -t ed25519 -f helios-webapp-deploy -C "helios-webapp-deploy"`
2. Add the **public key** as a deploy key on the `helios-app` repo (Settings > Deploy keys, enable write access)
3. Add the **private key** as a secret named `WEBAPP_DEPLOY_KEY` on the main `helios` repo (Settings > Secrets > Actions)

### Manual Deploy

Trigger the workflow manually from the GitHub Actions UI, or build locally:

```bash
flutter build web --release
cd build/web
python3 -m http.server 8080
```

### PWA Support

The web app is configured as a Progressive Web App. Users can install it to their home screen or desktop for a native-like experience. The `manifest.json` defines the app name, icons, theme colour, and standalone display mode. A service worker handles offline caching of static assets.

## Developing for Web

### Local Development

```bash
# Run in Chrome with hot reload
flutter run -d chrome

# Or build and serve
flutter build web
cd build/web && python3 -m http.server 8080
```

### Testing with SITL

1. Start SITL: `make sitl`
2. Start the relay: `dart run scripts/helios_relay.dart`
3. Open the web app and connect via WebSocket to `ws://localhost:8765`

### Platform-Specific Code

When adding features that use native APIs, always provide a web implementation:

```dart
// In database.dart — conditional export
export 'database_native.dart'
    if (dart.library.js_interop) 'database_web.dart';
```

Use `kIsWeb` from `package:flutter/foundation.dart` sparingly — prefer compile-time conditional imports over runtime checks. This keeps the web bundle smaller and avoids importing `dart:io` on web.

### Adding a New Platform-Conditional Feature

1. Define the interface in a `*_interface.dart` file
2. Implement the native version in `*_native.dart` (uses `dart:io`, FFI, etc.)
3. Implement the web version in `*_web.dart` (uses `dart:js_interop`, IndexedDB, etc.)
4. Re-export with a conditional import in the barrel file
5. Update the feature parity table above

### Hiding Features on Web

Features that use native APIs and cannot work on web are hidden from the UI using `kIsWeb`:

- **Video tab**: Removed from `responsive_scaffold.dart` destination list
- **Simulate tab**: Removed from `setup_view.dart` tab list
- **Logs tab**: Removed from `setup_view.dart` tab list
- **Video settings tab**: Removed from `setup_view.dart` tab list
- **Serial/UDP/TCP transport**: Removed from connection transport selector
- **Export buttons**: Hidden in analyse view, replaced with "not available" message
- **Default transport**: Set to WebSocket on web (instead of UDP)

When adding new features, check if they depend on native APIs and add `kIsWeb` guards accordingly. Prefer hiding the UI entirely over showing disabled buttons — it's a cleaner experience.

### User Documentation

The user-facing web app guide is at `website/docs/web-app-guide.md`. Keep it in sync when changing feature parity.
