import 'package:flutter/material.dart';
import 'helios_colors.dart';

/// Helios GCS typography tokens.
///
/// Tighter scale for GCS use — titles are moderate, body/caption are
/// readable at arm's length on a tablet in sunlight.
///
/// Scale ratio ~1.5:1 (was 2:1) between heading1 and caption.
abstract final class HeliosTypography {
  // UI text
  static const heading1 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: HeliosColors.textPrimary,
  );

  static const heading2 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: HeliosColors.textPrimary,
  );

  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: HeliosColors.textPrimary,
  );

  static const caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: HeliosColors.textSecondary,
  );

  static const small = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: HeliosColors.textTertiary,
  );

  // Telemetry values — monospace
  static const telemetryLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    fontFamily: 'monospace',
    color: HeliosColors.textPrimary,
  );

  static const telemetryMedium = TextStyle(
    fontSize: 16,
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
