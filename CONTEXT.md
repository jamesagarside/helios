# Helios

Open-source ground control station for MAVLink/MSP UAVs. This glossary names the concepts that recur across the codebase. It is a glossary, not a spec — no implementation details.

## Language

### Airframe & orientation

**Airframe Model**:
The procedurally-built, frame-aware 3D representation of the connected vehicle, rendered in real time from live attitude so the pilot can debug flight-controller mounting and orientation. Its shape is generated from the configured airframe (e.g. a quad vs a tricopter vs a fixed-wing/VTOL), not loaded from a static asset. It is a reusable component embedded wherever orientation matters (orientation/mounting check, sensor calibration), and can be given a target orientation so it signals (turns green) when the vehicle matches the requested pose.
_Avoid_: 3D model (too generic), mesh, avatar.

**Orientation match**:
The state in which the Airframe Model's live attitude is within tolerance of a requested target pose. Used to validate hands-on calibration steps (e.g. confirming the vehicle is correctly nose-down during 6-point accelerometer calibration).
_Avoid_: alignment, lock.

**Body frame**:
The vehicle's own coordinate frame as MAVLink reports it: X-forward, Y-right, Z-down. Attitude telemetry is expressed in this frame.
_Avoid_: vehicle frame, NED-body (NED is the world frame, not this).

**Render frame**:
The coordinate frame the Airframe Model is drawn in. Distinct from the Body frame; live attitude must be converted from Body frame to Render frame or the model appears inverted/mirrored.
_Avoid_: screen frame, camera frame.

### Connectivity

**Link**:
A live connection to a single vehicle — a transport carrying a protocol, together with its health. The unit that is connected, degraded, lost, or disconnected.
_Avoid_: connection (too generic), session, channel.

**Protocol adapter**:
The per-protocol component (MAVLink or MSP) that turns a Link's wire bytes into Protocol messages and presents them through one shared seam. Behind the seam there is exactly one adapter per protocol.
_Avoid_: driver, handler, codec.

**Protocol message**:
A single typed fact decoded off the wire (e.g. one attitude reading or one GPS reading), before it is folded into vehicle state. The unit that flows through the shared seam.
_Avoid_: packet, event. (A _frame_ is the raw on-wire envelope, not yet a typed fact.)

**Link health**:
The connected / degraded / lost status of a Link, derived from message activity and computed the same way for every protocol. Distinct from the transport's lower-level connected/error state.
_Avoid_: signal, connection state.

**State convergence**:
The protocol-specific step that folds Protocol messages into the single unified vehicle state. The one place protocol _and_ firmware knowledge legitimately remains after the seam (e.g. interpreting Betaflight vs iNav mode bits).
_Avoid_: merge, sync.

**Protocol** vs **Autopilot firmware**:
Two distinct axes. The _Protocol_ is the wire language a Link speaks — MAVLink or MSP. The _Autopilot firmware_ is who is speaking it — ArduPilot, PX4, Betaflight, or iNav (`AutopilotType`). ArduPilot/PX4 ride MAVLink; Betaflight/iNav ride MSP. The seam unifies Protocols; firmware differences live above it, in State convergence and in feature panels.
_Avoid_: conflating "protocol" with "firmware"; "flight stack" (ambiguous between the two).

### Airframes

**Quadplane**:
An ArduPilot fixed-wing airframe with added VTOL lift motors. Identified by the `Q_ENABLE` parameter being 1 — _not_ by MAV_TYPE, which a quadplane commonly reports as plain fixed-wing. Its VTOL behaviour and tuning live under the `Q_*` parameters and are configured through the VTOL panel.
_Avoid_: VTOL plane, hybrid (both ambiguous); using `VehicleType.vtol` as the test for "is a quadplane".
