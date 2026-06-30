import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// Converts attitude from the MAVLink **Body frame** (X-forward, Y-right,
/// Z-down) into the **Render frame** used to draw the Airframe Model.
///
/// This is the single highest correctness risk in the feature: get the basis
/// change wrong and the model appears inverted or mirrored. It is therefore
/// isolated here, pure, and unit-tested with known quaternion inputs.
///
/// ## Render frame definition
///
/// The render frame is a conventional right-handed screen frame:
/// * **X → right** on screen
/// * **Y → up** on screen
/// * **Z → out of the screen**, toward the viewer
///
/// ## Mapping (Body axis → Render axis)
///
/// Resolved so that, at identity attitude (vehicle level, nose world-North):
/// * body +X (forward) → render (0, 0, −1): nose points *into* the screen,
/// * body +Y (right)   → render (1, 0,  0): right wing points right,
/// * body +Z (down)    → render (0, −1, 0): belly points down.
///
/// Both frames are right-handed, so the change of basis is a pure rotation
/// (determinant +1) — never a reflection. A reflection here is exactly the
/// "mirrored" failure mode we are guarding against. The camera tilts this
/// view for a "from behind and above" angle, but that is a cosmetic view
/// transform in the renderer, not part of this correctness-critical basis.
class FrameConversion {
  const FrameConversion._();

  /// Static change-of-basis matrix from Body frame to Render frame.
  ///
  /// `vector_math`'s `Matrix3` constructor takes arguments **column by
  /// column**. Columns are the images of the body basis vectors in the
  /// render frame:
  ///   col0 = image of body +X = (0, 0, -1)
  ///   col1 = image of body +Y = (1, 0,  0)
  ///   col2 = image of body +Z = (0, -1, 0)
  static final Matrix3 bodyToRenderBasis = Matrix3(
    0.0, 0.0, -1.0, // col0
    1.0, 0.0, 0.0, // col1
    0.0, -1.0, 0.0, // col2
  );

  /// Equivalent rotation as a quaternion (precomputed, normalised).
  static final Quaternion bodyToRender =
      Quaternion.fromRotation(bodyToRenderBasis)..normalize();

  /// Rotate a body-frame point into the render frame.
  static Vector3 point(Vector3 bodyPoint) =>
      bodyToRenderBasis.transformed(bodyPoint);

  /// Convert a body→world attitude quaternion into the render-frame
  /// orientation quaternion used to rotate the model's geometry.
  ///
  /// The model's mesh is authored in the body frame. To draw it at the live
  /// attitude in the render frame we apply the live body→world rotation and
  /// then the fixed basis change. Composing [bodyToRender] with the live
  /// attitude yields the model orientation directly.
  static Quaternion renderOrientation(Quaternion bodyAttitude) {
    return (bodyToRender * bodyAttitude)..normalize();
  }

  /// Angular difference (radians) between two body-frame attitudes.
  ///
  /// Used by Orientation match to decide whether the live attitude is within
  /// tolerance of a requested target pose. Returns the geodesic angle on the
  /// unit-quaternion sphere, in `[0, π]`, treating `q` and `−q` as equal.
  static double angleBetween(Quaternion a, Quaternion b) {
    final an = a.normalized();
    final bn = b.normalized();
    var dot = an.x * bn.x + an.y * bn.y + an.z * bn.z + an.w * bn.w;
    dot = dot.abs().clamp(0.0, 1.0);
    return 2.0 * math.acos(dot);
  }
}
