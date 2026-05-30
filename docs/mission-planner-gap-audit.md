# Helios vs Mission Planner — Feature Gap Audit & Closure Plan

> Status: Draft for review · Date: 2026-05-30 · Scope: Helios `v0.5.2-alpha`
>
> Purpose: A full, file-referenced audit of where Helios stands against
> **Mission Planner** (the de-facto ArduPilot GCS) and what we can learn from
> the **Betaflight Configurator** UX, followed by a prioritised roadmap to close
> the gaps. Special focus areas (called out by the maintainer): a best-in-class
> **parameter configuration** experience, a **"non-default parameters only"**
> view, and a **graphical, Betaflight-style configuration** experience.

---

## 1. Executive summary

Helios is already a competent, modern, multi-platform GCS with several things
Mission Planner does *not* do well (auto flight recording to DuckDB, SQL
analytics, a clean Flutter UI, web build, MSP + MAVLink in one app). Where it is
behind is in the **breadth and depth of vehicle configuration and tuning**, and
in **mission-planning richness**. Mission Planner has had 13+ years to accrete
features; we don't need all of them, but several are table-stakes for pilots
switching from MP.

The three biggest strategic gaps:

1. **Configuration & tuning depth (ArduPilot).** Helios has a strong parameter
   editor and a handful of dedicated panels, but is missing the guided setup
   flows MP pilots expect (radio cal, flight-mode setup, ESC cal, battery
   monitor wizard, firmware flashing) and the *parameter niceties* the
   maintainer specifically wants (defaults shown, non-default-only view).
2. **MSP/Betaflight configuration is essentially absent.** Helios reads MSP
   telemetry but cannot *configure* a Betaflight/iNav board at all — no Ports,
   Receiver, Modes, Motors, OSD, PID, Filters, or Blackbox tabs. This is the
   single largest protocol-side gap.
3. **Mission planning richness.** Solid foundation (surveys, fence, rally,
   KML/GPX, terrain *visualisation*), but missing per-waypoint altitude/frame
   modes, terrain-following, splines, structure scan, most `DO_`/`CONDITION_`
   commands, and mission validation.

Plus two cross-cutting enablers that unlock multiple features at once:

- **MAVLink FTP (MAVFTP).** Required for fetching parameter **defaults**
  (`@PARAM/param.pck?withdefaults=1`), faster log download, terrain upload, and
  Lua script management. Helios does not implement it yet. This is the keystone
  for the maintainer's "non-default params" view.
- **MSP settings read/write (MSP2 `SETTING`/CLI).** Required for any Betaflight
  configuration UI.

This document is organised as: feature audit by domain (§2), the Betaflight UX
lessons (§3), the parameter-config deep dive incl. the non-default view (§4),
and a phased roadmap with effort sizing and file pointers (§5).

Effort sizing legend: **S** ≈ ≤2 days · **M** ≈ ~1 week · **L** ≈ 2–4 weeks ·
**XL** ≈ multi-month track.

---

## 2. Feature audit by domain

Legend: ✅ have · ⚠️ partial · ❌ missing · n/a not applicable

### 2.1 Connect / link management

| Capability | MP | Helios | Notes |
|---|:--:|:--:|---|
| UDP / TCP / Serial | ✅ | ✅ | `lib/core/mavlink/transports/` |
| WebSocket (web build) | ❌ | ✅ | Helios advantage |
| Protocol auto-detect (MAVLink/MSP) | ❌ | ✅ | Helios advantage |
| Baud/port auto-scan, sysid select | ✅ | ⚠️ | Serial monitor exists; no multi-sysid switcher |
| SiK radio config (RSSI, net ID, power) | ✅ | ❌ | MP "Optional Hardware → Sik Radio" |
| Multi-vehicle on one link | ✅ | ❌ | Single-vehicle model in `vehicle_state.dart` |

### 2.2 Flight Data / Fly view

