import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

import 'airframe_config.dart';
import 'mesh.dart';

/// Emits an [AirframeMesh] procedurally from an [AirframeConfig].
///
/// Geometry is authored in the **body frame** (X-forward, Y-right, Z-down),
/// in arbitrary model units (~1.0 = body half-extent). The renderer scales to
/// fit. The builder is pure and deterministic so meshes can be cached and
/// rebuilt only when the config changes.
class DroneMeshBuilder {
  const DroneMeshBuilder();

  // Palette — kept neutral so the model reads on the dark theme. The nose/
  // front is tinted so orientation is unambiguous at a glance.
  static const _bodyTop = Color(0xFF4A5568);
  static const _bodyBottom = Color(0xFF2D3748);
  static const _bodySide = Color(0xFF3C4757);
  static const _arm = Color(0xFF5A6678);
  static const _rotor = Color(0x66A0AEC0);
  static const _nose = Color(0xFFE53E3E);
  static const _wing = Color(0xFF4A5568);
  static const _tail = Color(0xFF3C4757);

  AirframeMesh build(AirframeConfig config) {
    switch (config.archetype) {
      case AirframeArchetype.multirotor:
        return AirframeMesh(_multirotor(config));
      case AirframeArchetype.fixedWing:
        return AirframeMesh(_fixedWing());
      case AirframeArchetype.quadplane:
        return AirframeMesh(_quadplane(config));
    }
  }

  // ─── Multirotor ────────────────────────────────────────────────────────

  List<Face> _multirotor(AirframeConfig config) {
    final faces = <Face>[];
    // Central body: a small box with a forward nose wedge.
    faces.addAll(_box(
      center: Vector3(0, 0, 0),
      halfExtents: Vector3(0.35, 0.35, 0.12),
      top: _bodyTop,
      bottom: _bodyBottom,
      side: _bodySide,
      nose: _nose,
    ));

    final n = config.motorCount.clamp(1, 12);
    final angles = _armAngles(n, config.armLayout);
    const armRadius = 0.95;
    const rotorRadius = 0.38;
    for (final ang in angles) {
      final dir = Vector3(math.cos(ang), math.sin(ang), 0);
      final motorPos = dir * armRadius;
      // Arm: a thin box from body edge to motor.
      faces.addAll(_armBox(Vector3.zero(), motorPos, 0.05, 0.04));
      // Motor pod.
      faces.addAll(_box(
        center: motorPos + Vector3(0, 0, -0.02),
        halfExtents: Vector3(0.08, 0.08, 0.06),
        top: _bodyTop,
        bottom: _bodyBottom,
        side: _bodySide,
        nose: _bodySide,
      ));
      // Rotor disc, just above the motor (negative Z = up in body frame).
      faces.addAll(_disc(
        center: motorPos + Vector3(0, 0, -0.10),
        radius: rotorRadius,
        color: _rotor,
        segments: 16,
        faceUp: true,
      ));
    }
    return faces;
  }

  /// Body-frame yaw angles (radians, 0 = +X forward) for [n] arms in [layout].
  List<double> _armAngles(int n, ArmLayout layout) {
    if (n <= 0) return const [];
    if (n == 1) return [0.0]; // single rotor / heli — forward
    final out = <double>[];
    switch (layout) {
      case ArmLayout.plus:
        for (var i = 0; i < n; i++) {
          out.add(2 * math.pi * i / n);
        }
      case ArmLayout.x:
        // Rotate so no arm sits on the nose; arms straddle the X axis.
        final offset = math.pi / n;
        for (var i = 0; i < n; i++) {
          out.add(offset + 2 * math.pi * i / n);
        }
      case ArmLayout.v:
        // Forward-swept fan within ±70° of the nose, plus a tail arm.
        const spread = 70 * math.pi / 180;
        for (var i = 0; i < n; i++) {
          final t = n == 1 ? 0.0 : (i / (n - 1)) * 2 - 1; // -1..1
          out.add(t * spread);
        }
      case ArmLayout.h:
        // Front/back pairs offset left/right.
        for (var i = 0; i < n; i++) {
          final front = i.isEven;
          final base = front ? math.pi / 4 : 3 * math.pi / 4;
          final side = (i ~/ 2).isEven ? 1.0 : -1.0;
          out.add(side * base);
        }
    }
    return out;
  }

