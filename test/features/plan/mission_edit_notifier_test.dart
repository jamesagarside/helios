import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/features/plan/providers/mission_edit_notifier.dart';
import 'package:helios_gcs/shared/models/mission_item.dart';

void main() {
  late MissionEditNotifier notifier;

  setUp(() {
    notifier = MissionEditNotifier();
  });

  group('MissionEditNotifier', () {
    test('starts with empty state', () {
      expect(notifier.state.items, isEmpty);
      expect(notifier.state.selectedIndex, -1);
      expect(notifier.state.isDirty, false);
      expect(notifier.state.hasSelection, false);
    });

    test('addWaypoint adds item and selects it', () {
      notifier.addWaypoint(-35.363, 149.165);

      expect(notifier.state.waypointCount, 1);
      expect(notifier.state.selectedIndex, 0);
      expect(notifier.state.items[0].latitude, -35.363);
      expect(notifier.state.items[0].longitude, 149.165);
      expect(notifier.state.items[0].altitude, 50.0);
      expect(notifier.state.isDirty, true);
    });

    test('first waypoint defaults to NAV_TAKEOFF', () {
      notifier.addWaypoint(-35.363, 149.165);
      expect(notifier.state.items[0].command, MavCmd.navTakeoff);
    });

    test('subsequent waypoints default to NAV_WAYPOINT', () {
      notifier.addWaypoint(-35.363, 149.165);
      notifier.addWaypoint(-35.364, 149.166);
      expect(notifier.state.items[1].command, MavCmd.navWaypoint);
    });

    test('removeWaypoint removes and renumbers', () {
      notifier.addWaypoint(-35.363, 149.165);
      notifier.addWaypoint(-35.364, 149.166);
      notifier.addWaypoint(-35.365, 149.167);

      notifier.removeWaypoint(1);

      expect(notifier.state.waypointCount, 2);
      expect(notifier.state.items[0].seq, 0);
      expect(notifier.state.items[1].seq, 1);
      expect(notifier.state.items[1].latitude, closeTo(-35.365, 0.001));
    });

    test('moveWaypoint updates position', () {
      notifier.addWaypoint(-35.363, 149.165);
      notifier.moveWaypoint(0, -35.370, 149.170);

      expect(notifier.state.items[0].latitude, -35.370);
      expect(notifier.state.items[0].longitude, 149.170);
    });

    test('reorderWaypoint moves and renumbers', () {
      notifier.addWaypoint(-35.363, 149.165);
      notifier.addWaypoint(-35.364, 149.166);
      notifier.addWaypoint(-35.365, 149.167);

      // Move item 0 to position 2
      notifier.reorderWaypoint(0, 2);

      expect(notifier.state.items[0].latitude, closeTo(-35.364, 0.001));
      expect(notifier.state.items[1].latitude, closeTo(-35.365, 0.001));
      expect(notifier.state.items[2].latitude, closeTo(-35.363, 0.001));
      expect(notifier.state.items[0].seq, 0);
      expect(notifier.state.items[1].seq, 1);
      expect(notifier.state.items[2].seq, 2);
    });

    test('select and deselect', () {
      notifier.addWaypoint(-35.363, 149.165);
      notifier.addWaypoint(-35.364, 149.166);

      notifier.select(1);
      expect(notifier.state.selectedIndex, 1);
      expect(notifier.state.hasSelection, true);
      expect(notifier.state.selectedItem!.seq, 1);

      notifier.select(-1);
      expect(notifier.state.hasSelection, false);
    });

    test('updateWaypoint modifies item', () {
      notifier.addWaypoint(-35.363, 149.165);
      final updated = notifier.state.items[0].copyWith(altitude: 100.0);
      notifier.updateWaypoint(0, updated);

      expect(notifier.state.items[0].altitude, 100.0);
    });

    test('undo reverses last action', () {
      notifier.addWaypoint(-35.363, 149.165);
      notifier.addWaypoint(-35.364, 149.166);

      expect(notifier.state.waypointCount, 2);
      expect(notifier.canUndo, true);

      notifier.undo();
      expect(notifier.state.waypointCount, 1);

      notifier.undo();
      expect(notifier.state.waypointCount, 0);
    });

    test('redo restores undone action', () {
      notifier.addWaypoint(-35.363, 149.165);
      notifier.undo();
      expect(notifier.state.waypointCount, 0);
      expect(notifier.canRedo, true);

      notifier.redo();
      expect(notifier.state.waypointCount, 1);
    });

    test('new action clears redo stack', () {
      notifier.addWaypoint(-35.363, 149.165);
      notifier.undo();
      expect(notifier.canRedo, true);

      notifier.addWaypoint(-35.370, 149.170);
      expect(notifier.canRedo, false);
    });

    test('clear removes all items', () {
      notifier.addWaypoint(-35.363, 149.165);
      notifier.addWaypoint(-35.364, 149.166);
      notifier.clear();

      expect(notifier.state.items, isEmpty);
      expect(notifier.state.isDirty, true);
    });

    test('loadItems replaces all and clears undo', () {
      notifier.addWaypoint(-35.363, 149.165);

      notifier.loadItems([
        const MissionItem(seq: 0, latitude: -36.0, longitude: 150.0),
        const MissionItem(seq: 1, latitude: -36.1, longitude: 150.1),
      ]);

      expect(notifier.state.waypointCount, 2);
      expect(notifier.state.items[0].latitude, -36.0);
      expect(notifier.state.selectedIndex, -1);
      expect(notifier.state.isDirty, false);
      expect(notifier.canUndo, false);
    });

    test('markClean clears dirty flag', () {
      notifier.addWaypoint(-35.363, 149.165);
      expect(notifier.state.isDirty, true);

      notifier.markClean();
      expect(notifier.state.isDirty, false);
    });

    test('setDefaultAltitude affects new waypoints', () {
      notifier.setDefaultAltitude(100.0);
      notifier.addWaypoint(-35.363, 149.165);

      expect(notifier.state.items[0].altitude, 100.0);
    });
  });
}
