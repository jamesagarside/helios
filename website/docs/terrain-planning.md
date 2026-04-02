# Terrain Planning

Helios integrates SRTM (Shuttle Radar Topography Mission) digital elevation model data into the Plan View to provide terrain-aware mission planning. This allows pilots to visualize ground elevation along a planned route and verify safe altitude clearance before uploading a mission.

## Overview

When a mission is loaded or edited in the Plan View, Helios samples the terrain elevation beneath each waypoint and along the connecting legs. The result is displayed as a terrain profile chart below the map, showing the relationship between planned flight altitude and ground level.

## SRTM Digital Elevation Model

Helios uses NASA SRTM elevation data, which covers most of the Earth's land surface between 60 degrees north and 56 degrees south latitude.

Two resolutions are supported:

| Dataset | Grid Size | Resolution | Coverage |
|---|---|---|---|
| SRTM3 | 1201 x 1201 samples per tile | ~90m (3 arc-seconds) | Global |
| SRTM1 | 3601 x 3601 samples per tile | ~30m (1 arc-second) | United States, select regions |

Each tile covers a 1-degree-by-1-degree area and is identified by the latitude and longitude of its south-west corner (for example, `N51W002.hgt` covers the area from 51N 2W to 52N 1W).

## DEM Tile Loading

Tiles are loaded on demand as the mission route requires them. The loading process:

1. Determine which 1-degree tiles are intersected by the planned route.
2. Check the local tile cache for each required tile.
3. Download missing tiles from the configured SRTM server if network is available.
4. Parse the `.hgt` file as a flat array of signed 16-bit integers in big-endian byte order.

Each `.hgt` file contains elevation values in metres above the WGS84 geoid (mean sea level). A value of -32768 indicates a void (no data) in the dataset.

### File sizes

| Dataset | Samples | File Size |
|---|---|---|
| SRTM3 | 1,442,401 (1201 x 1201) | 2,884,802 bytes (~2.75 MB) |
| SRTM1 | 12,967,201 (3601 x 3601) | 25,934,402 bytes (~24.7 MB) |

## Bilinear Interpolation

Querying the elevation at an arbitrary latitude/longitude typically falls between grid sample points. Helios uses bilinear interpolation to estimate the elevation from the four surrounding grid samples.

Given a query point at fractional grid coordinates `(x, y)` within a cell bounded by four known elevations `Q11`, `Q12`, `Q21`, `Q22`:

```
elevation = Q11 * (1 - x) * (1 - y)
           + Q21 * x * (1 - y)
           + Q12 * (1 - x) * y
           + Q22 * x * y
```

This provides sub-grid accuracy without the computational cost of higher-order interpolation, which is sufficient for mission planning where the horizontal error of the SRTM dataset itself (typically 10-20m) exceeds the interpolation error.

## Terrain Profile Visualization

The Plan View displays a terrain profile chart that shows:

- **Ground elevation** (brown/tan filled area) along the planned route.
- **Planned flight altitude** (blue line) at each waypoint, with linear interpolation between waypoints.
- **Altitude reference**: Either AGL (above ground level) or AMSL (above mean sea level), matching the mission altitude frame.
- **Horizontal axis**: Distance along the route in metres or kilometres.
- **Vertical axis**: Elevation in metres.

The profile updates in real time as waypoints are added, moved, or removed.

## Altitude Clearance Checking

Helios checks the planned altitude against the terrain elevation at regular intervals along each mission leg. The checks performed are:

| Check | Description | Severity |
|---|---|---|
| Terrain collision | Planned altitude falls below terrain elevation | Error (red) |
| Minimum clearance | Planned altitude is within a configurable minimum clearance above terrain | Warning (amber) |
| Void data | SRTM tile contains void values along the route (no elevation data available) | Info (grey) |

When a clearance violation is detected, the affected leg is highlighted on both the map and the terrain profile chart. The waypoint editor also flags the specific waypoints involved.

The default minimum clearance is 30 metres AGL. This value can be adjusted in the Plan View settings.

## How Terrain Data Is Used in Mission Planning

### AGL Altitude Missions

When planning a mission with AGL (above ground level) altitudes, the terrain elevation is added to the desired AGL altitude to compute the AMSL altitude sent to the flight controller. This means the vehicle maintains a consistent height above the ground even as terrain rises and falls.

For example, a waypoint at 50m AGL over terrain at 200m AMSL results in a commanded altitude of 250m AMSL.

### Terrain-Following Survey Patterns

Polygon survey and corridor scan patterns can use terrain data to adjust the altitude of each generated waypoint independently, maintaining consistent ground sampling distance (GSD) for mapping and inspection missions.

### Altitude Frame Reference

The terrain profile visualization respects the altitude frame set on the mission:

| Frame | Altitude Reference | Terrain Use |
|---|---|---|
| MAV_FRAME_GLOBAL | AMSL (above mean sea level) | Terrain shown for context; clearance checked |
| MAV_FRAME_GLOBAL_RELATIVE_ALT | AGL (relative to home) | Terrain used to compute required AMSL altitude |
| MAV_FRAME_GLOBAL_TERRAIN_ALT | AGL (relative to terrain at each point) | Terrain used per-waypoint for AMSL conversion |

## Limitations

- SRTM coverage does not extend beyond 60N or 56S latitude. Missions in polar regions will not have terrain data.
- SRTM data reflects terrain elevation at the time of the 2000 shuttle mission. Significant terrain changes since then (construction, mining, erosion) are not reflected.
- Void areas (typically steep mountain slopes, water bodies) produce no elevation data. Helios marks these as "no data" in the profile.
- Terrain data requires either pre-cached tiles or network access. Air-gapped operation requires pre-downloading tiles for the operating area.
