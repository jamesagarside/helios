import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/airframe/frame_conversion.dart';
import 'package:vector_math/vector_math_64.dart';

/// These tests are the correctness gate for the Body→Render frame conversion.
/// A wrong basis here makes the Airframe Model appear inverted or mirrored,
/// which cannot be verified from code alone — so we pin the conversion with
/// known inputs and expected outputs.
void main() {
  void expectVec(Vector3 actual, Vector3 expected, {double tol = 1e-9}) {
    expect(actual.x, closeTo(expected.x, tol), reason: 'x: $actual');
    expect(actual.y, closeTo(expected.y, tol), reason: 'y: $actual');
    expect(actual.z, closeTo(expected.z, tol), reason: 'z: $actual');
  }

  group('FrameConversion basis (Body X-fwd/Y-right/Z-down → Render)', () {
    test('body +X (forward) maps to render (0, 0, -1) — nose into screen', () {
      expectVec(FrameConversion.point(Vector3(1, 0, 0)), Vector3(0, 0, -1));
    });

    test('body +Y (right) maps to render (1, 0, 0) — right stays right', () {
      expectVec(FrameConversion.point(Vector3(0, 1, 0)), Vector3(1, 0, 0));
    });

    test('body +Z (down) maps to render (0, -1, 0) — belly points down', () {
      expectVec(FrameConversion.point(Vector3(0, 0, 1)), Vector3(0, -1, 0));
    });

    test('basis is a pure rotation (determinant +1, NOT a mirror)', () {
      final m = FrameConversion.bodyToRenderBasis;
      // determinant of a 3x3
      final det = m.determinant();
      expect(det, closeTo(1.0, 1e-9),
          reason: 'A determinant of -1 would mean the model is mirrored.');
    });

    test('basis is orthonormal (columns are unit and mutually perpendicular)',
        () {
      final m = FrameConversion.bodyToRenderBasis;
      final cx = m.transformed(Vector3(1, 0, 0));
      final cy = m.transformed(Vector3(0, 1, 0));
      final cz = m.transformed(Vector3(0, 0, 1));
      expect(cx.length, closeTo(1.0, 1e-9));
      expect(cy.length, closeTo(1.0, 1e-9));
      expect(cz.length, closeTo(1.0, 1e-9));
      expect(cx.dot(cy), closeTo(0.0, 1e-9));
      expect(cy.dot(cz), closeTo(0.0, 1e-9));
      expect(cx.dot(cz), closeTo(0.0, 1e-9));
    });
  });

  group('renderOrientation composes attitude then basis change', () {
    test('identity attitude yields the static basis-change quaternion', () {
      final q = FrameConversion.renderOrientation(Quaternion.identity());
      // Rotating render-frame nothing else, the model orientation equals the
      // basis change: its action on body axes equals FrameConversion.point.
      final m = q.asRotationMatrix();
      expectVec(m.transformed(Vector3(1, 0, 0)), Vector3(0, 0, -1), tol: 1e-7);
      expectVec(m.transformed(Vector3(0, 1, 0)), Vector3(1, 0, 0), tol: 1e-7);
      expectVec(m.transformed(Vector3(0, 0, 1)), Vector3(0, -1, 0), tol: 1e-7);
    });

    test('roll +90° right (about body +X) — right wing rotates down', () {
      // Body +X roll by +90°: body +Y (right) → body +Z (down),
      //                       body +Z (down)  → body −Y (left).
      final roll = Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2)
        ..normalize();
      final q = FrameConversion.renderOrientation(roll);
      final m = q.asRotationMatrix();
      // The right-wing tip (body +Y) should now point where body +Z maps in
      // render frame, i.e. (0, -1, 0) = down on screen. This confirms a
      // right roll tips the model's right side downward (not upward/mirrored).
      expectVec(m.transformed(Vector3(0, 1, 0)), Vector3(0, -1, 0), tol: 1e-7);
    });

    test('pitch +90° up (about body +Y) — nose rotates up', () {
      // Body +Y pitch by +90° (nose up in NED, where +pitch is nose-up):
      // body +X (forward) → body −Z (up), body +Z (down) → body +X (forward).
      final pitch = Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2)
        ..normalize();
      final q = FrameConversion.renderOrientation(pitch);
      final m = q.asRotationMatrix();
      // Nose (body +X) now points where body −Z maps in render = −(0,-1,0)
      // = (0, 1, 0) = up on screen. Nose-up pitches the model nose upward.
      expectVec(m.transformed(Vector3(1, 0, 0)), Vector3(0, 1, 0), tol: 1e-7);
    });
  });

  group('angleBetween', () {
    test('identical attitudes → 0', () {
      final q = Quaternion.axisAngle(Vector3(0, 0, 1), 0.5)..normalize();
      expect(FrameConversion.angleBetween(q, q.clone()), closeTo(0.0, 1e-6));
    });

    test('q and −q are treated as equal (double cover)', () {
      final q = Quaternion.axisAngle(Vector3(0, 1, 0), 1.0)..normalize();
      final neg = Quaternion(-q.x, -q.y, -q.z, -q.w);
      expect(FrameConversion.angleBetween(q, neg), closeTo(0.0, 1e-7));
    });

    test('90° apart about same axis → π/2', () {
      final a = Quaternion.axisAngle(Vector3(0, 0, 1), 0)..normalize();
      final b = Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 2)
        ..normalize();
      expect(FrameConversion.angleBetween(a, b), closeTo(math.pi / 2, 1e-7));
    });
  });
}
