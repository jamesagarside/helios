import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// The six orientations of a full accelerometer calibration, in the order the
/// autopilot requests them. The [posIndex] is the value sent back to the
/// autopilot in `MAV_CMD_ACCELCAL_VEHICLE_POS` to confirm the vehicle is held
/// in that position.
enum AccelCalPosition {
  level(1, 'Level'),
  leftSide(2, 'Left side'),
  rightSide(3, 'Right side'),
  noseDown(4, 'Nose down'),
  noseUp(5, 'Nose up'),
  back(6, 'On its back');

  const AccelCalPosition(this.posIndex, this.label);

  /// Value sent in `MAV_CMD_ACCELCAL_VEHICLE_POS` param1.
  final int posIndex;

  /// Human-readable label.
  final String label;

  /// The target body→world attitude quaternion the vehicle must be held in for
  /// this position, expressed in the MAVLink body frame (X-forward, Y-right,
  /// Z-down) consumed by the Airframe Model's Orientation match.
  ///
  /// Identity is level with the nose at world reference. Each non-level
  /// position is a single 90°/180° rotation about a body axis:
  /// * left side  → roll −90° (left wing down),
  /// * right side → roll +90° (right wing down),
  /// * nose down  → pitch −90° (MAVLink pitch positive is nose-up),
  /// * nose up    → pitch +90°,
  /// * on its back → roll 180°.
  Quaternion get targetPose {
    switch (this) {
      case AccelCalPosition.level:
        return Quaternion.identity();
      case AccelCalPosition.leftSide:
        return Quaternion.axisAngle(Vector3(1, 0, 0), -math.pi / 2);
      case AccelCalPosition.rightSide:
        return Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2);
      case AccelCalPosition.noseDown:
        return Quaternion.axisAngle(Vector3(0, 1, 0), -math.pi / 2);
      case AccelCalPosition.noseUp:
        return Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2);
      case AccelCalPosition.back:
        return Quaternion.axisAngle(Vector3(1, 0, 0), math.pi);
    }
  }
}

/// High-level phase of the 6-point accelerometer calibration.
enum AccelCalPhase {
  /// Not started.
  idle,

  /// Calibration command sent, waiting for the first position prompt.
  starting,

  /// Autopilot has requested a position; waiting for the pilot to hold the
  /// vehicle in it and confirm.
  awaitingPosition,

  /// Pilot confirmed; waiting for the autopilot to acknowledge and request the
  /// next position (or report completion).
  confirming,

  /// Calibration completed successfully.
  success,

  /// Calibration failed.
  failed,

  /// Calibration was cancelled by the pilot.
  cancelled,
}

/// Immutable snapshot of the calibration progress, emitted on every transition.
class AccelCalSnapshot {
  const AccelCalSnapshot({
    required this.phase,
    this.position,
    this.message = '',
    this.completedPositions = const {},
  });

  final AccelCalPhase phase;

  /// The position the autopilot is currently requesting, if any.
  final AccelCalPosition? position;

  /// Latest human-readable status (verbatim autopilot text where available).
  final String message;

  /// Positions the pilot has already confirmed this run.
  final Set<AccelCalPosition> completedPositions;

  bool get isTerminal =>
      phase == AccelCalPhase.success ||
      phase == AccelCalPhase.failed ||
      phase == AccelCalPhase.cancelled;

  bool get isActive =>
      phase == AccelCalPhase.starting ||
      phase == AccelCalPhase.awaitingPosition ||
      phase == AccelCalPhase.confirming;

  AccelCalSnapshot copyWith({
    AccelCalPhase? phase,
    AccelCalPosition? position,
    bool clearPosition = false,
    String? message,
    Set<AccelCalPosition>? completedPositions,
  }) {
    return AccelCalSnapshot(
      phase: phase ?? this.phase,
      position: clearPosition ? null : (position ?? this.position),
      message: message ?? this.message,
      completedPositions: completedPositions ?? this.completedPositions,
    );
  }
}

/// Action the driver (service) should take in response to a state transition.
enum AccelCalAction {
  /// Nothing to do.
  none,

  /// The pilot's position confirmation should be sent
  /// (`MAV_CMD_ACCELCAL_VEHICLE_POS` with the current position index).
  sendPositionConfirm,
}

/// Pure, transport-free state machine for ArduPilot/PX4 6-point accelerometer
/// calibration.
///
/// It is fed verbatim `STATUSTEXT` strings from the autopilot plus pilot
/// confirmation events, and emits an [AccelCalSnapshot] after each. It holds no
/// MAVLink, timers, or I/O so it can be unit-tested with simulated text
/// sequences (the acceptance criterion).
class AccelCalStateMachine {
  AccelCalStateMachine();

