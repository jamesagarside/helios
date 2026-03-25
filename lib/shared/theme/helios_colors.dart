import 'package:flutter/material.dart';

/// Helios GCS colour tokens — dark-first design for outdoor tablet use.
abstract final class HeliosColors {
  // Backgrounds
  static const background = Color(0xFF0D1117);
  static const surface = Color(0xFF161B22);
  static const surfaceLight = Color(0xFF21262D);
  static const surfaceDim = Color(0xFF010409);

  // Borders
  static const border = Color(0xFF30363D);
  static const borderLight = Color(0xFF3D444D);

  // Text
  static const textPrimary = Color(0xFFE6EDF3);
  static const textSecondary = Color(0xFF8B949E);
  static const textTertiary = Color(0xFF6E7681);

  // Semantic — status indicators
  static const accent = Color(0xFF58A6FF);
  static const accentDim = Color(0xFF1F6FEB);
  static const success = Color(0xFF3FB950);
  static const successDim = Color(0xFF238636);
  static const warning = Color(0xFFD29922);
  static const warningDim = Color(0xFF9E6A03);
  static const danger = Color(0xFFF85149);
  static const dangerDim = Color(0xFFDA3633);

  // Instruments (PFD)
  static const sky = Color(0xFF1A3A5C);
  static const ground = Color(0xFF5C3A1A);
  static const horizon = Color(0xFFE6EDF3);
  static const pitchLine = Color(0x88E6EDF3);
}
