import 'package:flutter/material.dart';
import 'helios_colors.dart';

/// Helios GCS dark theme — optimised for outdoor tablet use.
ThemeData heliosTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: HeliosColors.background,
    colorScheme: const ColorScheme.dark(
      primary: HeliosColors.accent,
      onPrimary: HeliosColors.textPrimary,
      secondary: HeliosColors.accentDim,
      surface: HeliosColors.surface,
      onSurface: HeliosColors.textPrimary,
      error: HeliosColors.danger,
      onError: HeliosColors.textPrimary,
    ),
    cardColor: HeliosColors.surface,
    dividerColor: HeliosColors.border,
    appBarTheme: const AppBarTheme(
      backgroundColor: HeliosColors.surface,
      foregroundColor: HeliosColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: HeliosColors.surface,
      selectedIconTheme: IconThemeData(color: HeliosColors.accent),
      unselectedIconTheme: IconThemeData(color: HeliosColors.textSecondary),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: HeliosColors.surface,
      selectedItemColor: HeliosColors.accent,
      unselectedItemColor: HeliosColors.textSecondary,
    ),
    cardTheme: CardThemeData(
      color: HeliosColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: HeliosColors.border),
      ),
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: HeliosColors.accent,
        foregroundColor: HeliosColors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: HeliosColors.textPrimary,
        side: const BorderSide(color: HeliosColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HeliosColors.surfaceDim,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: HeliosColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: HeliosColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: HeliosColors.accent),
      ),
      labelStyle: const TextStyle(color: HeliosColors.textSecondary),
      hintStyle: const TextStyle(color: HeliosColors.textTertiary),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: HeliosColors.surfaceLight,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: HeliosColors.border),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: HeliosColors.surfaceLight,
      contentTextStyle: TextStyle(color: HeliosColors.textPrimary),
    ),
  );
}
