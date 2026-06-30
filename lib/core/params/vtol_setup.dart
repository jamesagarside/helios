/// VTOL / Quadplane setup core logic.
///
/// Pure, UI-free model for the VTOL panel: the `Q_ENABLE` gating decision, the
/// `Q_OPTIONS` behaviour bitmask, the conditional-tilt rule, and the grouped
/// definitions of the editable `Q_*` parameters. Keeping this here lets the
/// dangerous bits (a wrong bitmask silently changes VTOL behaviour; a wrong
/// gate hides the panel on the vehicles it exists for) be pinned by unit tests.
///
/// See `docs/adr/0003-gate-vtol-panel-on-q-enable.md` and the **Quadplane**
/// glossary entry in `CONTEXT.md`.
library;

/// How the VTOL tab should present itself, derived purely from the parameter
/// cache. ArduPilot quadplanes commonly advertise `MAV_TYPE_FIXED_WING`, so the
/// decision is driven by `Q_ENABLE`, never by the heartbeat vehicle type.
enum VtolGate {
  /// Params not yet loaded — hide the tab until the cache arrives (no flash).
  paramsUnloaded,

  /// `Q_ENABLE` absent — non-quadplane firmware. Hide the tab entirely.
  hidden,

  /// `Q_ENABLE == 0` — ArduPilot Plane with quadplane off. Show an
  /// enable-prompt so a fresh build is discoverable.
  enablePrompt,

  /// `Q_ENABLE == 1` — show the full panel.
  fullPanel,
}

/// The `Q_ENABLE` parameter id.
const String kQEnableParam = 'Q_ENABLE';

/// The `Q_OPTIONS` behaviour-bitmask parameter id.
const String kQOptionsParam = 'Q_OPTIONS';

/// The `Q_TILT_MASK` parameter id — non-zero only on a real tiltrotor.
const String kQTiltMaskParam = 'Q_TILT_MASK';

/// Decide how the VTOL tab should present itself given the parameter cache.
///
/// [paramsLoaded] is whether the cache has been populated at all (used to
/// suppress the empty flash before the first param sweep lands). [qEnable] is
/// the raw `Q_ENABLE` value, or null when the parameter is absent.
VtolGate vtolGateFor({required bool paramsLoaded, required double? qEnable}) {
  if (!paramsLoaded) return VtolGate.paramsUnloaded;
  if (qEnable == null) return VtolGate.hidden;
  return qEnable.round() == 0 ? VtolGate.enablePrompt : VtolGate.fullPanel;
}

/// Whether the VTOL tab should appear at all (any state other than hidden /
/// unloaded). Convenience over [vtolGateFor] for the tab-list builder.
bool vtolTabVisible({required bool paramsLoaded, required double? qEnable}) {
  final gate = vtolGateFor(paramsLoaded: paramsLoaded, qEnable: qEnable);
  return gate == VtolGate.enablePrompt || gate == VtolGate.fullPanel;
}

/// Whether the tilt section should be shown automatically.
///
/// `Q_TILT_*` are only meaningful on a tiltrotor, identified by a present and
/// non-zero `Q_TILT_MASK`. When this is false the panel still offers a
/// "show tilt settings anyway" override (a pragmatic default, not a lockout).
bool tiltAutoVisible(double? qTiltMask) {
  if (qTiltMask == null) return false;
  return qTiltMask.round() != 0;
}

// ─── Q_OPTIONS bitmask ───────────────────────────────────────────────────────

/// A single selectable `Q_OPTIONS` behaviour bit.
class QOptionBit {
  const QOptionBit(this.bit, this.label, this.description);

  /// The bit value within the `Q_OPTIONS` bitmask.
  final int bit;

  /// Short, human-readable behaviour name.
  final String label;

  /// One-line explanation of what enabling the bit does.
  final String description;
}

