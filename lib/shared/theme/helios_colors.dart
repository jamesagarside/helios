import 'package:flutter/material.dart';

/// Helios GCS colour tokens — theme-aware, dark and light.
///
/// Registered as a [ThemeExtension] in both [heliosTheme()] and [heliosLightTheme()].
/// Access in widgets via [HeliosColors.of(context)] or the [BuildContext.hc] shorthand.
@immutable
class HeliosColors extends ThemeExtension<HeliosColors> {
  const HeliosColors({
    required this.background,
    required this.surface,
    required this.surfaceLight,
    required this.surfaceDim,
    required this.border,
    required this.borderLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentDim,
    required this.success,
    required this.successDim,
    required this.warning,
    required this.warningDim,
    required this.danger,
    required this.dangerDim,
    required this.sky,
    required this.ground,
    required this.horizon,
    required this.pitchLine,
  });

  final Color background;
  final Color surface;
  final Color surfaceLight;
  final Color surfaceDim;
  final Color border;
  final Color borderLight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentDim;
  final Color success;
  final Color successDim;
  final Color warning;
  final Color warningDim;
  final Color danger;
  final Color dangerDim;
  final Color sky;
  final Color ground;
  final Color horizon;
  final Color pitchLine;

  // ─── Dark (default, outdoor tablet) ───────────────────────────────────

  static const dark = HeliosColors(
    background: Color(0xFF0D1117),
    surface: Color(0xFF161B22),
    surfaceLight: Color(0xFF21262D),
    surfaceDim: Color(0xFF010409),
    border: Color(0xFF30363D),
    borderLight: Color(0xFF3D444D),
    textPrimary: Color(0xFFE6EDF3),
    textSecondary: Color(0xFF8B949E),
    textTertiary: Color(0xFF6E7681),
    accent: Color(0xFF58A6FF),
    accentDim: Color(0xFF1F6FEB),
    success: Color(0xFF3FB950),
    successDim: Color(0xFF238636),
    warning: Color(0xFFD29922),
    warningDim: Color(0xFF9E6A03),
    danger: Color(0xFFF85149),
    dangerDim: Color(0xFFDA3633),
    sky: Color(0xFF1A3A5C),
    ground: Color(0xFF5C3A1A),
    horizon: Color(0xFFE6EDF3),
    pitchLine: Color(0x88E6EDF3),
  );

  // ─── Light ─────────────────────────────────────────────────────────────

  static const light = HeliosColors(
    background: Color(0xFFF5F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceLight: Color(0xFFE8E8ED),
    surfaceDim: Color(0xFFD1D1D6),
    border: Color(0xFFD1D1D6),
    borderLight: Color(0xFFC7C7CC),
    textPrimary: Color(0xFF1C1C1E),
    textSecondary: Color(0xFF6C6C70),
    textTertiary: Color(0xFF8E8E93),
    accent: Color(0xFF0066CC),
    accentDim: Color(0xFF0055A8),
    success: Color(0xFF34C759),
    successDim: Color(0xFF248A3D),
    warning: Color(0xFFFF9500),
    warningDim: Color(0xFFB36600),
    danger: Color(0xFFFF3B30),
    dangerDim: Color(0xFFD70015),
    sky: Color(0xFFB8D4F0),
    ground: Color(0xFFD4B896),
    horizon: Color(0xFF1C1C1E),
    pitchLine: Color(0x881C1C1E),
  );

  // ─── Context access ────────────────────────────────────────────────────

  /// Returns the active theme's Helios colors. Falls back to [dark] in tests.
  static HeliosColors of(BuildContext context) =>
      Theme.of(context).extension<HeliosColors>() ?? dark;

  // ─── ThemeExtension ────────────────────────────────────────────────────

  @override
  HeliosColors copyWith({
    Color? background, Color? surface, Color? surfaceLight, Color? surfaceDim,
    Color? border, Color? borderLight, Color? textPrimary, Color? textSecondary,
    Color? textTertiary, Color? accent, Color? accentDim, Color? success,
    Color? successDim, Color? warning, Color? warningDim, Color? danger,
    Color? dangerDim, Color? sky, Color? ground, Color? horizon, Color? pitchLine,
  }) => HeliosColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceLight: surfaceLight ?? this.surfaceLight,
    surfaceDim: surfaceDim ?? this.surfaceDim,
    border: border ?? this.border,
    borderLight: borderLight ?? this.borderLight,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    accent: accent ?? this.accent,
    accentDim: accentDim ?? this.accentDim,
    success: success ?? this.success,
    successDim: successDim ?? this.successDim,
    warning: warning ?? this.warning,
    warningDim: warningDim ?? this.warningDim,
    danger: danger ?? this.danger,
    dangerDim: dangerDim ?? this.dangerDim,
    sky: sky ?? this.sky,
    ground: ground ?? this.ground,
    horizon: horizon ?? this.horizon,
    pitchLine: pitchLine ?? this.pitchLine,
  );

  @override
  HeliosColors lerp(HeliosColors? other, double t) {
    if (other == null) return this;
    return HeliosColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceLight: Color.lerp(surfaceLight, other.surfaceLight, t)!,
      surfaceDim: Color.lerp(surfaceDim, other.surfaceDim, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderLight: Color.lerp(borderLight, other.borderLight, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDim: Color.lerp(accentDim, other.accentDim, t)!,
      success: Color.lerp(success, other.success, t)!,
      successDim: Color.lerp(successDim, other.successDim, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningDim: Color.lerp(warningDim, other.warningDim, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerDim: Color.lerp(dangerDim, other.dangerDim, t)!,
      sky: Color.lerp(sky, other.sky, t)!,
      ground: Color.lerp(ground, other.ground, t)!,
      horizon: Color.lerp(horizon, other.horizon, t)!,
      pitchLine: Color.lerp(pitchLine, other.pitchLine, t)!,
    );
  }
}

/// Shorthand: `context.hc.surface`, `context.hc.accent`, etc.
extension HeliosColorsX on BuildContext {
  HeliosColors get hc => HeliosColors.of(this);
}