  AccelCalSnapshot _snapshot = const AccelCalSnapshot(phase: AccelCalPhase.idle);
  AccelCalSnapshot get snapshot => _snapshot;

  /// Begin a calibration run. Returns the starting snapshot.
  AccelCalSnapshot start() {
    _snapshot = const AccelCalSnapshot(
      phase: AccelCalPhase.starting,
      message: 'Starting accelerometer calibration…',
      completedPositions: {},
    );
    return _snapshot;
  }

  /// Feed an autopilot `STATUSTEXT`. Returns the new snapshot.
  ///
  /// Recognises the six position prompts, the success report, and failure
  /// reports. Unrelated text leaves the state unchanged but updates the
  /// displayed message when it is clearly calibration-related.
  AccelCalSnapshot onStatusText(String text) {
    if (_snapshot.isTerminal) return _snapshot;

    final lower = text.toLowerCase();

    if (_isFailure(lower)) {
      _snapshot = _snapshot.copyWith(
        phase: AccelCalPhase.failed,
        message: text,
      );
      return _snapshot;
    }

    if (_isSuccess(lower)) {
      _snapshot = _snapshot.copyWith(
        phase: AccelCalPhase.success,
        message: text,
        clearPosition: true,
      );
      return _snapshot;
    }

    final pos = _positionFromPrompt(lower);
    if (pos != null) {
      _snapshot = _snapshot.copyWith(
        phase: AccelCalPhase.awaitingPosition,
        position: pos,
        message: text,
      );
      return _snapshot;
    }

    // Calibration-related chatter — surface it without changing phase.
    if (lower.contains('calibrat') || lower.contains('accel')) {
      _snapshot = _snapshot.copyWith(message: text);
    }
    return _snapshot;
  }

  /// The pilot confirms the vehicle is held in the currently-requested
  /// position. Transitions to [AccelCalPhase.confirming] and marks the position
  /// complete. Returns the action the driver must perform.
  ({AccelCalSnapshot snapshot, AccelCalAction action}) confirmPosition() {
    if (_snapshot.phase != AccelCalPhase.awaitingPosition ||
        _snapshot.position == null) {
      return (snapshot: _snapshot, action: AccelCalAction.none);
    }
    final completed = {..._snapshot.completedPositions, _snapshot.position!};
    _snapshot = _snapshot.copyWith(
      phase: AccelCalPhase.confirming,
      completedPositions: completed,
      message: 'Confirming ${_snapshot.position!.label}…',
    );
    return (snapshot: _snapshot, action: AccelCalAction.sendPositionConfirm);
  }

  /// Cancel the run.
  AccelCalSnapshot cancel() {
    _snapshot = _snapshot.copyWith(
      phase: AccelCalPhase.cancelled,
      message: 'Calibration cancelled.',
      clearPosition: true,
    );
    return _snapshot;
  }

  /// Reset back to idle so a fresh run can be started.
  AccelCalSnapshot reset() {
    _snapshot = const AccelCalSnapshot(phase: AccelCalPhase.idle);
    return _snapshot;
  }

  static bool _isSuccess(String lower) =>
      (lower.contains('calibrat') &&
          (lower.contains('success') || lower.contains('done'))) ||
      lower.contains('calibration successful');

  static bool _isFailure(String lower) =>
      lower.contains('fail') &&
      (lower.contains('calibrat') ||
          lower.contains('accel') ||
          lower.contains('cal'));

  /// Match an autopilot position prompt to its [AccelCalPosition].
  ///
  /// Tolerant of the wording variations seen across firmware ("Place vehicle
  /// level", "Place vehicle on its LEFT side", "nose Down", "on its back").
  /// Order matters: nose checks before side checks so "nose down" wins.
  static AccelCalPosition? _positionFromPrompt(String lower) {
    if (!lower.contains('place') && !lower.contains('vehicle')) return null;

    if (lower.contains('nose')) {
      if (lower.contains('down')) return AccelCalPosition.noseDown;
      if (lower.contains('up')) return AccelCalPosition.noseUp;
    }
    if (lower.contains('back')) return AccelCalPosition.back;
    if (lower.contains('left')) return AccelCalPosition.leftSide;
    if (lower.contains('right')) return AccelCalPosition.rightSide;
    if (lower.contains('level')) return AccelCalPosition.level;
    return null;
  }
}
