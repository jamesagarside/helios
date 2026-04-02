import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/rally_point.dart';

/// Local editing state for rally points in Plan View.
class RallyPointNotifier extends StateNotifier<List<RallyPoint>> {
  RallyPointNotifier() : super([]);

  void addPoint(double lat, double lon, {double altitude = 50.0}) {
    state = [
      ...state,
      RallyPoint(seq: state.length, latitude: lat, longitude: lon, altitude: altitude),
    ];
  }

  void removePoint(int index) {
    if (index < 0 || index >= state.length) return;
    final newList = List<RallyPoint>.from(state)..removeAt(index);
    for (var i = 0; i < newList.length; i++) {
      if (newList[i].seq != i) {
        newList[i] = newList[i].copyWith(seq: i);
      }
    }
    state = newList;
  }

  void loadPoints(List<RallyPoint> points) {
    state = List.of(points);
  }

  void clear() {
    state = [];
  }
}

final rallyPointProvider =
    StateNotifierProvider<RallyPointNotifier, List<RallyPoint>>(
  (ref) => RallyPointNotifier(),
);
