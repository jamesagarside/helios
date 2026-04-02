import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unit system for display formatting.
enum UnitSystem {
  /// Metres, km, m/s, C.
  metric,

  /// Feet, miles, mph, F.
  imperial,

  /// Feet, nautical miles, knots, C.
  aviation,
}

const _kPrefKey = 'unit_system';

// ─── Conversion constants ────────────────────────────────────────────────────

const double _metresToFeet = 3.28084;
const double _metresToMiles = 0.000621371;
const double _metresToNauticalMiles = 0.000539957;
const double _msToMph = 2.23694;
const double _msToKnots = 1.94384;
const double _msToKmh = 3.6;
const double _sqMetresToAcres = 0.000247105;
const double _sqMetresToSqFeet = 10.7639;

// ─── Formatting utilities ────────────────────────────────────────────────────

/// Format a distance in metres to a human-readable string.
///
/// Uses km/mi/nm for large distances, m/ft for small.
String formatDistance(double metres, UnitSystem system) {
  switch (system) {
    case UnitSystem.metric:
      if (metres >= 1000) {
        return '${(metres / 1000).toStringAsFixed(2)} km';
      }
      return '${metres.toStringAsFixed(1)} m';
    case UnitSystem.imperial:
      final miles = metres * _metresToMiles;
      if (miles >= 0.1) {
        return '${miles.toStringAsFixed(2)} mi';
      }
      return '${(metres * _metresToFeet).toStringAsFixed(0)} ft';
    case UnitSystem.aviation:
      final nm = metres * _metresToNauticalMiles;
      if (nm >= 0.1) {
        return '${nm.toStringAsFixed(2)} nm';
      }
      return '${(metres * _metresToFeet).toStringAsFixed(0)} ft';
  }
}

/// Format an altitude in metres to a human-readable string.
String formatAltitude(double metres, UnitSystem system) {
  switch (system) {
    case UnitSystem.metric:
      return '${metres.toStringAsFixed(1)} m';
    case UnitSystem.imperial:
    case UnitSystem.aviation:
      return '${(metres * _metresToFeet).toStringAsFixed(0)} ft';
  }
}

/// Format a speed in m/s to a human-readable string.
String formatSpeed(double ms, UnitSystem system) {
  switch (system) {
    case UnitSystem.metric:
      return '${(ms * _msToKmh).toStringAsFixed(1)} km/h';
    case UnitSystem.imperial:
      return '${(ms * _msToMph).toStringAsFixed(1)} mph';
    case UnitSystem.aviation:
      return '${(ms * _msToKnots).toStringAsFixed(1)} kts';
  }
}

/// Format an area in m^2 to a human-readable string.
String formatArea(double sqMetres, UnitSystem system) {
  switch (system) {
    case UnitSystem.metric:
      if (sqMetres >= 1e6) {
        return '${(sqMetres / 1e6).toStringAsFixed(2)} km\u00B2';
      }
      return '${sqMetres.toStringAsFixed(0)} m\u00B2';
    case UnitSystem.imperial:
      final acres = sqMetres * _sqMetresToAcres;
      if (acres >= 1) {
        return '${acres.toStringAsFixed(2)} acres';
      }
      return '${(sqMetres * _sqMetresToSqFeet).toStringAsFixed(0)} ft\u00B2';
    case UnitSystem.aviation:
      if (sqMetres >= 1e6) {
        final nm2 = sqMetres /
            (1852 * 1852); // 1 nm = 1852 m
        return '${nm2.toStringAsFixed(2)} nm\u00B2';
      }
      return '${sqMetres.toStringAsFixed(0)} m\u00B2';
  }
}

/// Format a temperature in Celsius to a human-readable string.
String formatTemperature(double celsius, UnitSystem system) {
  switch (system) {
    case UnitSystem.metric:
    case UnitSystem.aviation:
      return '${celsius.toStringAsFixed(1)}\u00B0C';
    case UnitSystem.imperial:
      final f = celsius * 9 / 5 + 32;
      return '${f.toStringAsFixed(1)}\u00B0F';
  }
}

/// Convert metres to the raw numeric value in the target unit (no label).
double convertDistance(double metres, UnitSystem system) {
  return switch (system) {
    UnitSystem.metric => metres,
    UnitSystem.imperial => metres * _metresToFeet,
    UnitSystem.aviation => metres * _metresToFeet,
  };
}

/// Convert m/s to the raw numeric value in the target unit (no label).
double convertSpeed(double ms, UnitSystem system) {
  return switch (system) {
    UnitSystem.metric => ms * _msToKmh,
    UnitSystem.imperial => ms * _msToMph,
    UnitSystem.aviation => ms * _msToKnots,
  };
}

// ─── Provider ────────────────────────────────────────────────────────────────

/// Notifier for the selected unit system, persisted to SharedPreferences.
class UnitSystemNotifier extends StateNotifier<UnitSystem> {
  UnitSystemNotifier() : super(UnitSystem.metric) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_kPrefKey);
      if (stored == null || !mounted) return;
      state = UnitSystem.values.firstWhere(
        (u) => u.name == stored,
        orElse: () => UnitSystem.metric,
      );
    } catch (_) {
      // Non-fatal — default to metric.
    }
  }

  Future<void> setSystem(UnitSystem system) async {
    state = system;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefKey, system.name);
    } catch (_) {
      // Non-fatal.
    }
  }
}

/// The currently selected unit system.
final unitSystemProvider =
    StateNotifierProvider<UnitSystemNotifier, UnitSystem>(
  (ref) => UnitSystemNotifier(),
);
