import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'main_native.dart' if (dart.library.js_interop) 'main_web.dart'
    as platform_init;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await platform_init.initialise();
  runApp(
    const ProviderScope(
      child: HeliosApp(),
    ),
  );
}
