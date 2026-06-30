/// Pure, transport-free logic for ESC (Electronic Speed Controller)
/// calibration.
///
/// Two flows are supported, mirroring the autopilot's own capabilities:
///
/// * **Semi-automatic** — set the `ESC_CALIBRATION` parameter to the
///   "calibrate on next boot" value, then power-cycle the vehicle. On the next
///   boot (battery freshly connected) the autopilot passes the radio's full
///   throttle range straight through to the ESCs so they learn their min/max
///   endpoints, then auto-resets the parameter. This requires an explicit
///   power-cycle the GCS cannot perform on the pilot's behalf, so the flow is
///   built around clear, gated instructions.
///
/// * **Manual endpoints** — directly editing the PWM output limits
///   (`MOT_PWM_MIN`/`MOT_PWM_MAX`) and the spin thresholds
///   (`MOT_SPIN_ARM`/`MOT_SPIN_MIN`/`MOT_SPIN_MAX`). These are normal
///   parameters and need no power-cycle.
///
/// Digital protocols (DShot) and CAN ESCs are factory-calibrated and have no
/// analog throttle endpoints to learn, so calibration is neither needed nor
/// possible — [EscProtocol] classifies these so the UI can say so.
///
/// This file holds no MAVLink, timers, or I/O so the flow logic can be
/// unit-tested without live hardware (the issue's acceptance criterion).
library;

/// The ESC output protocol, derived from the `MOT_PWM_TYPE` parameter.
///
/// Values follow ArduPilot's `MOT_PWM_TYPE` enumeration. Anything we don't
/// explicitly recognise is treated as [unknown] and handled conservatively
/// (calibration offered with a caveat rather than silently skipped).
enum EscProtocol {
  /// Standard 1000–2000µs PWM. Calibratable.
  normalPwm(0, 'Normal PWM', calibratable: true),

  /// OneShot — still an analog pulse train. Calibratable.
  oneShot(1, 'OneShot', calibratable: true),

  /// OneShot125. Calibratable.
  oneShot125(2, 'OneShot125', calibratable: true),

  /// Brushed motors driven by a PWM duty cycle. No ESC endpoints to learn.
  brushed(3, 'Brushed', calibratable: false),

  /// DShot150 — digital. Factory-calibrated, no calibration possible.
  dShot150(4, 'DShot150', calibratable: false),

  /// DShot300 — digital.
  dShot300(5, 'DShot300', calibratable: false),

  /// DShot600 — digital.
  dShot600(6, 'DShot600', calibratable: false),

  /// DShot1200 — digital.
  dShot1200(7, 'DShot1200', calibratable: false),

  /// Explicit PWM range mode. Calibratable.
  pwmRange(8, 'PWM Range', calibratable: true),

  /// Unrecognised protocol value. Treated as calibratable-with-caution.
  unknown(-1, 'Unknown', calibratable: true);

  const EscProtocol(this.value, this.label, {required this.calibratable});

  /// The `MOT_PWM_TYPE` parameter value, or -1 for [unknown].
  final int value;

  /// Human-readable name for display.
  final String label;

  /// Whether semi-automatic / endpoint calibration applies to this protocol.
  ///
  /// Digital (DShot) and brushed outputs have no analog endpoints to learn, so
  /// the calibration flow is skipped and explained instead.
  final bool calibratable;

  /// Whether this is a digital (DShot) protocol, for tailored messaging.
  bool get isDigital =>
      this == dShot150 ||
      this == dShot300 ||
      this == dShot600 ||
      this == dShot1200;

  /// Resolve a [EscProtocol] from a raw `MOT_PWM_TYPE` value.
  static EscProtocol fromValue(num? raw) {
    if (raw == null) return EscProtocol.unknown;
    final v = raw.round();
    for (final p in EscProtocol.values) {
      if (p != EscProtocol.unknown && p.value == v) return p;
    }
    return EscProtocol.unknown;
  }
}

/// Parameter identifiers used by the calibration flow.
abstract final class EscParams {
  /// ESC output protocol selector. Read to detect DShot/brushed/CAN.
  static const pwmType = 'MOT_PWM_TYPE';

  /// Semi-automatic calibration trigger. Setting this to
  /// [semiAutoCalibrateValue] then rebooting performs the calibration.
  static const calibration = 'ESC_CALIBRATION';

  /// Minimum PWM output endpoint (µs).
  static const pwmMin = 'MOT_PWM_MIN';

  /// Maximum PWM output endpoint (µs).
  static const pwmMax = 'MOT_PWM_MAX';

  /// Throttle output when armed but idle (0..1 of the PWM range).
  static const spinArm = 'MOT_SPIN_ARM';

  /// Minimum throttle that produces motor spin (0..1).
  static const spinMin = 'MOT_SPIN_MIN';

  /// Maximum throttle output (0..1).
  static const spinMax = 'MOT_SPIN_MAX';

  /// The ordered list of manually-editable endpoint parameters.
  static const editableEndpoints = [pwmMin, pwmMax, spinArm, spinMin, spinMax];

  /// `ESC_CALIBRATION` value that requests a calibration on the next boot.
  ///
  /// 0 = normal, 1 = calibrate at startup (one-shot), 2 = saved value,
  /// 3 = auto-calibrate on next boot then reset to 0.
  static const semiAutoCalibrateValue = 3.0;

  /// `ESC_CALIBRATION` value for normal (no calibration) operation.
  static const normalValue = 0.0;
}

/// Phase of the semi-automatic calibration flow.
enum EscCalPhase {
  /// Nothing in progress.
  idle,