| Capability | MP | Helios | Notes |
|---|:--:|:--:|---|
| PFD / HUD | ✅ | ✅ | `fly_view.dart` glass cockpit, 60fps |
| Moving map + trail + home | ✅ | ✅ | `vehicle_map.dart` |
| Configurable telemetry tiles | ⚠️ | ✅ | Helios drag-to-reorder is nicer |
| Arm/disarm, mode change, RTL/Land/Takeoff | ✅ | ✅ | `action_panel.dart` |
| Click-to-go (Guided) | ✅ | ✅ | `SET_POSITION_TARGET_GLOBAL_INT` |
| Set ROI / clear ROI | ✅ | ✅ | `DO_SET_ROI_LOCATION` |
| Gimbal + camera trigger | ✅ | ⚠️ | `gimbal_control.dart`; no zoom/focus/record-mode |
| ADS-B traffic | ✅ | ⚠️ | Rendered, but no conflict alerting/avoidance |
| Joystick/gamepad flight | ✅ | ⚠️ | `joystick_service.dart` sends RC override; **no UI** to enable/calibrate/map, no on-screen sticks |
| Status / Messages / Gauges tabs | ✅ | ⚠️ | Inspector + STATUSTEXT overlay; no MP-style "Status" grid |
| Servo/Relay quick-toggle | ✅ | ⚠️ | Servo *viewer* only (`servo_output_panel.dart`), no actuate |
| Follow-me | ✅ | ❌ | `FOLLOW_TARGET` not sent |
| Geo-fence enable/disable from Fly | ✅ | ❌ | — |
| Aux function trigger (RCx options) | ✅ | ❌ | — |

### 2.3 Plan / Mission

| Capability | MP | Helios | Notes |
|---|:--:|:--:|---|
| Waypoint draw/drag/reorder | ✅ | ✅ | `plan_view.dart`, `waypoint_list.dart` |
| Nav commands | ✅ | ⚠️ | 7 of many: WP, Takeoff, Land, RTL, Loiter (Unlim/Time/Turns). **Missing**: `NAV_SPLINE_WAYPOINT`, `NAV_DELAY`, `NAV_GUIDED_ENABLE`, `NAV_PAYLOAD_PLACE`, `NAV_VTOL_TAKEOFF/LAND` |
| DO_ commands | ✅ | ⚠️ | 7 supported. **Missing**: `DO_SET_SERVO`, `DO_REPEAT_SERVO`, `DO_SET_RELAY`, `DO_DIGICAM_CONTROL`, `DO_FENCE_ENABLE`, `DO_WINCH`, `DO_GUIDED_LIMITS`, `DO_SET_ROI` (in-mission), `DO_VTOL_TRANSITION` |
| CONDITION_ commands | ✅ | ❌ | `CONDITION_DELAY/DISTANCE/YAW` absent |
| Per-waypoint altitude frame (rel/abs/terrain) | ✅ | ❌ | **Hardcoded `globalRelativeAlt`** in `mission_edit_notifier.dart`. High-value gap. |
| Survey: simple grid | ✅ | ✅ | `plan_view.dart::_generateSurveyGrid` |
| Survey: polygon | ✅ | ✅ | `_generatePolygonSurvey` |
| Survey: corridor/strip scan | ✅ | ✅ | `corridor_scan.dart` |
| Survey: camera/GSD/overlap calc, footprint | ✅ | ❌ | No camera model → no GSD/overlap-driven spacing |
| Survey: structure/building scan | ✅ | ❌ | — |
| Survey: terrain-following grid | ✅ | ❌ | DEM exists for *display* only |
| WP circle / spline circle generator | ✅ | ⚠️ | Orbit-around-POI only (12-pt); no spline |
| Geofence (polygon + circle, inc/exc) | ✅ | ✅ | `fence_edit_notifier.dart`, `fence_service.dart` |
| Geofence altitude min/max (ceiling/floor) | ✅ | ❌ | `FENCE_ALT_MAX/MIN` not surfaced |
| Rally points | ✅ | ✅ | `rally_service.dart` |
| Terrain elevation profile | ✅ | ✅ | `dem_service.dart` + altitude profile chart |
| Mission validation (reachability, alt vs terrain, size) | ⚠️ | ❌ | Only airspace-conflict count today |
| File: ArduPilot `.waypoints` / QGC `.plan` | ✅ | ✅ | `mission_file_service.dart` |
| File: KML/GPX import | ✅ | ✅ | `kml_importer.dart`, `gpx_importer.dart` |
| File: KML/SHP export, GeoFence file | ✅ | ⚠️ | `.plan` carries fence; no SHP/KML export |
| Undo/redo, multi-select batch | ⚠️ | ✅ | 50-level undo — Helios advantage |

