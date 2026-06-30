# Mission Planning

The Plan View is Helios's mission planning screen. It supports waypoint editing, survey generation, fence and rally point management, and KML/GPX import.

**Platform**: All (macOS, Linux, Windows, iOS, Android)

---

## Waypoint Commands

### Navigation commands

| Command | Description |
|---|---|
| Waypoint | Fly to lat/lon at altitude |
| Takeoff | Arm and climb to altitude |
| Land | Land at current position |
| Loiter (unlimited) | Circle indefinitely at position |
| Loiter (turns) | Circle N times then continue |
| Loiter (time) | Circle for T seconds then continue |
| Return to Launch | Return home |
| Spline waypoint | Smooth curve through waypoint |

### Action commands (DO_ / CONDITION)

Action and condition commands execute alongside navigation and do not move the vehicle.

| Command | Parameters | Description |
|---|---|---|
| Change Speed | Speed type, Speed (m/s), Throttle % | Change cruise speed mid-mission |
| Jump | Target seq, Repeat count | Loop back to a waypoint N times |
| Camera Trigger | Distance (m) | Trigger camera every N metres |
| Gimbal Control | Pitch, Roll, Yaw | Point gimbal to angle (mount control) |
| Land Start | — | Mark start of auto-landing sequence |
| Gripper | Gripper ID, Action | Open/close servo gripper |
| Pause/Continue | Pause or continue flag | Pause mission until resumed |
| Set Servo | Servo #, PWM (us) | Move a servo to a PWM value |
| Set Relay | Relay #, State | Switch a relay on or off |
| Repeat Servo | Servo #, PWM (us), Count, Cycle (s) | Cycle a servo N times |
| Repeat Relay | Relay #, Count, Cycle (s) | Cycle a relay N times |
| Fence Enable | Enable (off / on / floor-only) | Enable or disable the geofence |
| Condition: Delay | Delay (s) | Wait before the next command |
| Condition: Distance | Distance (m) | Hold the next command until a distance is reached |
| Condition: Yaw | Angle, Rate, Direction, Relative | Turn to a heading before continuing |

Each command shows labelled parameter fields rather than generic "Param 1"–"Param 7".

---

## Altitude Frames

Each waypoint carries its own altitude frame, selected from the **Alt Frame**
picker in the waypoint editor:

| Frame | Meaning |
|---|---|
| Relative (home) | Altitude is measured above the home position |
| Absolute (AMSL) | Altitude is measured above mean sea level |
| Terrain | Altitude is measured above the ground beneath the waypoint |

---

## Pre-Upload Validation

Helios checks the mission before upload and surfaces findings as a chip in the
mission stats bar. Findings are ordered errors first, then warnings, then info:

| Finding | Severity |
|---|---|
| `DO_JUMP` target out of range | Error |
| Mission above the item limit | Warning |
| Waypoint altitude at or below home / ground (relative or terrain frame) | Warning |
| Below the minimum terrain clearance (absolute frame, when terrain data is available) | Warning |
| Duplicate of the previous waypoint (same position) | Warning |
| Large altitude change from the previous waypoint | Info |

---

## Multi-select + Batch Edit

Select multiple waypoints to edit or delete them together.

### Entering selection mode

- **Long-press** any waypoint in the list to enter multi-select mode
- Checkboxes appear on all waypoints
- **Ctrl+A** selects all navigation waypoints

### Batch operations

| Operation | Effect |
|---|---|
| Set Altitude | Opens a dialog; sets altitude on all selected waypoints |
| Delete | Removes all selected waypoints and re-sequences |
| × (clear) | Exits multi-select mode |

---

## KML / GPX Import

Import waypoints from Google Earth KML files or GPS track files.

### Supported formats

| Format | Elements parsed |
|---|---|
| KML | `<Placemark>` with `<Point>`, `<LineString>`, `<MultiGeometry>` |
| GPX | `<wpt>`, `<trkpt>` (inside `<trkseg>`), `<rtept>` |

### How to import

1. Tap the **Import KML/GPX** button in the Plan View map controls.
2. Select a `.kml` or `.gpx` file.
3. If the mission already has waypoints, choose **Replace** or **Append**.
4. A snackbar confirms: _"Imported N waypoints from filename"_.

Altitude is read from KML altitude coordinates or GPX `<ele>` elements. If absent, a default of 30 m AGL is used.

**Platform note**: File picker on iOS/Android may require files to be in the app's Documents folder.

---

## Survey Tools

### Rectangle survey (existing)

Draw a rectangle on the map by tapping two corners. Configure spacing, altitude, angle, and entry point in the survey dialog.

### Polygon survey (new)

Generate a lawnmower grid within an arbitrary polygon.

1. Tap the **Polygon Survey** button (grid icon) in the map controls.
2. Tap the map to add polygon vertices (3+ required). A dashed preview is shown.
3. Once you have the shape, tap **Generate Survey**.
4. Configure spacing (m) and altitude (m AGL) in the dialog.

The grid is automatically clipped to the polygon boundary. Scan lines run left-to-right in alternating directions for efficient coverage.

---

## Keyboard Shortcuts (Plan View)

| Key | Action |
|---|---|
| Ctrl+A | Select all waypoints |
| Ctrl+Z | Undo |
| Ctrl+Shift+Z / Ctrl+Y | Redo |
| Delete / Backspace | Delete selected waypoint(s) |
| Escape | Deselect / cancel current mode |

---

## Platform Notes

| Feature | macOS | Linux | Windows | iOS | Android |
|---|:---:|:---:|:---:|:---:|:---:|
| Waypoint editing | ✅ | ✅ | ✅ | ✅ | ✅ |
| DO_ commands | ✅ | ✅ | ✅ | ✅ | ✅ |
| Multi-select + batch edit | ✅ | ✅ | ✅ | ✅ | ✅ |
| KML/GPX import | ✅ | ✅ | ✅ | ⚠️ | ⚠️ |
| Polygon survey | ✅ | ✅ | ✅ | ✅ | ✅ |

⚠️ File picker has platform restrictions on iOS/Android.
