import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/mission_item.dart';

/// Local editing state for the Plan View.
///
/// Separate from [missionStateProvider] which tracks the vehicle's mission.
/// This notifier handles tap-to-place, reorder, delete, undo/redo, and
/// multi-select batch operations.
class MissionEditState {
  const MissionEditState({
    this.items = const [],
    this.selectedIndex = -1,
    this.defaultAltitude = 50.0,
    this.isDirty = false,
    this.selectedSeqs = const {},
  });

  final List<MissionItem> items;
  final int selectedIndex;
  final double defaultAltitude;
  final bool isDirty;

  /// Sequence numbers currently selected for multi-select batch operations.
  final Set<int> selectedSeqs;

  int get waypointCount => items.length;
  bool get hasSelection => selectedIndex >= 0 && selectedIndex < items.length;
  MissionItem? get selectedItem =>
      hasSelection ? items[selectedIndex] : null;

  /// True when two or more items are selected via multi-select.
  bool get hasMultiSelection => selectedSeqs.length > 1;

  MissionEditState copyWith({
    List<MissionItem>? items,
    int? selectedIndex,
    double? defaultAltitude,
    bool? isDirty,
    Set<int>? selectedSeqs,
  }) {
    return MissionEditState(
      items: items ?? this.items,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      defaultAltitude: defaultAltitude ?? this.defaultAltitude,
      isDirty: isDirty ?? this.isDirty,
      selectedSeqs: selectedSeqs ?? this.selectedSeqs,
    );
  }
}

class MissionEditNotifier extends StateNotifier<MissionEditState> {
  MissionEditNotifier() : super(const MissionEditState());

