import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/widgets/status_bar.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('StatusBar', () {
    testWidgets('shows DISARMED when not armed', (tester) async {
      await tester.pumpWidget(_wrap(const StatusBar(armed: false)));
      expect(find.text('DISARMED'), findsOneWidget);
      expect(find.text('ARMED'), findsNothing);
    });

    testWidgets('shows ARMED when armed', (tester) async {
      await tester.pumpWidget(_wrap(const StatusBar(armed: true)));
      expect(find.text('ARMED'), findsOneWidget);
      expect(find.text('DISARMED'), findsNothing);
    });

    testWidgets('shows flight mode', (tester) async {
      await tester.pumpWidget(_wrap(const StatusBar(flightMode: 'STABILIZE')));
      expect(find.text('STABILIZE'), findsOneWidget);
    });

    testWidgets('shows GPS info', (tester) async {
      await tester.pumpWidget(
        _wrap(const StatusBar(gpsFixType: '3D Fix', satellites: 12)),
      );
      expect(find.textContaining('3D Fix'), findsOneWidget);
      expect(find.textContaining('12 sats'), findsOneWidget);
    });

    testWidgets('shows flight time formatted', (tester) async {
      await tester.pumpWidget(
        _wrap(const StatusBar(
            flightTime: Duration(hours: 1, minutes: 23, seconds: 45))),
      );
      expect(find.text('01:23:45'), findsOneWidget);
    });

    testWidgets('shows message rate', (tester) async {
      await tester.pumpWidget(_wrap(const StatusBar(messageRate: 42)));
      expect(find.textContaining('42 msg/s'), findsOneWidget);
    });
  });
}
