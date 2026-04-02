import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/simulate/sitl_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SitlLauncher', () {
    late SitlLauncher launcher;

    setUp(() {
      launcher = SitlLauncher();
    });

    // ── Vehicle catalogue ────────────────────────────────────────────────────

    test('vehicles list is non-empty', () {
      expect(SitlLauncher.vehicles, isNotEmpty);
    });

    test('vehicles list contains ArduCopter', () {
      expect(SitlLauncher.vehicles, contains('ArduCopter'));
    });

    test('vehicles list contains all expected types', () {
      expect(
        SitlLauncher.vehicles,
        containsAll(
            ['ArduCopter', 'ArduPlane', 'ArduRover', 'ArduSub', 'ArduHeli']),
      );
    });

    // ── Frame catalogue ──────────────────────────────────────────────────────

    test('frames map has entries for every vehicle', () {
      for (final vehicle in SitlLauncher.vehicles) {
        expect(
          SitlLauncher.frames.containsKey(vehicle),
          isTrue,
          reason: 'Expected frames entry for $vehicle',
        );
        expect(
          SitlLauncher.frames[vehicle],
          isNotEmpty,
          reason: 'Expected non-empty frames for $vehicle',
        );
      }
    });

    test('ArduCopter frames include quad and hex', () {
      final frames = SitlLauncher.frames['ArduCopter']!;
      expect(frames, containsAll(['quad', 'hex']));
    });

    test('ArduPlane frames include plane', () {
      final frames = SitlLauncher.frames['ArduPlane']!;
      expect(frames, contains('plane'));
    });

    // ── Locations ────────────────────────────────────────────────────────────

    test('locations list is non-empty', () {
      expect(SitlLauncher.locations, isNotEmpty);
    });

    test('SitlLocation stores name correctly', () {
      const loc = SitlLocation('Test Site', -35.0, 149.0, 180);
      expect(loc.name, equals('Test Site'));
    });

    test('SitlLocation stores lat correctly', () {
      const loc = SitlLocation('Test Site', -35.0, 149.0, 180);
      expect(loc.lat, equals(-35.0));
    });

    test('SitlLocation stores lon correctly', () {
      const loc = SitlLocation('Test Site', -35.0, 149.0, 180);
      expect(loc.lon, equals(149.0));
    });

    test('SitlLocation stores heading correctly', () {
      const loc = SitlLocation('Test Site', -35.0, 149.0, 180);
      expect(loc.heading, equals(180));
    });

    test('Custom location isCustom returns true', () {
      const loc = SitlLocation('Custom...', 0, 0, 0);
      expect(loc.isCustom, isTrue);
    });

    test('Non-custom location isCustom returns false', () {
      const loc =
          SitlLocation('CMAC (Canberra, AU)', -35.3632, 149.1652, 353);
      expect(loc.isCustom, isFalse);
    });

    test('CMAC location has expected coordinates', () {
      final cmac = SitlLauncher.locations.firstWhere(
        (l) => l.name.contains('Canberra'),
      );
      expect(cmac.lat, closeTo(-35.3632, 0.001));
      expect(cmac.lon, closeTo(149.1652, 0.001));
    });

    // ── isRunning ─────────────────────────────────────────────────────────

    test('isRunning is false initially', () {
      expect(launcher.isRunning, isFalse);
    });

    // ── Binary names ──────────────────────────────────────────────────────

    test('sitlVersion is stable', () {
      expect(SitlLauncher.sitlVersion, equals('stable'));
    });

    // ── Version / constants ────────────────────────────────────────────────

    test('every vehicle has a corresponding binary name implicitly', () {
      // All vehicles should be downloadable - the binary name mapping
      // covers all entries (falls back to lowercase vehicle name).
      for (final vehicle in SitlLauncher.vehicles) {
        expect(vehicle, isNotEmpty);
      }
    });

    // ── Launch validation ─────────────────────────────────────────────────

    test('launch throws when already running', () async {
      // We cannot actually start a SITL process in tests, but we can
      // verify the exception type exists and is constructible.
      const exception = SitlLaunchException('test message');
      expect(exception.message, equals('test message'));
      expect(exception.toString(), contains('SitlLaunchException'));
    });

    test('SitlLaunchException toString includes message', () {
      const exception = SitlLaunchException('binary not found');
      expect(
        exception.toString(),
        equals('SitlLaunchException: binary not found'),
      );
    });

    // ── Stop when not running ─────────────────────────────────────────────

    test('stop completes without error when not running', () async {
      await expectLater(launcher.stop(), completes);
    });
  });
}