  final List<List<MissionItem>> _undoStack = [];
  final List<List<MissionItem>> _redoStack = [];
  static const int _maxUndo = 50;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void _pushUndo() {
    _undoStack.add(List.of(state.items));
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  /// Add a waypoint at the given lat/lon.
  void addWaypoint(double latitude, double longitude) {
    _pushUndo();
    final seq = state.items.length;
    final item = MissionItem(
      seq: seq,
      latitude: latitude,
      longitude: longitude,
      altitude: state.defaultAltitude,
      command: seq == 0 ? MavCmd.navTakeoff : MavCmd.navWaypoint,
    );
    final newItems = [...state.items, item];
    state = state.copyWith(
      items: newItems,
      selectedIndex: seq,
      isDirty: true,
    );
  }

  /// Remove the waypoint at [index] and renumber.
  void removeWaypoint(int index) {
    if (index < 0 || index >= state.items.length) return;
    _pushUndo();
    final newItems = List<MissionItem>.from(state.items)..removeAt(index);
    _renumber(newItems);
    final newSel = state.selectedIndex >= newItems.length
        ? newItems.length - 1
        : state.selectedIndex == index
            ? -1
            : state.selectedIndex > index
                ? state.selectedIndex - 1
                : state.selectedIndex;
    state = state.copyWith(
      items: newItems,
      selectedIndex: newSel,
      isDirty: true,
    );
  }

  /// Move a waypoint's position on the map (drag).
  void moveWaypoint(int index, double latitude, double longitude) {
    if (index < 0 || index >= state.items.length) return;
    _pushUndo();
    final newItems = List<MissionItem>.from(state.items);
    newItems[index] = newItems[index].copyWith(
      latitude: latitude,
      longitude: longitude,
    );
    state = state.copyWith(items: newItems, isDirty: true);
  }

  /// Reorder a waypoint from [oldIndex] to [newIndex].
  void reorderWaypoint(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    _pushUndo();
    final newItems = List<MissionItem>.from(state.items);
    final item = newItems.removeAt(oldIndex);
    newItems.insert(newIndex, item);
    _renumber(newItems);

    // Track selection through the reorder
    int newSel = state.selectedIndex;
    if (state.selectedIndex == oldIndex) {
      newSel = newIndex;
    } else if (oldIndex < state.selectedIndex && newIndex >= state.selectedIndex) {
      newSel--;
    } else if (oldIndex > state.selectedIndex && newIndex <= state.selectedIndex) {
      newSel++;
    }

    state = state.copyWith(
      items: newItems,
      selectedIndex: newSel,
      isDirty: true,
    );
  }

  /// Update a single field on the selected waypoint.
  void updateWaypoint(int index, MissionItem updated) {
    if (index < 0 || index >= state.items.length) return;
    _pushUndo();
    final newItems = List<MissionItem>.from(state.items);
    newItems[index] = updated.copyWith(seq: index);
    state = state.copyWith(items: newItems, isDirty: true);
  }

  /// Select a waypoint by index (-1 to deselect).
  void select(int index) {
    state = state.copyWith(selectedIndex: index);
  }

  /// Set the default altitude for new waypoints.
  void setDefaultAltitude(double alt) {
    state = state.copyWith(defaultAltitude: alt);
  }

  /// Load items (e.g., from a download or file).
  void loadItems(List<MissionItem> items) {
    _undoStack.clear();
    _redoStack.clear();
    state = MissionEditState(
      items: List.of(items),
      selectedIndex: -1,
      defaultAltitude: state.defaultAltitude,
    );
  }

  /// Clear all waypoints.
  void clear() {
    _pushUndo();
    state = MissionEditState(
      defaultAltitude: state.defaultAltitude,
      isDirty: true,
    );
  }

  /// Undo last action.
  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List.of(state.items));
    final items = _undoStack.removeLast();
    state = state.copyWith(
      items: items,
      selectedIndex: -1,
      isDirty: _undoStack.isNotEmpty,
      selectedSeqs: const {},
    );
  }

  /// Redo last undone action.
  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List.of(state.items));
    final items = _redoStack.removeLast();
    state = state.copyWith(
      items: items,
      selectedIndex: -1,
      isDirty: true,
      selectedSeqs: const {},
    );
  }

  /// Mark as clean (after upload).
  void markClean() {
    state = state.copyWith(isDirty: false);
  }

  // ─── Multi-select ──────────────────────────────────────────────────────────

  /// Toggle [seq] in the multi-select set.
  void toggleSelection(int seq) {
    final current = Set<int>.from(state.selectedSeqs);
    if (current.contains(seq)) {
      current.remove(seq);
    } else {
      current.add(seq);
    }
    state = state.copyWith(selectedSeqs: current);
  }

  /// Select all navigation waypoints (items where [MissionItem.isNavCommand]).
  void selectAll() {
    final seqs = state.items
        .where((i) => i.isNavCommand)
        .map((i) => i.seq)
        .toSet();
    state = state.copyWith(selectedSeqs: seqs);
  }

  /// Clear the multi-select set.
  void clearSelection() {
    state = state.copyWith(selectedSeqs: const {});
  }

  /// Set the altitude of every item whose seq is in [selectedSeqs].
  void batchSetAltitude(double alt) {
    if (state.selectedSeqs.isEmpty) return;
    _pushUndo();
    final newItems = state.items.map((item) {
      if (state.selectedSeqs.contains(item.seq)) {
        return item.copyWith(altitude: alt);
      }
      return item;
    }).toList();
    state = state.copyWith(items: newItems, isDirty: true);
  }

  /// Delete all items whose seq is in [selectedSeqs] and clear the selection.
  void batchDelete() {
    if (state.selectedSeqs.isEmpty) return;
    _pushUndo();
    final newItems = state.items
        .where((i) => !state.selectedSeqs.contains(i.seq))
        .toList();
    _renumber(newItems);
    state = state.copyWith(
      items: newItems,
      selectedIndex: -1,
      isDirty: true,
      selectedSeqs: const {},
    );
  }

  /// Insert a DO_CHANGE_SPEED command immediately before each selected
  /// navigation waypoint.
  void batchSetSpeed(double speedMs) {
    if (state.selectedSeqs.isEmpty) return;
    _pushUndo();
    final result = <MissionItem>[];
    for (final item in state.items) {
      if (state.selectedSeqs.contains(item.seq) && item.isNavCommand) {
        result.add(MissionItem(
          seq: 0, // renumbered below
          command: MavCmd.doChangeSpeed,
          param1: 1, // groundspeed
          param2: speedMs,
          param3: -1, // no throttle change
        ));
      }
      result.add(item);
    }
    _renumber(result);
    state = state.copyWith(
      items: result,
      isDirty: true,
      selectedSeqs: const {},
    );
  }

  void _renumber(List<MissionItem> items) {
    for (var i = 0; i < items.length; i++) {
      if (items[i].seq != i) {
        items[i] = items[i].copyWith(seq: i);
      }
    }
  }
}

/// Provider for the mission edit notifier.
final missionEditProvider =
    StateNotifierProvider<MissionEditNotifier, MissionEditState>(
  (ref) => MissionEditNotifier(),
);
