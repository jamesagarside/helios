import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

import 'frame_conversion.dart';
import 'mesh.dart';

/// Renders an [AirframeMesh] at a given orientation using stable
/// `Canvas.drawVertices`, a painter's-algorithm depth sort, and simple
/// Lambert face shading. No 3D-engine dependency (see ADR-0001) — runs on all
/// six Flutter targets including web.
class AirframePainter extends CustomPainter {
  AirframePainter({
    required this.mesh,
    required this.bodyAttitude,
    required this.colors,
    this.matched = false,
  });

  /// Geometry in the body frame.
  final AirframeMesh mesh;

  /// Live body→world attitude quaternion to draw the model at.
  final Quaternion bodyAttitude;

  final AirframePainterColors colors;

  /// When true (Orientation match), faces are tinted toward [colors.matched].
  final bool matched;

  // Fixed camera: looking from behind and above the vehicle. Applied on top
  // of the body→render basis change, so it is a cosmetic view only.
  static final Quaternion _cameraTilt =
      Quaternion.axisAngle(Vector3(1, 0, 0), -0.45);

  // Directional light in render space (from upper-front-left).
  static final Vector3 _lightDir = Vector3(-0.4, 0.7, 0.6).normalized();

  @override
  void paint(Canvas canvas, Size size) {
    if (mesh.isEmpty) return;

    final orientation = FrameConversion.renderOrientation(bodyAttitude);
    final view = (_cameraTilt * orientation)..normalize();
    final rot = view.asRotationMatrix();

    final cx = size.width / 2;
    final cy = size.height / 2;
    // Scale model units to fit the smaller dimension with margin.
    final scale = math.min(size.width, size.height) * 0.34;
    // Weak perspective: foreshorten by depth.
    const camZ = 4.0;

    // Transform every face into view space once.
    final transformed = <_ViewFace>[];
    for (final face in mesh.faces) {
      final a = rot.transformed(face.a);
      final b = rot.transformed(face.b);
      final c = rot.transformed(face.c);
      final depth = (a.z + b.z + c.z) / 3.0;

      // Back-face culling: skip faces whose normal points away from camera.
      final n = (b - a).cross(c - a);
      if (n.z <= 0) continue; // render frame +Z points toward viewer

      transformed.add(_ViewFace(a, b, c, depth, _shade(face, n)));
    }

    // Painter's algorithm: far faces first (most negative Z = furthest away).
    transformed.sort((p, q) => p.depth.compareTo(q.depth));

    // Project and emit per-face vertices. drawVertices with VertexMode.triangles
    // draws each triple as one flat-shaded triangle.
    Offset project(Vector3 v) {
      final persp = camZ / (camZ - v.z);
      return Offset(cx + v.x * scale * persp, cy - v.y * scale * persp);
    }

    final positions = <Offset>[];
    final vColors = <Color>[];
    for (final f in transformed) {
      positions.add(project(f.a));
      positions.add(project(f.b));
      positions.add(project(f.c));
      vColors.add(f.color);
      vColors.add(f.color);
      vColors.add(f.color);
    }

    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      colors: vColors,
    );
    // Faces are sorted far→near, so painting in order (srcOver) makes nearer
    // faces correctly occlude farther ones — the painter's algorithm.
    canvas.drawVertices(vertices, BlendMode.srcOver, Paint());

    // Thin edge pass for definition (only the silhouette would be ideal, but
    // per-face outlines read cleanly at this poly count).
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = colors.edge;
    for (final f in transformed) {
      final p = Path()
        ..moveTo(project(f.a).dx, project(f.a).dy)
        ..lineTo(project(f.b).dx, project(f.b).dy)
        ..lineTo(project(f.c).dx, project(f.c).dy)
        ..close();
      canvas.drawPath(p, edge);
    }
  }

  Color _shade(Face face, Vector3 viewNormal) {
    final n = viewNormal.normalized();
    // Lambert term: clamp to an ambient floor so back regions aren't black.
    final lambert = n.dot(_lightDir).clamp(0.0, 1.0);
    const ambient = 0.45;
    final intensity = (ambient + (1 - ambient) * lambert).clamp(0.0, 1.0);
    var base = face.baseColor;
    if (matched) {
      base = Color.lerp(base, colors.matched, 0.55)!;
    }
    final r = (base.r * 255.0 * intensity).round().clamp(0, 255);
    final g = (base.g * 255.0 * intensity).round().clamp(0, 255);
    final b = (base.b * 255.0 * intensity).round().clamp(0, 255);
    return Color.fromARGB((base.a * 255.0).round(), r, g, b);
  }

  @override
  bool shouldRepaint(covariant AirframePainter old) =>
      old.bodyAttitude != bodyAttitude ||
      old.matched != matched ||
      !identical(old.mesh, mesh);
}

/// View-space face after rotation, ready to project.
class _ViewFace {
  _ViewFace(this.a, this.b, this.c, this.depth, this.color);
  final Vector3 a;
  final Vector3 b;
  final Vector3 c;
  final double depth;
  final Color color;
}

/// Theme colours the painter needs, decoupled from the Flutter theme so the
/// painter stays testable.
class AirframePainterColors {
  const AirframePainterColors({required this.edge, required this.matched});
  final Color edge;
  final Color matched;
}
