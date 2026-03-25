# Helios GCS — UI/UX Specification

**Version**: 1.0.0 | **Status**: Draft | **Date**: 2026-03-24

---

## 1. Design System

### 1.1 Colour Tokens

```dart
abstract class HeliosColors {
  // Backgrounds
  static const background    = Color(0xFF0D1117);
  static const surface       = Color(0xFF161B22);
  static const surfaceLight  = Color(0xFF21262D);
  static const surfaceDim    = Color(0xFF010409);

  // Borders
  static const border        = Color(0xFF30363D);
  static const borderLight   = Color(0xFF3D444D);

  // Text
  static const textPrimary   = Color(0xFFE6EDF3);
  static const textSecondary = Color(0xFF8B949E);
  static const textTertiary  = Color(0xFF6E7681);

  // Semantic
  static const accent        = Color(0xFF58A6FF);  // selected, links, primary
  static const accentDim     = Color(0xFF1F6FEB);  // pressed states
  static const success       = Color(0xFF3FB950);  // connected, GPS fix, healthy
  static const successDim    = Color(0xFF238636);
  static const warning       = Color(0xFFD29922);  // degraded, medium battery
  static const warningDim    = Color(0xFF9E6A03);
  static const danger        = Color(0xFFF85149);  // disconnected, critical
  static const dangerDim     = Color(0xFFDA3633);

  // Instruments
  static const sky           = Color(0xFF1A3A5C);  // PFD sky colour
  static const ground        = Color(0xFF5C3A1A);  // PFD ground colour
  static const horizon       = Color(0xFFE6EDF3);  // PFD horizon line
  static const pitchLine     = Color(0x88E6EDF3);  // PFD pitch ladder
}
```

### 1.2 Typography

```dart
abstract class HeliosTypography {
  // UI text — system sans-serif
  static const TextStyle heading1 = TextStyle(
    fontSize: 24, fontWeight: FontWeight.w600, color: HeliosColors.textPrimary,
  );
  static const TextStyle heading2 = TextStyle(
    fontSize: 18, fontWeight: FontWeight.w600, color: HeliosColors.textPrimary,
  );
  static const TextStyle body = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w400, color: HeliosColors.textPrimary,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12, fontWeight: FontWeight.w400, color: HeliosColors.textSecondary,
  );

  // Telemetry values — monospace, bold for primary readouts
  static const TextStyle telemetryLarge = TextStyle(
    fontSize: 28, fontWeight: FontWeight.w700, fontFamily: 'JetBrains Mono',
    color: HeliosColors.textPrimary,
  );
  static const TextStyle telemetryMedium = TextStyle(
    fontSize: 18, fontWeight: FontWeight.w600, fontFamily: 'JetBrains Mono',
    color: HeliosColors.textPrimary,
  );
  static const TextStyle telemetrySmall = TextStyle(
    fontSize: 13, fontWeight: FontWeight.w500, fontFamily: 'JetBrains Mono',
    color: HeliosColors.textSecondary,
  );

  // SQL editor
  static const TextStyle sqlEditor = TextStyle(
    fontSize: 13, fontWeight: FontWeight.w400, fontFamily: 'JetBrains Mono',
    color: HeliosColors.textPrimary,
  );
}
```

### 1.3 Spacing Scale

```
4px  — xs (icon padding, dense list item gaps)
8px  — sm (between related elements)
12px — md (section padding, card content)
16px — lg (between sections)
24px — xl (major section gaps)
32px — 2xl (view-level padding)
```

### 1.4 Component Tokens

| Component | Background | Border | Border Radius |
|-----------|-----------|--------|---------------|
| Card | surface | border | 8px |
| Panel | surface | none | 0px (edge-to-edge) |
| Button (primary) | accent | none | 6px |
| Button (secondary) | surfaceLight | border | 6px |
| Button (danger) | danger | none | 6px |
| Input field | surfaceDim | border | 6px |
| Tooltip | surfaceLight | border | 4px |
| Badge | varies by severity | none | 4px |

---

## 2. Navigation Architecture

### 2.1 App Shell

```
┌──────────────────────────────────────────────────┐
│  [Logo] Helios GCS        [Connection Badge] [⚙] │
├──────┬───────────────────────────────────────────┤
│      │                                           │
│  ✈   │                                           │
│ Fly  │           ACTIVE VIEW CONTENT             │
│      │                                           │
│  📍  │                                           │
│ Plan │                                           │
│      │                                           │
│  📊  │                                           │
│ Data │                                           │
│      │                                           │
│  ⚙   │                                           │
│Setup │                                           │
│      │                                           │
├──────┴───────────────────────────────────────────┤
│  [Status bar: GPS sats | HDOP | Mode | Armed]    │
└──────────────────────────────────────────────────┘
```

