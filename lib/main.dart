import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'core/map/cached_tile_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await CachedTileProvider.initialise();
  runApp(
    const ProviderScope(
      child: HeliosApp(),
    ),
  );
}