### 2.4 Setup & Configuration (ArduPilot)

This is the densest gap area. MP's SETUP = *Install Firmware*, *Wizard*,
*Mandatory Hardware*, *Optional Hardware*; CONFIG = the tuning/param screens.

| Capability | MP | Helios | Notes |
|---|:--:|:--:|---|
| Firmware flashing/install | ✅ | ❌ | Helios "Firmware" tab is read-only (version display) |
| Setup wizard (first-flight) | ✅ | ❌ | — |
| Frame type select | ✅ | ✅ | `frame_type_panel.dart` (hardcoded enums) |
| Accel/level calibration | ✅ | ✅ | `calibration_service.dart` + wizard (no 3D model) |
| Compass calibration (onboard/relax) | ✅ | ✅ | `MAG_CAL_PROGRESS/REPORT` handled |
| CompassMot (compass/motor interference) | ✅ | ❌ | — |
| Radio/RC calibration (min/max/trim/reverse) | ✅ | ❌ | RC tab is **live view only** (`_RcTab`), no cal/map |
| Flight-mode setup (6-pos channel) | ✅ | ❌ | No PWM-band → mode mapping UI |
| ESC calibration | ✅ | ❌ | — |
| Motor test | ✅ | ✅ | `motor_test_panel.dart` |
| Servo output setup (function per channel) | ✅ | ❌ | Viewer only |
| Failsafe config (battery/RC/GCS) | ✅ | ⚠️ | `failsafe_panel.dart` (8 hardcoded params) |
| Battery monitor wizard (calibrate V/A) | ✅ | ❌ | — |
| Airspeed / optical-flow setup | ✅ | ❌ | — |
| Onboard OSD param layout | ✅ | ❌ | ArduPilot `OSDn_*` params editable only raw |
| Camera/gimbal setup | ✅ | ❌ | — |
| Pre-arm / sensor health display | ✅ | ✅ | `prearm_panel.dart` (read-only) |
| Antenna tracker config | ✅ | ❌ | — |

### 2.5 CONFIG / Tuning & Parameters (ArduPilot)

| Capability | MP | Helios | Notes |
|---|:--:|:--:|---|
| Full parameter list (search/filter) | ✅ | ✅ | `parameter_editor.dart` — strong |
| Parameter metadata (desc/units/range/enum/bitmask) | ✅ | ✅ | apm.pdef.xml via `param_meta_service.dart` |
| Enum dropdowns + bitmask editor | ✅ | ✅ | Helios bitmask dialog is good |
| **Default value column** | ✅ | ❌ | **No defaults sourced** — see §4 |
| **Non-default / modified-only view** | ✅ | ❌ | **The maintainer's headline ask** — see §4 |
| Reset-param-to-default | ✅ | ❌ | Blocked on defaults |
| Parameter tree (grouped) | ✅ | ⚠️ | Group *filter* only; no tree |
| Compare params / load+diff file | ✅ | ✅ | `param_file_service.dart` + profile diff |
| Save/load `.param` (MP/QGC/AP) | ✅ | ✅ | — |
| Basic Tuning (sliders) | ✅ | ❌ | No curated beginner tuning screen |
| Extended Tuning (PID matrix) | ✅ | ❌ | Raw params only |
| Flight-mode config screen | ✅ | ❌ | (also listed under Setup) |
| Standard/Advanced level toggle | ✅ | ✅ | userLevel from metadata |

### 2.6 MSP / Betaflight configuration

