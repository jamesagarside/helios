# Corridor Scan

The corridor scan is a mission pattern that generates parallel flight lines along a polyline centerline. It is designed for inspecting or mapping linear features such as power lines, roads, pipelines, rivers, and railways.

## Use Cases

- **Power line inspection** -- Fly along a transmission line corridor capturing imagery of towers and cables.
- **Road surveys** -- Map road surfaces and surrounding infrastructure for condition assessment.
- **Pipeline monitoring** -- Survey oil, gas, or water pipelines for leak detection or vegetation encroachment.
- **River and waterway mapping** -- Capture imagery along a river corridor for environmental monitoring.
- **Railway inspection** -- Inspect rail lines and embankments for maintenance planning.
- **Corridor mapping** -- General photogrammetric mapping of any linear feature.

## How It Works

The corridor scan generator takes a polyline centerline (drawn on the Plan View map) and produces a complete set of waypoints that cover the corridor with parallel flight lines.

### Algorithm

1. **Input**: A polyline of at least 2 points defines the corridor centerline. The corridor extends equally on both sides of this line.

2. **Line spacing**: The generator computes the distance between parallel flight lines from the corridor width and the overlap percentage:

   ```
   line_spacing = corridor_width * (1.0 - overlap_percent / 100)
   ```

3. **Polyline offset**: Each flight line is created by offsetting the centerline perpendicular to its direction by a computed distance. The offset uses the bearing at each vertex, with averaged bearings at interior points to handle direction changes smoothly.

4. **Snake pattern**: Flight lines are connected in a serpentine (boustrophedon) pattern. Even-numbered lines follow the polyline direction; odd-numbered lines follow the reverse direction. This minimizes transit distance between lines.

5. **Turnaround waypoints**: At the start and end of each flight line (except the first and last), extra waypoints are placed beyond the corridor boundary. These give the vehicle space to decelerate, turn, and accelerate before entering the next survey line, ensuring stable flight and consistent image overlap within the corridor.

6. **Camera triggers**: If a camera trigger distance is specified, the generator inserts a `DO_SET_CAM_TRIGG_DIST` command at the start of the mission (to begin triggering) and another at the end (to stop triggering). The flight controller fires the camera at the specified distance interval along the flight path.

### Output

The generator produces a list of mission items containing:

- `DO_SET_CAM_TRIGG_DIST` -- Start camera triggering (if configured)
- `NAV_WAYPOINT` -- Navigation waypoints for each flight line and turnaround
- `DO_SET_CAM_TRIGG_DIST` (param1=0) -- Stop camera triggering (if configured)

All waypoints use the configured altitude AGL.

## Configuration

The corridor scan is configured through the Corridor Scan Dialog in Plan View (Templates menu).

| Parameter | Range | Default | Description |
|---|---|---|---|
| Corridor Width | 10 -- 500 m | -- | Total width of the survey corridor, centered on the polyline |
| Line Overlap | 60 -- 90% | 70% | Overlap between adjacent flight lines |
| Altitude AGL | -- | -- | Flight altitude above ground level in metres |
| Camera Trigger Distance | 0+ m | 0 (disabled) | Distance interval for camera triggering. Set to 0 to disable. |
| Turnaround Distance | 0+ m | 20 m | Extra distance beyond the corridor for vehicle turnaround |
| Start From End | on/off | off | Begin scanning from the last point of the polyline instead of the first |

### Parameter Guidance

**Corridor width** should match the width of the feature being surveyed plus a margin. For a 30m-wide road, a corridor width of 50-80m provides coverage of the road and its immediate surroundings.

**Line overlap** controls redundancy. Higher overlap produces more flight lines and longer flight times but increases the reliability of photogrammetric processing. For photogrammetry, 70-80% is typical. For visual inspection where full overlap is not required, 60% may be sufficient.

**Camera trigger distance** depends on the camera, lens, flight speed, and desired ground sampling distance (GSD). Calculate it based on:

```
trigger_distance = ground_footprint_along_track * (1 - forward_overlap)
```

**Turnaround distance** should be large enough for the vehicle to complete a 180-degree turn at its cruise speed. 20m is suitable for most multirotor aircraft. Fixed-wing vehicles may require 50-100m or more depending on their minimum turn radius.

## UI Location

1. Open the **Plan View**.
2. Draw a polyline on the map to define the corridor centerline (minimum 2 points).
3. Open the **Templates** menu.
4. Select **Corridor Scan**.
5. Configure the parameters in the dialog.
6. Press **Generate** to create the mission waypoints.

The generated waypoints replace the current mission. They can be edited, reordered, or modified like any other mission waypoints after generation.

## Example

A power line inspection with the following settings:

| Parameter | Value |
|---|---|
| Corridor Width | 60 m |
| Line Overlap | 70% |
| Altitude AGL | 40 m |
| Camera Trigger Distance | 10 m |
| Turnaround Distance | 25 m |

This produces flight lines spaced 18m apart (60m * 0.30), covering the 60m corridor. With a 5km power line, this generates approximately 4 flight lines with turnarounds, plus camera trigger commands at the start and end of the mission.
