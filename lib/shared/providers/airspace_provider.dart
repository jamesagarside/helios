import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/airspace/airspace_service.dart';
import '../../core/airspace/openair_fetch_service.dart';
import '../models/airspace_zone.dart';

/// State for the airspace provider.
class AirspaceState {
  const AirspaceState({
    this.zones = const [],
    this.isFetching = false,
  });

  final List<AirspaceZone> zones;
  final bool isFetching;

  AirspaceState copyWith({
    List<AirspaceZone>? zones,
    bool? isFetching,
  }) =>
      AirspaceState(
        zones: zones ?? this.zones,
        isFetching: isFetching ?? this.isFetching,
      );
}

/// Holds the currently loaded airspace zones.
class AirspaceNotifier extends StateNotifier<AirspaceState> {
  AirspaceNotifier() : super(const AirspaceState());

  final _service = AirspaceService();
  final _fetchService = OpenAirFetchService();

  /// Convenience accessor for the zones list.
  List<AirspaceZone> get zones => state.zones;

  /// Returns true if at least one file was successfully imported.
  Future<bool> importFromFilePicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'geojson'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return false;

    final added = <AirspaceZone>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      final zones = await _service.importGeoJson(path);
      added.addAll(zones);
    }

    if (added.isNotEmpty) {
      state = state.copyWith(zones: [...state.zones, ...added]);
      return true;
    }
    return false;
  }

  /// Fetches airspace from OpenAIP for the given bounding box, merges results
  /// into state (deduplicates by id), and returns the count of new zones added.
  Future<int> fetchFromOpenAip(
    double minLat,
    double maxLat,
    double minLon,
    double maxLon,
    String apiKey,
  ) async {
    state = state.copyWith(isFetching: true);
    try {
      final fetched = await _fetchService.fetchForBounds(
        minLat: minLat,
        maxLat: maxLat,
        minLon: minLon,
        maxLon: maxLon,
        apiKey: apiKey,
      );

      final existingIds = {for (final z in state.zones) z.id};
      final newZones = fetched.where((z) => !existingIds.contains(z.id)).toList();
      state = state.copyWith(
        zones: [...state.zones, ...newZones],
        isFetching: false,
      );
      return newZones.length;
    } catch (_) {
      state = state.copyWith(isFetching: false);
      rethrow;
    }
  }

  void clear() => state = state.copyWith(zones: const []);

  void removeZone(String id) {
    state = state.copyWith(
      zones: state.zones.where((z) => z.id != id).toList(),
    );
  }
}

final airspaceProvider =
    StateNotifierProvider<AirspaceNotifier, AirspaceState>(
  (ref) => AirspaceNotifier(),
);
