import '../../shared/models/vehicle_state.dart';

/// ArduPilot flight mode information.
class FlightModeInfo {
  const FlightModeInfo(this.number, this.name, this.category);

  final int number;
  final String name;

  /// Rough category: 'manual', 'assisted', 'auto'.
  final String category;
}

const _kCopterModes = <FlightModeInfo>[
  FlightModeInfo(0, 'STABILIZE', 'manual'),
  FlightModeInfo(1, 'ACRO', 'manual'),
  FlightModeInfo(2, 'ALT_HOLD', 'assisted'),
  FlightModeInfo(3, 'AUTO', 'auto'),
  FlightModeInfo(4, 'GUIDED', 'auto'),
  FlightModeInfo(5, 'LOITER', 'assisted'),
  FlightModeInfo(6, 'RTL', 'auto'),
  FlightModeInfo(7, 'CIRCLE', 'auto'),
  FlightModeInfo(9, 'LAND', 'auto'),
  FlightModeInfo(11, 'DRIFT', 'assisted'),
  FlightModeInfo(13, 'SPORT', 'manual'),
  FlightModeInfo(15, 'AUTOTUNE', 'assisted'),
  FlightModeInfo(16, 'POSHOLD', 'assisted'),
  FlightModeInfo(17, 'BRAKE', 'assisted'),
  FlightModeInfo(18, 'THROW', 'assisted'),
  FlightModeInfo(19, 'AVOID_ADSB', 'auto'),
  FlightModeInfo(20, 'GUIDED_NOGPS', 'auto'),
  FlightModeInfo(21, 'SMART_RTL', 'auto'),
  FlightModeInfo(22, 'FLOWHOLD', 'assisted'),
  FlightModeInfo(23, 'FOLLOW', 'auto'),
  FlightModeInfo(24, 'ZIGZAG', 'auto'),
  FlightModeInfo(27, 'AUTO_RTL', 'auto'),
];

const _kPlaneModes = <FlightModeInfo>[
  FlightModeInfo(0, 'MANUAL', 'manual'),
  FlightModeInfo(1, 'CIRCLE', 'assisted'),
  FlightModeInfo(2, 'STABILIZE', 'manual'),
  FlightModeInfo(3, 'TRAINING', 'manual'),
  FlightModeInfo(4, 'ACRO', 'manual'),
  FlightModeInfo(5, 'FLY_BY_WIRE_A', 'assisted'),
  FlightModeInfo(6, 'FLY_BY_WIRE_B', 'assisted'),
  FlightModeInfo(7, 'CRUISE', 'assisted'),
  FlightModeInfo(8, 'AUTOTUNE', 'assisted'),
  FlightModeInfo(10, 'AUTO', 'auto'),
  FlightModeInfo(11, 'RTL', 'auto'),
  FlightModeInfo(12, 'LOITER', 'assisted'),
  FlightModeInfo(13, 'TAKEOFF', 'auto'),
  FlightModeInfo(14, 'AVOID_ADSB', 'auto'),
  FlightModeInfo(15, 'GUIDED', 'auto'),
  FlightModeInfo(17, 'QSTABILIZE', 'manual'),
  FlightModeInfo(18, 'QHOVER', 'assisted'),
  FlightModeInfo(19, 'QLOITER', 'assisted'),
  FlightModeInfo(20, 'QLAND', 'auto'),
  FlightModeInfo(21, 'QRTL', 'auto'),
  FlightModeInfo(22, 'QAUTOTUNE', 'assisted'),
  FlightModeInfo(23, 'QACRO', 'manual'),
  FlightModeInfo(24, 'THERMAL', 'auto'),
];

const _kRoverModes = <FlightModeInfo>[
  FlightModeInfo(0, 'MANUAL', 'manual'),
  FlightModeInfo(1, 'ACRO', 'manual'),
  FlightModeInfo(3, 'STEERING', 'assisted'),
  FlightModeInfo(4, 'HOLD', 'assisted'),
  FlightModeInfo(5, 'LOITER', 'assisted'),
  FlightModeInfo(6, 'FOLLOW', 'auto'),
  FlightModeInfo(7, 'SIMPLE', 'auto'),
  FlightModeInfo(10, 'AUTO', 'auto'),
  FlightModeInfo(11, 'RTL', 'auto'),
  FlightModeInfo(12, 'SMART_RTL', 'auto'),
  FlightModeInfo(15, 'GUIDED', 'auto'),
];

/// Lookup and list ArduPilot flight modes by vehicle type.
abstract final class FlightModeRegistry {
  /// Returns the [FlightModeInfo] for [modeNumber] given [vehicleType],
  /// or null if the mode number is unknown.
  static FlightModeInfo? lookup(VehicleType vehicleType, int modeNumber) {
    for (final m in modesFor(vehicleType)) {
      if (m.number == modeNumber) return m;
    }
    return null;
  }

  /// Returns the display name for [modeNumber], or `'MODE_$modeNumber'`
  /// if the number is not in the registry.
  static String name(VehicleType vehicleType, int modeNumber) {
    return lookup(vehicleType, modeNumber)?.name ?? 'MODE_$modeNumber';
  }

  /// All known modes for the given vehicle type.
  static List<FlightModeInfo> modesFor(VehicleType vehicleType) {
    return switch (vehicleType) {
      VehicleType.fixedWing || VehicleType.vtol => _kPlaneModes,
      VehicleType.rover || VehicleType.boat => _kRoverModes,
      _ => _kCopterModes,
    };
  }

  // ── Per-vehicle shortcut mode numbers ──────────────────────────────────────

  static int rtlMode(VehicleType v) => switch (v) {
        VehicleType.fixedWing || VehicleType.vtol => 11,
        VehicleType.rover || VehicleType.boat => 11,
        _ => 6, // Copter RTL
      };

  static int landMode(VehicleType v) => switch (v) {
        VehicleType.fixedWing || VehicleType.vtol => 20, // QLAND / manual
        VehicleType.rover || VehicleType.boat => 4, // HOLD
        _ => 9, // Copter LAND
      };

  static int loiterMode(VehicleType v) => switch (v) {
        VehicleType.fixedWing || VehicleType.vtol => 12,
        VehicleType.rover || VehicleType.boat => 4, // HOLD
        _ => 5, // Copter LOITER
      };

  static int autoMode(VehicleType v) => switch (v) {
        VehicleType.fixedWing || VehicleType.vtol => 10,
        VehicleType.rover || VehicleType.boat => 10,
        _ => 3, // Copter AUTO
      };

  static int brakeMode(VehicleType v) => switch (v) {
        VehicleType.fixedWing || VehicleType.vtol => 12, // LOITER
        VehicleType.rover || VehicleType.boat => 4, // HOLD
        _ => 17, // Copter BRAKE
      };

  static int guidedMode(VehicleType v) => switch (v) {
        VehicleType.fixedWing || VehicleType.vtol => 15,
        VehicleType.rover || VehicleType.boat => 15,
        _ => 4, // Copter GUIDED
      };
}
