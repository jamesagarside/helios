/// Airspeed sensor calibration: parameter mapping and field descriptors.
///
/// This module is pure (no Flutter / no transport) so the read/write mapping
/// can be unit-tested in isolation. It describes the differential-pressure
/// airspeed parameters exposed by the configuration UI and converts between
/// raw parameter values and typed editor state.
///
/// Two calibration concerns are covered:
///   1. Pre-flight **zero-offset** — with the pitot covered, the autopilot
///      captures the static differential-pressure reading into `ARSPD_OFFSET`.
///      This is commanded with `MAV_CMD_PREFLIGHT_CALIBRATION` (ground-pressure
///      slot), which on ArduPilot also re-zeroes the airspeed sensor.
///   2. In-flight **ratio** — `ARSPD_RATIO` scales indicated to true airspeed
///      and is refined either by hand or by the `ARSPD_AUTOCAL` estimator
///      during forward flight.
library;

/// The kind of editor a parameter needs.
enum AirspeedFieldKind {
  /// Free numeric entry (offset, ratio).
  number,

  /// A bounded enum rendered as a dropdown (type, autocal toggle, bus, pin).
  enumeration,
}

/// Descriptor for a single airspeed parameter exposed in the UI.
class AirspeedParam {
  const AirspeedParam({
    required this.id,
    required this.label,
    required this.kind,
    this.unit = '',
    this.helpText = '',
    this.options = const {},
    this.decimals = 2,
  });

  /// Flight-controller parameter id, e.g. `ARSPD_OFFSET`.
  final String id;

  /// Human-readable label for the row.
  final String label;

  /// Which editor to render.
  final AirspeedFieldKind kind;

  /// Display unit suffix (empty when unitless).
  final String unit;

  /// One-line guidance shown beneath the field.
  final String helpText;

  /// Enum value → label, when [kind] is [AirspeedFieldKind.enumeration].
  final Map<int, String> options;

  /// Decimal places to show for a [AirspeedFieldKind.number] field.
  final int decimals;

  /// Format [value] for display in a text field.
  String format(double value) {
    if (kind == AirspeedFieldKind.enumeration) {
      return options[value.round()] ?? value.round().toString();
    }
    return value.toStringAsFixed(decimals);
  }
}

/// Static catalogue of airspeed calibration / configuration parameters.
class AirspeedCalibration {
  AirspeedCalibration._();

  /// `MAV_CMD_PREFLIGHT_CALIBRATION` command id.
  static const int cmdPreflightCalibration = 241;

  /// Parameter id holding the captured zero offset.
  static const String offsetParam = 'ARSPD_OFFSET';

  /// Parameter id holding the indicated→true airspeed ratio.
  static const String ratioParam = 'ARSPD_RATIO';

  /// Parameter id toggling the in-flight auto-calibration estimator.
  static const String autocalParam = 'ARSPD_AUTOCAL';

  /// Sensor type parameter.
  static const String typeParam = 'ARSPD_TYPE';

  /// I2C bus parameter.
  static const String busParam = 'ARSPD_BUS';

  /// Analog pin parameter.
  static const String pinParam = 'ARSPD_PIN';

  /// Master enable parameter.
  static const String enableParam = 'ARSPD_ENABLE';

  /// `MAV_PARAM_TYPE` for floating-point params (REAL32).
  static const int typeReal32 = 9;

  /// `MAV_PARAM_TYPE` for an unsigned 8-bit param (the enum-style params).
  static const int typeUint8 = 1;

  /// All parameters surfaced by the airspeed panel, in display order.
  static const List<AirspeedParam> params = [
    AirspeedParam(
      id: enableParam,
      label: 'Airspeed sensor',
      kind: AirspeedFieldKind.enumeration,
      options: {0: 'Disabled', 1: 'Enabled'},
      helpText: 'Master enable for the differential-pressure airspeed sensor.',
    ),
    AirspeedParam(
      id: typeParam,
      label: 'Sensor type',
      kind: AirspeedFieldKind.enumeration,
      options: {
        0: 'None',
        1: 'I2C-MS4525',
        2: 'Analog',
        3: 'I2C-MS5525',
        4: 'I2C-MS5525 (0x76)',
        5: 'I2C-MS5525 (0x77)',
        6: 'I2C-SDP3X',
        7: 'I2C-DLVR-5in',
        8: 'DroneCAN',
        9: 'I2C-DLVR-10in',
        10: 'I2C-DLVR-20in',
        11: 'I2C-DLVR-30in',
        12: 'I2C-DLVR-60in',
        13: 'NMEA water speed',
        14: 'MSP',
        15: 'I2C-ASP5033',
      },
      helpText: 'Differential-pressure sensor model and interface.',
    ),
    AirspeedParam(
      id: busParam,
      label: 'I2C bus',
      kind: AirspeedFieldKind.enumeration,
      options: {0: 'Bus 0', 1: 'Bus 1', 2: 'Bus 2', 3: 'Bus 3'},
      helpText: 'I2C bus the sensor is wired to (ignored for analog sensors).',
    ),
    AirspeedParam(
      id: pinParam,
      label: 'Analog pin',
      kind: AirspeedFieldKind.enumeration,
      options: {
        0: 'Pin 0',
        1: 'Pin 1',
        2: 'Pin 2',
        13: 'Pin 13',
        14: 'Pin 14',
        15: 'Pin 15',
      },
      helpText: 'ADC pin for an analog sensor (ignored for I2C sensors).',
    ),
    AirspeedParam(
      id: offsetParam,
      label: 'Zero offset',
      kind: AirspeedFieldKind.number,
      unit: 'Pa',
      decimals: 2,
      helpText: 'Captured by the pre-flight zero with the pitot covered.',
    ),
    AirspeedParam(
      id: ratioParam,
      label: 'Ratio',
      kind: AirspeedFieldKind.number,
      decimals: 3,
      helpText: 'Indicated→true airspeed scale. Refined by in-flight auto-cal.',
    ),
    AirspeedParam(
      id: autocalParam,
      label: 'In-flight auto-cal',
      kind: AirspeedFieldKind.enumeration,
      options: {0: 'Disabled', 1: 'Enabled'},
      helpText:
          'When enabled, the ratio is estimated during forward flight. Turn '
          'off once the ratio has settled.',
    ),
  ];

  /// Parameter ids the panel must fetch.
  static List<String> get paramIds => [for (final p in params) p.id];

  /// Look up the descriptor for [id], or null if it is not an airspeed param.
  static AirspeedParam? descriptorFor(String id) {
    for (final p in params) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The `MAV_PARAM_TYPE` to use when writing [id].
  ///
  /// Offset and ratio are floats; the rest are small unsigned integers.
  static int paramTypeFor(String id) {
    return (id == offsetParam || id == ratioParam) ? typeReal32 : typeUint8;
  }

  /// Whether the given [value] is a meaningful change from [previous],
  /// accounting for float noise on the value echoed back by the FC.
  static bool isChanged(double previous, double value) =>
      (previous - value).abs() > 1e-6;
}
