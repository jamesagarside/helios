import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/joystick/joystick_service.dart';
import 'providers.dart';

class JoystickState {
  const JoystickState({
    this.enabled = false,
    this.gamepadConnected = false,
  });

  final bool enabled;
  final bool gamepadConnected;

  JoystickState copyWith({bool? enabled, bool? gamepadConnected}) =>
      JoystickState(
        enabled: enabled ?? this.enabled,
        gamepadConnected: gamepadConnected ?? this.gamepadConnected,
      );
}

class JoystickNotifier extends StateNotifier<JoystickState> {
  JoystickNotifier(this._ref) : super(const JoystickState());

  final Ref _ref;
  final JoystickService _joystick = JoystickService();
  Timer? _sendTimer;

  /// Toggle RC override on/off.
  Future<void> toggle() async {
    if (state.enabled) {
      _disable();
    } else {
      await _enable();
    }
  }

  Future<void> _enable() async {
    _joystick.start();
    state = state.copyWith(enabled: true);
    // Send RC_CHANNELS_OVERRIDE at 25 Hz
    _sendTimer = Timer.periodic(
      const Duration(milliseconds: 40),
      (_) => _sendChannels(),
    );
  }

  void _disable() {
    _sendTimer?.cancel();
    _sendTimer = null;
    _joystick.stop();
    state = state.copyWith(enabled: false);
  }

  void _sendChannels() {
    final ctrl = _ref.read(connectionControllerProvider.notifier);
    final ch = _joystick.channels;
    ctrl.sendRcOverride(
      ch1: ch.ch1Roll,
      ch2: ch.ch2Pitch,
      ch3: ch.ch3Throttle,
      ch4: ch.ch4Yaw,
    );
  }

  @override
  void dispose() {
    _disable();
    super.dispose();
  }
}

final joystickProvider =
    StateNotifierProvider<JoystickNotifier, JoystickState>(
  (ref) => JoystickNotifier(ref),
);
