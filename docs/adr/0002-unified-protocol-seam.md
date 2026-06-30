# Unified protocol seam: sealed `ProtocolMessage` with per-protocol convergence

**Status:** accepted

MAVLink and MSP were two parallel stacks: `MavlinkService` emitted typed `Stream<MavlinkMessage>` while `MspService` decoded frames inline into whole `Stream<VehicleState>` snapshots, the connection layer branched into separate `_connectMavlink`/`_connectMsp` lifecycles (~323 lines of duplicated wiring), and the heartbeat/link watchdog existed twice. We unify them behind one **ProtocolService** seam: each protocol becomes a **Protocol adapter** that owns its transport, parser, and decoder and emits **Protocol messages** (typed facts) through a single inbound stream, plus one shared **Link health** stream. The connection layer holds one adapter and dispatches messages with a single exhaustive `switch` over a sealed `ProtocolMessage` (`MavlinkMsg` | `MspMsg`).

## Considered options

- **Converge to `VehicleState` at the seam** (adapters emit `Stream<VehicleState>`) — rejected: it discards the message-level detail the MAVLink inspector and the DuckDB flight recorder consume, and forces MAVLink down MSP's lossy whole-state-snapshot path.
- **A shared marker interface on `MavlinkMessage`** — rejected: `MavlinkMessage` is generated/vendored in `packages/dart_mavlink`; tagging it means editing generated code. A sealed wrapper leaves the vendored package untouched and yields an exhaustive switch.
- **Total protocol-agnosticism (zero branching anywhere)** — rejected as a mirage: MAVLink carries far richer semantics (multi-vehicle, ADS-B, mission/param sub-protocols) than MSP. We accept one honest, exhaustive dispatch switch instead.

## Consequences

- **State convergence** stays per-protocol and is the one place protocol _and_ firmware knowledge legitimately remains. Betaflight-vs-iNav interpretation moves out of the MSP decoder (which becomes firmware-agnostic, bytes → raw typed fields) and into MSP convergence; `MSP_FC_VARIANT` detection is preserved so convergence always knows the firmware. This is the protocol/firmware distinction recorded in `CONTEXT.md`.
- The seam guarantees **inbound + lifecycle + link health + stats** only. **Outbound stays protocol-specific** on the concrete adapter (MAVLink command/mission/param/calibration vs MSP polling); it is deliberately not unified (YAGNI — the shapes are genuinely different).
- `MavlinkMessageRouter` behaviour and `VehicleState`'s shape are unchanged; the MSP path gains a sibling pure `MspMessageRouter`. The duplicated watchdog collapses into one `LinkHealthMonitor` fed by `recordActivity()`.
