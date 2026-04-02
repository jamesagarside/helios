import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helios_gcs/app.dart';
import 'package:helios_gcs/shared/widgets/splash_screen.dart';

/// Pump the widget tree far enough past the splash screen's timers and
/// animations so the main shell is fully visible.
///
/// The splash:
///   1. Runs a 1800 ms assemble animation.
///   2. Waits 1400 ms via a Timer.
///   3. Runs a 500 ms fade-out animation.
///   4. Calls onComplete() → _splashDone = true → rebuilds shell.
///
/// We advance the fake clock by 4 s (well past 1800 + 1400 + 500 ms) and
/// then pump one final frame to flush the setState rebuild.
Future<void> _dismissSplash(WidgetTester tester) async {
  // The splash runs:
  //   1800 ms assemble animation
  //   1400 ms delay (Timer)
  //    500 ms fade animation
  // Total: 3700 ms.
  //
  // We pump one frame at a time through the splash lifecycle, flushing
  // microtasks (from TickerFuture.then() chains) between animation phases.
  await tester.pump(); // start controllers

  // Tick through each millisecond of the animation in coarse steps.
  // Using runAsync so that TickerFuture.then() microtasks fire naturally
  // between steps.
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  // Extra frames to flush setState rebuild.
  await tester.pump();
  await tester.pump();
}

void main() {

  group('HeliosApp smoke tests', () {
    testWidgets('app launches and shows Fly view by default', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: HeliosApp()),
      );
      await _dismissSplash(tester);

      // Fly view should be visible (contains PFD placeholder)
      expect(find.byType(CustomPaint), findsWidgets);
      // Splash should be dismissed.
      expect(find.byType(SplashScreen), findsNothing);
    });

    testWidgets('sidebar visible on desktop width', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(child: HeliosApp()),
      );
      await _dismissSplash(tester);

      // Extended sidebar shows Helios branding and nav labels
      expect(find.text('Helios'), findsOneWidget);
      expect(find.text('Fly'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
    });

    testWidgets('navigation rail visible on tablet width', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(child: HeliosApp()),
      );
      await _dismissSplash(tester);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(BottomNavigationBar), findsNothing);
    });

    testWidgets('bottom nav visible on mobile width', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(child: HeliosApp()),
      );
      await _dismissSplash(tester);

      expect(find.byType(BottomNavigationBar), findsOneWidget);
    });

    testWidgets('can navigate between views', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(child: HeliosApp()),
      );
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
    });

    testWidgets('status bar is visible', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: HeliosApp()),
      );
      await _dismissSplash(tester);

      // Status bar shows DISARMED by default
      expect(find.text('DISARMED'), findsOneWidget);
    });
  });
}
