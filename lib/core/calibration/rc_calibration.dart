/// Pure logic for RC / radio calibration.
///
/// Captures per-channel min/max/trim endpoints as the pilot sweeps every stick
/// and switch, supports channel reversal, and maps the results onto the
/// flight-controller parameters (`RCx_MIN`, `RCx_MAX`, `RCx_TRIM`,
/// `RCx_REVERSED`, `RCx_DZ`) plus the `RCMAP_*` channel-function assignment.
///
/// This module contains NO UI and NO transport so it can be unit-tested in
/// isolation. The widget layer feeds it live PWM samples from `RC_CHANNELS`
/// telemetry and reads back the resulting parameter map to write to the FC.
library;

/// Logical RC functions that ArduPilot maps onto physical channels via the
/// `RCMAP_*` parameters. The pilot assigns which transmitter channel drives
/// each function.
enum RcFunction {
  roll('RCMAP_ROLL', 'Roll / Aileron'),
  pitch('RCMAP_PITCH', 'Pitch / Elevator'),
  throttle('RCMAP_THROTTLE', 'Throttle'),
  yaw('RCMAP_YAW', 'Yaw / Rudder');

  const RcFunction(this.param, this.label);

  /// The `RCMAP_*` parameter name this function is written to.
  final String param;

  /// Human-readable label for the UI.
  final String label;
}

/// Captured calibration data for a single RC channel (1-based channel number).
///
/// [min] and [max] track the extremes seen during a sweep; [trim] records the
/// resting (centre) value, typically captured with sticks centred. [reversed]
/// flips the channel direction. [deadzone] (`RCx_DZ`) is a small band around
/// trim within which input is ignored.
class RcChannelCalibration {
  const RcChannelCalibration({
    required this.channel,
    required this.min,
    required this.max,
    required this.trim,
    this.reversed = false,
    this.deadzone = 0,
  });

  /// 1-based channel number (CH1 == 1).
  final int channel;
  final int min;
  final int max;
  final int trim;
  final bool reversed;
  final int deadzone;

  /// The travel span between [min] and [max].
  int get span => max - min;

