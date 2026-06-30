# Vehicle Configuration (FC Config)

The FC Config view groups vehicle setup and calibration into a single tabbed
screen. On desktop it uses a vertical tab list down the left; on narrower
screens it switches to a horizontal tab bar.

**Protocol**: MAVLink only (ArduPilot / PX4). The configuration parameters and
calibration commands described here are not part of the MSP protocol.

The tabs appear in this order:

| Tab | Purpose |
|---|---|
| Firmware | Autopilot, firmware version, board, and link status |
| Orientation | Board orientation editor beside a live 3D Airframe Model |
| Calibration | Sensor calibration, including the 6-point accelerometer wizard |
| Airspeed | Airspeed sensor zero-offset calibration and configuration |
| Safety | Failsafe action configuration |
| Frame | Frame class and type selection |
| VTOL | Quadplane setup — shown only when `Q_ENABLE` = 1 |
| Motors | Per-motor test spin |
| ESC | ESC calibration and output endpoints |
| RC | Radio / RC channel calibration |
| Flight Modes | Map flight modes to RC PWM bands |
| Pre-Arm | Arming-check editor and live pre-arm health |
| Battery | Power-monitor setup and calibration |
| Parameters | Full parameter editor |

The VTOL tab is conditional; the remaining tabs are always present.

---

## Airframe Model

The Airframe Model is a real-time 3D representation of the connected vehicle. It
is rendered procedurally from the vehicle's frame parameters (`FRAME_CLASS` /
`FRAME_TYPE`) and rotates to follow live attitude, so moving the airframe moves
the on-screen model.

| Behaviour | Detail |
|---|---|
| Source | Live attitude from `ATTITUDE_QUATERNION` telemetry |
| Frame-aware geometry | Mesh is built at runtime from the vehicle's frame class and type |
| Target-pose match | When a target pose is requested, the model turns green once the vehicle is held within about 5° of it |
| Reuse | The same widget drives the Orientation tab and the 6-point accelerometer wizard |

The renderer is a custom `Canvas.drawVertices` implementation rather than a 3D
engine, which keeps it running on every supported platform including the web
build. The rationale is recorded in
[ADR 0001](https://github.com/jamesagarside/helios/blob/main/docs/adr/0001-custom-airframe-model-renderer.md).

---

## Orientation

The Orientation tab places the board-orientation editor next to the Airframe
Model. Moving the vehicle and watching the model follow confirms that the
flight controller's mounting orientation is set correctly.

| Control | Parameter | Notes |
|---|---|---|
| Board orientation | `AHRS_ORIENTATION` | Written on modern firmware |
| Compass orientation | `COMPASS_ORIENT` | Kept aligned when present (legacy) |

When the vehicle exposes neither parameter, the panel reports that orientation
cannot be set on this firmware.

---

## Calibration (6-point accelerometer)

The Calibration tab includes a 6-point accelerometer calibration wizard. It
drives `MAV_CMD_PREFLIGHT_CALIBRATION` through six orientations and parses the
autopilot's `STATUSTEXT` position prompts to advance.

The wizard embeds the Airframe Model as a live target-pose validator: for each
step the model is given that step's target pose and turns green only when the
vehicle is actually held in it, giving hands-on confirmation before the step is
confirmed.

---

## Airspeed

For airspeed-equipped vehicles, the Airspeed tab provides:

| Flow | Detail |
|---|---|
| Zero-offset calibration | Cover the pitot, command the preflight zero (`MAV_CMD_PREFLIGHT_CALIBRATION`), and watch live airspeed settle as `ARSPD_OFFSET` is captured |
| Sensor configuration | Edit `ARSPD_TYPE`, `ARSPD_BUS`, `ARSPD_PIN`, the in-flight `ARSPD_RATIO`, and the `ARSPD_AUTOCAL` toggle |

A live airspeed readout confirms the captured offset is effective.

---

## RC / Radio Calibration

The RC tab calibrates the transmitter and stick endpoints.

| Feature | Detail |
|---|---|
| Live channel bars | Per-channel bars driven by `RC_CHANNELS` telemetry |
| Endpoint capture | Captures per-channel min / max / trim as you sweep every stick and switch |
| Reversal | Per-channel reversal |
| Channel mapping | `RCMAP_*` function-to-channel assignments |

Results are written as `RCx_MIN`, `RCx_MAX`, `RCx_TRIM`, `RCx_REVERSED`, and
`RCx_DZ`, plus the `RCMAP_*` assignments.

---

## Flight Modes

The Flight Modes tab assigns up to six flight modes to the PWM bands of the
mode-selector channel.

| Item | Parameter |
|---|---|
| Mode-selector channel | `FLTMODE_CH` |
| Mode slots | `FLTMODE1` .. `FLTMODE6` |

The slot the live mode channel currently selects is highlighted as you flip
switches, using the same `RC_CHANNELS` telemetry as RC calibration. Available
mode choices adapt to the connected vehicle type.

---

## ESC Calibration

The ESC tab detects the output protocol (`MOT_PWM_TYPE`) and adapts:

| Output type | Behaviour |
|---|---|
| Analog PWM | Guided semi-automatic calibration plus direct editing of manual endpoint parameters (`MOT_PWM_*`, `MOT_SPIN_*`) |
| Digital (DShot) / brushed | No calibration needed; the panel detects this and explains why instead of offering a no-op flow |

Throttle is only commanded after a mandatory props-off confirmation, and the
semi-automatic flow refuses to run while the vehicle is armed.

---

## Pre-Arm (Arming Checks)

The Pre-Arm tab is a bitmask editor for the `ARMING_CHECK` parameter. Individual
pre-arm check categories (plus an "All" option) can be toggled and written back
to the flight controller. Live pre-arm health from `SYS_STATUS` is surfaced as a
status pill, so the editor reflects whether checks are currently passing.

---

## Battery / Power Monitor

The Battery tab configures and calibrates the power monitor:

| Item | Parameter |
|---|---|
| Monitor type | `BATT_MONITOR` |
| Voltage / current sensing | Sense pins and multipliers |
| Calibration | Calibrate the voltage and current multipliers against a trusted measurement |
| Capacity | Pack capacity |

A live readout from `SYS_STATUS` voltage and current telemetry verifies the
result.

---

## VTOL / Quadplane

The VTOL tab appears only when `Q_ENABLE` = 1. It is gated on the parameter, not
on the reported vehicle type, because ArduPilot quadplanes commonly advertise as
fixed-wing. When `Q_ENABLE` = 0 the tab shows an enable prompt; when the
parameter is absent the tab is hidden. The gating rationale is recorded in
[ADR 0003](https://github.com/jamesagarside/helios/blob/main/docs/adr/0003-gate-vtol-panel-on-q-enable.md).

The panel uses progressive disclosure:

| Section | Contents |
|---|---|
| Setup | Frame class and type, transition and assist settings |
| Tilt | Conditional tilt-rotor settings, shown automatically when `Q_TILT_MASK` is non-zero (with a manual override) |
| Options | `Q_OPTIONS` behaviour bitmask editor |
| Advanced tuning | VTOL PID parameters in a collapsed expander |
| QAUTOTUNE | Entry to autotune, behind a guarded modal that explains the action and offers an escape hatch rather than a hard lockout |

---

## Parameters

The Parameters tab is the full parameter editor. See
[Setup & Config](docs.html?page=setup-guide) for the parameter editor in detail,
including the Modified-only view and board-exact defaults fetched over MAVLink
FTP.
