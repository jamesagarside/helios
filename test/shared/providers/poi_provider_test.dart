import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/models/point_of_interest.dart';
import 'package:helios_gcs/shared/providers/poi_provider.dart';

// ─── Helpers ────────────────────────────────────────────────────────────────

PointOfInterest _makePoi(String id, {String name = 'Test', double lat = 0, double lon = 0}) {
  return PointOfInterest(
    id: id,
    name: name,
    latitude: lat,
    longitude: lon,
  );
}

/// Creates a [PoiNotifier] in isolation (no filesystem I/O).
///
/// The notifier constructor calls [_load()] asynchronously; since there is no
/// real file in test context the load silently returns and state stays [].
PoiNotifier _makeNotifier() => PoiNotifier();

void main() {
  // path_provider requires a binding even when not hitting real storage.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PoiNotifier state transitions', () {
    late PoiNotifier notifier;

    setUp(() {
      notifier = _makeNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    // ─── addPoi ─────────────────────────────────────────────────────────────

    test('starts with empty state', () {
      expect(notifier.state, isEmpty);
    });

    test('addPoi appends to state', () {
      notifier.addPoi(_makePoi('1', name: 'Alpha'));
      expect(notifier.state.length, 1);
      expect(notifier.state.first.name, 'Alpha');
    });

    test('addPoi appends multiple items in order', () {
      notifier.addPoi(_makePoi('1', name: 'Alpha'));
      notifier.addPoi(_makePoi('2', name: 'Beta'));
      notifier.addPoi(_makePoi('3', name: 'Gamma'));
      expect(notifier.state.length, 3);
      expect(notifier.state.map((p) => p.name).toList(),
          ['Alpha', 'Beta', 'Gamma']);
    });

    // ─── updatePoi ──────────────────────────────────────────────────────────

    test('updatePoi replaces POI with matching id', () {
      notifier.addPoi(_makePoi('1', name: 'Original'));
      notifier.updatePoi(_makePoi('1', name: 'Updated'));
      expect(notifier.state.length, 1);
      expect(notifier.state.first.name, 'Updated');
    });

    test('updatePoi does not affect other POIs', () {
      notifier.addPoi(_makePoi('1', name: 'Alpha'));
      notifier.addPoi(_makePoi('2', name: 'Beta'));
      notifier.updatePoi(_makePoi('1', name: 'Alpha Revised'));
      expect(notifier.state.length, 2);
      expect(notifier.state.first.name, 'Alpha Revised');
      expect(notifier.state.last.name, 'Beta');
    });

    test('updatePoi with unknown id leaves state unchanged', () {
      notifier.addPoi(_makePoi('1', name: 'Alpha'));
      notifier.updatePoi(_makePoi('999', name: 'Ghost'));
      // 'Ghost' not inserted, but the original list size stays the same
      // (the for loop doesn't match, so 'Ghost' is never included)
      expect(notifier.state.length, 1);
      expect(notifier.state.first.name, 'Alpha');
    });

    // ─── removePoi ──────────────────────────────────────────────────────────

    test('removePoi removes the matching POI', () {
      notifier.addPoi(_makePoi('1'));
      notifier.addPoi(_makePoi('2'));
      notifier.removePoi('1');
      expect(notifier.state.length, 1);
      expect(notifier.state.first.id, '2');
    });

    test('removePoi with unknown id leaves state unchanged', () {
      notifier.addPoi(_makePoi('1'));
      notifier.removePoi('non-existent');
      expect(notifier.state.length, 1);
    });

    // ─── clear ──────────────────────────────────────────────────────────────

    test('clear removes all POIs', () {
      notifier.addPoi(_makePoi('1'));
      notifier.addPoi(_makePoi('2'));
      notifier.clear();
      expect(notifier.state, isEmpty);
    });

    test('clear on empty state is a no-op', () {
      notifier.clear();
      expect(notifier.state, isEmpty);
    });

    // ─── POI content preservation ───────────────────────────────────────────

    test('added POI preserves all fields', () {
      const poi = PointOfInterest(
        id: 'full-001',
        name: 'Full POI',
        notes: 'some notes',
        latitude: -35.0,
        longitude: 149.0,
        altitudeM: 50.0,
        colour: PoiColour.red,
        icon: PoiIcon.camera,
      );
      notifier.addPoi(poi);
      final stored = notifier.state.first;
      expect(stored.id, poi.id);
      expect(stored.name, poi.name);
      expect(stored.notes, poi.notes);
      expect(stored.latitude, poi.latitude);
      expect(stored.longitude, poi.longitude);
      expect(stored.altitudeM, poi.altitudeM);
      expect(stored.colour, poi.colour);
      expect(stored.icon, poi.icon);
    });
  });

  // ─── Provider wiring ──────────────────────────────────────────────────────

  group('poiProvider via ProviderContainer', () {
    test('provider starts empty and accepts mutations', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Initial read — starts empty (async load from non-existent file)
      final initial = container.read(poiProvider);
      expect(initial, isEmpty);

      // Add via notifier
      container.read(poiProvider.notifier).addPoi(_makePoi('p1', name: 'One'));
      expect(container.read(poiProvider).length, 1);
      expect(container.read(poiProvider).first.name, 'One');

      // Remove
      container.read(poiProvider.notifier).removePoi('p1');
      expect(container.read(poiProvider), isEmpty);
    });

    test('clear via provider empties the list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(poiProvider.notifier).addPoi(_makePoi('a'));
      container.read(poiProvider.notifier).addPoi(_makePoi('b'));
      container.read(poiProvider.notifier).clear();
      expect(container.read(poiProvider), isEmpty);
    });
  });
}
