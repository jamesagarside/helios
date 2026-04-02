# Diagnostic Panels — Servo Output & RC Input

Two floating overlay panels in the Fly View provide real-time diagnostic data for pre-flight checks, calibration verification, and in-flight monitoring.

**Protocol**: MAVLink only (SERVO_OUTPUT_RAW and RC_CHANNELS messages)
**Platform**: All

---

## Servo Output Panel

Shows live PWM output values for all 16 servo/motor channels from the flight controller (`SERVO_OUTPUT_RAW` MAVLink message).

### Opening

Tap the **SRV** button in the Fly View toolbar. The panel appears at the top-left of the map. Visibility is persisted per layout profile.

### Reading the panel

Each of the 16 channels (CH1–CH16) is shown as a horizontal bar graph:

| Colour | PWM range | Meaning |
|---|---|---|
| Green | 1100–1900 µs | Normal operating range |
| Amber | 1050–1099 or 1901–1950 µs | Near limit — check travel |
| Red | < 1050 or > 1950 µs | At/beyond limit |

A vertical marker at the **1500 µs** position indicates neutral/centre.

Channels with a value of **0** (not assigned or not used) are shown as greyed dashed rows.

### Use cases

- **Pre-flight**: Verify all control surfaces move in the correct direction and with correct travel
- **Calibration**: Confirm trim and endpoint settings
- **Motor check**: Verify ESC outputs during spin-up (with propellers removed)
- **Gimbal**: Monitor camera mount servo positions

---

## RC Input Panel

Shows live PWM values for all RC receiver channels (RC_CHANNELS MAVLink message) and link quality indicators.

### Opening

Tap the **RC** button in the Fly View toolbar. The panel appears to the right of the Servo panel (or at the top-left if the Servo panel is hidden). Visibility is persisted per layout profile.

### Header indicators

| Indicator | Meaning |
|---|---|
| **RSSI: NNN** (green ≥ 150) | Strong RC link |
| **RSSI: NNN** (amber ≥ 80) | Moderate RC link — monitor |
| **RSSI: NNN** (red < 80) | Weak RC link |
| **RSSI: ---** (grey) | RSSI not reported by receiver |
| **FAILSAFE** badge (red) | RC failsafe is active |

### Channel labels

| Channel | Label | Standard ArduPilot mapping |
|---|---|---|
| CH1 | AIL | Aileron / Roll |
| CH2 | ELE | Elevator / Pitch |
| CH3 | THR | Throttle |
| CH4 | RUD | Rudder / Yaw |
| CH5–CH18 | CH5–CH18 | Flight mode, aux switches, etc. |

Bar graph colours follow the same traffic-light scheme as the servo panel.

### Use cases

- **RC range check**: Walk away from vehicle and watch signal degrade
- **Channel mapping**: Verify stick inputs reach the correct channels
- **Failsafe verification**: Confirm channels move to expected values on signal loss
- **Auxiliary channels**: Verify switch positions for flight mode, RTL, etc.

---

## Platform Notes

| Feature | macOS | Linux | Windows | iOS | Android |
|---|:---:|:---:|:---:|:---:|:---:|
| Servo Output Panel | ✅ | ✅ | ✅ | ✅ | ✅ |
| RC Input Panel | ✅ | ✅ | ✅ | ✅ | ✅ |

Both panels require a MAVLink connection that streams `SERVO_OUTPUT_RAW` and `RC_CHANNELS`. These messages are requested via the stream rate control system on connect. MSP protocol does not provide equivalent data.
