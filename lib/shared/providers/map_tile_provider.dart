import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MapTileType {
  osm('OpenStreetMap'),
  satellite('Satellite (ESRI)'),
  terrain('Terrain'),
  hybrid('Hybrid (Sat + Labels)');

  const MapTileType(this.label);
  final String label;
}

class MapTileNotifier extends StateNotifier<MapTileType> {
  MapTileNotifier() : super(MapTileType.osm) {
    _load();
  }

  static const _key = 'map_tile_type';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) {
      try {
        state = MapTileType.values.firstWhere((t) => t.name == saved);
      } catch (_) {}
    }
  }

  Future<void> setType(MapTileType type) async {
    state = type;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, type.name);
  }
}

final mapTileTypeProvider = StateNotifierProvider<MapTileNotifier, MapTileType>(
  (ref) => MapTileNotifier(),
);