  // ─── Fixed-wing ────────────────────────────────────────────────────────

  List<Face> _fixedWing() {
    final faces = <Face>[];
    // Fuselage: slender box with a nose wedge.
    faces.addAll(_box(
      center: Vector3(0.1, 0, 0),
      halfExtents: Vector3(0.7, 0.12, 0.12),
      top: _bodyTop,
      bottom: _bodyBottom,
      side: _bodySide,
      nose: _nose,
    ));
    // Main wing: flat slab spanning Y, set slightly back from the nose.
    faces.addAll(_slab(
      center: Vector3(-0.05, 0, -0.02),
      halfExtents: Vector3(0.22, 1.05, 0.02),
      color: _wing,
    ));
    // Horizontal stabiliser at the tail.
    faces.addAll(_slab(
      center: Vector3(-0.75, 0, -0.02),
      halfExtents: Vector3(0.16, 0.45, 0.02),
      color: _tail,
    ));
    // Vertical fin (in body X-Z plane, standing up = −Z).
    faces.addAll(_fin(
      base: Vector3(-0.78, 0, 0),
      length: 0.34,
      height: 0.32,
      color: _tail,
    ));
    return faces;
  }

  // ─── Quadplane / VTOL ──────────────────────────────────────────────────

  List<Face> _quadplane(AirframeConfig config) {
    final faces = <Face>[];
    faces.addAll(_fixedWing());
    // Lift arms running fore/aft along the fuselage with rotors.
    final n = config.motorCount.clamp(2, 8);
    const span = 0.85; // lateral booms
    const fore = 0.55;
    const rotorRadius = 0.30;
    // Place pairs: front-left, front-right, rear-left, rear-right, ...
    final positions = <Vector3>[];
    final pairs = (n / 2).ceil();
    for (var i = 0; i < pairs; i++) {
      final x = fore - (i * 2 * fore / math.max(1, pairs - 1));
      positions.add(Vector3(x, span, 0));
      if (positions.length < n) positions.add(Vector3(x, -span, 0));
    }
    // Lateral booms connecting rotors to the fuselage.
    for (final side in [span, -span]) {
      faces.addAll(_armBox(
        Vector3(fore, side * 0.4, 0),
        Vector3(-fore, side * 0.4, 0),
        0.04,
        0.03,
      ));
      faces.addAll(_armBox(
        Vector3(0, side * 0.18, 0),
        Vector3(0, side, 0),
        0.04,
        0.03,
      ));
    }
    for (final p in positions) {
      faces.addAll(_box(
        center: p + Vector3(0, 0, -0.02),
        halfExtents: Vector3(0.07, 0.07, 0.05),
        top: _bodyTop,
        bottom: _bodyBottom,
        side: _bodySide,
        nose: _bodySide,
      ));
      faces.addAll(_disc(
        center: p + Vector3(0, 0, -0.10),
        radius: rotorRadius,
        color: _rotor,
        segments: 14,
        faceUp: true,
      ));
    }
    return faces;
  }

  // ─── Primitive helpers ──────────────────────────────────────────────────

