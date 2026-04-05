# Web App Guide

Helios GCS is available as a web app at [app.heliosgcs.com](https://app.heliosgcs.com). You can use it from any computer with a modern browser -- no installation required. This guide covers what works in the browser, how to connect to your flight controller, and how to install Helios as an app on your device.

## What You Can Do

The web app supports most of the features you would use on a desktop, with a few exceptions. Here is a summary:

| Feature | Works on Web? | Notes |
|---|---|---|
| Real-time telemetry (PFD, map, charts) | Yes | Requires Helios Relay (see below) |
| Mission planning | Yes | Full drag-and-drop editor with waypoints, surveys, geofence |
| Post-flight analytics | Yes | SQL queries and charts from recorded flights |
| Geofence editor | Yes | |
| Parameter editor | Yes | Requires connection via relay |
| Rally points | Yes | |
| Calibration | Yes | Requires connection via relay |
| Offline map tiles | Yes | Cached by your browser |
| Install as app (PWA) | Yes | Add to Home Screen for a native-like experience |
| Video streaming | No | Not available in browsers |
| USB serial connections | No | Use the relay instead |
| SITL simulator | No | Desktop only |
| Log download from FC | No | Desktop only |
| File export (CSV/Parquet/JSON) | No | Browser security prevents direct file writes |

## Connecting to Your Flight Controller

Browsers cannot open direct TCP or serial connections to a flight controller. Instead, you run a small relay program on a computer that is on the same network as your drone. The relay bridges the gap between the browser and the flight controller.

```
  Browser (any device)          Your computer            Flight controller
  ┌──────────────────┐     ┌─────────────────────┐     ┌──────────────────┐
  │  app.heliosgcs.com│────>│   Helios Relay      │────>│  ArduPilot / PX4 │
  │  (WebSocket)      │<────│   (WebSocket ↔ TCP) │<────│  (TCP 5760)      │
  └──────────────────┘     └─────────────────────┘     └──────────────────┘
```

The relay is lightweight and runs entirely in user space -- no admin access required.

### Installing the Relay

**Option 1 -- Download the binary (recommended):**

```bash
curl -fsSL https://heliosgcs.com/relay/install.sh | sh
```

This downloads a pre-built binary for your platform and places it in your path.

**Option 2 -- Build from source (requires Dart SDK):**

```bash
git clone https://github.com/jamesagarside/helios.git
cd helios
dart compile exe scripts/helios_relay.dart -o helios-relay
./helios-relay
```

### Running the Relay

Start the relay and tell it where your flight controller is:

```bash
# Default: connects to SITL on localhost:5760
helios-relay

# Connect to a WiFi flight controller
helios-relay --fc-host 192.168.4.1

# Custom flight controller port
helios-relay --fc-host 10.0.0.5 --fc-port 5762

# Custom WebSocket port (default is 8765)
helios-relay --ws-port 9000
```

Once the relay is running, open [app.heliosgcs.com](https://app.heliosgcs.com), go to **Setup > Connection**, select **WebSocket**, and enter `ws://localhost:8765` (or the IP address of the machine running the relay if you are on a different device).

The relay also serves a status page at `http://localhost:8765` that you can check in a browser to confirm it is running.

## Installing as an App (PWA)

You can install Helios as a Progressive Web App for a native-like experience. Once installed, it appears in your app launcher and runs in its own window without browser toolbars.

### Chrome / Edge (desktop)

1. Open [app.heliosgcs.com](https://app.heliosgcs.com)
2. Click the install icon in the address bar (or open the browser menu and select **Install Helios GCS**)
3. Confirm the installation

### Chrome (Android)

1. Open [app.heliosgcs.com](https://app.heliosgcs.com)
2. Tap the three-dot menu
3. Select **Add to Home Screen**
4. Tap **Install**

### Safari (iOS / iPadOS)

1. Open [app.heliosgcs.com](https://app.heliosgcs.com) in Safari
2. Tap the Share button
3. Scroll down and tap **Add to Home Screen**
4. Tap **Add**

## Browser Compatibility

Helios works best in **Google Chrome** (version 100 or later). Other Chromium-based browsers (Edge, Brave, Opera) also work well.

| Browser | Supported | Notes |
|---|---|---|
| Chrome | Yes | Recommended. Best performance and PWA support |
| Edge | Yes | Chromium-based, fully compatible |
| Brave | Yes | Chromium-based, fully compatible |
| Firefox | Partial | WebSocket works, but PWA install is not supported |
| Safari | Partial | Works for viewing, but WebSocket reliability varies |

The web app requires **WebSocket** support for real-time connections. All modern browsers support this. If you are behind a corporate proxy or firewall, WebSocket connections may be blocked -- check with your network administrator.

## How Flight Data is Stored

On desktop, Helios records flights into DuckDB database files. In the browser, flight data is stored in your browser's IndexedDB using a lightweight SQL engine (sql.js). Your data stays in your browser and is not sent to any server.

If you clear your browser data, your recorded flights will be lost. For long-term storage, use the desktop app or export your flights before clearing.

## Troubleshooting

### The relay is running but Helios cannot connect

- Make sure the WebSocket address in Helios matches the relay's address and port (default: `ws://localhost:8765`)
- If the browser is on a different device than the relay, use the relay machine's IP address instead of `localhost`
- Check that no firewall is blocking port 8765
- Open `http://localhost:8765` in a browser to verify the relay is responding

### Telemetry is not updating

- Confirm your flight controller is powered on and connected to the relay machine (via USB or network)
- Check the relay terminal output for error messages
- Try restarting the relay with the correct `--fc-host` and `--fc-port` values

### The app feels slow or laggy

- Close other browser tabs to free up memory
- Chrome generally provides the best performance for WebGL and WebSocket workloads
- On low-powered devices, reduce the map zoom level and close chart panels you are not using

### PWA install option does not appear

- Make sure you are using Chrome or Edge -- Firefox and Safari do not support PWA installation on desktop
- The site must be loaded over HTTPS (app.heliosgcs.com uses HTTPS by default)
- Try refreshing the page or clearing the browser cache

### Cannot export flights to CSV or Parquet

File export is not available in the web app due to browser security restrictions. To export flight data, use the desktop version of Helios. You can record flights in the browser and later transfer them by re-flying the same data through the desktop app's analytics view.

## Next Steps

- [Connection Guide](docs.html?page=connection-guide) -- Full details on all connection methods
- [Fly View](docs.html?page=fly_view) -- Using the real-time flight display
- [Mission Planning](docs.html?page=mission_planning) -- Creating and uploading missions
- [Data and Analytics](docs.html?page=analyse-view) -- Querying and charting flight data
- [Web App (Developer Docs)](docs.html?page=webapp) -- Technical details on the web architecture and platform abstraction
