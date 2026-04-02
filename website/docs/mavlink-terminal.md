# MAVLink Terminal

**Protocol**: MAVLink only
**Location**: Inspect tab > Terminal sub-tab

The MAVLink Terminal is an interactive command console for sending MAVLink commands directly to the flight controller. It is designed for debugging, testing, and advanced operations that are not covered by the graphical interface.

## Getting Started

1. Navigate to the **Inspect** tab.
2. Select the **Terminal** sub-tab (next to Inspector).
3. Type a command in the input field at the bottom and press Enter.

The terminal requires an active MAVLink connection. If no vehicle is connected, all commands will return an error.

## Available Commands

| Command | Syntax | Description |
|---------|--------|-------------|
| `arm` | `arm` | Arm the vehicle |
| `disarm` | `disarm` | Disarm the vehicle |
| `mode` | `mode <number>` | Set flight mode by mode number |
| `reboot` | `reboot` | Reboot the flight controller |
| `preflight` | `preflight` | Send preflight calibration command |
| `cmd` | `cmd <id> [p1] [p2] ... [p7]` | Send a generic COMMAND_LONG |
| `request` | `request <msg_id> [interval_us]` | Request a message at an interval |
| `status` | `status` | Display current vehicle state |
| `clear` | `clear` | Clear terminal output |
| `help` | `help` | Show command reference |

## Command Details

### arm / disarm

Send arm or disarm commands to the vehicle.

```
> arm
Sent ARM command
  ACK: cmd 400 -> ACCEPTED

> disarm
Sent DISARM command
  ACK: cmd 400 -> ACCEPTED
```

Both use `MAV_CMD_COMPONENT_ARM_DISARM` (400). Arming may fail if pre-arm checks are not satisfied -- check the ACK response.

### mode

Set the flight mode by its numeric identifier. Mode numbers are autopilot-specific.

```
> mode 4
Sent SET_MODE 4
  ACK: cmd 176 -> ACCEPTED
```

Common ArduCopter mode numbers:

| Number | Mode |
|--------|------|
| 0 | STABILIZE |
| 2 | ALT_HOLD |
| 3 | AUTO |
| 4 | GUIDED |
| 5 | LOITER |
| 6 | RTL |
| 9 | LAND |

### reboot

Reboot the flight controller. Only use when the vehicle is disarmed.

```
> reboot
Sent REBOOT command
  ACK: cmd 246 -> ACCEPTED
```

Uses `MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN` (246) with param1=1.

### preflight

Send a preflight calibration command. This is a general-purpose calibration trigger; the specific calibration performed depends on the parameters. The terminal sends all parameters as zero, which can be used to reset calibration state.

```
> preflight
Sent PREFLIGHT_CALIBRATION command
```

Uses `MAV_CMD_PREFLIGHT_CALIBRATION` (241).

### cmd (Generic Command)

Send any `COMMAND_LONG` message by specifying the command ID and up to seven parameters. Parameters that are not provided default to 0.

**Syntax:** `cmd <command_id> [p1] [p2] [p3] [p4] [p5] [p6] [p7]`

```
> cmd 400 1 0 0 0 0 0 0
Sent COMMAND_LONG #400
  ACK: cmd 400 -> ACCEPTED

> cmd 511 33 1000000
Sent COMMAND_LONG #511
  ACK: cmd 511 -> ACCEPTED
```

The first example arms the vehicle (command 400, param1=1). The second requests GLOBAL_POSITION_INT (msg 33) at 1 Hz (1000000 microseconds).

This is the most flexible command in the terminal and can send any MAVLink COMMAND_LONG.

### request (Message Request)

Request the flight controller to send a specific message at a given interval.

**Syntax:** `request <msg_id> [interval_us]`

The interval is in microseconds. If omitted, it defaults to 1000000 (1 Hz).

```
> request 33 500000
Requested msg 33 at 2.0 Hz

> request 24
Requested msg 24 at 1.0 Hz
```

Uses `MAV_CMD_SET_MESSAGE_INTERVAL` (511). This is useful for enabling messages that are not sent by default, or adjusting the rate of specific messages for debugging.

### status

Display a snapshot of the current vehicle state, including system IDs, vehicle type, autopilot type, flight mode, arm state, GPS, battery, and firmware version.

```
> status
  System ID:    1
  Component ID: 1
  Vehicle Type: quadrotor
  Autopilot:    ardupilotmega
  Flight Mode:  GUIDED
  Armed:        true
  GPS Fix:      fix3d
  Satellites:   12
  HDOP:         1.20
  Battery:      12.4V  78%
  Firmware:     4.5.7
```

### clear

Clears all terminal output. Does not affect the vehicle or connection state.

### help

Displays the built-in command reference.

## Command History

Use the **Up** and **Down** arrow keys to navigate through previously entered commands. This works the same way as a standard terminal:

- **Up arrow** -- Recall the previous command in history.
- **Down arrow** -- Move forward through history. When you reach the end, the input clears.

The history is maintained for the duration of the current session. It resets when you navigate away from the Inspect tab.

## ACK Responses

After sending a command (except `help`, `clear`, and `status`), the terminal listens for a `COMMAND_ACK` response from the flight controller for up to 3 seconds.

| ACK result | Meaning |
|------------|---------|
| ACCEPTED | Command was received and will be executed |
| REJECTED (result) | Command was refused; the result code indicates why |
| No ACK within 3 seconds | The flight controller did not respond; the command may not have been received |

## Use Cases

**Debugging stream rates:** Use `request` to enable or adjust the rate of specific messages, then switch to the Inspector sub-tab to verify they are arriving.

**Testing commands before adding UI:** Use `cmd` to prototype new MAVLink interactions before building a graphical control for them.

**Advanced parameter operations:** Combine with the Parameter Editor for operations like changing a parameter and then sending a reboot to apply it.

**Vehicle diagnostics:** Use `status` to quickly check the vehicle state without switching views, and `cmd` to query specific subsystems.
