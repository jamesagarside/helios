# Connection Guide

Helios supports three transport methods for communicating with a flight controller: UDP, TCP, and Serial (USB or radio telemetry). This guide covers each method, protocol auto-detection, and the convenience features that simplify connecting to a vehicle.

## Connection Methods

### UDP

UDP is the default transport for connecting to a vehicle over a network. It is commonly used with telemetry radios that bridge serial to WiFi, or with companion computers running MAVProxy or similar forwarding software.

| Setting | Default | Description |
|---|---|---|
| Bind Address | `0.0.0.0` | Listen on all network interfaces |
| Port | `14550` | Standard MAVLink GCS port |

Helios binds a UDP socket to the specified address and port, then waits for incoming packets. The remote endpoint (the vehicle or relay) is discovered automatically from the first received packet. Once the remote is known, Helios sends GCS heartbeats and commands to that address.

No manual entry of the vehicle's IP address is required. Simply start the connection and ensure the vehicle or relay is configured to send MAVLink data to your machine on port 14550.

### TCP

TCP provides a reliable, ordered byte stream and is the standard method for connecting to ArduPilot SITL (Software In The Loop) simulators.

| Setting | Default | Description |
|---|---|---|
| Host | `127.0.0.1` | IP address or hostname of the flight controller or SITL instance |
| Port | `5760` | Standard SITL MAVLink port |

Helios initiates a TCP connection to the specified host and port. The connection remains open until explicitly disconnected or the remote side closes the socket.

**Typical SITL usage:**

1. Start SITL: `make sitl` (launches ArduPilot SITL in Docker).
2. In Setup > Connection, select TCP.
3. Set host to `127.0.0.1` and port to `5760`.
4. Press Connect.

### Serial

Serial connections are used for direct USB links to a flight controller (Pixhawk, Cube, etc.) and for SiK radio telemetry modules.

| Setting | Default | Description |
|---|---|---|
| Port | (auto-detected) | Serial port path, e.g. `/dev/tty.usbmodem01` |
| Baud Rate | 115200 | Data rate in bits per second |

Common baud rates:

| Device | Baud Rate |
|---|---|
| Pixhawk USB | 115200 |
| SiK Radio (default) | 57600 |
| SiK Radio (high bandwidth) | 115200 |
| Holybro Telemetry Radio | 57600 |

The serial port dropdown lists all currently available serial ports. On macOS, Pixhawk controllers typically appear as `/dev/tty.usbmodemXXXX`. On Linux, they appear as `/dev/ttyACM0` or `/dev/ttyUSB0`.

**Note:** Serial port access on macOS requires the app sandbox to be disabled, which is already configured in the Helios build settings.

## Protocol Auto-Detection

When connecting on any transport, Helios runs a 5-second protocol detection probe to determine whether the flight controller speaks MAVLink or MSP (Multiwii Serial Protocol, used by Betaflight and iNav).

The detection process:

1. Open the transport connection.
2. Listen for incoming data for up to 5 seconds.
3. Attempt to parse received bytes as MAVLink v2 frames.
4. If MAVLink parsing succeeds, proceed with the MAVLink service.
5. If MAVLink parsing fails, attempt MSP frame detection.
6. If MSP is detected, switch to the MSP service for telemetry polling.
7. If neither protocol is detected within 5 seconds, report a connection error.

The detected protocol is shown in the status bar after connection.

## Auto-Connect

The auto-connect feature monitors the system for newly attached serial ports and connects automatically when a recognized device appears. This is useful for USB flight controllers that are plugged in after Helios is already running.

To enable or disable auto-connect:

1. Open Setup > Connection.
2. Toggle the "Auto-connect" switch.

When enabled, Helios polls the serial port list every 2 seconds. If a new port appears that was not present at the last poll, it initiates a connection using the default baud rate (115200) and runs the protocol auto-detection probe.

Auto-connect does not apply to UDP or TCP connections.

## Quick Connection Bar

The Quick Connection Bar is displayed at the top of every view. It shows:

- **Current connection status** (disconnected, connecting, connected, error).
- **Transport type and address** (e.g. "TCP 127.0.0.1:5760" or "Serial /dev/tty.usbmodem01").
- **Reconnect button** to re-establish the last-used connection with one click.
- **Disconnect button** to close the active connection.

The reconnect button uses the most recently saved connection configuration, so you can disconnect and reconnect without navigating to the Setup tab.

## Connection Persistence

Helios saves the last-used connection configuration (transport type, address, port, baud rate) to local preferences. On the next launch, the saved configuration is pre-filled in the Setup > Connection panel and available via the Quick Connection Bar's reconnect button.

The saved settings include:

- Transport type (UDP, TCP, or Serial)
- Host address (TCP) or bind address (UDP)
- Port number
- Serial port path
- Baud rate
- Auto-connect enabled state

## Reconnect on Disconnect

If the connection is lost unexpectedly (cable unplugged, radio signal lost, SITL crash), Helios transitions to a disconnected state and resets the vehicle telemetry. The heartbeat watchdog detects connection loss when no heartbeat is received for 5 seconds.

The reconnect behavior depends on the transport:

| Transport | Reconnect Behavior |
|---|---|
| TCP | Manual reconnect via Quick Connection Bar or Setup |
| UDP | Automatic -- UDP is connectionless, so the socket remains open and will resume when packets arrive again |
| Serial | If auto-connect is enabled, reconnects when the serial port reappears (e.g. USB re-plugged) |

## Multi-Vehicle Support

Helios supports connecting to multiple vehicles simultaneously. Each vehicle is identified by its MAVLink system ID (1-255) from the HEARTBEAT message.

| Feature | Description |
|---|---|
| Vehicle Registry | Tracks all discovered system IDs with their vehicle type and last heartbeat time |
| Vehicle Selector Bar | Switch between active vehicles to view their individual telemetry |
| Per-Vehicle State | Each system ID has its own VehicleState with independent telemetry, position, and status |

When multiple heartbeats with different system IDs arrive on the same transport, Helios registers each as a separate vehicle. The Fly View, Plan View, and all telemetry displays reflect the currently selected vehicle.

## Troubleshooting

| Symptom | Likely Cause | Solution |
|---|---|---|
| No connection after pressing Connect (UDP) | Firewall blocking port 14550 | Allow incoming UDP on port 14550 |
| No connection after pressing Connect (TCP) | SITL not running or wrong port | Verify SITL is running; check host and port |
| Serial port not listed | Device not recognized by OS | Check USB cable; install driver if needed |
| "Protocol detection timeout" | FC not sending data, or wrong baud rate | Verify baud rate matches FC configuration |
| Frequent disconnects (Serial) | Loose USB connection or radio interference | Secure cable; check antenna placement |
| Telemetry but no commands accepted | GCS heartbeat not reaching FC | Check that the link is bidirectional |
