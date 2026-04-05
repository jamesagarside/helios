import 'package:media_kit/media_kit.dart';
import 'core/map/cached_tile_provider.dart';

/// Native platform initialisation (macOS, Linux, Windows, iOS, Android).
Future<void> initialise() async {
  MediaKit.ensureInitialized();
  await CachedTileProvider.initialise();
}
