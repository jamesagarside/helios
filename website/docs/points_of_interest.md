# Points of Interest (POIs)

POIs let you mark named locations on the map — landmarks, targets, survey areas, reference points, or anything you want to remember during planning or flight.

POIs appear on both the **Plan View** and **Fly View** maps. In the Plan View they are interactive; in the Fly View they are read-only visual references.

**Platform**: All (macOS, Linux, Windows, iOS, Android)

---

## Creating a POI

1. In the Plan View toolbar (right side), tap the **Add POI** button (pin icon). The button highlights to show add-mode is active.
2. Tap anywhere on the map to place the POI.
3. A quick-create dialog appears — enter a name, optional notes, altitude, colour, and icon.
4. Tap **Save** to confirm.

Tap the **Add POI** button again to exit add-mode.

---

## Interacting with POIs

**Tap a POI marker** to open the details panel:
- Name and notes
- Latitude / longitude
- Altitude
- **Edit** — modify any field
- **Delete** — remove with confirmation
- **Generate Orbit** — create a circular survey mission around the POI

**Long-press a POI marker** to open the edit dialog directly.

---

## Orbit Mission Generator

The orbit generator creates a circular waypoint mission centred on a POI.

**Inputs:**

| Field | Default | Description |
|---|---|---|
| Radius | 50 m | Distance from POI centre |
| Altitude | POI altitude (min 30 m) | Orbit altitude AGL |
| Speed | 5 m/s | Cruise speed |
| Laps | 2 | Number of clockwise circles |

**Output**: 12 waypoints per lap (evenly-spaced on the circle) + a TAKEOFF waypoint at the start. If the current mission already has waypoints, you will be asked to **Replace**, **Append**, or **Cancel**.

---

## POI Colours and Icons

### Colours

| Colour | Use case suggestion |
|---|---|
| Red | No-go zones, hazards |
| Orange | Caution areas, staging points |
| Yellow | Survey targets, inspection points |
| Green | Safe zones, landing areas |
| Blue | Waypoints of interest, objectives |
| Purple | Reference markers |

### Icons

| Icon | Symbol |
|---|---|
| Pin | General location marker |
| Star | Important point |
| Camera | Photo / survey target |
| Target | Inspection or survey point |
| Home | Base / recovery point |
| Flag | Checkpoint or boundary |

---

## Persistence

POIs are saved to `{appSupportDir}/points_of_interest.json` and loaded automatically on startup. They persist across sessions.

Tap **Clear POIs** in the Plan View map controls to remove all POIs (irreversible — no undo).

---

## Platform Notes

| Feature | macOS | Linux | Windows | iOS | Android |
|---|:---:|:---:|:---:|:---:|:---:|
| Create / edit / delete POIs | ✅ | ✅ | ✅ | ✅ | ✅ |
| POI display on Plan + Fly maps | ✅ | ✅ | ✅ | ✅ | ✅ |
| Orbit mission generator | ✅ | ✅ | ✅ | ✅ | ✅ |
| Persistent storage | ✅ | ✅ | ✅ | ✅ | ✅ |
