import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helios_gcs/app.dart';
import 'package:helios_gcs/shared/widgets/splash_screen.dart';

/// Pumps [HeliosApp] inside an [UncontrolledProviderScope] backed by a
/// freshly-created [ProviderContainer], returned so the test can dispose it.
///
/// Isolating a container per test — and disposing it at the end of the test
/// body via [_teardownApp] — is what makes these smoke tests deterministic
/// under parallel test isolates. The main shell reads
/// `serialPortMonitorProvider` from its `initState`, which starts a
/// `Timer.periodic(2 s)` inside [_SerialPortMonitor]. The splash dismissal
/// advances the fake clock well past 2 s, so that periodic timer is live by
/// the time the test body ends. flutter_test's `_verifyInvariants` runs at the
/// end of the test body (before any `addTearDown`) and fails with "A Timer is
/// still pending" if any periodic timer is outstanding. Whether the timer was
/// even created depended on microtask scheduling under load — hence the
/// intermittent failure. Disposing the container in-body cancels the monitor's
/// timer (via the notifier's `dispose()`) before that check runs.
Future<ProviderContainer> _pumpApp(WidgetTester tester) async {
  final container = ProviderContainer();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const HeliosApp(),
    ),
  );
  return container;
}

/// Tears the app down deterministically *within the test body*, before
/// flutter_test's end-of-body invariant check.
///
/// First unmounts the widget tree so each widget's `dispose()` cancels its own
/// timers (live chart, flight-mode strip, etc.), then disposes the container
/// so the [_SerialPortMonitor]'s `Timer.periodic` is cancelled too.
Future<void> _teardownApp(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
}

/// Pump the widget tree past the splash screen's timers and animations so the
/// main shell is fully visible.
///
/// The splash lifecycle is:
///   1. 1800 ms assemble animation
///   2. 1400 ms delay (Timer)
///   3.  500 ms fade-out animation
///   4. onComplete() → _splashDone = true → rebuilds shell
/// Total: 3700 ms.
///
/// The completion chain is built lazily — each stage is scheduled only once
/// the previous one finishes (`assemble.then(() => Timer(1400).then(() =>
/// fade.then(onComplete)))`). A single large clock jump cannot traverse it,
/// because the `Timer` and the fade controller don't exist until the earlier
/// microtasks have run. We step the fake clock in coarse increments so every
/// stage gets scheduled and fired, then `pumpAndSettle` to flush the final
/// fade-out and `setState` rebuild deterministically.
Future<void> _dismissSplash(WidgetTester tester) async {
  await tester.pump(); // start controllers

  // Step through the full 3700 ms lifecycle. Stepping (rather than one jump)
  // lets each TickerFuture.then() microtask fire and schedule the next stage.
  // 50 × 100 ms = 5000 ms, comfortably past 3700 ms.
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  // Settle remaining frames/microtasks (fade-out completion + the setState
  // that swaps the splash for the shell).
  await tester.pumpAndSettle();
}

void main() {
  group('HeliosApp smoke tests', () {
    testWidgets('app launches and shows Fly view by default', (tester) async {
      final container = await _pumpApp(tester);
      await _dismissSplash(tester);

      // Fly view should be visible (contains PFD placeholder)
      expect(find.byType(CustomPaint), findsWidgets);
      // Splash should be dismissed.
      expect(find.byType(SplashScreen), findsNothing);

      await _teardownApp(tester, container);
    });

    testWidgets('sidebar visible on desktop width', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = await _pumpApp(tester);
      await _dismissSplash(tester);

      // Extended sidebar shows Helios branding and nav labels
      expect(find.text('Helios'), findsOneWidget);
      expect(find.text('Fly'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);

      await _teardownApp(tester, container);
    });

    testWidgets('navigation rail visible on tablet width', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = await _pumpApp(tester);
      await _dismissSplash(tester);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);

      await _teardownApp(tester, container);
    });

    testWidgets('bottom nav visible on mobile width', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = await _pumpApp(tester);
      await _dismissSplash(tester);

      expect(find.byType(BottomNavigationBar), findsOneWidget);

      await _teardownApp(tester, container);
    });

    testWidgets('can navigate between views', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = await _pumpApp(tester);
      await _dismissSplash(tester);

      // Tap Plan
      await tester.tap(find.text('Plan'));
      await tester.pump();
      expect(find.text('Mission'), findsOneWidget);

      // Tap Data (Analyse)
      await tester.tap(find.text('Data'));
      await tester.pump();
      expect(find.text('Flights'), findsOneWidget);

      // Note: Video and Setup tabs use media_kit which requires native libs
      // not available in the test environment. Tested manually.

      await _teardownApp(tester, container);
    });

    testWidgets('status bar is visible', (tester) async {
      final container = await _pumpApp(tester);
      await _dismissSplash(tester);

      // Status bar shows DISARMED by default
      expect(find.text('DISARMED'), findsOneWidget);

      await _teardownApp(tester, container);
    });
  });
}
