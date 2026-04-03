import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'openaip_api_key';

/// Persists the user's OpenAIP API key in SharedPreferences.
class OpenAipKeyNotifier extends StateNotifier<String> {
  OpenAipKeyNotifier() : super('') {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_key) ?? '';
  }

  Future<void> setKey(String apiKey) async {
    state = apiKey.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, state);
  }

  Future<void> clear() async {
    state = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

final openAipKeyProvider =
    StateNotifierProvider<OpenAipKeyNotifier, String>(
  (ref) => OpenAipKeyNotifier(),
);