  /// Axis-aligned box centred at [center]. The +X (forward) face is coloured
  /// [nose] so heading is unambiguous.
  List<Face> _box({
    required Vector3 center,
    required Vector3 halfExtents,
    required Color top,
    required Color bottom,
    required Color side,
    required Color nose,
  }) {
    final h = halfExtents;
    Vector3 v(double sx, double sy, double sz) =>
        center + Vector3(sx * h.x, sy * h.y, sz * h.z);
    // 8 corners
    final ppp = v(1, 1, 1), ppm = v(1, 1, -1), pmp = v(1, -1, 1);
    final pmm = v(1, -1, -1), mpp = v(-1, 1, 1), mpm = v(-1, 1, -1);
    final mmp = v(-1, -1, 1), mmm = v(-1, -1, -1);
    // In body frame, −Z is up, +Z is down.
    return [
      // +X (forward / nose) — coloured
      ..._quad(pmm, pmp, ppp, ppm, nose),
      // −X (rear)
      ..._quad(mpm, mpp, mmp, mmm, side),
      // +Y (right)
      ..._quad(ppm, ppp, mpp, mpm, side),
      // −Y (left)
      ..._quad(mmm, mmp, pmp, pmm, side),
      // −Z (top)
      ..._quad(mpm, mmm, pmm, ppm, top),
      // +Z (bottom)
      ..._quad(mmp, mpp, ppp, pmp, bottom),
    ];
  }

  /// Thin slab (wing/stabiliser): a flattened box, single colour.
  List<Face> _slab({
    required Vector3 center,
    required Vector3 halfExtents,
    required Color color,
  }) {
    return _box(
      center: center,
      halfExtents: halfExtents,
      top: color,
      bottom: color,
      side: color,
      nose: color,
    );
  }

  /// Vertical tail fin in the body X-Z plane, rising from [base] toward −Z
  /// (up) and back toward −X.
  List<Face> _fin({
    required Vector3 base,
    required double length,
    required double height,
    required Color color,
  }) {
    final a = base + Vector3(length * 0.4, 0, 0);
    final b = base - Vector3(length * 0.6, 0, 0);
    final c = base - Vector3(length * 0.6, 0, height);
    // Two triangles, both sides (thin), wound for outward normals on ±Y.
    return [
      Face(a, b, c, color),
      Face(a.clone(), c.clone(), b.clone(), color),
    ];
  }

  /// A box-section arm between two body-frame points [from] and [to].
  List<Face> _armBox(Vector3 from, Vector3 to, double width, double thick) {
    final axis = to - from;
    final len = axis.length;
    if (len < 1e-6) return const [];
    final dir = axis / len;
    // Perpendicular in the body XY plane.
    var perp = Vector3(-dir.y, dir.x, 0);
    if (perp.length < 1e-6) perp = Vector3(0, 1, 0);
    perp = perp.normalized() * width;
    final up = Vector3(0, 0, thick);
    // 8 corners of the rectangular prism.
    final f0 = from + perp + up, f1 = from - perp + up;
    final f2 = from - perp - up, f3 = from + perp - up;
    final t0 = to + perp + up, t1 = to - perp + up;
    final t2 = to - perp - up, t3 = to + perp - up;
    return [
      ..._quad(f0, t0, t1, f1, _arm), // top
      ..._quad(f3, f2, t2, t3, _arm), // bottom
      ..._quad(f0, f3, t3, t0, _arm), // +perp side
      ..._quad(f1, t1, t2, f2, _arm), // −perp side
      ..._quad(t0, t3, t2, t1, _arm), // far cap
      ..._quad(f0, f1, f2, f3, _arm), // near cap
    ];
  }

  /// A flat n-gon disc (rotor) centred at [center] in the body XY plane.
  List<Face> _disc({
    required Vector3 center,
    required double radius,
    required Color color,
    required int segments,
    required bool faceUp,
  }) {
    final faces = <Face>[];
    for (var i = 0; i < segments; i++) {
      final a0 = 2 * math.pi * i / segments;
      final a1 = 2 * math.pi * (i + 1) / segments;
      final p0 = center + Vector3(math.cos(a0), math.sin(a0), 0) * radius;
      final p1 = center + Vector3(math.cos(a1), math.sin(a1), 0) * radius;
      // Wind so the normal points up (−Z) when faceUp.
      if (faceUp) {
        faces.add(Face(center, p1, p0, color));
      } else {
        faces.add(Face(center, p0, p1, color));
      }
    }
    return faces;
  }

  /// Quad as two triangles, wound a→b→c→d (CCW from outside).
  List<Face> _quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Color color) {
    return [Face(a, b, c, color), Face(a.clone(), c.clone(), d.clone(), color)];
  }
}
