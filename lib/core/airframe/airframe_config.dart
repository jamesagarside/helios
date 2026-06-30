import 'package:equatable/equatable.dart';

import '../../shared/models/vehicle_state.dart';

/// The three Airframe Model archetypes v1 can render. Per the ADR, exact
/// per-`FRAME_TYPE` cosmetic variants are out of scope — these archetypes
/// cover the structurally distinct shapes.
enum AirframeArchetype { multirotor, fixedWing, quadplane }

/// How the arms of a multirotor are laid out around the body.
enum ArmLayout {
  /// Arms straddle the nose (e.g. ArduPilot X / BetaFlightX / DJIX).
  x,

  /// One arm points straight forward (e.g. ArduPilot Plus / +).
  plus,

  /// Forward-swept V arrangement.
  v,

  /// Front/back pairs (H).
  h,
}

/// Resolved description of the connected vehicle's airframe, used by the
/// [DroneMeshBuilder] to emit geometry. Built from `FRAME_CLASS`/`FRAME_TYPE`
/// when parameters are loaded, else from `MAV_TYPE` (always present from the
/// heartbeat).
class AirframeConfig extends Equatable {
  const AirframeConfig({
    required this.archetype,
    required this.motorCount,
    required this.armLayout,
    required this.fromParams,
  });

  /// Resolve an [AirframeConfig] from FRAME_CLASS/FRAME_TYPE when present,
  /// falling back to [vehicleType] (MAV_TYPE) for a generic shape.
  ///
  /// [frameClass]/[frameType] are null when parameters have not loaded.
  factory AirframeConfig.resolve({
    required VehicleType vehicleType,
    int? frameClass,
    int? frameType,
  }) {
    if (frameClass != null) {
      final isVtol = vehicleType == VehicleType.vtol;
      if (isVtol) {
        final motors = frameClassMotorCount[frameClass] ?? 4;
        return AirframeConfig(
          archetype: AirframeArchetype.quadplane,
          motorCount: motors.clamp(3, 12),
          armLayout: _layoutFromType(frameType),
          fromParams: true,
        );
      }
      // Heli classes fall back to a generic single-rotor multirotor look.
      final motors = frameClassMotorCount[frameClass] ?? 4;
      return AirframeConfig(
        archetype: AirframeArchetype.multirotor,
        motorCount: motors.clamp(1, 12),
        armLayout: _layoutFromType(frameType),
        fromParams: true,
      );
    }

    // No params — infer from MAV_TYPE.
    switch (vehicleType) {
      case VehicleType.fixedWing:
        return const AirframeConfig(
          archetype: AirframeArchetype.fixedWing,
          motorCount: 0,
          armLayout: ArmLayout.x,
          fromParams: false,
        );
      case VehicleType.vtol:
        return const AirframeConfig(
          archetype: AirframeArchetype.quadplane,
          motorCount: 4,
          armLayout: ArmLayout.x,
          fromParams: false,
        );
      case VehicleType.helicopter:
        return const AirframeConfig(
          archetype: AirframeArchetype.multirotor,
          motorCount: 1,
          armLayout: ArmLayout.plus,
          fromParams: false,
        );
      case VehicleType.quadrotor:
      case VehicleType.unknown:
      case VehicleType.rover:
      case VehicleType.boat:
        return const AirframeConfig(
          archetype: AirframeArchetype.multirotor,
          motorCount: 4,
          armLayout: ArmLayout.x,
          fromParams: false,
        );
    }
  }

  final AirframeArchetype archetype;

  /// Number of lift motors/arms. Ignored for pure fixed-wing.
  final int motorCount;

  final ArmLayout armLayout;

  /// True if derived from FRAME_CLASS/FRAME_TYPE, false if from MAV_TYPE.
  final bool fromParams;

  /// ArduPilot FRAME_CLASS → motor count (mirrors the map in
  /// `frame_type_panel.dart`).
  static const Map<int, int> frameClassMotorCount = {
    0: 4, // Undefined — assume quad
    1: 4, // Quad
    2: 6, // Hexa
    3: 8, // Octo
    4: 8, // OctoQuad
    5: 6, // Y6
    7: 3, // Tri
    8: 1, // Single / Heli
    9: 2, // Coax / Heli Dual
    11: 4, // Heli Quad
    13: 6, // Hex Plus
    14: 6, // Y6B
    15: 10, // Deca
  };

  /// FRAME_CLASS values that are helicopter rotor heads, not multirotor arms.
  static const Set<int> heliFrameClasses = {8, 9};

  static ArmLayout _layoutFromType(int? frameType) {
    // ArduPilot FRAME_TYPE: 0=Plus, 1=X, 2=V, 3=H, 12=BFX, 13=DJIX, 14=CW X.
    switch (frameType) {
      case 0:
        return ArmLayout.plus;
      case 2:
        return ArmLayout.v;
      case 3:
        return ArmLayout.h;
      case 1:
      case 12:
      case 13:
      case 14:
      case 18:
        return ArmLayout.x;
      default:
        return ArmLayout.x;
    }
  }

  @override
  List<Object?> get props =>
      [archetype, motorCount, armLayout, fromParams];
}
