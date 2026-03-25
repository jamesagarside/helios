import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _scaleKey = 'display_scale';
const double defaultScale = 1.0;
const double minScale = 0.8;
const double maxScale = 1.6;
const double scaleStep = 0.05;

/// Display settings — currently just UI scale factor.
class DisplayNotifier extends StateNotifier<double> {
  DisplayNotifier() : super(defaultScale) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final scale = prefs.getDouble(_scaleKey) ?? defaultScale;
    state = scale.clamp(minScale, maxScale);
  }

  Future<void> setScale(double scale) async {
    state = scale.clamp(minScale, maxScale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scaleKey, state);
  }

  void increase() => setScale(state + scaleStep);
  void decrease() => setScale(state - scaleStep);
  void reset() => setScale(defaultScale);
}

/// Global UI scale factor provider.
final displayScaleProvider = StateNotifierProvider<DisplayNotifier, double>(
  (ref) => DisplayNotifier(),
);
