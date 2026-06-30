import 'dart:async';

import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter/foundation.dart';

import '../mavlink/mavlink_service.dart';
import 'attitude_sample.dart';

/// A live source of [AttitudeSample]s for the Airframe Model.
///
/// Subscribes to the dedicated high-rate `ATTITUDE_QUATERNION` (msg 31)
/// stream off [MavlinkService], with a fall-back to euler `ATTITUDE`
/// (msg 30) when the FC does not emit the quaternion message. Exposes the
/// latest sample plus availability, and notifies listeners on each new
/// sample.
///
/// This deliberately does **not** go through `vehicleStateProvider`, which is
/// throttled to 30 Hz, carries euler only, and would trigger a global rebuild
/// storm at the rates the model wants.
class AttitudeSource extends ChangeNotifier {
  AttitudeSource(this._service) {
    _quatSub =
        _service.messagesOf<AttitudeQuaternionMessage>().listen(_onQuaternion);
    _eulerSub = _service.messagesOf<AttitudeMessage>().listen(_onEuler);
  }

  final MavlinkService _service;
  StreamSubscription<AttitudeQuaternionMessage>? _quatSub;
  StreamSubscription<AttitudeMessage>? _eulerSub;

  AttitudeSample? _latest;
  bool _usingQuaternion = false;
  DateTime? _lastQuaternionAt;

  /// How long we keep trusting the quaternion stream after the last sample
  /// before allowing euler to take over.
  static const _quaternionGrace = Duration(milliseconds: 500);

  /// The most recent attitude sample, or null if none has arrived yet.
  AttitudeSample? get latest => _latest;

  /// Whether any attitude has been received.
  bool get hasAttitude => _latest != null;

  /// True when the active source is the quaternion stream (vs euler fallback).
  bool get usingQuaternion => _usingQuaternion;

  void _onQuaternion(AttitudeQuaternionMessage m) {
    _lastQuaternionAt = DateTime.now();
    _usingQuaternion = true;
    _latest = AttitudeSample.fromComponents(
      w: m.q1,
      x: m.q2,
      y: m.q3,
      z: m.q4,
    );
    notifyListeners();
  }

  void _onEuler(AttitudeMessage m) {
    // Defer to the quaternion stream while it is fresh.
    final last = _lastQuaternionAt;
    if (last != null &&
        DateTime.now().difference(last) < _quaternionGrace) {
      return;
    }
    _usingQuaternion = false;
    _latest = AttitudeSample.fromEuler(
      roll: m.roll,
      pitch: m.pitch,
      yaw: m.yaw,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _quatSub?.cancel();
    _eulerSub?.cancel();
    super.dispose();
  }
}
