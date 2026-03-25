import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helios_gcs/app.dart';

void main() {
  group('HeliosApp smoke tests', () {
    testWidgets('app launches and shows Fly view by default', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: HeliosApp()),
      );
      await tester.pumpAndSettle();

      // Fly view should be visible (contains PFD placeholder)
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('navigation rail visible on desktop width', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(child: HeliosApp()),
      );
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      expect(find.byType(BottomNavigationBar), findsOneWidget);
    });

    testWidgets('can navigate to all four views', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const ProviderScope(child: HeliosApp()),
      );
      await tester.pumpAndSettle();

      // Tap Plan
      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();
      expect(find.text('Mission'), findsOneWidget);

      // Tap Data (Analyse)
      await tester.tap(find.text('Data'));
      await tester.pumpAndSettle();
      expect(find.text('Flights'), findsOneWidget);

      // Tap Setup
      await tester.tap(find.text('Setup'));
      await tester.pumpAndSettle();
      expect(find.text('Connection Manager'), findsOneWidget);

      // Tap Fly
      await tester.tap(find.text('Fly'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('status bar is visible', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: HeliosApp()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mode'), findsOneWidget);
    });
  });
}
