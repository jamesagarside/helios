import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';
import 'package:helios_gcs/shared/providers/providers.dart';
import 'package:helios_gcs/shared/providers/vehicle_state_notifier.dart';
import 'package:helios_gcs/shared/theme/helios_colors.dart';
import 'package:helios_gcs/features/fly/widgets/flight_mode_strip.dart';

Widget _wrap({VehicleState? vehicle}) {
  return ProviderScope(
    overrides: [
      if (vehicle != null)
        vehicleStateProvider.overrideWith((ref) {
          final n = VehicleStateNotifier();
          n.applyReplayState(vehicle);
          return n;
        }),
    ],
    child: MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: const [HeliosColors.dark]),
      home: const Scaffold(body: Center(child: FlightModeStrip())),
    ),
  );
}

void main() {
  group('FlightModeStrip', () {
    testWidgets('shows UNKNOWN mode', (t) async {
      await t.pumpWidget(_wrap());
      expect(find.text('UNKNOWN'), findsOneWidget);
    });
    testWidgets('shows DISARMED', (t) async {
      await t.pumpWidget(_wrap(vehicle: const VehicleState(armed: false)));
      expect(find.text('DISARMED'), findsOneWidget);
    });
    testWidgets('shows ARMED', (t) async {
      await t.pumpWidget(_wrap(vehicle: const VehicleState(armed: true)));
      expect(find.text('ARMED'), findsOneWidget);
    });
    testWidgets('shows satellite count', (t) async {
      await t.pumpWidget(_wrap(vehicle: const VehicleState(satellites: 12)));
      expect(find.text('12'), findsOneWidget);
    });
    testWidgets('shows timer placeholder', (t) async {
      await t.pumpWidget(_wrap(vehicle: const VehicleState(armed: false)));
      expect(find.text('--:--'), findsOneWidget);
    });
  });
}
