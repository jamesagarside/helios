import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/features/setup/widgets/esc_calibration_panel.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';
import 'package:helios_gcs/shared/providers/providers.dart';
import 'package:helios_gcs/shared/providers/vehicle_state_notifier.dart';
import 'package:helios_gcs/shared/theme/helios_colors.dart';

Widget _wrap(Widget child, {VehicleState? vehicleState}) {
  return ProviderScope(
    overrides: [
      if (vehicleState != null)
        vehicleStateProvider.overrideWith((ref) {
          final notifier = VehicleStateNotifier();
          notifier.applyReplayState(vehicleState);
          return notifier;
        }),
    ],
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: const [HeliosColors.dark],
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('EscCalibrationPanel', () {
    testWidgets('shows section header', (tester) async {
      await tester.pumpWidget(_wrap(
        const EscCalibrationPanel(),
        vehicleState: const VehicleState(),
      ));
      await tester.pump();

      expect(find.text('ESC CALIBRATION'), findsOneWidget);
    });

    testWidgets('shows disconnected banner when not connected', (tester) async {
      await tester.pumpWidget(_wrap(
        const EscCalibrationPanel(),
        vehicleState: const VehicleState(),
      ));
      await tester.pump();

      expect(
        find.text('Connect to a vehicle to calibrate ESCs.'),
        findsOneWidget,
      );
    });

    testWidgets('does not offer calibration controls while disconnected',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const EscCalibrationPanel(),
        vehicleState: const VehicleState(),
      ));
      await tester.pump();

      // Manual-endpoints / semi-auto sections only render once connected.
      expect(find.text('SEMI-AUTOMATIC CALIBRATION'), findsNothing);
      expect(find.text('MANUAL ENDPOINTS'), findsNothing);
    });
  });
}
