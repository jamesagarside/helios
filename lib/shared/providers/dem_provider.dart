import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/dem/dem_service.dart';

/// Exposes the DEM service as a singleton Riverpod provider.
class DemNotifier extends StateNotifier<bool> {
  DemNotifier() : super(false);

  final service = DemService();

  /// Open a file picker and load selected SRTM .hgt files.
  /// Returns true if at least one tile was loaded.
  Future<bool> importFromFilePicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['hgt'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return false;

    var loaded = false;
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      await service.loadHgt(path);
      loaded = true;
    }

    if (loaded) state = service.hasData;
    return loaded;
  }

  void clear() {
    service.clear();
    state = false;
  }
}

final demProvider = StateNotifierProvider<DemNotifier, bool>(
  (ref) => DemNotifier(),
);
