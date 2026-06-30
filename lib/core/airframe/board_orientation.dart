/// Board orientation rotations for the flight controller's `AHRS_ORIENTATION`
/// (and the legacy `COMPASS_ORIENT`) parameter.
///
/// These integer values are the autopilot's standard `Rotation` enumeration,
/// describing how the autopilot board is physically mounted relative to the
/// vehicle's forward axis. The numeric values are part of the firmware ABI and
/// must not be renumbered; only the human-readable [label]s are ours.
///
/// This module is deliberately UI-free and pure so the value↔label mapping the
/// picker depends on can be unit-tested in isolation.
library;

/// A single board-orientation rotation: a firmware [value] plus a
/// human-readable [label].
class BoardOrientation {
  const BoardOrientation(this.value, this.label);

  /// The `AHRS_ORIENTATION` / `COMPASS_ORIENT` integer value.
  final int value;

  /// Human-readable rotation label shown in the picker.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is BoardOrientation &&
      other.value == value &&
      other.label == label;

  @override
  int get hashCode => Object.hash(value, label);

  @override
  String toString() => 'BoardOrientation($value, $label)';
}

/// Catalogue of the standard board-orientation rotations.
///
/// Ordered with the everyday mountings first (None, the four yaw rotations),
/// then the rolled/pitched and composite rotations. Values match the
/// autopilot `Rotation` enum used by `AHRS_ORIENTATION` and `COMPASS_ORIENT`.
class BoardOrientations {
  const BoardOrientations._();

  /// All supported rotations, in display order.
  static const List<BoardOrientation> all = [
    BoardOrientation(0, 'None (forward, level)'),
    BoardOrientation(1, 'Yaw 45°'),
    BoardOrientation(2, 'Yaw 90°'),
    BoardOrientation(3, 'Yaw 135°'),
    BoardOrientation(4, 'Yaw 180°'),
    BoardOrientation(5, 'Yaw 225°'),
    BoardOrientation(6, 'Yaw 270°'),
    BoardOrientation(7, 'Yaw 315°'),
    BoardOrientation(8, 'Roll 180°'),
    BoardOrientation(9, 'Roll 180°, Yaw 45°'),
    BoardOrientation(10, 'Roll 180°, Yaw 90°'),
    BoardOrientation(11, 'Roll 180°, Yaw 135°'),
    BoardOrientation(12, 'Pitch 180°'),
    BoardOrientation(13, 'Roll 180°, Yaw 225°'),
    BoardOrientation(14, 'Roll 180°, Yaw 270°'),
    BoardOrientation(15, 'Roll 180°, Yaw 315°'),
    BoardOrientation(16, 'Roll 90°'),
    BoardOrientation(17, 'Roll 90°, Yaw 45°'),
    BoardOrientation(18, 'Roll 90°, Yaw 90°'),
    BoardOrientation(19, 'Roll 90°, Yaw 135°'),
    BoardOrientation(20, 'Roll 270°'),
    BoardOrientation(21, 'Roll 270°, Yaw 45°'),
    BoardOrientation(22, 'Roll 270°, Yaw 90°'),
    BoardOrientation(23, 'Roll 270°, Yaw 135°'),
    BoardOrientation(24, 'Pitch 90°'),
    BoardOrientation(25, 'Pitch 270°'),
    BoardOrientation(26, 'Pitch 180°, Yaw 90°'),
    BoardOrientation(27, 'Pitch 180°, Yaw 270°'),
    BoardOrientation(28, 'Roll 90°, Pitch 90°'),
    BoardOrientation(29, 'Roll 180°, Pitch 90°'),
    BoardOrientation(30, 'Roll 270°, Pitch 90°'),
    BoardOrientation(31, 'Roll 90°, Pitch 180°'),
    BoardOrientation(32, 'Roll 270°, Pitch 180°'),
    BoardOrientation(33, 'Roll 90°, Pitch 270°'),
    BoardOrientation(34, 'Roll 180°, Pitch 270°'),
    BoardOrientation(35, 'Roll 270°, Pitch 270°'),
    BoardOrientation(36, 'Roll 90°, Pitch 180°, Yaw 90°'),
    BoardOrientation(37, 'Roll 90°, Yaw 270°'),
    BoardOrientation(38, 'Yaw 293°, Pitch 68°, Roll 180°'),
    BoardOrientation(39, 'Pitch 315°'),
    BoardOrientation(40, 'Roll 90°, Pitch 315°'),
    BoardOrientation(42, 'Roll 45°'),
    BoardOrientation(43, 'Roll 315°'),
  ];

  /// The default ("no rotation") orientation.
  static const BoardOrientation none = BoardOrientation(0, 'None (forward, level)');

  /// Look up a rotation by its firmware [value], or `null` when not a known
  /// standard rotation.
  static BoardOrientation? byValue(int value) {
    for (final o in all) {
      if (o.value == value) return o;
    }
    return null;
  }

  /// The human-readable label for [value], falling back to a generic
  /// "Custom (N)" label for values outside the standard catalogue.
  static String labelFor(int value) =>
      byValue(value)?.label ?? 'Custom ($value)';

  /// Resolve the effective board-orientation value from raw parameter values.
  ///
  /// `AHRS_ORIENTATION` is authoritative on modern firmware; the legacy
  /// `COMPASS_ORIENT` is used only as a fallback when AHRS is absent. Returns
  /// `null` when neither parameter is present.
  ///
  /// Values are doubles because MAVLink carries every parameter as a float;
  /// they are rounded to the nearest integer rotation code.
  static int? resolveValue({double? ahrsOrientation, double? compassOrient}) {
    if (ahrsOrientation != null) return ahrsOrientation.round();
    if (compassOrient != null) return compassOrient.round();
    return null;
  }
}