### 2.2 Responsive Navigation

| Breakpoint | Navigation | Implementation |
|------------|-----------|----------------|
| Desktop (> 1200px) | NavigationRail (left, 72px wide) | Icons + labels |
| Tablet (768-1200px) | NavigationRail (left, 56px wide) | Icons only, expand on hover |
| Mobile (< 768px) | BottomNavigationBar | 4 items with labels |

### 2.3 View Hierarchy

```
App Shell
├── Fly View (default)
│   ├── Map layer
│   ├── PFD overlay
│   ├── Telemetry strip
│   └── Action buttons
├── Plan View
│   ├── Map layer (interactive)
│   ├── Waypoint list panel
│   └── Waypoint editor sheet
├── Analyse View
│   ├── Flight browser
│   ├── SQL editor
│   ├── Results table
│   ├── Chart view
│   └── Template gallery
└── Setup View
    ├── Connection manager
    ├── Recording settings
    ├── Parameter editor (P1)
    └── About / diagnostics
```

---

## 3. Fly View — Detailed Layout

### 3.1 Desktop Layout (> 1200px)

```
┌─────────────────────────────────────────────────────────┐
│                                              [Telemetry]│
│                                              │ Battery  │
│              MOVING MAP                      │ 12.4V    │
│         (vehicle marker, trail,              │ 78%      │
│          waypoint overlay)                   │          │
│                                              │ GPS      │
│    ┌──────────────┐                         │ 3D Fix   │
│    │              │                         │ 14 sats  │
│    │     PFD      │                         │ HDOP 0.9 │
│    │  (attitude)  │                         │          │
│    │              │                         │ Speed    │
│    └──────────────┘                         │ AS 22m/s │
│                                              │ GS 25m/s│
│                                              │          │
│                                              │ Alt      │
│                                              │ 120m REL│
│                                              │ 245m MSL│
├─────────────────────────────────────────────────────────┤
│ Mode: AUTO │ Armed │ Flight time: 04:32 │ Msg/s: 142  │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Tablet Layout (768-1200px)

```
┌─────────────────────────────────────────┐
│              MOVING MAP                  │
│         (full width, 60% height)        │
│                                          │
│                         [Connection     │
│                          Badge]          │
├─────────────────────────────────────────┤
│  ┌────────┐  Battery  GPS   Speed  Alt  │
│  │  PFD   │  12.4V   3D   22m/s  120m  │
│  │        │  78%     14   25m/s  245m  │
│  └────────┘                              │
├─────────────────────────────────────────┤
│ AUTO │ Armed │ 04:32 │ 142 msg/s        │
└─────────────────────────────────────────┘
```

### 3.3 Mobile Layout (< 768px)

```
┌─────────────────────────┐
│                          │
│      MOVING MAP          │
│    (full screen)         │
│                          │
│  ┌──────┐               │
│  │ PFD  │  [Badge]      │
│  │(mini)│               │
│  └──────┘               │
│                          │
├─────────────────────────┤
│ AUTO│Armed│12.4V│14 sats│
├─────────────────────────┤
│  ↑ Pull-up sheet for    │
│    detailed telemetry   │
└─────────────────────────┘
```

---

## 4. Primary Flight Display (PFD)

### 4.1 Rendering

The PFD is a CustomPainter widget rendering at 60fps. It displays:

- **Attitude indicator**: Sky/ground split at pitch angle. Roll via rotation.
- **Pitch ladder**: 5-degree increments, numbered at 10-degree.
- **Roll indicator**: Arc at top with tick marks at 0, ±10, ±20, ±30, ±45, ±60.
- **Heading tape**: Bottom of PFD, scrolling compass with cardinal/intercardinal labels.
- **Aircraft symbol**: Fixed centre reference (W shape).
- **Sideslip indicator**: Small ball below roll arc (from yaw rate).

### 4.2 PFD Sizing

| Breakpoint | PFD Size | Position |
|------------|---------|----------|
| Desktop | 320x240px | Bottom-left over map |
| Tablet | 240x180px | Bottom-left panel |
| Mobile | 160x120px | Top-left overlay |

### 4.3 Performance Requirements

- CustomPainter must complete `paint()` in < 4ms (16ms budget for 60fps, leaving headroom).
- No object allocation in `paint()` — pre-allocate all Paint objects.
- Use `shouldRepaint()` to skip frames when attitude unchanged.
- RepaintBoundary around PFD to isolate from map layer repaints.

---

## 5. Telemetry Strip

### 5.1 Data Cards

Each telemetry card shows: label, value, unit, and status colour.

| Card | Label | Format | Thresholds |
|------|-------|--------|------------|
| Battery Voltage | BATT | `12.4V` | > 11.5V green, 10.5-11.5V yellow, < 10.5V red |
| Battery Percent | BAT% | `78%` | > 30% green, 15-30% yellow, < 15% red |
| GPS Fix | GPS | `3D Fix` | 3D+ green, 2D yellow, No Fix red |
| Satellites | SATS | `14` | > 8 green, 5-8 yellow, < 5 red |
| HDOP | HDOP | `0.9` | < 1.5 green, 1.5-2.5 yellow, > 2.5 red |
| Airspeed | IAS | `22.4 m/s` | Always white (informational) |
| Groundspeed | GS | `25.1 m/s` | Always white |
| Altitude (REL) | ALT | `120m` | Always white |
| Altitude (MSL) | MSL | `245m` | Always white |
| Climb Rate | VS | `+2.1 m/s` | Always white, sign displayed |
| Heading | HDG | `182°` | Always white |
| Throttle | THR | `65%` | Always white |
| RSSI | RSSI | `189` | > 150 green, 50-150 yellow, < 50 red |
| Flight Mode | MODE | `AUTO` | Background colour by category |
| Arm State | ARM | `ARMED` | Armed = red background, Disarmed = green |

### 5.2 Status Colour Encoding

Every colour-coded element also uses a secondary indicator (icon, text label, or pattern) to ensure colour-blind accessibility.

---

## 6. Map View

### 6.1 Map Layers

| Layer | Z-order | Description |
|-------|---------|-------------|
| Base tiles | 0 | OSM raster tiles (online or cached) |
| Satellite tiles (P2) | 0 | Optional satellite imagery |
| Geofence overlay | 1 | Inclusion/exclusion zones (P1) |
| Mission path | 2 | Waypoint polyline with direction arrows |
| Vehicle trail | 3 | GPS track, fading gradient, last 5 minutes |
| Waypoint markers | 4 | Numbered circles with command type icon |
| Vehicle marker | 5 | Rotated aircraft icon at current position |
| Home marker | 5 | Home position with range ring |

### 6.2 Vehicle Marker

- Rotated to heading (not yaw — heading from VFR_HUD)
- SVG icon: stylised top-down aircraft outline
- Colour: accent blue when connected, grey when stale
- Size: 40x40px, fixed regardless of zoom

### 6.3 Vehicle Trail

- Last 300 GPS points (approximately 30 seconds at 10 Hz)
- Polyline with gradient opacity: fully opaque at newest, 20% at oldest
- Colour: accent blue
- Cleared on mode change or user action

### 6.4 Offline Tile Management

```dart
class TileManager {
  /// Download a rectangular region at specified zoom levels.
  Future<DownloadProgress> downloadRegion({
    required LatLngBounds bounds,
    required List<int> zoomLevels,  // e.g., [10, 11, 12, 13, 14, 15, 16]
  });

