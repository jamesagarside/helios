import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../models/home_location.dart';

const _kFileName = 'home_locations.json';

/// Well-known default locations pre-populated on first run.
const _kDefaults = [
  HomeLocation(
    name: 'CMAC (ArduPilot Default)',
    position: LatLng(-35.3632, 149.1652),
    altitude: 584,
    isDefault: true,
    notes: 'Canberra Model Aircraft Club — ArduPilot SITL default',
  ),
  HomeLocation(
    name: 'Duxford Airfield',
    position: LatLng(52.0907, 0.1319),
    altitude: 38,
    notes: 'Imperial War Museum Duxford, Cambridgeshire',
  ),
  HomeLocation(
    name: 'NASA Ames',
    position: LatLng(37.4090, -122.0640),
    altitude: 12,
    notes: 'Moffett Federal Airfield, Mountain View CA',
  ),
];

/// Manages saved home/launch locations, persisted to
/// `{appSupportDir}/home_locations.json`.
///
/// Platform: All
class HomeLocationNotifier extends StateNotifier<List<HomeLocation>> {
  HomeLocationNotifier() : super(const []) {
    _load();
  }

  Future<void> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        // First run — seed with defaults.
        if (mounted) state = _kDefaults;
        await _save();
        return;
      }
      final raw = await file.readAsString();
      final list = (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(HomeLocation.fromJson)
          .toList();
      if (mounted) state = list;
    } catch (_) {
      // Corrupt file — seed with defaults.
      if (mounted) state = _kDefaults;
    }
  }

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode(state.map((h) => h.toJson()).toList()),
      );
    } catch (_) {
      // Save failure is non-fatal — state is still in memory.
    }
  }

  Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}/$_kFileName');
  }

  /// Adds a new home location.
  void add(HomeLocation location) {
    state = [...state, location];
    _save();
  }

  /// Removes the location matching [name].
  void remove(String name) {
    state = state.where((h) => h.name != name).toList();
    _save();
  }

  /// Replaces a location by name.
  void update(String originalName, HomeLocation updated) {
    state = [
      for (final h in state)
        if (h.name == originalName) updated else h,
    ];
    _save();
  }

  /// Sets one location as default, clearing the default flag on all others.
  void setDefault(String name) {
    state = [
      for (final h in state)
        h.copyWith(isDefault: h.name == name),
    ];
    _save();
  }

  /// Removes all saved locations and reseeds with defaults.
  void resetToDefaults() {
    state = _kDefaults;
    _save();
  }

  /// Import locations from a CSV string (name,lat,lon,alt per line).
  /// Skips malformed rows. Returns the number of successfully imported items.
  int importCsv(String csv) {
    final lines = csv.split('\n').where((l) => l.trim().isNotEmpty);
    final imported = <HomeLocation>[];
    for (final line in lines) {
      final parts = line.split(',');
      if (parts.length < 3) continue;
      final name = parts[0].trim();
      final lat = double.tryParse(parts[1].trim());
      final lon = double.tryParse(parts[2].trim());
      if (name.isEmpty || lat == null || lon == null) continue;
      final alt = parts.length > 3
          ? (double.tryParse(parts[3].trim()) ?? 0)
          : 0.0;
      imported.add(HomeLocation(
        name: name,
        position: LatLng(lat, lon),
        altitude: alt,
      ));
    }
    if (imported.isEmpty) return 0;
    state = [...state, ...imported];
    _save();
    return imported.length;
  }
}

/// All saved home locations.
final savedLocationsProvider =
    StateNotifierProvider<HomeLocationNotifier, List<HomeLocation>>(
  (ref) => HomeLocationNotifier(),
);

/// The current default home location (first marked as default, or first item).
final defaultHomeProvider = Provider<HomeLocation?>((ref) {
  final locations = ref.watch(savedLocationsProvider);
  if (locations.isEmpty) return null;
  return locations.firstWhere(
    (h) => h.isDefault,
    orElse: () => locations.first,
  );
});