/// ArduPilot Plane `Q_OPTIONS` behaviour bits, in display order.
///
/// Sourced from the ArduPilot Plane `Q_OPTIONS` parameter bitmask. Each entry
/// toggles one quadplane behaviour; the meaning of a wrong bit is a silent
/// change to how the aircraft transitions, assists, or lands, so the list is
/// pinned by tests.
const List<QOptionBit> qOptionBits = [
  QOptionBit(1 << 0, 'Level Transition',
      'Hold wings level through forward transition.'),
  QOptionBit(1 << 1, 'Allow FW Takeoff',
      'Allow fixed-wing takeoff modes on a quadplane.'),
  QOptionBit(1 << 2, 'Allow FW Land',
      'Allow fixed-wing landing modes on a quadplane.'),
  QOptionBit(1 << 3, 'Respect Takeoff Frame',
      'Use the takeoff command altitude frame as given.'),
  QOptionBit(1 << 4, 'Use QRTL',
      'Use QRTL instead of fixed-wing RTL on return.'),
  QOptionBit(1 << 5, 'Use Hover Throttle for Land',
      'Use the hover throttle estimate during VTOL land.'),
  QOptionBit(1 << 6, 'Force QRTL',
      'Force QRTL mode for all RTL events.'),
  QOptionBit(1 << 7, 'Tilt Rotor Tilt in Wait',
      'Tilt the rotors forward while waiting to take off.'),
  QOptionBit(1 << 8, 'Airmode on Arm',
      'Enable air-mode immediately on arming.'),
  QOptionBit(1 << 9, 'Disarmed Tilt',
      'Allow rotor tilt control while disarmed.'),
  QOptionBit(1 << 10, 'Delay Spoolup',
      'Delay motor spool-up until after arming completes.'),
  QOptionBit(1 << 11, 'Disable Synthetic Airspeed (FW)',
      'Disable synthetic airspeed while in fixed-wing flight.'),
  QOptionBit(1 << 12, 'Disable Ground Effect Comp',
      'Disable ground-effect compensation on landing.'),
  QOptionBit(1 << 13, 'Ignore Forward Flight Climb Limits',
      'Ignore forward-flight climb-rate limits.'),
  QOptionBit(1 << 14, 'Allow continue mission on RC failsafe',
      'Continue an auto mission through an RC failsafe.'),
  QOptionBit(1 << 15, 'Ena Repos Loiter',
      'Allow stick repositioning during VTOL loiter.'),
  QOptionBit(1 << 16, 'Ena Approach Mode',
      'Enable the dedicated VTOL approach mode before land.'),
  QOptionBit(1 << 17, 'Allow Stabilize VTOL Throttle',
      'Allow direct VTOL throttle in stabilize modes.'),
  QOptionBit(1 << 18, 'Mtrs Only Quad Throttle',
      'Quad motors only respond to throttle in quad modes.'),
  QOptionBit(1 << 19, 'Scale FF by Voltage',
      'Scale attitude feed-forward by battery voltage.'),
];

/// Immutable view over a `Q_OPTIONS` bitmask value with decode/encode helpers.
class QOptionsMask {
  const QOptionsMask(this.value);

  /// Construct from a parameter value (the FC stores ints as doubles).
  factory QOptionsMask.fromParam(double raw) => QOptionsMask(raw.round());

  /// The raw integer bitmask value.
  final int value;

  /// The parameter value to write back to the flight controller.
  double get paramValue => value.toDouble();

  /// Whether a specific behaviour [bit] is currently enabled.
  bool isEnabled(int bit) => (value & bit) != 0;

  /// The set of behaviour bits explicitly enabled.
  Set<int> get enabledBits =>
      qOptionBits.where((o) => isEnabled(o.bit)).map((o) => o.bit).toSet();

  /// Toggle a single behaviour [bit] on or off, returning a new mask.
  QOptionsMask toggle(int bit, bool enabled) {
    final base = enabled ? (value | bit) : (value & ~bit);
    return QOptionsMask(base);
  }

  @override
  bool operator ==(Object other) =>
      other is QOptionsMask && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'QOptionsMask(0x${value.toRadixString(16)})';
}

// ─── Editable Q_* parameter groups ───────────────────────────────────────────

/// One editable `Q_*` parameter with display metadata.
class VtolParam {
  const VtolParam(this.id, this.label, this.unit, {this.help = '', this.enumOptions});

  /// The parameter id (e.g. `Q_TRANSITION_MS`).
  final String id;

  /// Human-readable label.
  final String label;

  /// Unit suffix (empty for unitless).
  final String unit;

  /// Optional one-line inline help.
  final String help;

  /// When non-null, the parameter is an enum and these are its choices.
  final Map<int, String>? enumOptions;

  /// Whether this parameter is presented as an enum dropdown.
  bool get isEnum => enumOptions != null;
}

/// ArduPilot Plane `Q_FRAME_CLASS` values (the quadplane motor layout class).
const Map<int, String> qFrameClasses = {
  0: 'Undefined',
  1: 'Quad',
  2: 'Hexa',
  3: 'Octa',
  4: 'OctaQuad',
  5: 'Y6',
  7: 'Tri',
  10: 'Tailsitter',
  12: 'Dodeca-Hexa',
  15: 'Single/Dual Motor (tailsitter)',
  17: 'Quad + Single tilt',
};

/// ArduPilot Plane `Q_FRAME_TYPE` values.
const Map<int, String> qFrameTypes = {
  0: 'Plus (+)',
  1: 'X',
  2: 'V',
  3: 'H',
  4: 'V-Tail',
  5: 'A-Tail',
  10: 'Y6B',
  11: 'Y6F',
  12: 'BetaFlightX',
  13: 'DJIX',
  14: 'CW X',
};

/// Transition & assist parameters (Setup tier, bench-safe).
const List<VtolParam> qTransitionAssistParams = [
  VtolParam('Q_TRANSITION_MS', 'Transition time', 'ms',
      help: 'Time to ramp down lift motors during forward transition.'),
  VtolParam('Q_ASSIST_SPEED', 'Assist speed', 'm/s',
      help: 'Airspeed below which VTOL motors assist fixed-wing flight. '
          '0 disables speed-based assist.'),
  VtolParam('Q_ASSIST_ANGLE', 'Assist angle', 'deg',
      help: 'Attitude error past which VTOL motors assist. 0 disables.'),
  VtolParam('Q_ASSIST_ALT', 'Assist altitude', 'm',
      help: 'Height below which VTOL motors assist. 0 disables.'),
];

