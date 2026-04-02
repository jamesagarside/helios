import 'package:flutter/material.dart';

/// Helios GCS typography tokens.
///
/// Tighter scale for GCS use — titles are moderate, body/caption are
/// readable at arm's length on a tablet in sunlight.
///
/// Scale ratio ~1.5:1 (was 2:1) between heading1 and caption.
///
/// No color is set here — text inherits color from the theme or the
/// enclosing widget. Use [HeliosColors.of(context)] at the widget level.
abstract final class HeliosTypography {
  // UI text
  static const heading1 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  static const heading2 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static const caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  static const small = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  // Telemetry values — monospace
  static const telemetryLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    fontFamily: 'monospace',
  );

  static const telemetryMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    fontFamily: 'monospace',
  );

  static const telemetrySmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    fontFamily: 'monospace',
  );

  // SQL editor
  static const sqlEditor = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    fontFamily: 'monospace',
  );
}
