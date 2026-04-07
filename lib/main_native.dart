import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'core/map/cached_tile_provider.dart';

/// Native platform initialisation (macOS, Linux, Windows, iOS, Android).
Future<void> initialise() async {
  // media_kit native libs are only bundled for desktop platforms.
  if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
    MediaKit.ensureInitialized();
  }
  await initialiseTileCache();
}
