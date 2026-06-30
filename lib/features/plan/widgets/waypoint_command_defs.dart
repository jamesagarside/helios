import 'package:dart_mavlink/dart_mavlink.dart';

// ─── Param metadata ──────────────────────────────────────────────────────────

/// A single parameter field descriptor.
class ParamDef {
  const ParamDef(this.label, {this.min = 0, this.max = double.infinity});

  final String label;
  final double min;
  final double max;
}

/// Maps a MAVLink command int to its 7 param labels.
/// Null means "not used — hide this param".
const kParamDefs = <int, List<ParamDef?>>{
  MavCmd.navWaypoint: [
    ParamDef('Hold (s)', min: 0, max: 600),
    ParamDef('Radius (m)', min: 0, max: 1000),
    null,
    ParamDef('Yaw (deg)', min: 0, max: 360),
    null, null, null,
  ],
  MavCmd.navTakeoff: [
    null,
    null,
    null,
    ParamDef('Yaw (deg)', min: 0, max: 360),
    null, null, null,
  ],
  MavCmd.navLand: [
    ParamDef('Abort Alt (m)', min: 0, max: 200),
    null,
    null,
    ParamDef('Yaw (deg)', min: 0, max: 360),
    null, null, null,
  ],
  MavCmd.navReturnToLaunch: [null, null, null, null, null, null, null],
  MavCmd.navLoiterUnlim: [
    null,
    ParamDef('Radius (m)', min: 0, max: 2000),
    null,
    ParamDef('Yaw (deg)', min: 0, max: 360),
    null, null, null,
  ],
  MavCmd.navLoiterTime: [
    ParamDef('Time (s)', min: 0, max: 3600),
    ParamDef('Radius (m)', min: 0, max: 2000),
    null,
    ParamDef('Yaw (deg)', min: 0, max: 360),
    null, null, null,
  ],
  MavCmd.navLoiterTurns: [
    ParamDef('Turns', min: 1, max: 100),
    ParamDef('Radius (m)', min: 0, max: 2000),
    null,
    ParamDef('Yaw (deg)', min: 0, max: 360),
    null, null, null,
  ],
  // DO_ commands
  MavCmd.doChangeSpeed: [
    ParamDef('Speed Type (0=air,1=gnd)', min: 0, max: 1),
    ParamDef('Speed (m/s, -1=nc)', min: -1, max: 50),
    ParamDef('Throttle % (-1=nc)', min: -1, max: 100),
    null, null, null, null,
  ],
  MavCmd.doJump: [
    ParamDef('Target Seq', min: 0, max: 9999),
    ParamDef('Repeat Count', min: 0, max: 100),
    null, null, null, null, null,
  ],
  MavCmd.doSetCamTriggDist: [
    ParamDef('Distance (m)', min: 0, max: 10000),
    null, null, null, null, null, null,
  ],
  MavCmd.doMountControl: [
    ParamDef('Pitch (deg)', min: -180, max: 180),
    ParamDef('Roll (deg)', min: -180, max: 180),
    ParamDef('Yaw (deg)', min: -180, max: 180),
    null, null, null, null,
  ],
  MavCmd.doLandStart: [null, null, null, null, null, null, null],
  MavCmd.doGripper: [
    ParamDef('Gripper ID', min: 0, max: 10),
    ParamDef('Action (0=rel,1=grab)', min: 0, max: 1),
    null, null, null, null, null,
  ],
  MavCmd.doPauseContinue: [
    ParamDef('Pause (1) or Continue (0)', min: 0, max: 1),
    null, null, null, null, null, null,
  ],
  MavCmd.navSplineWaypoint: [
    ParamDef('Hold (s)', min: 0, max: 600),
    null,
    null,
    ParamDef('Yaw (deg)', min: 0, max: 360),
    null, null, null,
  ],
  MavCmd.doSetServo: [
    ParamDef('Servo #', min: 1, max: 16),
    ParamDef('PWM (us)', min: 800, max: 2200),
    null, null, null, null, null,
  ],
  MavCmd.doSetRelay: [
    ParamDef('Relay #', min: 0, max: 5),
    ParamDef('State (0=off,1=on)', min: 0, max: 1),
    null, null, null, null, null,
  ],
  MavCmd.doRepeatServo: [
    ParamDef('Servo #', min: 1, max: 16),
    ParamDef('PWM (us)', min: 800, max: 2200),
    ParamDef('Count', min: 1, max: 100),
    ParamDef('Cycle (s)', min: 0, max: 60),
    null, null, null,
  ],
  MavCmd.doRepeatRelay: [
    ParamDef('Relay #', min: 0, max: 5),
    ParamDef('Count', min: 1, max: 100),
    ParamDef('Cycle (s)', min: 0, max: 60),
    null, null, null, null,
  ],
  MavCmd.doFenceEnable: [
    ParamDef('Enable (0=off,1=on,2=floor)', min: 0, max: 2),
    null, null, null, null, null, null,
  ],
  MavCmd.conditionDelay: [
    ParamDef('Delay (s)', min: 0, max: 600),
    null, null, null, null, null, null,
  ],
  MavCmd.conditionDistance: [
    ParamDef('Distance (m)', min: 0, max: 10000),
    null, null, null, null, null, null,
  ],
  MavCmd.conditionYaw: [
    ParamDef('Angle (deg)', min: 0, max: 360),
    ParamDef('Rate (deg/s)', min: 0, max: 90),
    ParamDef('Dir (-1=ccw,1=cw)', min: -1, max: 1),
    ParamDef('Relative (0/1)', min: 0, max: 1),
    null, null, null,
  ],
};

