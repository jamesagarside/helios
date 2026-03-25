import 'dart:async';
import '../../shared/models/vehicle_state.dart';

/// Monitors vehicle heartbeat and transitions through link states.
///
/// States: DISCONNECTED → CONNECTED → DEGRADED → LOST
/// Recovers to CONNECTED when heartbeat resumes.
class HeartbeatWatchdog {
  HeartbeatWatchdog({
    this.degradedThreshold = const Duration(seconds: 2),
    this.lostThreshold = const Duration(seconds: 5),
  });

  final Duration degradedThreshold;
  final Duration lostThreshold;

  Timer? _timer;
  DateTime? _lastHeartbeat;
  LinkState _state = LinkState.disconnected;

  final _stateController = StreamController<LinkState>.broadcast();

  /// Current link state.
  LinkState get state => _state;

  /// Stream of link state changes.
  Stream<LinkState> get stateStream => _stateController.stream;

  /// Call when a heartbeat message is received.
  void onHeartbeatReceived() {
    _lastHeartbeat = DateTime.now();
    _setState(LinkState.connected);
    _ensureTimerRunning();
  }

  /// Reset to disconnected state.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _lastHeartbeat = null;
    _setState(LinkState.disconnected);
  }

  void _setState(LinkState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(newState);
    }
  }

  void _ensureTimerRunning() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_lastHeartbeat == null) return;

      final elapsed = DateTime.now().difference(_lastHeartbeat!);
      if (elapsed >= lostThreshold) {
        _setState(LinkState.lost);
      } else if (elapsed >= degradedThreshold) {
        _setState(LinkState.degraded);
      }
    });
  }

  /// Dispose resources.
  void dispose() {
    _timer?.cancel();
    _stateController.close();
  }
}
