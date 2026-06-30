/// Pure logic for flight-modes setup.
///
/// ArduPilot selects one of six flight-mode slots from the PWM of a single mode
/// channel ([flightModeChannel], stored in `FLTMODE_CH`). The six slots
/// (`FLTMODE1`..`FLTMODE6`) each hold a mode number; which slot is active is
/// decided by fixed PWM bands. This module maps a PWM value onto its slot,
/// builds the `FLTMODE*` parameter writes, and reads them back — with NO UI and
/// NO transport so it can be unit-tested in isolation.
///
/// The widget layer feeds it live PWM samples from `RC_CHANNELS` telemetry
/// (reusing the same channel-read plumbing as RC calibration) and reads back the
/// resulting parameter map to write to the FC.
library;

/// Parameter name of the channel that selects the flight mode.
const String kFlightModeChannelParam = 'FLTMODE_CH';

/// Number of mode slots ArduPilot supports on the mode channel.
const int kFlightModeSlotCount = 6;

/// Default mode channel when `FLTMODE_CH` is unset (ArduPilot default is CH5).
const int kDefaultFlightModeChannel = 5;

/// The six PWM bands ArduPilot uses to pick a flight-mode slot from the mode
/// channel, in slot order (slot 1 == index 0).
///
/// These thresholds match ArduPilot's `RC_Channel::read_3pos_switch` /
/// flight-mode logic: the channel PWM is bucketed into six contiguous bands.
const List<FlightModeBand> kFlightModeBands = <FlightModeBand>[
  FlightModeBand(slot: 1, lower: 0, upper: 1230),
  FlightModeBand(slot: 2, lower: 1231, upper: 1360),
  FlightModeBand(slot: 3, lower: 1361, upper: 1490),
  FlightModeBand(slot: 4, lower: 1491, upper: 1620),
  FlightModeBand(slot: 5, lower: 1621, upper: 1749),
  FlightModeBand(slot: 6, lower: 1750, upper: 2200),
];

/// A contiguous PWM band that selects one flight-mode slot (1-based).
class FlightModeBand {
  const FlightModeBand({
    required this.slot,
    required this.lower,
    required this.upper,
  });

  /// 1-based slot index (1..6) — maps to `FLTMODE{slot}`.
  final int slot;

  /// Inclusive lower PWM bound.
  final int lower;

  /// Inclusive upper PWM bound.
  final int upper;

  /// Whether [pwm] falls within this band.
  bool contains(int pwm) => pwm >= lower && pwm <= upper;

  @override
  bool operator ==(Object other) =>
      other is FlightModeBand &&
      other.slot == slot &&
      other.lower == lower &&
      other.upper == upper;

  @override
  int get hashCode => Object.hash(slot, lower, upper);

  @override
  String toString() => 'FlightModeBand(slot=$slot, $lower-$upper)';
}

/// The `FLTMODE{slot}` parameter name for a 1-based [slot] (1..6).
String flightModeSlotParam(int slot) => 'FLTMODE$slot';

/// Returns the 1-based slot (1..6) the given mode-channel [pwm] selects, or
/// null when the value is below the first band's lower bound or above the last
/// band's upper bound (e.g. failsafe / no signal).
int? slotForPwm(int pwm) {
  for (final band in kFlightModeBands) {
    if (band.contains(pwm)) return band.slot;
  }
  return null;
}

/// Returns the [FlightModeBand] for a 1-based [slot] (1..6), or null when out of
/// range.
FlightModeBand? bandForSlot(int slot) {
  for (final band in kFlightModeBands) {
    if (band.slot == slot) return band;
  }
  return null;
}

/// The full flight-modes configuration: the selector channel plus a mode number
/// for each of the six slots.
class FlightModeAssignment {
  const FlightModeAssignment({
    required this.channel,
    required this.slotModes,
  });

  /// 1-based mode-selector channel (written to `FLTMODE_CH`).
  final int channel;

  /// Mode number assigned to each slot, keyed by 1-based slot (1..6). Slots not
  /// present in the map are treated as unset.
  final Map<int, int> slotModes;

  /// The mode number assigned to [slot] (1-based), or null when unset.
  int? modeForSlot(int slot) => slotModes[slot];

  FlightModeAssignment copyWith({
    int? channel,
    Map<int, int>? slotModes,
  }) {
    return FlightModeAssignment(
      channel: channel ?? this.channel,
      slotModes: slotModes ?? this.slotModes,
    );
  }

  /// Returns a copy with [mode] assigned to 1-based [slot]. A null [mode]
  /// removes the slot's assignment.
  FlightModeAssignment withSlotMode(int slot, int? mode) {
    final next = Map<int, int>.from(slotModes);
    if (mode == null) {
      next.remove(slot);
    } else {
      next[slot] = mode;
    }
    return copyWith(slotModes: next);
  }

  @override
  bool operator ==(Object other) =>
      other is FlightModeAssignment &&
      other.channel == channel &&
      _mapsEqual(other.slotModes, slotModes);

  @override
  int get hashCode => Object.hash(
        channel,
        Object.hashAllUnordered(
          slotModes.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );

  @override
  String toString() =>
      'FlightModeAssignment(channel=$channel, slotModes=$slotModes)';

  static bool _mapsEqual(Map<int, int> a, Map<int, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// Builds the flight-controller parameter map for a flight-modes assignment.
///
/// Produces `FLTMODE_CH` plus `FLTMODE1`..`FLTMODE6` for every slot present in
/// [assignment]. Slots left unset are omitted so an existing value on the FC is
/// not clobbered with a guessed default.
Map<String, double> buildFlightModeWrites(FlightModeAssignment assignment) {
  final out = <String, double>{
    kFlightModeChannelParam: assignment.channel.toDouble(),
  };
  for (var slot = 1; slot <= kFlightModeSlotCount; slot++) {
    final mode = assignment.slotModes[slot];
    if (mode != null) out[flightModeSlotParam(slot)] = mode.toDouble();
  }
  return out;
}

/// Reads back a [FlightModeAssignment] from a raw parameter map (param name →
/// value). The channel falls back to [kDefaultFlightModeChannel] when
/// `FLTMODE_CH` is absent; slots missing from the map are simply not included.
FlightModeAssignment readFlightModeAssignment(Map<String, double> params) {
  final channel =
      params[kFlightModeChannelParam]?.round() ?? kDefaultFlightModeChannel;
  final slotModes = <int, int>{};
  for (var slot = 1; slot <= kFlightModeSlotCount; slot++) {
    final value = params[flightModeSlotParam(slot)];
    if (value != null) slotModes[slot] = value.round();
  }
  return FlightModeAssignment(channel: channel, slotModes: slotModes);
}
