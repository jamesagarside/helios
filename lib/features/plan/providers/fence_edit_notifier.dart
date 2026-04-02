import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/fence_zone.dart';

/// Local editing state for geofence zones in Plan View.
class FenceEditState {
  const FenceEditState({
    this.zones = const [],
    this.drawingMode = false,
    this.drawingType = FenceZoneType.inclusion,
    this.drawingVertices = const [],
    this.selectedZoneIndex = -1,
  });

  final List<FenceZone> zones;
  final bool drawingMode;
  final FenceZoneType drawingType;
  final List<({double lat, double lon})> drawingVertices;
  final int selectedZoneIndex;

  FenceEditState copyWith({
    List<FenceZone>? zones,
    bool? drawingMode,
    FenceZoneType? drawingType,
    List<({double lat, double lon})>? drawingVertices,
    int? selectedZoneIndex,
  }) {
    return FenceEditState(
      zones: zones ?? this.zones,
      drawingMode: drawingMode ?? this.drawingMode,
      drawingType: drawingType ?? this.drawingType,
      drawingVertices: drawingVertices ?? this.drawingVertices,
      selectedZoneIndex: selectedZoneIndex ?? this.selectedZoneIndex,
    );
  }
}

class FenceEditNotifier extends StateNotifier<FenceEditState> {
  FenceEditNotifier() : super(const FenceEditState());

  /// Start drawing a new polygon fence.
  void startDrawing(FenceZoneType type) {
    state = state.copyWith(
      drawingMode: true,
      drawingType: type,
      drawingVertices: [],
    );
  }

  /// Add a vertex to the current drawing.
  void addVertex(double lat, double lon) {
    if (!state.drawingMode) return;
    state = state.copyWith(
      drawingVertices: [...state.drawingVertices, (lat: lat, lon: lon)],
    );
  }

  /// Complete the current polygon and add it as a zone.
  void finishDrawing() {
    if (state.drawingVertices.length < 3) {
      cancelDrawing();
      return;
    }

    final zone = FenceZone(
      type: state.drawingType,
      shape: FenceShape.polygon,
      vertices: List.of(state.drawingVertices),
    );

    state = FenceEditState(
      zones: [...state.zones, zone],
    );
  }

  /// Cancel the current drawing.
  void cancelDrawing() {
    state = state.copyWith(
      drawingMode: false,
      drawingVertices: [],
    );
  }

  /// Add a circle fence zone.
  void addCircleZone({
    required FenceZoneType type,
    required double lat,
    required double lon,
    required double radius,
  }) {
    final zone = FenceZone(
      type: type,
      shape: FenceShape.circle,
      centerLat: lat,
      centerLon: lon,
      radius: radius,
    );
    state = FenceEditState(
      zones: [...state.zones, zone],
    );
  }

  /// Remove a zone by index.
  void removeZone(int index) {
    if (index < 0 || index >= state.zones.length) return;
    final newZones = List<FenceZone>.from(state.zones)..removeAt(index);
    state = FenceEditState(zones: newZones);
  }

  /// Load zones (e.g. from download).
  void loadZones(List<FenceZone> zones) {
    state = FenceEditState(zones: zones);
  }

  /// Clear all zones.
  void clear() {
    state = const FenceEditState();
  }

  /// Select a zone.
  void selectZone(int index) {
    state = state.copyWith(selectedZoneIndex: index);
  }
}

final fenceEditProvider =
    StateNotifierProvider<FenceEditNotifier, FenceEditState>(
  (ref) => FenceEditNotifier(),
);
