import 'dart:async';
import 'package:gamepads/gamepads.dart';

/// Joystick channel values from a single event poll.
class JoystickChannels {
  const JoystickChannels({
    this.ch1Roll = 1500,
    this.ch2Pitch = 1500,
    this.ch3Throttle = 1000,
    this.ch4Yaw = 1500,
  });

  final int ch1Roll;
  final int ch2Pitch;
  final int ch3Throttle;
  final int ch4Yaw;
}

/// Listens to a connected gamepad and exposes RC channel values.
///
/// Mode 2 mapping (standard transmitter layout):
///   Left stick X  → CH4 Yaw
///   Left stick Y  → CH3 Throttle (up = max, center = mid, down = min)
///   Right stick X → CH1 Roll
///   Right stick Y → CH2 Pitch (inverted)
class JoystickService {
  StreamSubscription<NormalizedGamepadEvent>? _sub;

  // Current axis values in normalized form (-1..1 or 0..1 for triggers)
  double _rollAxis = 0.0;
  double _pitchAxis = 0.0;
  double _throttleAxis = -1.0; // starts at bottom (1000 µs)
  double _yawAxis = 0.0;

  bool _active = false;
  bool get isActive => _active;

  /// Start listening to gamepad events.
  void start() {
    if (_active) return;
    _active = true;
    _sub = Gamepads.normalizedEvents.listen(_onEvent);
  }

  /// Stop listening.
  void stop() {
    _active = false;
    _sub?.cancel();
    _sub = null;
  }

  void _onEvent(NormalizedGamepadEvent event) {
    if (event.axis == null) return;
    switch (event.axis!) {
      case GamepadAxis.rightStickX:
        _rollAxis = event.value.clamp(-1.0, 1.0);
      case GamepadAxis.rightStickY:
        _pitchAxis = event.value.clamp(-1.0, 1.0);
      case GamepadAxis.leftStickY:
        _throttleAxis = event.value.clamp(-1.0, 1.0);
      case GamepadAxis.leftStickX:
        _yawAxis = event.value.clamp(-1.0, 1.0);
      default:
        break;
    }
  }

  /// Convert current axis state to RC channel PWM values (1000–2000 µs).
  JoystickChannels get channels => JoystickChannels(
        ch1Roll: _axisToPwm(_rollAxis),
        ch2Pitch: _axisToPwm(-_pitchAxis), // inverted
        ch3Throttle: _throttleToPwm(_throttleAxis),
        ch4Yaw: _axisToPwm(_yawAxis),
      );

  /// Symmetric axis (-1..1) → 1000..2000, center = 1500.
  static int _axisToPwm(double v) => (1500 + v * 500).round().clamp(1000, 2000);

  /// Throttle axis: -1 = fully down = 1000 µs, +1 = fully up = 2000 µs.
  static int _throttleToPwm(double v) =>
      (1000 + (v + 1) / 2 * 1000).round().clamp(1000, 2000);

  void dispose() => stop();
}
