# Emergency Procedures

**Protocol**: MAVLink only
**Location**: Fly View > SOS button (top-right overlay)

The Emergency Actions Panel provides immediate access to critical safety commands during flight. It is designed for situations where you need to override normal flight behaviour to prevent damage, injury, or loss of the vehicle.

## Accessing the Emergency Panel

The panel appears as a compact **SOS** button in the Fly View overlay. Tap it to expand the full set of emergency actions. The button glows red when expanded to indicate the panel is active.

All emergency actions require an active MAVLink connection. The Kill Switch, Emergency Land, and Emergency RTL buttons are only enabled when the vehicle is **connected and armed**. Reboot Autopilot is only available when the vehicle is **connected and disarmed**.

## Emergency Actions

### Kill Switch (Force Disarm)

| Property | Value |
|----------|-------|
| MAVLink command | `MAV_CMD_COMPONENT_ARM_DISARM` (400) |
| Parameters | param1=0 (disarm), param2=21196 (force flag) |
| Confirmation | Double-tap, then dialog confirmation |
| Requires | Connected + Armed |

The Kill Switch immediately stops all motors by sending a force-disarm command. This bypasses all normal disarm safety checks on the flight controller.

**Activation sequence:**

1. Tap the KILL SWITCH button once. The button changes to **TAP AGAIN TO KILL** with a highlighted border.
2. Tap again within 3 seconds. A confirmation dialog appears.
3. Read the warning, then tap **KILL MOTORS** to confirm.

If you do not complete the second tap within 3 seconds, the button resets to its default state.

**When to use:** The vehicle is in an uncontrollable state, is about to collide with people or property, or all other recovery options have failed. This is the last resort.

**Warning:** The vehicle will fall from the sky immediately. There is no controlled descent. Only use this when an uncontrolled crash is preferable to the alternative.

### Emergency Land

| Property | Value |
|----------|-------|
| Flight mode | LAND |
| Confirmation | Single tap (no dialog) |
| Requires | Connected + Armed |

Commands the vehicle to land at its current position. The autopilot handles descent rate and touchdown detection. The vehicle will attempt a controlled vertical descent directly below its current location.

**When to use:** You need the vehicle on the ground quickly but a controlled descent is acceptable. Examples include unexpected weather, low battery that has not triggered automatic failsafe, or loss of confidence in the flight plan.

### Emergency RTL (Return to Launch)

| Property | Value |
|----------|-------|
| Flight mode | RTL |
| Confirmation | Single tap (no dialog) |
| Requires | Connected + Armed |

Commands the vehicle to return to its launch point using the autopilot's RTL behaviour. The vehicle will climb to the configured RTL altitude (if below it), fly back to the launch point, then land.

**When to use:** You want the vehicle to come home but it is too far away or conditions make manual control difficult. The vehicle still has GPS lock and enough battery to complete the return journey.

### Reboot Autopilot

| Property | Value |
|----------|-------|
| MAVLink command | `MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN` (246) |
| Parameters | param1=1 (reboot autopilot) |
| Confirmation | Dialog confirmation |
| Requires | Connected + Disarmed |

Reboots the flight controller. This is only available when the vehicle is disarmed as a safety measure.

**When to use:** The flight controller is in a bad state after a failed calibration, parameter change, or firmware issue. You need a clean restart without physically power-cycling the vehicle.

## Decision Guide

Use this table to select the appropriate action based on the situation:

| Situation | Recommended Action |
|-----------|-------------------|
| Vehicle flying normally, want it home | Emergency RTL |
| Vehicle flying normally, want it down now | Emergency Land |
| Vehicle spinning, flipping, or uncontrollable | Kill Switch |
| Vehicle heading toward people | Kill Switch |
| Low battery, vehicle nearby | Emergency Land |
| Low battery, vehicle far away | Emergency RTL |
| Lost orientation but vehicle is stable | Emergency RTL |
| Flight controller unresponsive to mode changes | Kill Switch |
| Post-flight, controller needs restart | Reboot Autopilot |

## Safety Notes

- **Maintain visual line of sight (VLOS)** at all times during flight. Emergency actions are most effective when you can see the vehicle and assess its state.
- **Know your failsafe settings** before every flight. The flight controller has its own battery, GPS, and RC failsafe actions that may trigger independently of Helios. Check these in the Setup tab under Failsafe.
- **Emergency Land and RTL depend on GPS.** If the vehicle has lost GPS lock, these modes may not work as expected. In a no-GPS situation, the Kill Switch may be the only reliable option.
- **RTL altitude matters.** If the RTL altitude is set very high, the vehicle will climb before returning. Verify this value before flight if you anticipate needing emergency RTL.
- **The Kill Switch is irreversible once confirmed.** There is no way to undo it mid-fall. Use it only as a genuine last resort.
- **All emergency actions are logged** to the alert history with timestamps for post-flight review.
