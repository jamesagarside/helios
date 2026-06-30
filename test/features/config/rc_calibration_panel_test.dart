import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/features/setup/widgets/rc_calibration_panel.dart';
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
  group('RcCalibrationPanel', () {
    testWidgets('renders section labels', (tester) async {
      await tester.pumpWidget(_wrap(
        const RcCalibrationPanel(),
        vehicleState: const VehicleState(),
      ));
      await tester.pump();

      expect(find.textContaining('LIVE CHANNELS'), findsOneWidget);
      expect(find.text('CHANNEL FUNCTION (RCMAP)'), findsOneWidget);
    });

    testWidgets('shows disconnected banner when not connected', (tester) async {
      await tester.pumpWidget(_wrap(
        const RcCalibrationPanel(),
        vehicleState: const VehicleState(),
      ));
      await tester.pump();

      expect(
        find.text('Connect to a vehicle to calibrate the radio.'),
        findsOneWidget,
      );
    });

    testWidgets('lists RCMAP function rows', (tester) async {
      await tester.pumpWidget(_wrap(
        const RcCalibrationPanel(),
        vehicleState: const VehicleState(),
      ));
      await tester.pump();

      expect(find.text('Roll / Aileron'), findsOneWidget);
      expect(find.text('Pitch / Elevator'), findsOneWidget);
      expect(find.text('Throttle'), findsOneWidget);
      expect(find.text('Yaw / Rudder'), findsOneWidget);
    });

    testWidgets('renders live channel rows from RC_CHANNELS', (tester) async {
      await tester.pumpWidget(_wrap(
        const RcCalibrationPanel(),
        vehicleState: const VehicleState().copyWith(
          rcChannels: const [1500, 1500, 1000, 1500],
          rcChannelCount: 4,
        ),
      ));
      await tester.pump();

      expect(find.text('CH1'), findsOneWidget);
      expect(find.text('CH4'), findsOneWidget);
      // PWM value label for an active channel.
      expect(find.textContaining('1500 µs'), findsWidgets);
    });
  });
}