  /// List all cached tile regions.
  Future<List<TileRegion>> listCachedRegions();

  /// Delete a cached region.
  Future<void> deleteRegion(String regionId);

  /// Total cache size on disk.
  Future<int> cacheSize();
}
```

---

## 7. Analyse View

### 7.1 Layout

```
┌─────────────────────────────────────────────────────┐
│  Flight Browser (left panel, 280px)                  │
│  ┌───────────────────────────────────┐  ┌─────────┐│
│  │ 📁 2026-03-24 14:30 (42min)      │  │Templates││
│  │ 📁 2026-03-23 09:15 (28min)      │  │ Vibrate ││
│  │ 📁 2026-03-22 16:45 (1h 12min)   │  │ Battery ││
│  │                                   │  │ GPS     ││
│  └───────────────────────────────────┘  │ Alt     ││
│                                          │ Anomaly ││
│  ┌──────────────────────────────────────┴─────────┐│
│  │  SQL Editor (syntax highlighted, monospace)     ││
│  │  SELECT ts, voltage FROM battery ORDER BY ts    ││
│  │  [▶ Run] [📊 Chart] [💾 Export Parquet]        ││
│  ├─────────────────────────────────────────────────┤│
│  │  Results Table                                   ││
│  │  ts                    │ voltage                 ││
│  │  2026-03-24 14:30:01  │ 12.42                   ││
│  │  2026-03-24 14:30:02  │ 12.41                   ││
│  │  ...                   │ ...                     ││
│  └─────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────┘
```

### 7.2 SQL Editor Features

- Syntax highlighting (DuckDB SQL keywords, strings, numbers)
- Auto-complete for table and column names
- Query history (last 50 queries, persisted)
- Ctrl+Enter to execute
- Results as scrollable data table with sortable columns
- Error messages displayed inline below editor
- Execution time displayed after query completes

### 7.3 Chart View

When results contain a timestamp column and numeric columns, offer chart view:

- X-axis: timestamp
- Y-axis: selectable numeric columns (multi-series)
- Chart type: line (default), scatter (optional)
- Zoom: mouse wheel / pinch
- Pan: click-drag
- Tooltip: hover for exact values

---

## 8. Plan View

### 8.1 Layout

```
┌─────────────────────────────────────────────────────┐
│                                    [Waypoint Panel] │
│              INTERACTIVE MAP        │ #1 Takeoff    │
│                                     │ Alt: 50m      │
│    [tap to place waypoints]         │               │
│                                     │ #2 Waypoint   │
│    ○─────○─────○─────○              │ Alt: 100m     │
│    1     2     3     4              │ Speed: 15m/s  │
│                                     │               │
│                                     │ #3 Waypoint   │
│                                     │ Alt: 100m     │
│                                     │               │
│                                     │ [Upload]      │
│                                     │ [Download]    │
│                                     │ [Clear]       │
├─────────────────────────────────────────────────────┤
│ Total: 4 waypoints │ Distance: 2.4 km │ Est: 8 min │
└─────────────────────────────────────────────────────┘
```

### 8.2 Waypoint Interaction

- **Add**: Tap/click on map to place waypoint at tap location
- **Move**: Long-press and drag waypoint marker
- **Edit**: Tap waypoint to open editor (altitude, speed, loiter, command type)
- **Delete**: Swipe or delete button in waypoint panel
- **Reorder**: Drag handle in waypoint list panel
- **Undo/Redo**: Ctrl+Z / Ctrl+Shift+Z

### 8.3 Waypoint Editor Fields

| Field | Type | Default | Validation |
|-------|------|---------|------------|
| Altitude | number (m) | 100 | 0 - 10,000 |
| Speed | number (m/s) | 0 (default) | 0 - 100 |
| Command | dropdown | NAV_WAYPOINT | supported commands |
| Hold time | number (s) | 0 | 0 - 3600 |
| Accept radius | number (m) | 10 | 0 - 1000 |
| Pass radius | number (m) | 0 | 0 - 1000 |
| Frame | dropdown | REL_ALT | GLOBAL, REL_ALT, TERRAIN |

---

## 9. Setup View

### 9.1 Connection Manager

```
┌─────────────────────────────────┐
│  Connection Manager              │
│                                  │
│  Transport: [UDP ▼]             │
│                                  │
│  ── UDP Settings ──             │
│  Bind Address: [0.0.0.0    ]    │
│  Bind Port:    [14550      ]    │
│                                  │
│  [Connect]  [Disconnect]         │
│                                  │
│  ── Status ──                   │
│  State: Connected ●             │
│  Vehicle: ArduPlane (SysID 1)   │
│  Firmware: ArduPilot 4.5.1      │
│  Messages/s: 142                │
│  Uptime: 00:04:32               │
│                                  │
│  ── Recording ──                │
│  Auto-record on arm: [✓]       │
│  [Start Recording] [Stop]       │
│  Current file: helios_2026...   │
│  Size: 12.4 MB                  │
│  Duration: 00:04:32             │
└─────────────────────────────────┘
```

### 9.2 Serial Port Selection

When Serial transport is selected:

- Auto-detect available serial ports
- Dropdown with port name and description
- Baud rate selector: 9600, 19200, 38400, 57600 (default), 115200, 230400, 460800, 921600
- Refresh button to rescan ports

---

## 10. Animations & Transitions

| Interaction | Animation | Duration |
|-------------|-----------|----------|
| View switch (nav) | Crossfade | 200ms |
| Panel open/close | Slide + fade | 250ms |
| Waypoint place | Scale from 0 + bounce | 300ms |
| Connection state change | Badge colour fade | 500ms |
| Alert appear | Slide down + fade in | 200ms |
| Alert dismiss | Fade out | 150ms |
| Telemetry value change | No animation (instant) | 0ms |

**Rule**: Telemetry values never animate. Instant updates only. Animations are for UI chrome, not data.

---

## 11. Keyboard Shortcuts (Desktop)

| Shortcut | Action |
|----------|--------|
| `1` | Switch to Fly View |
| `2` | Switch to Plan View |
| `3` | Switch to Analyse View |
| `4` | Switch to Setup View |
| `Space` | Arm/Disarm toggle (with confirmation) |
| `R` | Start/Stop recording |
| `M` | Cycle map zoom |
| `F` | Centre map on vehicle |
| `Ctrl+Enter` | Execute SQL query (Analyse) |
| `Ctrl+E` | Export Parquet (Analyse) |
| `Escape` | Dismiss dialogs/panels |
