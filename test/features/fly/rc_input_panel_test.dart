import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/features/fly/widgets/rc_input_panel.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';
import 'package:helios_gcs/shared/providers/providers.dart';
import 'package:helios_gcs/shared/providers/vehicle_state_notifier.dart';

Widget _wrap(Widget child, {VehicleState? vehicleState}) {
  return ProviderScope(
    overrides: [
      if (vehicleState != null)
        vehicleStateProvider.overrideWith(
          (ref) {
            final notifier = VehicleStateNotifier();
            // Set state to the desired test state immediately.
            notifier.applyReplayState(vehicleState);
            return notifier;
          },
        ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    ),
  );
}

void main() {
  group('RcInputPanel', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(_wrap(
        const RcInputPanel(),
        vehicleState: const VehicleState(),
      ));
      await tester.pump();

      expect(find.text('RC INPUT'), findsOneWidget);
    });

    testWidgets('shows RSSI label', (tester) async {
      await tester.pumpWidget(_wrap(
        const RcInputPanel(),
        vehicleState: const VehicleState(),
      ));
      await tester.pump();

      // Default rcRssi is 255 (invalid) so shows RSSI: ---
      expect(find.text('RSSI: ---'), findsOneWidget);
    });

    testWidgets('shows RSSI value when valid', (tester) async {
      await tester.pumpWidget(_wrap(
        const RcInputPanel(),
        vehicleState: const VehicleState().copyWith(rcRssi: 200),
      ));
      await tester.pump();

      expect(find.text('RSSI: 200'), findsOneWidget);
    });

    testWidgets('shows FAILSAFE badge when rcFailsafe is true', (tester) async {
      await tester.pumpWidget(_wrap(
        const RcInputPanel(),
        vehicleState: const VehicleState().copyWith(rcFailsafe: true),
      ));
      await tester.pump();

      expect(find.text('FAILSAFE'), findsOneWidget);
    });

    testWidgets('does not show FAILSAFE badge when rcFailsafe is false', (tester) async {
      await tester.pumpWidget(_wrap(
        const RcInputPanel(),
        vehicleState: const VehicleState().copyWith(rcFailsafe: false),
      ));
      await tester.pump();

      expect(find.text('FAILSAFE'), findsNothing);
    });

    testWidgets('shows standard RC channel labels AIL, ELE, THR, RUD', (tester) async {
      await tester.pumpWidget(_wrap(
        const RcInputPanel(),
        vehicleState: const VehicleState(),
      ));
      await tester.pump();

      expect(find.text('AIL'), findsOneWidget);
      expect(find.text('ELE'), findsOneWidget);
      expect(find.text('THR'), findsOneWidget);
      expect(find.text('RUD'), findsOneWidget);
    });

    testWidgets('shows generic channel labels CH5 through CH18', (tester) async {
      await tester.pumpWidget(_wrap(
        const RcInputPanel(),
        vehicleState: const VehicleState(),
      ));
      await tester.pump();

      for (var i = 5; i <= 18; i++) {
        expect(find.text('CH$i'), findsOneWidget, reason: 'CH$i label missing');
      }
    });
  });
}
