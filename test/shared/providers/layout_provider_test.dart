import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:helios_gcs/shared/providers/layout_provider.dart';
import 'package:helios_gcs/shared/models/layout_profile.dart';
import 'package:helios_gcs/features/fly/widgets/chart_toolbar.dart';

Future<ProviderContainer> createContainer() async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer();
  // Trigger the provider and let async _load() complete
  container.read(layoutProvider);
  await Future<void>.delayed(const Duration(milliseconds: 100));
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('snapToGrid', () {
    test('snaps to nearest 20px', () {
      expect(snapToGrid(0), 0);
      expect(snapToGrid(10), 20);
      expect(snapToGrid(9), 0);
      expect(snapToGrid(15), 20);
      expect(snapToGrid(29), 20);
      expect(snapToGrid(30), 40);
      expect(snapToGrid(355), 360);
    });

    test('handles negative values', () {
      expect(snapToGrid(-5), 0);
      expect(snapToGrid(-15), -20);
    });
  });

  group('LayoutState', () {
    test('activeProfile returns default when profiles empty', () {
      const state = LayoutState(
        profiles: [],
        activeProfileName: 'Nonexistent',
      );
      expect(state.activeProfile.name, 'Multirotor');
    });

    test('activeProfile returns first when name not found', () {
      final state = LayoutState(
        profiles: [defaultFixedWingProfile(), defaultVtolProfile()],
        activeProfileName: 'Nonexistent',
      );
      expect(state.activeProfile.name, 'Fixed Wing');
    });

    test('activeProfile finds matching profile', () {
      final state = LayoutState(
        profiles: [defaultMultirotorProfile(), defaultFixedWingProfile()],
        activeProfileName: 'Fixed Wing',
      );
      expect(state.activeProfile.name, 'Fixed Wing');
      expect(state.activeProfile.vehicleType, VehicleType.fixedWing);
    });

    test('copyWith preserves unchanged fields', () {
      const state = LayoutState(
        activeProfileName: 'Test',
        editMode: true,
      );
      final updated = state.copyWith(editMode: false);
      expect(updated.activeProfileName, 'Test');
      expect(updated.editMode, false);
    });
  });

  group('LayoutNotifier', () {
    test('initial active profile is Multirotor', () async {
      final container = await createContainer();
      addTearDown(container.dispose);
      expect(container.read(layoutProvider).activeProfileName, 'Multirotor');
    });

    test('has 3 default profiles after load', () async {
      final container = await createContainer();
      addTearDown(container.dispose);
      final profiles = container.read(layoutProvider).profiles;
      expect(profiles.length, greaterThanOrEqualTo(3));
      expect(profiles.any((p) => p.name == 'Multirotor'), true);
      expect(profiles.any((p) => p.name == 'Fixed Wing'), true);
      expect(profiles.any((p) => p.name == 'VTOL'), true);
    });

    test('toggleEditMode flips edit state', () async {
      final container = await createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      expect(container.read(layoutProvider).editMode, false);
      notifier.toggleEditMode();
      expect(container.read(layoutProvider).editMode, true);
      notifier.toggleEditMode();
      expect(container.read(layoutProvider).editMode, false);
    });

    test('selectProfile changes active', () async {
      final container = await createContainer();
      addTearDown(container.dispose);
      container.read(layoutProvider.notifier).selectProfile('Fixed Wing');
      expect(container.read(layoutProvider).activeProfileName, 'Fixed Wing');
    });

    test('activeLayoutProvider reflects active profile', () async {
      final container = await createContainer();
      addTearDown(container.dispose);
      final active = container.read(activeLayoutProvider);
      expect(active.name, 'Multirotor');
    });

    test('layoutEditModeProvider reflects edit mode', () async {
      final container = await createContainer();
      addTearDown(container.dispose);
      expect(container.read(layoutEditModeProvider), false);
      container.read(layoutProvider.notifier).toggleEditMode();
      expect(container.read(layoutEditModeProvider), true);
    });

    test('toggleChart adds a chart', () async {
      final container = await createContainer();
      addTearDown(container.dispose);
      container.read(layoutProvider.notifier).toggleChart(ChartType.vibration);
      final profile = container.read(layoutProvider).activeProfile;
      expect(profile.charts[ChartType.vibration.name]?.visible, true);
    });

    test('toggleChart twice hides the chart', () async {
      final container = await createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      notifier.toggleChart(ChartType.vibration);
      notifier.toggleChart(ChartType.vibration);
      final profile = container.read(layoutProvider).activeProfile;
      expect(profile.charts[ChartType.vibration.name]?.visible, false);
    });

    test('updateChartPosition snaps to grid', () async {
      final container = await createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      notifier.toggleChart(ChartType.altitude);
      notifier.updateChartPosition(ChartType.altitude, 355, 97);
      final config = container.read(layoutProvider).activeProfile
          .charts[ChartType.altitude.name]!;
      expect(config.x, 360);
      expect(config.y, 100);
    });

    test('updateChartSize clamps and snaps', () async {
      final container = await createContainer();
      addTearDown(container.dispose);
      final notifier = container.read(layoutProvider.notifier);
      notifier.toggleChart(ChartType.speed);
      notifier.updateChartSize(ChartType.speed, 155, 55);
      final config = container.read(layoutProvider).activeProfile
          .charts[ChartType.speed.name]!;
      expect(config.width, 200);
      expect(config.height, 100);
    });
  });
}
