/// Pure logic for battery / power-monitor calibration.
///
/// Converts a pilot-measured reference value (pack voltage from a multimeter,
/// or current from a clamp meter) plus the value the flight controller is
/// currently reporting into the corrected calibration parameter the FC needs.
///
/// The flight controller computes its reported reading as:
///
/// ```
/// reported_voltage = adc_voltage * BATT_VOLT_MULT
/// reported_current = (adc_voltage - BATT_AMP_OFFSET) * BATT_AMP_PERVLT
/// ```
///
/// So to make the reported reading match a trusted measurement we scale the
/// existing multiplier by the ratio measured/reported. This keeps the same ADC
/// pin scaling while correcting the gain.
///
/// This module contains NO UI and NO transport so it can be unit-tested in
/// isolation. The widget layer feeds it the current parameter value and the
/// live telemetry reading, then writes the result back to the FC.
library;

/// Result of a calibration computation.
///
/// [value] is the new parameter value to write; [valid] is false when the
/// inputs could not produce a meaningful result (e.g. a zero or negative
/// reported reading, which would divide by zero or invert the sign).
class BatteryCalibrationResult {
  const BatteryCalibrationResult({required this.value, required this.valid});

  /// The computed parameter value to write to the flight controller.
  final double value;

  /// Whether the computation produced a usable, finite, positive result.
  final bool valid;

  /// A result representing an invalid computation (no value to write).
  static const invalid =
      BatteryCalibrationResult(value: 0, valid: false);
}

/// Computes a new `BATT_VOLT_MULT` from a measured pack voltage.
///
/// [currentMultiplier] is the FC's existing `BATT_VOLT_MULT`.
/// [reportedVoltage] is the voltage the FC is currently reporting (telemetry).
/// [measuredVoltage] is the pilot's trusted multimeter reading.
///
/// New multiplier = currentMultiplier * (measured / reported).
///
/// Returns [BatteryCalibrationResult.invalid] when the reported or measured
/// voltage is non-positive, or when the current multiplier is non-positive
/// (an uncalibrated/zero multiplier can't be scaled — the pilot must pick a
/// monitor type first).
BatteryCalibrationResult computeVoltageMultiplier({
  required double currentMultiplier,
  required double reportedVoltage,
  required double measuredVoltage,
}) {
  if (currentMultiplier <= 0 ||
      reportedVoltage <= 0 ||
      measuredVoltage <= 0) {
    return BatteryCalibrationResult.invalid;
  }
  final result = currentMultiplier * (measuredVoltage / reportedVoltage);
  if (!result.isFinite || result <= 0) {
    return BatteryCalibrationResult.invalid;
  }
  return BatteryCalibrationResult(value: result, valid: true);
}

/// Computes a new `BATT_AMP_PERVLT` (amps-per-volt) from a measured current.
///
/// [currentPerVolt] is the FC's existing `BATT_AMP_PERVLT`.
/// [reportedCurrent] is the current the FC is currently reporting (telemetry).
/// [measuredCurrent] is the pilot's trusted clamp-meter reading.
///
/// New amps-per-volt = currentPerVolt * (measured / reported).
///
/// Returns [BatteryCalibrationResult.invalid] when the reported current is
/// non-positive (can't scale from a zero reading — the pilot needs a real load
/// drawing current), when the measured current is negative, or when the
/// existing amps-per-volt is non-positive.
BatteryCalibrationResult computeCurrentPerVolt({
  required double currentPerVolt,
  required double reportedCurrent,
  required double measuredCurrent,
}) {
  if (currentPerVolt <= 0 ||
      reportedCurrent <= 0 ||
      measuredCurrent < 0) {
    return BatteryCalibrationResult.invalid;
  }
  final result = currentPerVolt * (measuredCurrent / reportedCurrent);
  if (!result.isFinite || result <= 0) {
    return BatteryCalibrationResult.invalid;
  }
  return BatteryCalibrationResult(value: result, valid: true);
}