/// Tiltrotor parameters (Setup tier, shown only for a real tiltrotor — see
/// [tiltAutoVisible]).
const List<VtolParam> qTiltParams = [
  VtolParam('Q_TILT_MASK', 'Tilt motor mask', '',
      help: 'Bitmask of motors that tilt. 0 means no tiltrotor.'),
  VtolParam('Q_TILT_RATE_UP', 'Tilt rate (up)', 'deg/s',
      help: 'Rate the motors tilt towards vertical.'),
  VtolParam('Q_TILT_RATE_DN', 'Tilt rate (down)', 'deg/s',
      help: 'Rate the motors tilt towards horizontal.'),
  VtolParam('Q_TILT_MAX', 'Tilt max angle', 'deg',
      help: 'Maximum tilt angle in fixed-wing assisted flight.'),
  VtolParam('Q_TILT_TYPE', 'Tilt type', '', enumOptions: {
    0: 'Continuous',
    1: 'Binary',
    2: 'Vectored Yaw',
    3: 'Bicopter',
  }),
];

/// VTOL rate PID parameters (Advanced tuning tier — `Q_A_RAT_*`).
const List<VtolParam> qRatePidParams = [
  VtolParam('Q_A_RAT_RLL_P', 'Roll rate P', ''),
  VtolParam('Q_A_RAT_RLL_I', 'Roll rate I', ''),
  VtolParam('Q_A_RAT_RLL_D', 'Roll rate D', ''),
  VtolParam('Q_A_RAT_PIT_P', 'Pitch rate P', ''),
  VtolParam('Q_A_RAT_PIT_I', 'Pitch rate I', ''),
  VtolParam('Q_A_RAT_PIT_D', 'Pitch rate D', ''),
  VtolParam('Q_A_RAT_YAW_P', 'Yaw rate P', ''),
  VtolParam('Q_A_RAT_YAW_I', 'Yaw rate I', ''),
  VtolParam('Q_A_RAT_YAW_D', 'Yaw rate D', ''),
];

/// VTOL angle P parameters (Advanced tuning tier — `Q_A_ANG_*_P`).
const List<VtolParam> qAnglePidParams = [
  VtolParam('Q_A_ANG_RLL_P', 'Roll angle P', ''),
  VtolParam('Q_A_ANG_PIT_P', 'Pitch angle P', ''),
  VtolParam('Q_A_ANG_YAW_P', 'Yaw angle P', ''),
];

/// The ArduPilot Plane `QAUTOTUNE` custom flight-mode number.
const int kQAutotuneMode = 22;

/// VTOL ("Q") flight-mode numbers on ArduPilot Plane (QSTABILIZE..QACRO).
///
/// Used to decide whether QAUTOTUNE is likely to help: it only tunes while the
/// aircraft is already flying in a VTOL mode.
const Set<int> kVtolModeNumbers = {17, 18, 19, 20, 21, 22, 23};

/// Whether [modeNumber] is one of the VTOL ("Q") flight modes.
bool isVtolMode(int modeNumber) => kVtolModeNumbers.contains(modeNumber);

/// Whether engaging QAUTOTUNE right now is likely to actually tune the vehicle.
///
/// QAUTOTUNE only does useful work while the aircraft is airborne and already
/// in a VTOL mode. When this returns false the panel does **not** hard-disable
/// the button — it shows a modal explaining why it usually won't help, with an
/// "Engage anyway" escape hatch (the pragmatic-override pattern from ADR 0003).
bool qAutotuneLikelyEffective({required bool armed, required int currentMode}) {
  return armed && isVtolMode(currentMode);
}

/// Live QAUTOTUNE progress, decoded from autopilot `STATUSTEXT` lines.
enum QAutotuneProgress {
  /// No QAUTOTUNE status seen yet (or unrelated text).
  idle,

  /// A tune is running — gains are being learned.
  tuning,

  /// The tune produced gains that were saved to the flight controller.
  saved,

  /// The tune was failed/aborted by the autopilot.
  failed,
}

/// Classify an autopilot `STATUSTEXT` line for QAUTOTUNE progress.
///
/// ArduPilot emits lines such as "AutoTune: Started", "AutoTune: Saved gains"
/// and "AutoTune: Failed". Matching is case-insensitive and tolerant of the
/// "QAutoTune"/"AutoTune" prefix variants. Returns null for unrelated text so
/// callers can keep their previous state.
QAutotuneProgress? classifyQAutotuneStatus(String text) {
  final lower = text.toLowerCase();
  if (!lower.contains('autotune')) return null;
  if (lower.contains('saved')) return QAutotuneProgress.saved;
  if (lower.contains('fail') || lower.contains('abort')) {
    return QAutotuneProgress.failed;
  }
  if (lower.contains('start') ||
      lower.contains('begin') ||
      lower.contains('initialised') ||
      lower.contains('initialized') ||
      lower.contains('tuning')) {
    return QAutotuneProgress.tuning;
  }
  return null;
}
