# Gimbal Control

**Protocol**: MAVLink only
**Location**: Fly View > Gimbal panel (visible when gimbal is detected)

The Gimbal Control Panel provides manual gimbal pointing, camera capture, and preset angle commands. It appears automatically in the Fly View when the connected vehicle reports gimbal hardware (`hasGimbal=true` in the vehicle state).

## Panel Overview

When collapsed, the gimbal panel shows a compact button displaying the current pitch angle (e.g., `P:-45`). Tap it to expand the full control panel.

The expanded panel contains:

- **Angle readout** -- Real-time pitch (P), yaw (Y), and roll (R) values in degrees, updated from MAVLink gimbal attitude messages.
- **Virtual joystick** -- A drag-to-control area for manual pitch and yaw adjustment.
- **Action buttons** -- Centre, Capture, and Nadir presets.

## Virtual Joystick

The joystick area occupies the centre of the panel. Drag within it to command gimbal movement:

| Drag direction | Effect | Range |
|----------------|--------|-------|
| Up | Pitch up (tilt up) | -90 to +30 degrees |
| Down | Pitch down (tilt down) | -90 to +30 degrees |
| Left | Yaw left | -180 to +180 degrees |
| Right | Yaw right | -180 to +180 degrees |

A blue indicator dot shows the current commanded position relative to the crosshair centre. The crosshair represents the neutral (forward-facing) position.

Gimbal commands are sent to the flight controller as the drag gesture updates, providing near-real-time control.

## Action Buttons

### Centre

Resets the gimbal to its home position: pitch 0 degrees (level with the horizon) and yaw 0 degrees (forward-facing). Use this to quickly return to a neutral view after manual adjustment.

### Capture

Triggers the camera shutter. Sends a camera trigger command to the flight controller, which activates the connected camera via the configured camera interface (servo, relay, or MAVLink camera protocol).

### Nadir

Points the gimbal straight down: pitch -90 degrees, yaw 0 degrees. This is the standard orientation for mapping and survey operations where the camera needs to face directly at the ground.

## Supported Protocol

Gimbal control uses MAVLink gimbal commands sent through the flight controller:

| Function | Protocol |
|----------|----------|
| Pitch/Yaw control | `DO_MOUNT_CONTROL` or `GIMBAL_MANAGER_SET_ATTITUDE` |
| Camera trigger | `MAV_CMD_DO_DIGICAM_CONTROL` or `MAV_CMD_IMAGE_START_CAPTURE` |
| Angle feedback | `MOUNT_STATUS` or `GIMBAL_DEVICE_ATTITUDE_STATUS` |

The specific messages used depend on the flight controller firmware and gimbal protocol version. ArduPilot supports both the legacy MOUNT protocol and the newer Gimbal Manager/Device protocol.

## Integration with Orbit Missions

When flying an orbit command from the Guided Commands Panel, you can combine gimbal control with the orbit to achieve inspection or surveillance patterns:

1. Enter GUIDED mode and start an orbit around a point of interest.
2. Use the gimbal joystick to point the camera at the subject.
3. Alternatively, set a Region of Interest (ROI) from the Guided Commands Panel -- the gimbal will automatically track the ROI location if the autopilot supports it.

The ROI approach is generally preferred for hands-free tracking during orbits, while the manual joystick is better for dynamic inspection where you need to adjust the view in real time.

## Requirements

- The flight controller must report gimbal presence via MAVLink heartbeat or capability flags.
- The gimbal must be configured in the flight controller's mount parameters (e.g., `MNT1_TYPE` in ArduPilot).
- Camera capture requires a camera connected to the flight controller's camera interface.
