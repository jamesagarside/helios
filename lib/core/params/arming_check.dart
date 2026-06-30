/// ARMING_CHECK bitmask model and encode/decode helpers.
///
/// `ARMING_CHECK` is an integer parameter on the flight controller that selects
/// which pre-arm checks run before the vehicle will arm. It is a bitmask: each
/// bit enables one category of check. The special value `1` ("all") enables
/// every check and is mutually exclusive with the individual category bits.
///
/// This logic is intentionally UI-free so the encode/decode rules can be pinned
/// by unit tests — a wrong bitmask here silently disables safety checks.
library;

/// A single selectable pre-arm check category.
class ArmingCheckBit {
  const ArmingCheckBit(this.bit, this.label, this.description);

  /// The bit value within the ARMING_CHECK bitmask.
  final int bit;

  /// Short, human-readable category name.
  final String label;

  /// One-line explanation of what the check covers.
  final String description;
}

/// The "enable all checks" sentinel value for ARMING_CHECK.
///
/// When ARMING_CHECK == 1 the flight controller runs every check. It is treated
/// as a distinct mode rather than a normal bit because selecting it clears the
/// individual category selections.
const int armingCheckAll = 1;

/// Bit value meaning "no checks enabled" (arming checks disabled entirely).
const int armingCheckNone = 0;

/// ArduPilot ARMING_CHECK category bits, in display order.
///
/// Sourced from the ArduPilot ARMING_CHECK parameter bitmask. Bit 0 (value 1)
/// is the "All" sentinel handled separately via [armingCheckAll].
const List<ArmingCheckBit> armingCheckBits = [
  ArmingCheckBit(1 << 1, 'Barometer', 'Barometer health and consistency.'),
  ArmingCheckBit(1 << 2, 'Compass', 'Compass health, calibration, offsets.'),
  ArmingCheckBit(1 << 3, 'GPS Lock', 'GPS fix quality and HDOP.'),
  ArmingCheckBit(1 << 4, 'INS', 'Inertial sensors (gyro / accel).'),
  ArmingCheckBit(1 << 5, 'Parameters', 'Parameter and configuration sanity.'),
  ArmingCheckBit(1 << 6, 'RC Channels', 'RC calibration and failsafe setup.'),
  ArmingCheckBit(1 << 7, 'Board Voltage', 'Flight controller board voltage.'),
  ArmingCheckBit(1 << 8, 'Battery Level', 'Battery voltage and capacity.'),
  ArmingCheckBit(1 << 9, 'Airspeed', 'Airspeed sensor (if fitted).'),
  ArmingCheckBit(1 << 10, 'Logging', 'Onboard dataflash logging available.'),
  ArmingCheckBit(1 << 11, 'Safety Switch', 'Hardware safety switch state.'),
  ArmingCheckBit(1 << 12, 'GPS Config', 'GPS configuration consistency.'),
  ArmingCheckBit(1 << 13, 'System', 'System / scheduler health.'),
  ArmingCheckBit(1 << 14, 'Mission', 'Mission and rally point validity.'),
  ArmingCheckBit(1 << 15, 'Rangefinder', 'Rangefinder health (if fitted).'),
  ArmingCheckBit(1 << 16, 'Camera', 'Camera / mount configuration.'),
  ArmingCheckBit(1 << 17, 'AuxAuth', 'Auxiliary authorisation.'),
  ArmingCheckBit(1 << 18, 'VisOdom', 'Visual odometry sensor health.'),
  ArmingCheckBit(1 << 19, 'FFT', 'Gyro FFT / harmonic notch.'),
];

/// Immutable view over an ARMING_CHECK bitmask value with decode/encode helpers.
class ArmingCheckMask {
  const ArmingCheckMask(this.value);

  /// Construct from a parameter value (which the FC stores as a double).
  factory ArmingCheckMask.fromParam(double raw) =>
      ArmingCheckMask(raw.round());

  /// The raw integer bitmask value.
  final int value;

  /// The parameter value to write back to the flight controller.
  double get paramValue => value.toDouble();

  /// Whether the "All" sentinel is selected (ARMING_CHECK == 1).
  bool get isAll => value == armingCheckAll;

  /// Whether arming checks are entirely disabled (ARMING_CHECK == 0).
  bool get isNone => value == armingCheckNone;

  /// Whether a specific category [bit] is currently enabled.
  ///
  /// When [isAll] is set, every category reports as enabled.
  bool isEnabled(int bit) {
    if (isAll) return true;
    return (value & bit) != 0;
  }

  /// The set of category bits explicitly enabled (excludes the "All" sentinel).
  Set<int> get enabledBits =>
      armingCheckBits.where((c) => isEnabled(c.bit)).map((c) => c.bit).toSet();

  /// Toggle a single category [bit] on or off, returning a new mask.
  ///
  /// Toggling a category while in "All" mode first expands "All" into the full
  /// set of explicit category bits, then applies the toggle — so unchecking one
  /// box leaves the others enabled rather than disabling everything.
  ArmingCheckMask toggle(int bit, bool enabled) {
    var base = isAll ? _allCategoryBits : value;
    if (enabled) {
      base |= bit;
    } else {
      base &= ~bit;
    }
    return ArmingCheckMask(base);
  }

  /// Select the "All" sentinel (ARMING_CHECK == 1).
  ArmingCheckMask selectAll() => const ArmingCheckMask(armingCheckAll);

  /// Disable every check (ARMING_CHECK == 0).
  ArmingCheckMask selectNone() => const ArmingCheckMask(armingCheckNone);

  /// Bitmask with every known category bit set (used to expand "All").
  static int get _allCategoryBits =>
      armingCheckBits.fold(0, (acc, c) => acc | c.bit);

  @override
  bool operator ==(Object other) =>
      other is ArmingCheckMask && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ArmingCheckMask(0x${value.toRadixString(16)})';
}
