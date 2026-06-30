import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/airframe/airframe_config.dart';
import 'package:helios_gcs/core/airframe/drone_mesh_builder.dart';

void main() {
  const builder = DroneMeshBuilder();

  AirframeConfig multirotor(int motors, ArmLayout layout) => AirframeConfig(
        archetype: AirframeArchetype.multirotor,
        motorCount: motors,
        armLayout: layout,
        fromParams: true,
      );

  group('DroneMeshBuilder emits geometry for each archetype', () {
    test('multirotor mesh is non-empty and has finite vertices', () {
      final mesh = builder.build(multirotor(4, ArmLayout.x));
      expect(mesh.isEmpty, isFalse);
      for (final f in mesh.faces) {
        for (final v in [f.a, f.b, f.c]) {
          expect(v.x.isFinite && v.y.isFinite && v.z.isFinite, isTrue);
        }
      }
    });

    test('more arms → more faces (octa > quad)', () {
      final quad = builder.build(multirotor(4, ArmLayout.x));
      final octa = builder.build(multirotor(8, ArmLayout.x));
      expect(octa.faces.length, greaterThan(quad.faces.length));
    });

    test('fixed-wing mesh is non-empty', () {
      final mesh = builder.build(const AirframeConfig(
        archetype: AirframeArchetype.fixedWing,
        motorCount: 0,
        armLayout: ArmLayout.x,
        fromParams: false,
      ));
      expect(mesh.isEmpty, isFalse);
    });

    test('quadplane mesh is non-empty and larger than fixed-wing', () {
      final fw = builder.build(const AirframeConfig(
        archetype: AirframeArchetype.fixedWing,
        motorCount: 0,
        armLayout: ArmLayout.x,
        fromParams: false,
      ));
      final qp = builder.build(const AirframeConfig(
        archetype: AirframeArchetype.quadplane,
        motorCount: 4,
        armLayout: ArmLayout.x,
        fromParams: false,
      ));
      expect(qp.isEmpty, isFalse);
      expect(qp.faces.length, greaterThan(fw.faces.length));
    });

    test('tricopter (3 arms) builds without error', () {
      final mesh = builder.build(multirotor(3, ArmLayout.x));
      expect(mesh.isEmpty, isFalse);
    });

    test('face normals are unit length', () {
      final mesh = builder.build(multirotor(4, ArmLayout.x));
      for (final f in mesh.faces) {
        expect(f.normal.length, closeTo(1.0, 1e-6));
      }
    });
  });
}
