# Helios

Open-source ground control station for MAVLink/MSP UAVs. This glossary names the concepts that recur across the codebase. It is a glossary, not a spec — no implementation details.

## Language

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
