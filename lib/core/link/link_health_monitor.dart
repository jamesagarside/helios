import 'dart:async';
import '../../shared/models/vehicle_state.dart';

/// Tracks the **Link health** of a Link from raw message activity, the same way
/// for every protocol (see the *Link health* entry in `CONTEXT.md`).
///
/// Each Protocol adapter calls [recordActivity] whenever a fact arrives off the
/// wire — MAVLink on every HEARTBEAT, MSP on every response frame — and this
/// monitor folds that activity into the shared connected / degraded / lost
/// state machine:
///
/// ```
/// DISCONNECTED → CONNECTED → DEGRADED → LOST
/// ```
///
/// It recovers to CONNECTED as soon as activity resumes. This is the one
/// link-health module the seam exposes; it replaces the per-protocol watchdog
/// timers that used to live in both stacks.
class LinkHealthMonitor {
  LinkHealthMonitor({
    this.degradedThreshold = const Duration(seconds: 2),
    this.lostThreshold = const Duration(seconds: 5),
    this.pollInterval = const Duration(milliseconds: 500),
  });

  /// Elapsed-since-activity beyond which the Link is considered degraded.
  final Duration degradedThreshold;

  /// Elapsed-since-activity beyond which the Link is considered lost.
  final Duration lostThreshold;

  /// How often the internal timer re-evaluates elapsed time.
  final Duration pollInterval;

  Timer? _timer;
  DateTime? _lastActivity;
  LinkState _state = LinkState.disconnected;

  final _stateController = StreamController<LinkState>.broadcast();

  /// Current Link health.
  LinkState get state => _state;

  /// Stream of Link-health changes.
  Stream<LinkState> get stateStream => _stateController.stream;

  /// Record inbound message activity off the wire.
  ///
  /// Marks the Link connected and (re)starts the elapsed-time evaluation timer.
  /// Called by MAVLink on HEARTBEAT and by MSP on any response frame.
  void recordActivity() {
    _lastActivity = DateTime.now();
    _setState(LinkState.connected);
    _ensureTimerRunning();
  }

  /// Reset to the disconnected state and stop evaluating.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _lastActivity = null;
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
    _timer = Timer.periodic(pollInterval, (_) {
      final last = _lastActivity;
      if (last == null) return;

      final elapsed = DateTime.now().difference(last);
      if (elapsed >= lostThreshold) {
        _setState(LinkState.lost);
      } else if (elapsed >= degradedThreshold) {
        _setState(LinkState.degraded);
      }
    });
  }

  /// Release resources.
  void dispose() {
    _timer?.cancel();
    _stateController.close();
  }
}
