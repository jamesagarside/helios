import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/airframe/attitude_sample.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  group('AttitudeSample.fromComponents', () {
    test('normalises the quaternion', () {
      final s = AttitudeSample.fromComponents(w: 2, x: 0, y: 0, z: 0);
      expect(s.quaternion.length, closeTo(1.0, 1e-9));
      expect(s.quaternion.w, closeTo(1.0, 1e-9));
    });

    test('zero quaternion falls back to identity', () {
      final s = AttitudeSample.fromComponents(w: 0, x: 0, y: 0, z: 0);
      expect(s.quaternion.w, closeTo(1.0, 1e-9));
      expect(s.quaternion.x, closeTo(0.0, 1e-9));
    });

    test('maps MAVLink [q1,q2,q3,q4] = [w,x,y,z] correctly', () {
      // 90° yaw about Z: w=cos45, z=sin45.
      final c = math.cos(math.pi / 4);
      final s = AttitudeSample.fromComponents(w: c, x: 0, y: 0, z: c);
      expect(s.quaternion.w, closeTo(c, 1e-9));
      expect(s.quaternion.z, closeTo(c, 1e-9));
    });
  });

  group('AttitudeSample.fromEuler', () {
    test('level (0,0,0) → identity quaternion', () {
      final s = AttitudeSample.fromEuler(roll: 0, pitch: 0, yaw: 0);
      expect(s.quaternion.w.abs(), closeTo(1.0, 1e-9));
    });

    test('pure roll matches an axis-angle quaternion about X', () {
      final s = AttitudeSample.fromEuler(roll: math.pi / 2, pitch: 0, yaw: 0);
      final expected = Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2)
        ..normalize();
      // Compare as orientations (sign-independent).
      final dot = (s.quaternion.x * expected.x +
              s.quaternion.y * expected.y +
              s.quaternion.z * expected.z +
              s.quaternion.w * expected.w)
          .abs();
      expect(dot, closeTo(1.0, 1e-6));
    });
  });
}
