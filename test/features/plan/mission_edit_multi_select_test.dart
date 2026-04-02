import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/features/plan/providers/mission_edit_notifier.dart';
import 'package:helios_gcs/shared/models/mission_item.dart';

MissionItem _wp(int seq, {int? command}) => MissionItem(
      seq: seq,
      command: command ?? MavCmd.navWaypoint,
      latitude: -35.0 + seq * 0.001,
      longitude: 149.0 + seq * 0.001,
      altitude: 50.0,
    );

void main() {
  late MissionEditNotifier notifier;

  setUp(() {
    notifier = MissionEditNotifier();
    // Populate with 4 nav waypoints + 1 DO command
    notifier.loadItems([
      _wp(0, command: MavCmd.navTakeoff),
      _wp(1),
      _wp(2),
      _wp(3),
      MissionItem(
        seq: 4,
        command: MavCmd.doChangeSpeed,
        param2: 10.0,
        altitude: 0.0,
      ),
    ]);
  });

  group('toggleSelection', () {
    test('adds seq to selectedSeqs', () {
      notifier.toggleSelection(1);
      expect(notifier.state.selectedSeqs, contains(1));
    });

    test('removes seq when toggled again (deselect)', () {
      notifier.toggleSelection(1);
      notifier.toggleSelection(1);
      expect(notifier.state.selectedSeqs, isNot(contains(1)));
    });

    test('multiple seqs can be selected independently', () {
      notifier.toggleSelection(1);
      notifier.toggleSelection(3);
      expect(notifier.state.selectedSeqs, containsAll([1, 3]));
    });
  });

  group('selectAll', () {
    test('selects all nav waypoints only', () {
      notifier.selectAll();
      // seq 0,1,2,3 are nav; seq 4 is DO_CHANGE_SPEED (not nav)
      expect(notifier.state.selectedSeqs, containsAll([0, 1, 2, 3]));
      expect(notifier.state.selectedSeqs, isNot(contains(4)));
    });
  });

  group('clearSelection', () {
    test('empties the selected set', () {
      notifier.toggleSelection(1);
      notifier.toggleSelection(2);
      notifier.clearSelection();
      expect(notifier.state.selectedSeqs, isEmpty);
    });
  });

  group('batchSetAltitude', () {
    test('updates altitude on all selected items only', () {
      notifier.toggleSelection(1);
      notifier.toggleSelection(2);
      notifier.batchSetAltitude(120.0);

      final items = notifier.state.items;
      expect(items.firstWhere((i) => i.seq == 0).altitude, closeTo(50.0, 1e-3));
      expect(items.firstWhere((i) => i.seq == 1).altitude, closeTo(120.0, 1e-3));
      expect(items.firstWhere((i) => i.seq == 2).altitude, closeTo(120.0, 1e-3));
      expect(items.firstWhere((i) => i.seq == 3).altitude, closeTo(50.0, 1e-3));
    });

    test('does nothing when selection is empty', () {
      final before = notifier.state.items.map((i) => i.altitude).toList();
      notifier.batchSetAltitude(999.0);
      final after = notifier.state.items.map((i) => i.altitude).toList();
      expect(after, equals(before));
    });
  });

  group('batchDelete', () {
    test('removes all selected items and clears selection', () {
      notifier.toggleSelection(1);
      notifier.toggleSelection(3);
      notifier.batchDelete();

      final seqs = notifier.state.items.map((i) => i.seq).toList();
      // Items at old seq 1 and 3 are gone; remaining renumbered
      expect(notifier.state.items.length, 3); // was 5, minus 2
      expect(notifier.state.selectedSeqs, isEmpty);
      // Items are renumbered sequentially
      for (var i = 0; i < seqs.length; i++) {
        expect(seqs[i], i);
      }
    });

    test('does nothing when selection is empty', () {
      final before = notifier.state.items.length;
      notifier.batchDelete();
      expect(notifier.state.items.length, before);
    });

    test('clears selectedIndex after batch delete', () {
      notifier.select(1);
      notifier.toggleSelection(1);
      notifier.batchDelete();
      expect(notifier.state.selectedIndex, -1);
    });
  });

  group('hasMultiSelection', () {
    test('is false with 0 selected', () {
      expect(notifier.state.hasMultiSelection, isFalse);
    });

    test('is false with exactly 1 selected', () {
      notifier.toggleSelection(1);
      expect(notifier.state.hasMultiSelection, isFalse);
    });

    test('is true with 2 or more selected', () {
      notifier.toggleSelection(1);
      notifier.toggleSelection(2);
      expect(notifier.state.hasMultiSelection, isTrue);
    });
  });

  group('batchSetSpeed', () {
    test('inserts DO_CHANGE_SPEED before each selected nav waypoint', () {
      notifier.toggleSelection(1);
      notifier.toggleSelection(2);
      notifier.batchSetSpeed(15.0);

      // Should have inserted 2 extra items
      expect(notifier.state.items.length, 7);
      // DO_CHANGE_SPEED items are present with correct speed
      final speedItems = notifier.state.items
          .where((i) => i.command == MavCmd.doChangeSpeed)
          .toList();
      // Original seq 4 DO_ plus 2 new ones
      expect(speedItems.length, 3);
      for (final si in speedItems.where((i) => i.param2 == 15.0)) {
        expect(si.param2, closeTo(15.0, 1e-3));
      }
    });

    test('clears selection after operation', () {
      notifier.toggleSelection(1);
      notifier.batchSetSpeed(10.0);
      expect(notifier.state.selectedSeqs, isEmpty);
    });
  });
}
