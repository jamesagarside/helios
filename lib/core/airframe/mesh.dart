import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

/// A single flat-shaded triangle face in body-frame coordinates.
///
/// Vertices are wound counter-clockwise when viewed from outside the solid,
/// so the outward normal follows the right-hand rule. [baseColor] is the
/// unlit material colour; Lambert shading is applied at render time.
class Face {
  Face(this.a, this.b, this.c, this.baseColor);

  final Vector3 a;
  final Vector3 b;
  final Vector3 c;
  final Color baseColor;

  /// Geometric centroid — used for painter's-algorithm depth sorting.
  Vector3 get centroid => Vector3(
        (a.x + b.x + c.x) / 3.0,
        (a.y + b.y + c.y) / 3.0,
        (a.z + b.z + c.z) / 3.0,
      );

  /// Outward-facing unit normal (right-hand rule over a→b→c).
  Vector3 get normal {
    final n = (b - a).cross(c - a);
    final len = n.length;
    if (len < 1e-9) return Vector3(0, 0, 1);
    return n..scale(1.0 / len);
  }
}

/// An immutable collection of faces forming one Airframe Model, authored in
/// the body frame (X-forward, Y-right, Z-down).
class AirframeMesh {
  const AirframeMesh(this.faces);

  final List<Face> faces;

  bool get isEmpty => faces.isEmpty;
}
