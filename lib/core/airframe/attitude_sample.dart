import 'package:vector_math/vector_math_64.dart';

/// A single attitude reading expressed in the MAVLink **Body frame**
/// (X-forward, Y-right, Z-down), captured off the live link.
///
/// The quaternion follows the MAVLink ATTITUDE_QUATERNION convention
/// `[w, x, y, z]`, rotating the body frame to the world (NED) frame.
class AttitudeSample {
  AttitudeSample({
    required this.quaternion,
    required this.timestamp,
  });

  /// Build a sample from raw quaternion components `[w, x, y, z]`.
  factory AttitudeSample.fromComponents({
    required double w,
    required double x,
    required double y,
    required double z,
    DateTime? timestamp,
  }) {
    final q = Quaternion(x, y, z, w);
    // Guard against zero/denormalised quaternions from a stale FC.
    if (q.length2 < 1e-9) {
      return AttitudeSample(
        quaternion: Quaternion.identity(),
        timestamp: timestamp ?? DateTime.now(),
      );
    }
    q.normalize();
    return AttitudeSample(
      quaternion: q,
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  /// Build a sample from euler angles (radians) in the Body frame, as
  /// reported by the legacy `ATTITUDE` message.
  ///
  /// MAVLink convention: roll about body +X, pitch about body +Y, yaw about
  /// body +Z, composed as `R = Rz(yaw) · Ry(pitch) · Rx(roll)`. We build the
  /// quaternion explicitly from axis-angle factors rather than using
  /// `Quaternion.euler`, whose axis convention does **not** match MAVLink's.
  factory AttitudeSample.fromEuler({
    required double roll,
    required double pitch,
    required double yaw,
    DateTime? timestamp,
  }) {
    final qx = Quaternion.axisAngle(Vector3(1, 0, 0), roll);
    final qy = Quaternion.axisAngle(Vector3(0, 1, 0), pitch);
    final qz = Quaternion.axisAngle(Vector3(0, 0, 1), yaw);
    final q = (qz * qy * qx)..normalize();
    return AttitudeSample(
      quaternion: q,
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  /// Body→world (NED) rotation. Stored normalised.
  final Quaternion quaternion;

  /// Wall-clock time the sample was received (not the FC boot time).
  final DateTime timestamp;

  static final identity = AttitudeSample(
    quaternion: Quaternion.identity(),
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
  );
}
