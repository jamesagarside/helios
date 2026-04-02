import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/point_of_interest.dart';

const _kFileName = 'points_of_interest.json';

/// Manages user-defined points of interest, persisted to
/// `{appSupportDir}/points_of_interest.json`.
///
/// Platform: All
class PoiNotifier extends StateNotifier<List<PointOfInterest>> {
  PoiNotifier() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      final list = (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(PointOfInterest.fromJson)
          .toList();
      if (mounted) state = list;
    } catch (_) {
      // If the file is corrupt, start with an empty list.
      if (mounted) state = const [];
    }
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode(state.map((p) => p.toJson()).toList()),
      );
    } catch (_) {
      // Save failure is non-fatal — state is still in memory.
    }
  }

  Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/$_kFileName');
  }

  /// Adds a new point of interest.
  void addPoi(PointOfInterest poi) {
    state = [...state, poi];
    _save();
  }

  /// Replaces an existing POI by [PointOfInterest.id].
  void updatePoi(PointOfInterest poi) {
    state = [
      for (final existing in state)
        if (existing.id == poi.id) poi else existing,
    ];
    _save();
  }

  /// Removes the POI with the given [id].
  void removePoi(String id) {
    state = state.where((p) => p.id != id).toList();
    _save();
  }

  /// Removes all points of interest.
  void clear() {
    state = const [];
    _save();
  }
}

final poiProvider = StateNotifierProvider<PoiNotifier, List<PointOfInterest>>(
  (ref) => PoiNotifier(),
);