  /// The pilot must explicitly confirm all propellers are removed before any
  /// throttle can be commanded. Mandatory gate.
  awaitingPropsOff,

  /// Props-off confirmed; ready to arm the semi-automatic flow.
  ready,

  /// `ESC_CALIBRATION` has been written; the pilot must now power-cycle the
  /// vehicle (disconnect and reconnect the battery) to perform the calibration.
  awaitingPowerCycle,

  /// The flow finished (parameter armed and instructions delivered) or was
  /// cancelled.
  done,
}

/// Immutable snapshot of the semi-automatic calibration flow.
class EscCalSnapshot {
  const EscCalSnapshot({
    required this.phase,
    this.propsOff = false,
    this.message = '',
  });

  final EscCalPhase phase;

  /// Whether the mandatory props-off confirmation has been given.
  final bool propsOff;

  /// Latest human-readable guidance.
  final String message;

  /// Whether throttle output is allowed to be commanded in this state.
  ///
  /// Hard safety invariant: throttle is only ever permissible once the pilot
  /// has confirmed props are off.
  bool get throttleAllowed => propsOff;

  EscCalSnapshot copyWith({
    EscCalPhase? phase,
    bool? propsOff,
    String? message,
  }) {
    return EscCalSnapshot(
      phase: phase ?? this.phase,
      propsOff: propsOff ?? this.propsOff,
      message: message ?? this.message,
    );
  }
}

/// Action the driver (UI/service) should take after a transition.
enum EscCalAction {
  /// Nothing to do.
  none,

  /// Write `ESC_CALIBRATION = [EscParams.semiAutoCalibrateValue]` to the FC.
  armCalibrationParam,

  /// Write `ESC_CALIBRATION = [EscParams.normalValue]` to the FC (restore).
  restoreCalibrationParam,
}

/// Pure state machine for the semi-automatic ESC calibration flow.
///
/// It enforces the safety ordering — no calibration can be armed until the
/// pilot has confirmed propellers are removed — and tells the driver which
/// parameter writes to perform. It performs no I/O.
class EscCalStateMachine {
  EscCalStateMachine();

  EscCalSnapshot _snapshot = const EscCalSnapshot(phase: EscCalPhase.idle);
  EscCalSnapshot get snapshot => _snapshot;

  /// Begin the flow. Always lands on the mandatory props-off gate.
  EscCalSnapshot start() {
    _snapshot = const EscCalSnapshot(
      phase: EscCalPhase.awaitingPropsOff,
      propsOff: false,
      message: 'Remove all propellers, then confirm to continue.',
    );
    return _snapshot;
  }

  /// The pilot confirms (or un-confirms) that all propellers are removed.
  ///
  /// Confirming advances the gate to [EscCalPhase.ready]; un-confirming from a
  /// pre-arm phase returns to the gate. It is rejected once the parameter has
  /// been armed (the vehicle is mid-flow) so the safety state can't be silently
  /// dropped underneath an armed calibration.
  EscCalSnapshot setPropsOff(bool value) {
    if (_snapshot.phase == EscCalPhase.awaitingPowerCycle ||
        _snapshot.phase == EscCalPhase.done) {
      return _snapshot;
    }
    if (value) {
      _snapshot = _snapshot.copyWith(
        phase: EscCalPhase.ready,
        propsOff: true,
        message: 'Propellers confirmed off. You may arm the calibration.',
      );
    } else {
      _snapshot = _snapshot.copyWith(
        phase: EscCalPhase.awaitingPropsOff,
        propsOff: false,
        message: 'Remove all propellers, then confirm to continue.',
      );
    }
    return _snapshot;
  }

  /// Arm the semi-automatic calibration. Only valid from [EscCalPhase.ready]
  /// (i.e. after props-off confirmation). Returns the parameter-write action
  /// the driver must perform.
  ({EscCalSnapshot snapshot, EscCalAction action}) armCalibration() {
    if (_snapshot.phase != EscCalPhase.ready || !_snapshot.propsOff) {
      return (snapshot: _snapshot, action: EscCalAction.none);
    }
    _snapshot = _snapshot.copyWith(
      phase: EscCalPhase.awaitingPowerCycle,
      message: 'Calibration armed. Disconnect the battery, wait a moment, '
          'then reconnect it to run the calibration. The autopilot will beep '
          'to confirm the endpoints were captured.',
    );
    return (snapshot: _snapshot, action: EscCalAction.armCalibrationParam);
  }

  /// The pilot reports the power-cycle is complete. Closes the flow.
  EscCalSnapshot completePowerCycle() {
    if (_snapshot.phase != EscCalPhase.awaitingPowerCycle) return _snapshot;
    _snapshot = _snapshot.copyWith(
      phase: EscCalPhase.done,
      message: 'Calibration complete. Verify motor direction in the Motors '
          'tab before flight.',
    );
    return _snapshot;
  }

  /// Abort the flow. If the parameter was already armed, asks the driver to
  /// restore it to normal so the vehicle doesn't recalibrate unexpectedly.
  ({EscCalSnapshot snapshot, EscCalAction action}) cancel() {
    final wasArmed = _snapshot.phase == EscCalPhase.awaitingPowerCycle;
    _snapshot = const EscCalSnapshot(
      phase: EscCalPhase.idle,
      propsOff: false,
      message: '',
    );
    return (
      snapshot: _snapshot,
      action: wasArmed
          ? EscCalAction.restoreCalibrationParam
          : EscCalAction.none,
    );
  }

  /// Reset to idle without side effects.
  EscCalSnapshot reset() {
    _snapshot = const EscCalSnapshot(phase: EscCalPhase.idle);
    return _snapshot;
  }
}