/// Fallback when a command has no specific param defs.
const kFallbackDefs = [
  ParamDef('Param 1'),
  ParamDef('Param 2'),
  ParamDef('Param 3'),
  ParamDef('Param 4'),
  null, // param5 = latitude, not shown in generic fallback
  null, // param6 = longitude
  null, // param7 = altitude shown separately
];

// ─── Command groups ───────────────────────────────────────────────────────────

class CmdEntry {
  const CmdEntry(this.value, this.label);

  final int value;
  final String label;
}

const kNavCommands = <CmdEntry>[
  CmdEntry(MavCmd.navWaypoint, 'Waypoint'),
  CmdEntry(MavCmd.navSplineWaypoint, 'Spline WP'),
  CmdEntry(MavCmd.navTakeoff, 'Takeoff'),
  CmdEntry(MavCmd.navLand, 'Land'),
  CmdEntry(MavCmd.navReturnToLaunch, 'RTL'),
  CmdEntry(MavCmd.navLoiterUnlim, 'Loiter'),
  CmdEntry(MavCmd.navLoiterTime, 'Loiter Time'),
  CmdEntry(MavCmd.navLoiterTurns, 'Loiter Turns'),
];

const kActionCommands = <CmdEntry>[
  CmdEntry(MavCmd.doChangeSpeed, 'Change Speed'),
  CmdEntry(MavCmd.doJump, 'Jump'),
  CmdEntry(MavCmd.doSetCamTriggDist, 'Camera Trigger'),
  CmdEntry(MavCmd.doMountControl, 'Gimbal Control'),
  CmdEntry(MavCmd.doLandStart, 'Land Start'),
  CmdEntry(MavCmd.doGripper, 'Gripper'),
  CmdEntry(MavCmd.doPauseContinue, 'Pause/Continue'),
  CmdEntry(MavCmd.doSetServo, 'Set Servo'),
  CmdEntry(MavCmd.doSetRelay, 'Set Relay'),
  CmdEntry(MavCmd.doRepeatServo, 'Repeat Servo'),
  CmdEntry(MavCmd.doRepeatRelay, 'Repeat Relay'),
  CmdEntry(MavCmd.doFenceEnable, 'Fence Enable'),
  CmdEntry(MavCmd.conditionDelay, 'Condition: Delay'),
  CmdEntry(MavCmd.conditionDistance, 'Condition: Distance'),
  CmdEntry(MavCmd.conditionYaw, 'Condition: Yaw'),
];

/// All known commands (nav + action) in a flat list for value lookup.
const kAllCommands = [...kNavCommands, ...kActionCommands];

// ─── Altitude frame options ────────────────────────────────────────────────────

/// One selectable altitude-frame option.
class FrameEntry {
  const FrameEntry(this.value, this.label);

  final int value;
  final String label;
}

/// The three altitude frames a pilot actually selects between. Internal
/// `*Int` variants (5/6/11) are normalised onto these for display.
const kFrameOptions = <FrameEntry>[
  FrameEntry(MavFrame.globalRelativeAlt, 'Relative (home)'),
  FrameEntry(MavFrame.global, 'Absolute (AMSL)'),
  FrameEntry(MavFrame.globalTerrainAlt, 'Terrain'),
];

/// Collapse the `*Int` MAVLink frame variants onto the user-facing option so
/// the dropdown always has a matching value.
int normaliseFrame(int frame) => switch (frame) {
      MavFrame.globalInt => MavFrame.global,
      MavFrame.globalRelativeAltInt => MavFrame.globalRelativeAlt,
      MavFrame.globalTerrainAltInt => MavFrame.globalTerrainAlt,
      MavFrame.global ||
      MavFrame.globalRelativeAlt ||
      MavFrame.globalTerrainAlt =>
        frame,
      _ => MavFrame.globalRelativeAlt,
    };
