# Joystick / Gamepad RC Control

**Protocol**: MAVLink only
**Platform**: macOS, Linux, Windows (desktop only -- not supported on iOS or Android)

Helios supports USB and Bluetooth gamepads as RC transmitter substitutes, sending `RC_CHANNELS_OVERRIDE` messages to the flight controller at 25 Hz. This allows you to fly the vehicle using a standard game controller when a traditional RC transmitter is not available.

## Channel Mapping (Mode 2)

Helios uses Mode 2 transmitter mapping, which is the most common layout worldwide:

| Stick | Axis | RC Channel | Function | Centre value |
|-------|------|------------|----------|-------------|
| Left stick X | Horizontal | CH4 | Yaw | 1500 us |
| Left stick Y | Vertical | CH3 | Throttle | 1000 us (bottom) |
| Right stick X | Horizontal | CH1 | Roll | 1500 us |
| Right stick Y | Vertical | CH2 | Pitch (inverted) | 1500 us |

Pitch is inverted so that pushing the right stick forward commands nose-down pitch, matching standard RC transmitter convention.

## PWM Output

All channel values are output in the standard RC PWM range:

| Parameter | Value |
|-----------|-------|
| Minimum | 1000 us |
| Centre | 1500 us |
| Maximum | 2000 us |
| Update rate | 25 Hz (40 ms interval) |

**Symmetric axes** (roll, pitch, yaw) map the gamepad range of -1.0 to +1.0 onto 1000 to 2000 us, with the centre position at 1500 us.

**Throttle axis** maps the gamepad range so that fully down (-1.0) produces 1000 us and fully up (+1.0) produces 2000 us. The throttle does not self-centre -- it stays at the last commanded position. On most gamepads, the left stick Y axis springs back to centre, which will command mid-throttle (1500 us). Be aware of this behaviour and adjust your technique accordingly.

## Enabling Joystick Control

1. Connect a USB or Bluetooth gamepad to your computer.
2. Toggle the joystick control in the Fly View.
3. The system begins sending `RC_CHANNELS_OVERRIDE` at 25 Hz immediately.

When disabled, the override messages stop and the flight controller reverts to its primary RC input source.

## Hardware Requirements

Any gamepad recognised by the operating system should work. Helios uses the `gamepads` package which reads normalised axis events from the system input layer.

**Tested controllers:**

- Xbox controllers (USB and Bluetooth)
- PlayStation DualShock / DualSense (USB and Bluetooth)
- Generic USB gamepads with dual analog sticks

The controller must have at least two analog sticks. D-pads and buttons are not mapped to RC channels.

## Platform Support

| Platform | Supported | Notes |
|----------|-----------|-------|
| macOS | Yes | USB and Bluetooth gamepads |
| Linux | Yes | USB and Bluetooth gamepads |
| Windows | Yes | USB and Bluetooth gamepads |
| iOS | No | Gamepad input not available |
| Android | No | Gamepad input not available |

## Flight Controller Configuration

For `RC_CHANNELS_OVERRIDE` to work, the flight controller must be configured to accept it:

- **ArduPilot:** Ensure `SYSID_MYGCS` matches the GCS system ID that Helios uses (default 255). No additional configuration is typically needed.
- **PX4:** Joystick input via MAVLink is supported natively when connected to a GCS.

The flight controller should have appropriate failsafe behaviour configured for when the override messages stop (e.g., if Helios disconnects or the gamepad is removed).

## Safety Considerations

**Latency:** Gamepad-over-GCS control adds latency compared to a direct RC link. The signal path is: gamepad -> USB/BT -> computer -> Helios -> MAVLink transport -> flight controller. Expect 50-150 ms of total latency depending on your connection type. This is acceptable for slow manoeuvres but not suitable for aggressive or precision flying.

**No hardware failsafe:** Unlike a dedicated RC transmitter, a gamepad connected through Helios does not have an independent failsafe link. If Helios crashes, the computer freezes, or the MAVLink connection drops, the override messages stop. Ensure your flight controller failsafe is configured to handle this (e.g., RTL or LAND on GCS failsafe).

**Throttle behaviour:** Most gamepads have spring-centred sticks. When you release the left stick, it returns to centre, which maps to approximately 1500 us (mid-throttle). This is different from a real RC transmitter where the throttle stick stays in position. Plan accordingly and be ready to manage throttle actively.

**Always have a backup:** When flying with gamepad control, it is strongly recommended to have a traditional RC transmitter bound and ready as a backup. The RC transmitter takes priority over `RC_CHANNELS_OVERRIDE` messages on most flight controllers.

**Do not use for first flights or tuning.** The added latency and lack of a direct failsafe link make gamepad control inappropriate for initial setup flights or PID tuning. Use a proper RC transmitter for those tasks.
