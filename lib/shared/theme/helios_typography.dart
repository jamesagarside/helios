import 'package:flutter/material.dart';
import 'helios_colors.dart';

/// Helios GCS typography tokens.
///
/// UI text: system sans-serif.
/// Telemetry values: monospace, bold for primary readouts.
abstract final class HeliosTypography {
  // UI text
  static const heading1 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: HeliosColors.textPrimary,
  );

  static const heading2 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: HeliosColors.textPrimary,
  );

  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: HeliosColors.textPrimary,
  );

  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: HeliosColors.textSecondary,
  );

  // Telemetry values — monospace
  static const telemetryLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    fontFamily: 'monospace',
    color: HeliosColors.textPrimary,
  );

  static const telemetryMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    fontFamily: 'monospace',
    color: HeliosColors.textPrimary,
  );

  static const telemetrySmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    fontFamily: 'monospace',
    color: HeliosColors.textSecondary,
  );

  // SQL editor
  static const sqlEditor = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    fontFamily: 'monospace',
    color: HeliosColors.textPrimary,
  );
}
