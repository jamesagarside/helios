import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Configurable telemetry stream rates (Hz).
class StreamRateSettings {
  const StreamRateSettings({
    this.attitudeHz = 10,
    this.positionHz = 5,
    this.vfrHudHz = 5,
    this.statusHz = 2,
    this.rcChannelsHz = 2,
    this.preset = StreamRatePreset.normal,
  });

  final int attitudeHz;
  final int positionHz;
  final int vfrHudHz;
  final int statusHz;
  final int rcChannelsHz;
  final StreamRatePreset preset;

  StreamRateSettings copyWith({
    int? attitudeHz,
    int? positionHz,
    int? vfrHudHz,
    int? statusHz,
    int? rcChannelsHz,
    StreamRatePreset? preset,
  }) {
    return StreamRateSettings(
      attitudeHz: attitudeHz ?? this.attitudeHz,
      positionHz: positionHz ?? this.positionHz,
      vfrHudHz: vfrHudHz ?? this.vfrHudHz,
      statusHz: statusHz ?? this.statusHz,
      rcChannelsHz: rcChannelsHz ?? this.rcChannelsHz,
      preset: preset ?? this.preset,
    );
  }

  /// Estimated DuckDB rows per minute at these rates.
  int get estimatedRowsPerMinute =>
      (attitudeHz + positionHz + vfrHudHz + statusHz + rcChannelsHz) * 60;
}

enum StreamRatePreset {
  normal('Normal', 'Balanced for flight monitoring'),
  highRate('High Rate', 'For vibration analysis and tuning'),
  lowBandwidth('Low Bandwidth', 'For radio telemetry links'),
  custom('Custom', 'User-defined rates');

  const StreamRatePreset(this.label, this.description);
  final String label;
  final String description;
}

const _presets = {
  StreamRatePreset.normal: StreamRateSettings(
    attitudeHz: 10, positionHz: 5, vfrHudHz: 5, statusHz: 2, rcChannelsHz: 2,
    preset: StreamRatePreset.normal,
  ),
  StreamRatePreset.highRate: StreamRateSettings(
    attitudeHz: 25, positionHz: 10, vfrHudHz: 10, statusHz: 4, rcChannelsHz: 4,
    preset: StreamRatePreset.highRate,
  ),
  StreamRatePreset.lowBandwidth: StreamRateSettings(
    attitudeHz: 4, positionHz: 2, vfrHudHz: 2, statusHz: 1, rcChannelsHz: 1,
    preset: StreamRatePreset.lowBandwidth,
  ),
};

class StreamRateNotifier extends StateNotifier<StreamRateSettings> {
  StreamRateNotifier() : super(const StreamRateSettings()) {
    _load();
  }

  static const _keyAttitude = 'sr_attitude';
  static const _keyPosition = 'sr_position';
  static const _keyVfr = 'sr_vfr';
  static const _keyStatus = 'sr_status';
  static const _keyRc = 'sr_rc';
  static const _keyPreset = 'sr_preset';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final presetName = prefs.getString(_keyPreset);
    if (presetName == null) return;

    final preset = StreamRatePreset.values.firstWhere(
      (p) => p.name == presetName,
      orElse: () => StreamRatePreset.normal,
    );

    state = StreamRateSettings(
      attitudeHz: prefs.getInt(_keyAttitude) ?? 10,
      positionHz: prefs.getInt(_keyPosition) ?? 5,
      vfrHudHz: prefs.getInt(_keyVfr) ?? 5,
      statusHz: prefs.getInt(_keyStatus) ?? 2,
      rcChannelsHz: prefs.getInt(_keyRc) ?? 2,
      preset: preset,
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAttitude, state.attitudeHz);
    await prefs.setInt(_keyPosition, state.positionHz);
    await prefs.setInt(_keyVfr, state.vfrHudHz);
    await prefs.setInt(_keyStatus, state.statusHz);
    await prefs.setInt(_keyRc, state.rcChannelsHz);
    await prefs.setString(_keyPreset, state.preset.name);
  }

  void applyPreset(StreamRatePreset preset) {
    if (preset == StreamRatePreset.custom) {
      state = state.copyWith(preset: StreamRatePreset.custom);
    } else {
      state = _presets[preset]!;
    }
    _save();
  }

  void setRate({
    int? attitudeHz,
    int? positionHz,
    int? vfrHudHz,
    int? statusHz,
    int? rcChannelsHz,
  }) {
    state = state.copyWith(
      attitudeHz: attitudeHz,
      positionHz: positionHz,
      vfrHudHz: vfrHudHz,
      statusHz: statusHz,
      rcChannelsHz: rcChannelsHz,
      preset: StreamRatePreset.custom,
    );
    _save();
  }
}

final streamRateProvider =
    StateNotifierProvider<StreamRateNotifier, StreamRateSettings>(
  (ref) => StreamRateNotifier(),
);
