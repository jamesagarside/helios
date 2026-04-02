import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/mavlink/heartbeat_watchdog.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';

void main() {
  group('HeartbeatWatchdog', () {
    late HeartbeatWatchdog watchdog;

    tearDown(() {
      watchdog.dispose();
    });

    test('starts in disconnected state', () {
      watchdog = HeartbeatWatchdog();
      expect(watchdog.state, LinkState.disconnected);
    });

    test('transitions to connected on heartbeat', () {
      watchdog = HeartbeatWatchdog();
      watchdog.onHeartbeatReceived();
      expect(watchdog.state, LinkState.connected);
    });

    test('transitions to lost after both thresholds', () async {
      // Use thresholds wider than the 500ms poll interval
      watchdog = HeartbeatWatchdog(
        degradedThreshold: const Duration(milliseconds: 300),
        lostThreshold: const Duration(milliseconds: 800),
      );

      watchdog.onHeartbeatReceived();
      expect(watchdog.state, LinkState.connected);

      // Wait past lost threshold + poll interval margin
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(watchdog.state, LinkState.lost);
    });

    test('recovers to connected when heartbeat resumes after degraded', () async {
      watchdog = HeartbeatWatchdog(
        degradedThreshold: const Duration(milliseconds: 50),
        lostThreshold: const Duration(milliseconds: 5000), // very long — won't hit lost
      );

      watchdog.onHeartbeatReceived();

      // Wait for degraded
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(watchdog.state, LinkState.degraded);

      // Heartbeat resumes
      watchdog.onHeartbeatReceived();
      expect(watchdog.state, LinkState.connected);
    });

    test('reset returns to disconnected', () {
      watchdog = HeartbeatWatchdog();
      watchdog.onHeartbeatReceived();
      expect(watchdog.state, LinkState.connected);

      watchdog.reset();
      expect(watchdog.state, LinkState.disconnected);
    });

    test('emits state changes on stream', () async {
      watchdog = HeartbeatWatchdog();
      final states = <LinkState>[];
      watchdog.stateStream.listen(states.add);

      watchdog.onHeartbeatReceived();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states, contains(LinkState.connected));
    });

    test('stays connected with regular heartbeats', () async {
      watchdog = HeartbeatWatchdog(
        degradedThreshold: const Duration(milliseconds: 200),
        lostThreshold: const Duration(milliseconds: 500),
      );

      // Send heartbeats every 50ms for 400ms
      for (var i = 0; i < 8; i++) {
        watchdog.onHeartbeatReceived();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(watchdog.state, LinkState.connected);
    });
  });
}