  RcChannelCalibration copyWith({
    int? min,
    int? max,
    int? trim,
    bool? reversed,
    int? deadzone,
  }) {
    return RcChannelCalibration(
      channel: channel,
      min: min ?? this.min,
      max: max ?? this.max,
      trim: trim ?? this.trim,
      reversed: reversed ?? this.reversed,
      deadzone: deadzone ?? this.deadzone,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RcChannelCalibration &&
      other.channel == channel &&
      other.min == min &&
      other.max == max &&
      other.trim == trim &&
      other.reversed == reversed &&
      other.deadzone == deadzone;

  @override
  int get hashCode => Object.hash(channel, min, max, trim, reversed, deadzone);

  @override
  String toString() =>
      'RcChannelCalibration(ch$channel min=$min max=$max trim=$trim '
      'reversed=$reversed dz=$deadzone)';
}

/// A single validation problem found in a calibration set.
class RcCalibrationIssue {
  const RcCalibrationIssue(this.channel, this.message);

  /// 1-based channel number the issue applies to.
  final int channel;
  final String message;

  @override
  String toString() => 'CH$channel: $message';
}

/// Bounds and thresholds used when validating captured ranges. Defaults match
/// ArduPilot's expected RC PWM envelope.
class RcCalibrationBounds {
  const RcCalibrationBounds({
    this.absoluteMin = 800,
    this.absoluteMax = 2200,
    this.minSpan = 200,
  });

  /// Lowest PWM value considered physically plausible.
  final int absoluteMin;

  /// Highest PWM value considered physically plausible.
  final int absoluteMax;

  /// Minimum travel (max - min) required for a channel to be considered
  /// meaningfully calibrated.
  final int minSpan;
}

/// Captures per-channel min/max/trim endpoints from a live stream of
/// `RC_CHANNELS` PWM samples.
///
/// Lifecycle:
///   1. [start] with the trim (resting) snapshot — seeds min/max/trim.
///   2. Repeatedly call [addSample] as the pilot sweeps every stick and switch.
///   3. [finish] to obtain the captured [RcChannelCalibration] list, preserving
///      any existing reversal/deadzone passed in via [seedReversed].
///
/// Only PWM values within [bounds] are treated as real input; out-of-range or
/// zero values (failsafe / unconnected channels) are ignored so they don't
/// corrupt the captured extremes.
class RcEndpointCapture {
  RcEndpointCapture({this.bounds = const RcCalibrationBounds()});

  final RcCalibrationBounds bounds;

  final Map<int, int> _min = {};
  final Map<int, int> _max = {};
  final Map<int, int> _trim = {};
  bool _capturing = false;

  bool get isCapturing => _capturing;

  /// Channel numbers (1-based) that have received at least one valid sample.
  Iterable<int> get observedChannels => _min.keys.toList()..sort();

  bool _valid(int pwm) => pwm >= bounds.absoluteMin && pwm <= bounds.absoluteMax;

  /// Begin a capture session.
  ///
  /// [trimSnapshot] is the list of current PWM values (index 0 == CH1) used as
  /// the resting/centre position for each channel. Channels with out-of-range
  /// values are skipped until a valid sample arrives.
  void start(List<int> trimSnapshot) {
    _min.clear();
    _max.clear();
    _trim.clear();
    _capturing = true;
    for (var i = 0; i < trimSnapshot.length; i++) {
      final pwm = trimSnapshot[i];
      if (!_valid(pwm)) continue;
      final ch = i + 1;
      _min[ch] = pwm;
      _max[ch] = pwm;
      _trim[ch] = pwm;
    }
  }

  /// Feed one `RC_CHANNELS` sample (index 0 == CH1). No-op unless capturing.
  void addSample(List<int> channels) {
    if (!_capturing) return;
    for (var i = 0; i < channels.length; i++) {
      final pwm = channels[i];
      if (!_valid(pwm)) continue;
      final ch = i + 1;
      _min[ch] = _min.containsKey(ch) ? (pwm < _min[ch]! ? pwm : _min[ch]!) : pwm;
      _max[ch] = _max.containsKey(ch) ? (pwm > _max[ch]! ? pwm : _max[ch]!) : pwm;
      _trim.putIfAbsent(ch, () => pwm);
    }
  }

  /// Re-capture the trim (centre) values from the current resting snapshot.
  /// Call this with sticks centred to record neutral positions without
  /// disturbing the captured min/max extremes.
  void captureTrim(List<int> channels) {
    if (!_capturing) return;
    for (var i = 0; i < channels.length; i++) {
      final pwm = channels[i];
      if (!_valid(pwm)) continue;
      _trim[i + 1] = pwm;
    }
  }

  /// End the session and return the captured calibration per channel.
  ///
  /// [seedReversed] and [seedDeadzone] carry forward any pre-existing reversal
  /// / deadzone (keyed by 1-based channel) since those aren't derived from the
  /// sweep itself.
  List<RcChannelCalibration> finish({
    Map<int, bool> seedReversed = const {},
    Map<int, int> seedDeadzone = const {},
  }) {
    _capturing = false;
    final channels = observedChannels.toList();
    return [
      for (final ch in channels)
        RcChannelCalibration(
          channel: ch,
          min: _min[ch]!,
          max: _max[ch]!,
          // Clamp trim into [min, max] so a stale centre never escapes the
          // captured travel.
          trim: _trim[ch]!.clamp(_min[ch]!, _max[ch]!),
          reversed: seedReversed[ch] ?? false,
          deadzone: seedDeadzone[ch] ?? 0,
        ),
    ];
  }

  /// Abandon the current session without producing a result.
  void cancel() {
    _capturing = false;
    _min.clear();
    _max.clear();
    _trim.clear();
  }
}

/// Validates captured calibration before it is written to the FC.
///
/// Returns an empty list when the set is acceptable. A non-empty list means the
/// calibration is "obviously invalid" and must not be saved.
List<RcCalibrationIssue> validateCalibration(
  Iterable<RcChannelCalibration> calibrations, {
  RcCalibrationBounds bounds = const RcCalibrationBounds(),
}) {
  final issues = <RcCalibrationIssue>[];
  for (final c in calibrations) {
    if (c.min < bounds.absoluteMin || c.max > bounds.absoluteMax) {
      issues.add(RcCalibrationIssue(
        c.channel,
        'PWM out of range (${c.min}–${c.max}, expected '
        '${bounds.absoluteMin}–${bounds.absoluteMax})',
      ));
      continue;
    }
    if (c.max <= c.min) {
      issues.add(RcCalibrationIssue(
        c.channel,
        'max (${c.max}) must be greater than min (${c.min})',
      ));
      continue;
    }
    if (c.span < bounds.minSpan) {
      issues.add(RcCalibrationIssue(
        c.channel,
        'travel too small (${c.span} < ${bounds.minSpan}) — sweep the full '
        'range',
      ));
      continue;
    }
    if (c.trim < c.min || c.trim > c.max) {
      issues.add(RcCalibrationIssue(
        c.channel,
        'trim (${c.trim}) outside captured range (${c.min}–${c.max})',
      ));
    }
    if (c.deadzone < 0) {
      issues.add(RcCalibrationIssue(c.channel, 'deadzone must not be negative'));
    }
  }
  return issues;
}

/// Builds the flight-controller parameter map for a single channel's endpoints.
///
/// Produces `RCx_MIN`, `RCx_MAX`, `RCx_TRIM`, `RCx_REVERSED`, `RCx_DZ`.
Map<String, double> channelParams(RcChannelCalibration c) {
  final ch = c.channel;
  return {
    'RC${ch}_MIN': c.min.toDouble(),
    'RC${ch}_MAX': c.max.toDouble(),
    'RC${ch}_TRIM': c.trim.toDouble(),
    'RC${ch}_REVERSED': c.reversed ? 1.0 : 0.0,
    'RC${ch}_DZ': c.deadzone.toDouble(),
  };
}

/// Builds the complete parameter map to write for a calibration set plus the
/// `RCMAP_*` function assignments.
///
/// [assignments] maps each [RcFunction] to the 1-based channel that drives it.
/// Functions left unassigned (null) are omitted.
Map<String, double> buildParameterWrites(
  Iterable<RcChannelCalibration> calibrations,
  Map<RcFunction, int?> assignments,
) {
  final out = <String, double>{};
  for (final c in calibrations) {
    out.addAll(channelParams(c));
  }
  assignments.forEach((fn, channel) {
    if (channel != null) out[fn.param] = channel.toDouble();
  });
  return out;
}

/// Reads back an `RCMAP_*` assignment map from a raw parameter map (param name
/// → value). Missing entries are returned as null.
Map<RcFunction, int?> readAssignments(Map<String, double> params) {
  return {
    for (final fn in RcFunction.values)
      fn: params.containsKey(fn.param) ? params[fn.param]!.round() : null,
  };
}

/// Reads back a channel's stored calibration from a raw parameter map. Returns
/// null when the channel has no `RCx_MIN`/`RCx_MAX` stored.
RcChannelCalibration? readChannelCalibration(
  int channel,
  Map<String, double> params,
) {
  final min = params['RC${channel}_MIN'];
  final max = params['RC${channel}_MAX'];
  if (min == null || max == null) return null;
  return RcChannelCalibration(
    channel: channel,
    min: min.round(),
    max: max.round(),
    trim: (params['RC${channel}_TRIM'] ?? ((min + max) / 2)).round(),
    reversed: (params['RC${channel}_REVERSED'] ?? 0) >= 0.5,
    deadzone: (params['RC${channel}_DZ'] ?? 0).round(),
  );
}
