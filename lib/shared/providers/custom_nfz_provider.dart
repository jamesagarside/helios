import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/custom_nfz.dart';

const _kFileName = 'custom_nfz.json';

/// Persists user-drawn no-fly zones to `{appSupportDir}/custom_nfz.json`.
///
/// Platform: All platforms
class CustomNfzNotifier extends StateNotifier<List<CustomNfz>> {
  CustomNfzNotifier() : super(const []) {
    _load();
  }

  final _uuid = const Uuid();

  Future<void> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      final list = (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(CustomNfz.fromJson)
          .toList();
      state = list;
    } catch (_) {
      // If the file is corrupt, start fresh
      state = const [];
    }
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode(state.map((z) => z.toJson()).toList()),
      );
    } catch (_) {
      // Save failure is non-fatal — state is still in memory
    }
  }

  Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/$_kFileName');
  }

  /// Adds a new custom NFZ with the given polygon points and name.
  Future<void> addZone(
    List<LatLng> polygon,
    String name, {
    String colour = 'orange',
  }) async {
    final zone = CustomNfz(
      id: _uuid.v4(),
      name: name,
      polygon: List.unmodifiable(polygon),
      colour: colour,
    );
    state = [...state, zone];
    await _save();
  }

  /// Removes the zone with the given [id].
  Future<void> removeZone(String id) async {
    state = state.where((z) => z.id != id).toList();
    await _save();
  }

  /// Removes all custom NFZs.
  Future<void> clear() async {
    state = const [];
    await _save();
  }
}

final customNfzProvider =
    StateNotifierProvider<CustomNfzNotifier, List<CustomNfz>>(
  (ref) => CustomNfzNotifier(),
);
