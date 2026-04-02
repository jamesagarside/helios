import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/features/fly/widgets/servo_output_panel.dart';
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
  group('ServoOutputPanel', () {
    testWidgets('renders without error when servoOutputs are all zeros', (tester) async {
      const state = VehicleState();
      expect(state.servoOutputs, isEmpty);

      await tester.pumpWidget(_wrap(
        const ServoOutputPanel(),
        vehicleState: state,
      ));
      await tester.pump();

      // Panel header should be visible
      expect(find.text('SERVO OUTPUT'), findsOneWidget);
    });

    testWidgets('shows CH1 through CH4 labels', (tester) async {
      await tester.pumpWidget(_wrap(
        const ServoOutputPanel(),
        vehicleState: const VehicleState(),
      ));
      await tester.pump();

      expect(find.text('CH1'), findsOneWidget);
      expect(find.text('CH2'), findsOneWidget);
      expect(find.text('CH3'), findsOneWidget);
      expect(find.text('CH4'), findsOneWidget);
    });

    testWidgets('shows all 16 channel labels', (tester) async {
      await tester.pumpWidget(_wrap(
        const ServoOutputPanel(),
        vehicleState: const VehicleState(),
      ));
      await tester.pump();

      for (var i = 1; i <= 16; i++) {
        expect(find.text('CH$i'), findsOneWidget, reason: 'CH$i label missing');
      }
    });

    testWidgets('displays PWM values when servoOutputs are non-zero', (tester) async {
      final servos = List<int>.filled(16, 0);
      servos[0] = 1500;
      servos[1] = 1200;

      await tester.pumpWidget(_wrap(
        const ServoOutputPanel(),
        vehicleState: const VehicleState().copyWith(servoOutputs: servos),
      ));
      await tester.pump();

      expect(find.text('1500'), findsOneWidget);
      expect(find.text('1200'), findsOneWidget);
    });

    testWidgets('shows dashes for unused (zero) channels', (tester) async {
      await tester.pumpWidget(_wrap(
        const ServoOutputPanel(),
        vehicleState: const VehicleState(),
      ));
      await tester.pump();

      // All channels are 0, so dashes should be shown
      final dashes = find.text('----');
      expect(dashes, findsWidgets);
    });
  });
}
