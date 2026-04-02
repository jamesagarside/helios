import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:helios_gcs/shared/providers/display_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DisplayNotifier via ProviderContainer', () {
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial scale is default', () {
      final scale = container.read(displayScaleProvider);
      expect(scale, defaultScale);
    });

    test('setScale updates state', () async {
      final notifier = container.read(displayScaleProvider.notifier);
      await notifier.setScale(1.2);
      expect(container.read(displayScaleProvider), 1.2);
    });

    test('setScale clamps below min', () async {
      final notifier = container.read(displayScaleProvider.notifier);
      await notifier.setScale(0.5);
      expect(container.read(displayScaleProvider), minScale);
    });

    test('setScale clamps above max', () async {
      final notifier = container.read(displayScaleProvider.notifier);
      await notifier.setScale(3.0);
      expect(container.read(displayScaleProvider), maxScale);
    });

    test('increase and decrease by step', () {
      final notifier = container.read(displayScaleProvider.notifier);
      final initial = container.read(displayScaleProvider);
      notifier.increase();
      expect(
        container.read(displayScaleProvider),
        closeTo(initial + scaleStep, 0.001),
      );
      notifier.decrease();
      expect(
        container.read(displayScaleProvider),
        closeTo(initial, 0.001),
      );
    });

    test('reset returns to default', () async {
      final notifier = container.read(displayScaleProvider.notifier);
      await notifier.setScale(1.4);
      notifier.reset();
      expect(container.read(displayScaleProvider), defaultScale);
    });
  });

  group('scale constants', () {
    test('minScale < defaultScale < maxScale', () {
      expect(minScale, lessThan(defaultScale));
      expect(defaultScale, lessThan(maxScale));
    });

    test('scaleStep is positive', () {
      expect(scaleStep, greaterThan(0));
    });
  });
}
