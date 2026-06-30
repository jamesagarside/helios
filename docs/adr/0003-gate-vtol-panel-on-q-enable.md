# Gate the VTOL / quadplane panel on `Q_ENABLE`, not MAV_TYPE / vehicle type

**Status:** accepted

ArduPilot quadplanes commonly advertise `MAV_TYPE_FIXED_WING` in their heartbeat — the airframe is a plane with added lift motors — so `VehicleState.vehicleType` is an unreliable signal for "this is a quadplane." Gating the VTOL setup panel on `VehicleType.vtol` would hide it on the very vehicles it exists for. We gate on the **`Q_ENABLE` parameter** instead: absent → not a quadplane-capable firmware, hide the tab; `== 0` → ArduPilot Plane with quadplane disabled, show an enable-prompt (so a fresh build is discoverable); `== 1` → show the full panel.

## Consequences

- A future contributor may be tempted to "simplify" the gate to `VehicleType.vtol`; that reintroduces the bug. This ADR exists to stop that.
- The panel is inherently **ArduPilot-Plane-only**: `Q_*` parameters do not exist on Copter/Rover or on the MSP firmwares (Betaflight/iNav), so those vehicles never see the tab. This is consistent with the Protocol-vs-firmware split in `CONTEXT.md` — firmware-specific surfaces live above the protocol seam.
- Dangerous actions in the panel (QAUTOTUNE engagement) follow a **pragmatic-override** pattern: a sensible default guard that explains itself via a modal and offers an escape hatch, rather than a hard lockout — protect the novice without blocking the expert.
