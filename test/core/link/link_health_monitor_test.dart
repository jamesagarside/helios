import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/link/link_health_monitor.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';

void main() {
  group('LinkHealthMonitor', () {
    late LinkHealthMonitor monitor;

    tearDown(() {
      monitor.dispose();
    });

    test('starts in disconnected state', () {
      monitor = LinkHealthMonitor();
      expect(monitor.state, LinkState.disconnected);
    });

    test('transitions to connected on activity', () {
      monitor = LinkHealthMonitor();
      monitor.recordActivity();
      expect(monitor.state, LinkState.connected);
    });

    test('transitions to lost after both thresholds', () async {
      // Use thresholds wider than the 500ms poll interval
      monitor = LinkHealthMonitor(
        degradedThreshold: const Duration(milliseconds: 300),
        lostThreshold: const Duration(milliseconds: 800),
      );

      monitor.recordActivity();
      expect(monitor.state, LinkState.connected);

      // Wait past lost threshold + poll interval margin
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(monitor.state, LinkState.lost);
    });

    test('passes through degraded before lost', () async {
      monitor = LinkHealthMonitor(
        degradedThreshold: const Duration(milliseconds: 200),
        lostThreshold: const Duration(milliseconds: 5000),
        pollInterval: const Duration(milliseconds: 100),
      );

      final states = <LinkState>[];
      monitor.stateStream.listen(states.add);

      monitor.recordActivity();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(monitor.state, LinkState.degraded);
      expect(states, contains(LinkState.connected));
      expect(states, contains(LinkState.degraded));
    });

    test('recovers to connected when activity resumes after degraded',
        () async {
      monitor = LinkHealthMonitor(
        degradedThreshold: const Duration(milliseconds: 50),
        lostThreshold: const Duration(milliseconds: 5000), // very long
        pollInterval: const Duration(milliseconds: 100),
      );

      monitor.recordActivity();

      // Wait for degraded
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(monitor.state, LinkState.degraded);

      // Activity resumes
      monitor.recordActivity();
      expect(monitor.state, LinkState.connected);
    });

    test('reset returns to disconnected', () {
      monitor = LinkHealthMonitor();
      monitor.recordActivity();
      expect(monitor.state, LinkState.connected);

      monitor.reset();
      expect(monitor.state, LinkState.disconnected);
    });

    test('emits state changes on stream', () async {
      monitor = LinkHealthMonitor();
      final states = <LinkState>[];
      monitor.stateStream.listen(states.add);

      monitor.recordActivity();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states, contains(LinkState.connected));
    });

    test('stays connected with regular activity', () async {
      monitor = LinkHealthMonitor(
        degradedThreshold: const Duration(milliseconds: 200),
        lostThreshold: const Duration(milliseconds: 500),
      );

      // Record activity every 50ms for 400ms
      for (var i = 0; i < 8; i++) {
        monitor.recordActivity();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(monitor.state, LinkState.connected);
    });
  });
}
