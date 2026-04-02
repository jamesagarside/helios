# Fly View

The Fly View is the primary real-time operations screen in Helios. It combines a live map, primary flight display (PFD), telemetry sidebar, charts, and flight controls into a single configurable layout.

---

## Flight Action Panel

**Protocol**: MAVLink only
**Platform**: All (macOS, Linux, Windows)

A compact floating strip at the bottom-centre of the map. Provides one-tap access to the most critical flight operations.

### Controls

| Control | Behaviour |
|---|---|
| **Mode** | Displays current flight mode (colour-coded by category). Tap to open the mode picker. |
| **ARM / DISARM** | ARM requires a confirmation dialog. DISARM is immediate. |
| **TKOF** | Shown when armed and on the ground (`altRel < 1.5 m`). Opens an altitude dialog (default 10 m AGL). |
| **BRAKE** | Shown when airborne. Sends BRAKE mode (Copter) or equivalent. |
| **LOITER** | Holds current position and altitude. |
| **AUTO** | Engages the active mission. |
| **LAND** | Commands an in-place landing at the current position. |
| **RTL** | Returns to home and lands. |

### Mode Picker

Tapping the mode display opens a bottom sheet grouped into three categories:

- **AUTO** — mission-following modes (AUTO, GUIDED, etc.)
- **ASSISTED** — semi-autonomous modes (LOITER, ALT_HOLD, etc.)
- **MANUAL** — direct control modes (STABILIZE, MANUAL, ACRO, etc.)

Mode numbers are vehicle-type-aware: the correct table is used for Copter, Plane, Rover, and VTOL automatically.

### Toggling visibility

The action panel visibility is persisted per layout profile. Toggle it with the **ACT** button in the Fly View toolbar.

---

## Status Message Log

**Protocol**: MAVLink only (STATUSTEXT messages; no MSP equivalent)
**Platform**: All

A small floating panel (bottom-right of map) that displays the live STATUSTEXT feed from the flight controller. Severity colours match the MAVLink severity levels:

| Severity | Colour |
|---|---|
| EMERGENCY / ALERT / CRITICAL | Red (danger) |
| ERROR / WARNING | Amber (warning) |
| NOTICE / INFO | Primary text |
| DEBUG | Tertiary text |

- Scrolls automatically to the latest message.
- Pauses auto-scroll when you scroll up; resumes when you reach the bottom.
- Clear-all button in the panel header.

### Toggling visibility

Toggle with the **MSG** button in the Fly View toolbar. Visibility is persisted per layout profile.

---

## Customisable Telemetry Tiles

**Protocol**: MAVLink and MSP
**Platform**: All

The right-hand telemetry sidebar is fully user-configurable. The default set shows 12 fields; you can add, remove, and reorder to suit your workflow.

### Interactions

| Gesture | Action |
|---|---|
| Drag handle | Reorder tiles |
| Long-press | Remove tile |
| Tap **+ Add field** | Open field picker |

### Field Picker

A searchable bottom sheet grouped by category. Search by label, field ID, or category name. Already-displayed fields are hidden from the picker.

### Available categories and fields

| Category | Fields |
|---|---|
| Battery | BATT (V), BAT% (%), CURR (A), MAH (mAh) |
| GPS | SATS, HDOP, LAT (°), LON (°) |
| Altitude | ALT (m AGL), MSL (m) |
| Speed | IAS (m/s), GS (m/s), VS (m/s) |
| Attitude | ROLL (°), PITCH (°), HDG (°) |
| Control | THR (%) |
| Link | RSSI |
| Wind | WIND (m/s), WDIR (°) |
| EKF | EKF-V, EKF-P |

### Semantic colour thresholds

Several fields have built-in colour coding:

| Field | Warning | Danger |
|---|---|---|
| BATT (V) | < 11.5 V | < 10.5 V |
| BAT% | < 30 % | < 15 % |
| SATS | < 8 | < 5 |
| HDOP | > 2 | > 5 |
| RSSI | < 100 | < 50 |

Custom warn thresholds can be added via the `TelemetryTileConfig.warnLow` / `warnHigh` fields (configuration persisted to the layout profile).

### Layout persistence

Tile order and selection are saved per layout profile (Multirotor / Fixed Wing / VTOL / custom) to SharedPreferences.

---

## Vehicle-Type-Aware Flight Modes

**Protocol**: MAVLink only
**Platform**: All

ArduPilot encodes flight mode as a raw integer in the HEARTBEAT message. Helios resolves the correct human-readable name using `FlightModeRegistry`, which holds mode tables for:

- **ArduCopter** — e.g. mode 3 → `AUTO`, mode 6 → `RTL`
- **ArduPlane** — e.g. mode 10 → `AUTO`, mode 11 → `RTL`
- **ArduRover** — e.g. mode 10 → `AUTO`, mode 11 → `RTL`
- **VTOL** — uses the Plane table
- **Boat** — uses the Rover table
- **Helicopter** — uses the Copter table

Unknown mode numbers fall back to `MODE_<n>`.

---

## Layout Profiles

The Fly View layout (chart positions, PFD visibility, telemetry tiles, action panel, message log) is saved per named profile. Three default profiles ship with Helios:

| Profile | Vehicle | Default charts |
|---|---|---|
| Multirotor | Copter / Heli | Altitude + Battery |
| Fixed Wing | Plane / VTOL | Altitude + Speed + Climb Rate |
| VTOL | VTOL | Altitude + Speed + Attitude |

Custom profiles can be created from the toolbar and will inherit the current layout.

---

## Platform Notes

| Feature | macOS | Linux | Windows | iOS | Android |
|---|:---:|:---:|:---:|:---:|:---:|
| Flight action panel | ✅ | ✅ | ✅ | ✅ | ✅ |
| Status message log | ✅ | ✅ | ✅ | ✅ | ✅ |
| Customisable telemetry tiles | ✅ | ✅ | ✅ | ✅ | ✅ |
| Serial / USB connection | ✅ | ✅ | ✅ | ❌ | ❌ |
| UDP / TCP connection | ✅ | ✅ | ✅ | ✅ | ✅ |

iOS and Android do not support serial/USB transport (`flutter_libserialport` requires OS-level serial port access). All other Fly View features work across platforms.