| Capability | Betaflight Configurator | Helios | Notes |
|---|:--:|:--:|---|
| MSP telemetry read | ✅ | ✅ | `lib/core/msp/` — good coverage |
| Read/write settings (MSP2 SETTING) | ✅ | ❌ | **No write path at all** |
| Ports tab | ✅ | ❌ | — |
| Configuration tab | ✅ | ❌ | — |
| Receiver tab (live bars + map) | ✅ | ❌ | — |
| Modes tab (aux range sliders) | ✅ | ❌ | — |
| Motors tab (test + direction + 3D) | ✅ | ❌ | — |
| OSD layout editor | ✅ | ❌ | — |
| PID tuning + sliders/presets | ✅ | ❌ | — |
| Filters tab | ✅ | ❌ | — |
| Blackbox config + log download | ✅ | ❌ | README directs users to BF Configurator |
| CLI passthrough / `diff` | ✅ | ❌ | — |

### 2.7 Logs & Analysis

| Capability | MP | Helios | Notes |
|---|:--:|:--:|---|
| Auto flight recording (no start/stop) | ❌ | ✅ | **Major Helios advantage** (DuckDB) |
| SQL query / cross-flight analytics | ❌ | ✅ | Helios advantage |
| Dataflash `.bin` download | ✅ | ✅ | `log_download_service.dart` (LOG_DATA, slow) |
| Dataflash download via MAVFTP (fast) | ✅ | ❌ | — |
| `.bin`/`.tlog` parser + graphical review | ✅ | ❌ | No BIN parser; "Review a Log" equivalent missing |
| Auto log analysis (vibe/EKF/power flags) | ✅ | ⚠️ | Predictive maintenance exists; not log-driven |
| KMZ / 3D track export | ✅ | ⚠️ | Parquet export instead |
| MAVLink inspector | ⚠️ | ✅ | `inspect_view.dart` is excellent |

### 2.8 Simulation & misc

| Capability | MP | Helios | Notes |
|---|:--:|:--:|---|
| One-click SITL | ⚠️ | ✅ | `simulate_panel.dart` — Helios advantage |
| Wind/failure injection | ✅ | ✅ | — |
| Swarm / multi-vehicle ops | ✅ | ❌ | — |
| Lua script editor / upload | ✅ | ❌ | Needs MAVFTP |
| Terrain upload to vehicle | ✅ | ❌ | Needs MAVFTP |
| DroneID / RemoteID config | ✅ | ❌ | — |

---

## 3. Lessons from the Betaflight Configurator UX

The maintainer specifically called out Betaflight's "easy, graphical" config.
The reusable UX patterns (regardless of protocol) worth porting into Helios:

1. **Tab-per-concern, not one giant param list.** BF never shows raw settings
   first; each concern (Ports, Receiver, Modes…) gets a purpose-built graphical
   tab. The raw CLI is the *escape hatch*, not the front door. Helios should
   mirror this: dedicated visual panels backed by params, with the full
   parameter editor as the power-user fallback (it already is structured this
   way in `fc_config_view.dart` — extend it).
2. **Live feedback while configuring.** The Receiver tab shows **live moving
   bars** as you wiggle sticks; the Modes tab highlights the active range in
   real time; Motors shows live RPM/direction. Helios already streams RC/servo
   (`rc_input_panel.dart`, `servo_output_panel.dart`) — wire those live values
   *into* the config panels.
3. **Direct-manipulation editors.** Drag OSD elements onto a screen preview;
   drag mode-range handles on a slider; click a motor on a frame diagram to
   spin it. Replace number-entry where a graphical metaphor is clearer.
4. **Sane presets + sliders over raw PIDs.** BF's slider-based tuning maps a few
   intuitive sliders onto many underlying values. Mirror with ArduPilot Basic
   Tuning sliders and tuning presets.
5. **`diff`-first mental model.** BF's `diff` shows *only what differs from
   defaults* — exactly the non-default view the maintainer wants for ArduPilot
   (see §4). It's the same idea; we should build it for both protocols.
6. **3D vehicle model for orientation.** BF's Setup tab shows a live 3D model
   for attitude + accel-cal guidance. A lightweight 3D (or stylised 2.5D)
   attitude model would improve our calibration wizard and PFD.
