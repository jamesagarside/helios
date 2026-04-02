import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/providers.dart';

/// Sends failure and environment injection commands to a running SITL instance
/// by writing ArduPilot simulation parameters over MAVLink.
///
/// Platform: macOS, Linux, Windows (SITL mode only).
///
/// All methods are no-ops when not connected; callers do not need to guard
/// against a disconnected state.
class SitlInjector {
  const SitlInjector();

  // ─── Valid speed multiplier values ─────────────────────────────────────────

  static const List<int> validSpeedMultipliers = [1, 2, 4, 8];

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /// Clamps [multiplier] to the nearest valid SITL speed multiplier.
  static int clampSpeedMultiplier(int multiplier) {
    if (multiplier <= 1) return 1;
    if (multiplier <= 2) return 2;
    if (multiplier <= 4) return 4;
    return 8;
  }

  Future<void> _writeParam(
    WidgetRef ref,
    String paramId,
    double value,
  ) async {
    final controller = ref.read(connectionControllerProvider.notifier);
    final paramService = controller.paramService;
    if (paramService == null) return;

    final vehicle = ref.read(vehicleStateProvider);
    await paramService.setParam(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      paramId: paramId,
      value: value,
    );
  }

  // ─── Wind ──────────────────────────────────────────────────────────────────

  /// Sets simulated wind speed and direction.
  ///
  /// [speedMs] is wind speed in metres per second (0–20).
  /// [dirDeg] is wind direction in degrees (0–360, meteorological convention).
  Future<void> setWind(WidgetRef ref, double speedMs, double dirDeg) async {
    await _writeParam(ref, 'SIM_WIND_SPD', speedMs.clamp(0, 20));
    await _writeParam(ref, 'SIM_WIND_DIR', dirDeg % 360);
  }

  // ─── GPS failure ──────────────────────────────────────────────────────────

  /// Enables or disables simulated GPS failure.
  ///
  /// When [fail] is `true`, `SIM_GPS_DISABLE` is set to 1 (GPS disabled).
  Future<void> setGpsFailure(WidgetRef ref, {required bool fail}) async {
    await _writeParam(ref, 'SIM_GPS_DISABLE', fail ? 1 : 0);
  }

  // ─── Compass failure ──────────────────────────────────────────────────────

  /// Enables or disables simulated compass failure.
  ///
  /// When [fail] is `true`, `SIM_MAG1_FAIL` is set to 1 (primary mag failed).
  Future<void> setCompassFailure(WidgetRef ref, {required bool fail}) async {
    await _writeParam(ref, 'SIM_MAG1_FAIL', fail ? 1 : 0);
  }

  // ─── Battery voltage ──────────────────────────────────────────────────────

  /// Sets the simulated battery voltage.
  ///
  /// [voltage] is in volts.  Typical 4S LiPo range is 12–16.8 V.
  Future<void> setBatteryVoltage(WidgetRef ref, double voltage) async {
    await _writeParam(ref, 'SIM_BATT_VOLTAGE', voltage);
  }

  // ─── Simulation speed ─────────────────────────────────────────────────────

  /// Sets the SITL simulation speed multiplier.
  ///
  /// [multiplier] is clamped to a valid value (1, 2, 4, or 8).
  Future<void> setSpeedMultiplier(WidgetRef ref, int multiplier) async {
    final clamped = clampSpeedMultiplier(multiplier);
    await _writeParam(ref, 'SIM_SPEEDUP', clamped.toDouble());
  }
}
