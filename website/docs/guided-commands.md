# Guided Commands

**Protocol**: MAVLink only
**Location**: Fly View > Guided Commands Panel (left side, context-sensitive)

The Guided Commands Panel provides in-flight control commands that supplement the main flight actions. It appears automatically when the vehicle is **connected, armed, and in GUIDED or AUTO mode**. The panel adapts its content based on the current flight mode.

## GUIDED Mode Commands

When the vehicle is in GUIDED mode, the panel shows orbit, altitude, and speed controls.

### Orbit

Fly a circular orbit around the vehicle's current position.

| Parameter | Range | Default | Description |
|-----------|-------|---------|-------------|
| Radius (R) | 10 -- 500 m | 50 m | Distance from the centre point |
| Velocity (V) | 1 -- 10 m/s | 3 m/s | Orbital speed |
| Direction | CW / CCW | CW | Clockwise or counter-clockwise |

Adjust the radius and velocity sliders, select the orbit direction, then tap **ORBIT** to begin. The vehicle will orbit around its current position at its current altitude. The yaw behaviour is set to point at the orbit centre.

| Property | Value |
|----------|-------|
| MAVLink command | `MAV_CMD_DO_ORBIT` (34) |
| param1 | Radius in metres (negative for CCW) |
| param2 | Velocity in m/s |
| param3 | 0 (yaw pointed at centre) |

### Change Altitude

Adjust the vehicle's target altitude while maintaining its current horizontal position.

Enter the desired altitude in metres AGL (above ground level) in the text field and tap **GO**. The vehicle will climb or descend to the target altitude at its configured vertical speed.

This works by sending a position target at the vehicle's current latitude and longitude with the new altitude value.

### Change Speed

Adjust the vehicle's ground speed.

Enter the desired speed in m/s and tap **APPLY**.

| Property | Value |
|----------|-------|
| MAVLink command | `MAV_CMD_DO_CHANGE_SPEED` (178) |
| param1 | 1 (ground speed) |
| param2 | Target speed in m/s |
| param3 | -1 (do not change throttle) |

## AUTO Mode Commands

When the vehicle is in AUTO mode (executing a mission), the panel shows mission control commands.

### Current Waypoint

The panel displays the current waypoint index for situational awareness.

### Pause / Resume

| Button | MAVLink command | param1 |
|--------|----------------|--------|
| PAUSE | `MAV_CMD_DO_PAUSE_CONTINUE` (193) | 0 (pause) |
| RESUME | `MAV_CMD_DO_PAUSE_CONTINUE` (193) | 1 (continue) |

Pause halts the vehicle at its current position in the mission. Resume continues from where it stopped.

### Skip Waypoint

Advances the mission to the next waypoint, skipping the current one.

| Property | Value |
|----------|-------|
| MAVLink command | `MAV_CMD_DO_SET_MISSION_CURRENT` (224) |
| param1 | Current waypoint index + 1 |

### Restart Mission

Resets the mission back to waypoint 0. The vehicle will begin the mission from the start.

| Property | Value |
|----------|-------|
| MAVLink command | `MAV_CMD_DO_SET_MISSION_CURRENT` (224) |
| param1 | 0 |

## Region of Interest (Both Modes)

Available in both GUIDED and AUTO modes, the ROI section allows you to set or clear a point that the vehicle (and gimbal, if equipped) will track.

### Set ROI Here

Sets a Region of Interest 100 metres ahead of the vehicle's current heading at the vehicle's current altitude.

| Property | Value |
|----------|-------|
| MAVLink command | `MAV_CMD_DO_SET_ROI_LOCATION` (195) |
| param5-7 | Computed lat/lon/alt |

### Clear ROI

Removes the active ROI so the vehicle returns to normal yaw behaviour.

| Property | Value |
|----------|-------|
| MAVLink command | `MAV_CMD_DO_SET_ROI_NONE` (197) |

## Use Cases

**Infrastructure inspection:** Enter GUIDED mode, fly to the structure, start an orbit at an appropriate radius, and set an ROI on the structure. The vehicle will circle while the camera (and gimbal) points at the subject.

**Surveillance / overwatch:** Use Change Altitude to reach a good vantage point, then orbit a location at a wide radius. Adjust speed for the desired coverage rate.

**Follow-me alternative:** For stationary subjects, set a small orbit radius (10-20 m) at low speed. Manually adjust the ROI as needed.

**Mission adjustment:** During AUTO missions, use Pause to hold position while you assess conditions, Skip Waypoint to bypass an unsafe or unnecessary waypoint, or Restart to re-fly the mission.

## Visibility Conditions

The Guided Commands Panel is hidden when any of these conditions are true:

- No active MAVLink connection
- Vehicle is not armed
- Vehicle is not in GUIDED or AUTO mode

Switch to GUIDED or AUTO mode to access these commands.