7. **Non-blocking validation & "Save and Reboot".** Clear dirty-state, a single
   prominent save action, explicit reboot-required affordance (Helios already
   detects reboot-required params — surface it more like BF's banner).

---

## 4. Deep dive: world-class parameter configuration

This section addresses the maintainer's headline requests directly.

### 4.1 Where Helios is already strong

`lib/features/setup/widgets/parameter_editor.dart` (1688 lines) already does a
lot right: live fetch with progress, apm.pdef.xml metadata (descriptions,
units, range, increment, enum `values`, bitmask bits, Standard/Advanced level),
enum dropdowns with numeric fallback, an inline bitmask editor, search, group
filter, per-param and batch write with retry, reboot-required detection, and
parameter *profiles* with a diff preview. This is close to MP's Full Parameter
List already — the description/options/enum experience the maintainer admires in
MP is **mostly present**. Gaps below are what's missing.

### 4.2 Gap 1 — Show the default value (and reset to it)

**Problem.** `Parameter.defaultValue` exists in the model but is never
populated. apm.pdef.xml does **not** contain defaults, so metadata alone can't
provide them.

**Solution — MAVLink FTP `@PARAM/param.pck?withdefaults=1`.** ArduPilot exposes
the entire parameter set as a packed binary file over MAVFTP; with the
`withdefaults=1` query string each entry carries its **default value, included
only when it differs from the current value**. This is precisely how Mission
Planner populates its Default column and detects non-default params. It is the
correct, vehicle-exact source (accounts for board-specific and frame-specific
defaults, OEM `defaults.parm` overrides, etc.).

Implementation outline:
- New `lib/core/mavlink/mavftp_service.dart` — minimal MAVFTP client
  (`FILE_TRANSFER_PROTOCOL` msg): OpenFileRO / ReadFile / BurstReadFile / EOF,
  session + sequence handling, retries. This is a reusable enabler (logs,
  terrain, scripts also need it).
- `param.pck` decoder (the format is a simple typed key/value pack; reuse
  ArduPilot's documented layout). On connect (or on demand), fetch
  `@PARAM/param.pck?withdefaults=1`, populate `Parameter.defaultValue` for every
  param where a default is present.
- **Fallback** when MAVFTP/withdefaults is unavailable (older firmware): ship a
  bundled per-vehicle default `.param` snapshot (generated from ArduPilot's
  `extract_param_defaults.py`) keyed by firmware string; mark these defaults as
  "approximate" in the UI.

UI additions to `parameter_editor.dart`:
- A **Default** column / subtitle (e.g. `default: 4500`), greyed.
- A per-row **Reset to default** action (only when current ≠ default).
- "Reset all to default" in the batch menu (with confirmation + diff preview —
  reuse the existing profile-diff dialog).

Effort: **L** (MAVFTP client is the bulk; the UI is **S** once defaults exist).

### 4.3 Gap 2 — "Non-default parameters only" view (the headline feature)

Once defaults are available (§4.2), this becomes straightforward and is *the*
feature the maintainer asked for ("a view which shows only non-standard
parameters which the user must have edited").

Design:
- Add a filter mode to the parameter editor: **All · Standard · Advanced ·
  Modified (≠ default)**. "Modified" lists only params whose current value
  differs from default, sorted by group.
- Each row shows `name · current → (default)` with the delta emphasised, the
  human description, and a one-click revert.
- A **count badge** in the tab ("Config tab → Parameters · 37 changed").
- **Export "changed-only"** to a `.param` file (this is the GCS equivalent of
  Betaflight's `diff` — a compact, shareable record of exactly what was tuned).
  Reuse `param_file_service.dart`.
- Reverse direction too: **import a `.param` and preview only the changes** vs
  current (already mostly built via the profile-diff dialog — generalise it).

This also lights up workflows MP users love: "what did I change on this build?",
copying a tune between identical airframes, and bug reports that include a clean
non-default dump.

Effort: **S–M** (sits on top of §4.2).

### 4.4 Gap 3 — Metadata-driven panels & richer presentation

- Replace hardcoded enum maps in `failsafe_panel.dart` and `frame_type_panel.dart`
  with metadata-derived `values{}` so they never drift from firmware.
- **Parameter tree** (MP "Full Parameter Tree"): collapsible groups derived from
  the existing `group` field — better than the current flat-list-plus-filter.
- Always-available **full description** (expandable row / side panel), not just a
  2-line clip; include range, increment, units, reboot-required, and `RebootRequired`/`ReadOnly` flags from metadata.
- **Range/increment enforcement** (soft warn on out-of-range; snap option for
  increments).

Effort: **M**.

### 4.5 Apply the same idea to MSP/Betaflight

Betaflight already has the non-default concept natively (`diff`). When MSP
settings read/write lands (§5 Phase 4), expose the same **Modified-only** view
and a **`diff` export** for Betaflight/iNav, so the parameter experience is
symmetric across protocols.

---

## 5. Roadmap — phased plan to close the gaps

Phases are ordered by (maintainer priority × leverage). Each item lists effort
and the primary files to touch. Phases 1–2 deliver the maintainer's explicit
asks; 3–6 bring broader MP parity.

### Phase 0 — Enabler: MAVLink FTP client  ·  **L**
Keystone for params-defaults, fast log download, terrain & script upload.
- New `lib/core/mavlink/mavftp_service.dart` (+ tests).
- `@PARAM/param.pck?withdefaults=1` decoder.
- *Unlocks:* §4.2, §4.3, faster §2.7 log download, future terrain/script upload.

### Phase 1 — Parameter config excellence (maintainer ask #1)  ·  **M**
- Default values populated from MAVFTP, bundled fallback (§4.2). **S** post-Phase 0.
- **Non-default-only view** + count badge + changed-only export (§4.3). **S–M**.
- Reset-to-default (per-param + all). **S**.
- Parameter tree + always-on full description + metadata-driven failsafe/frame
  panels (§4.4). **M**.

### Phase 2 — Betaflight-style graphical setup (maintainer ask #2, ArduPilot first)  ·  **L**
Build purpose-built visual tabs in `fc_config_view.dart`, backed by params,
with the parameter editor as the power-user fallback (per §3).
- **Radio/RC calibration** wizard (min/max/trim/reverse, live bars) — `_RcTab` → editable.  **M**
- **Flight-mode setup** (6-position channel → mode mapping, live highlight).  **M**
- **Servo/output function** editor (per-channel `SERVOn_FUNCTION`, live bars).  **M**
- **Battery monitor** calibrate wizard (measured-vs-reported V/A).  **S**
- **ESC calibration** flow.  **S**
- **3D/2.5D attitude model** in calibration wizard + PFD.  **M**
- **Basic Tuning sliders** + tuning presets (curated param bundles).  **M**
- **First-flight setup wizard** stitching the above into a checklist.  **M**

### Phase 3 — Mission planning parity  ·  **L**
- **Per-waypoint altitude frame** (relative/absolute/terrain) picker — highest
  value; touch `mission_edit_notifier.dart`, `waypoint_editor.dart`, mission I/O.  **M**
- **Terrain-following survey** (reuse `dem_service.dart` to set per-WP alt).  **M**
- **Camera model + GSD/overlap-driven** survey spacing & footprint preview.  **M**
- **Structure scan** generator.  **M**
- **`NAV_SPLINE_WAYPOINT`** + spline circle.  **S–M**
- **More DO_/CONDITION_ commands** (`DO_SET_SERVO`, `DO_SET_RELAY`,
  `DO_DIGICAM_CONTROL`, `DO_FENCE_ENABLE`, `CONDITION_DELAY/DISTANCE/YAW`, …) —
  data-driven additions to `_kParamDefs`/`_kActionCommands` in `waypoint_editor.dart`.  **S** each
- **Geofence altitude min/max**; **mission validation** (alt-vs-terrain,
  reachability, size limits).  **M**
- KML/SHP export.  **S**

### Phase 4 — MSP / Betaflight configuration track  ·  **XL**
Largest net-new surface; can run in parallel as its own track.
- **MSP settings read/write** (MSP2 `SETTING`/`SET_SETTING`) + CLI passthrough.  **L**
- Graphical tabs mirroring BF: **Ports, Configuration, Receiver, Modes, Motors,
  OSD layout editor, PID/sliders, Filters, Blackbox**.  **XL** (incremental)
- **Modified-only / `diff` view** for MSP (symmetry with §4.5).  **S** once read/write exists.

### Phase 5 — Logs & analysis parity  ·  **M–L**
- **Dataflash `.bin` parser** + graphical log review (charts, message picker).  **L**
- Fast log download via MAVFTP (Phase 0).  **S**
- `.tlog` ingest into the DuckDB pipeline.  **M**
- Log-driven auto-analysis flags (vibe/EKF/power) feeding predictive maintenance.  **M**

### Phase 6 — Flight-data & misc parity  ·  **M**
- **Joystick/gamepad UI**: enable toggle, mapping, calibration, on-screen sticks
  (logic exists in `joystick_service.dart`; needs UI).  **M**
- **Follow-me** (`FOLLOW_TARGET`), aux-function triggers, servo/relay quick-toggle.  **M**
- ADS-B conflict alerting.  **S**
- Gimbal zoom/focus/record-mode; SiK radio config; firmware flashing (platform-gated).  **M–L**

---

## 6. Suggested sequencing & quick wins

**Do first (directly serves the two stated asks, high leverage):**
1. Phase 0 MAVFTP client → Phase 1 defaults + **non-default view** (the headline).
2. Phase 3's **per-waypoint altitude frame** picker (small, very visible win).
3. Metadata-driven failsafe/frame panels + parameter tree (Phase 1 tail).

**Cheap, high-visibility quick wins (each ≈ S):**
- Reset-to-default once defaults exist.
- Add missing `DO_`/`CONDITION_` commands to `waypoint_editor.dart` (pure data).
- Geofence altitude min/max surfaced in the fence panel.
- ADS-B conflict badge on the Fly map (data already parsed).
- Changed-only `.param` export.

**Bigger bets (plan as tracks):**
- Phase 4 Betaflight/MSP configuration (XL — own milestone).
- Phase 5 dataflash log review.
- Phase 2 graphical setup suite.

---

## 7. Appendix — key files referenced

| Area | Files |
|---|---|
| Top-level nav | `lib/app.dart` (Fly·Plan·Data·Video·Config·Inspect·Setup) |
| Parameters | `lib/features/setup/widgets/parameter_editor.dart`, `lib/core/params/{param_meta,param_meta_service,parameter_service,param_file_service}.dart` |
| FC config tabs | `lib/features/config/fc_config_view.dart` |
| Config panels | `lib/features/setup/widgets/{calibration_wizard,frame_type_panel,motor_test_panel,failsafe_panel,prearm_panel}.dart` |
| Calibration | `lib/core/calibration/calibration_service.dart` |
| Mission UI | `lib/features/plan/{plan_view.dart, widgets/waypoint_editor.dart, widgets/corridor_scan_dialog.dart, providers/*}` |
| Mission core | `lib/core/mission/{mission_service,mission_file_service,corridor_scan,kml_importer,gpx_importer}.dart` |
| Fence/Rally | `lib/core/fence/fence_service.dart`, `lib/core/rally/rally_service.dart` |
| Terrain | `lib/core/dem/dem_service.dart` |
| Fly view | `lib/features/fly/{fly_view,vehicle_map,action_panel,gimbal_control,telemetry_panel,...}.dart` |
| MAVLink | `lib/core/mavlink/` (+ `transports/`) — **no MAVFTP yet** |
| MSP | `lib/core/msp/` — telemetry only, **no settings write** |
| Logs | `lib/core/logs/log_download_service.dart` |
| Joystick | `lib/core/joystick/joystick_service.dart` — **no UI** |

### External references
- [Mission Planner — Features/Screens](https://ardupilot.org/planner/docs/mission-planner-features.html)
- [Mission Planner — Flight PLAN](https://ardupilot.org/planner/docs/mission-planner-flight-plan.html)
- [Mission Planner — Config & Tuning](https://ardupilot.org/planner/docs/mission-planner-configuration-and-tuning.html)
- [ArduPilot — MAVFTP (`@PARAM/param.pck`, `@SYS`)](https://ardupilot.org/dev/docs/mavlink-mavftp.html)
- [ArduPilot — Getting/Setting Parameters (defaults via FTP)](https://ardupilot.org/dev/docs/mavlink-get-set-params.html)
- [Betaflight — Configuration Tab / Configurator tabs](https://betaflight.com/docs/wiki/app/configuration-tab)
</content>
</invoke>
