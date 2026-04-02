import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kApiKey = 'openAipApiKey';

/// Settings for OpenAIP airspace data fetching.
class AirspaceSettings {
  const AirspaceSettings({this.apiKey = ''});

  final String apiKey;

  bool get hasApiKey => apiKey.isNotEmpty;

  AirspaceSettings copyWith({String? apiKey}) =>
      AirspaceSettings(apiKey: apiKey ?? this.apiKey);

  @override
  bool operator ==(Object other) =>
      other is AirspaceSettings && other.apiKey == apiKey;

  @override
  int get hashCode => apiKey.hashCode;
}

/// Persists the OpenAIP API key in SharedPreferences.
class AirspaceSettingsNotifier extends StateNotifier<AirspaceSettings> {
  AirspaceSettingsNotifier() : super(const AirspaceSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_kApiKey) ?? '';
    state = AirspaceSettings(apiKey: key);
  }

  Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kApiKey, key);
    state = state.copyWith(apiKey: key);
  }
}

final airspaceSettingsProvider =
    StateNotifierProvider<AirspaceSettingsNotifier, AirspaceSettings>(
  (ref) => AirspaceSettingsNotifier(),
);
