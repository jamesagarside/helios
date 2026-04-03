import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/layout_profile.dart';
import '../models/telemetry_tile_config.dart';
import '../../features/fly/widgets/chart_toolbar.dart';

const _profilesKey = 'layout_profiles';
const _activeProfileKey = 'layout_active_profile';
const _editModeKey = 'layout_edit_mode';

/// Snap-to-grid size in logical pixels.
const double gridSize = 20.0;

/// Snaps a value to the nearest grid line.
double snapToGrid(double value) {
  return (value / gridSize).round() * gridSize;
}

/// State for the layout system.
@immutable
class LayoutState {
  const LayoutState({
    this.profiles = const [],
    this.activeProfileName = 'Multirotor',
    this.editMode = false,
  });

  final List<LayoutProfile> profiles;
  final String activeProfileName;
  final bool editMode;

  LayoutProfile get activeProfile {
    return profiles.firstWhere(
      (p) => p.name == activeProfileName,
      orElse: () => profiles.isNotEmpty ? profiles.first : defaultMultirotorProfile(),
    );
  }

  LayoutState copyWith({
    List<LayoutProfile>? profiles,
    String? activeProfileName,
    bool? editMode,
  }) {
    return LayoutState(
      profiles: profiles ?? this.profiles,
      activeProfileName: activeProfileName ?? this.activeProfileName,
      editMode: editMode ?? this.editMode,
    );
  }
}

/// Manages layout profiles with SharedPreferences persistence.
class LayoutNotifier extends StateNotifier<LayoutState> {
  LayoutNotifier() : super(const LayoutState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getStringList(_profilesKey);
    final activeName = prefs.getString(_activeProfileKey);
    final editMode = prefs.getBool(_editModeKey) ?? false;

    final defaults = [
      defaultMultirotorProfile(),
      defaultFixedWingProfile(),
      defaultVtolProfile(),
    ];

    List<LayoutProfile> profiles;
    if (encoded != null && encoded.isNotEmpty) {
      profiles = encoded.map((e) {
        try {
          return LayoutProfile.fromJson(jsonDecode(e) as Map<String, dynamic>);
        } catch (_) {
          return null;
        }
      }).whereType<LayoutProfile>().toList();

      // Ensure all defaults exist
      for (final d in defaults) {
        if (!profiles.any((p) => p.name == d.name)) {
          profiles.add(d);
        }
      }
    } else {
      profiles = defaults;
    }

    if (!mounted) return;
    state = LayoutState(
      profiles: profiles,
      activeProfileName: activeName ?? 'Multirotor',
      editMode: editMode,
    );
  }

  Future<void> _save() async {
    if (!mounted) return;
    try {
      final data = state; // capture before any await
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final encoded = data.profiles.map((p) => jsonEncode(p.toJson())).toList();
      await prefs.setStringList(_profilesKey, encoded);
      await prefs.setString(_activeProfileKey, data.activeProfileName);
      await prefs.setBool(_editModeKey, data.editMode);
    } catch (_) {
      // Disposed during save — safe to ignore
    }
  }

  /// Switch to a different profile.
  void selectProfile(String name) {
    state = state.copyWith(activeProfileName: name);
    _save();
  }

  /// Toggle edit/lock mode.
  void toggleEditMode() {
    state = state.copyWith(editMode: !state.editMode);
    _save();
  }

  /// Toggle a chart's visibility in the active profile.
  void toggleChart(ChartType type) {
    final profile = state.activeProfile;
    final charts = Map<String, WidgetConfig>.from(profile.charts);
    final key = type.name;

    if (charts.containsKey(key) && charts[key]!.visible) {
      charts[key] = charts[key]!.copyWith(visible: false);
    } else {
      // Count currently visible charts to tile new ones sensibly
      final visibleCount =
          charts.values.where((c) => c.visible).length;
      final col = visibleCount % 2;
      final row = visibleCount ~/ 2;
      charts[key] = (charts[key] ?? WidgetConfig(
        x: 350.0 + col * 300,
        y: 50.0 + row * 170.0,
      )).copyWith(visible: true);
    }

    _updateActiveProfile(profile.copyWith(charts: charts));
  }

  /// Update a chart's position (called on drag end).
  void updateChartPosition(ChartType type, double x, double y) {
    final profile = state.activeProfile;
    final charts = Map<String, WidgetConfig>.from(profile.charts);
    final key = type.name;
    final existing = charts[key] ?? WidgetConfig(x: x, y: y);
    charts[key] = existing.copyWith(x: snapToGrid(x), y: snapToGrid(y));
    _updateActiveProfile(profile.copyWith(charts: charts));
  }

  /// Update a chart's size (called on resize end).
  void updateChartSize(ChartType type, double width, double height) {
    final profile = state.activeProfile;
    final charts = Map<String, WidgetConfig>.from(profile.charts);
    final key = type.name;
    final existing = charts[key] ?? const WidgetConfig(x: 350, y: 50);
    charts[key] = existing.copyWith(
      width: snapToGrid(width.clamp(200, 600)),
      height: snapToGrid(height.clamp(100, 400)),
    );
    _updateActiveProfile(profile.copyWith(charts: charts));
  }

  /// Toggle video PiP visibility.
  void toggleVideo() {
    final profile = state.activeProfile;
    _updateActiveProfile(profile.copyWith(
      video: profile.video.copyWith(visible: !profile.video.visible),
    ));
  }

  /// Update video PiP position.
  void updateVideoPosition(double x, double y) {
    final profile = state.activeProfile;
    _updateActiveProfile(profile.copyWith(
      video: profile.video.copyWith(x: snapToGrid(x), y: snapToGrid(y)),
    ));
  }

  /// Update PFD overlay position.
  void updatePfdPosition(double x, double y) {
    final profile = state.activeProfile;
    _updateActiveProfile(profile.copyWith(
      pfd: profile.pfd.copyWith(x: snapToGrid(x), y: snapToGrid(y)),
    ));
  }

  /// Update PFD overlay size.
  void updatePfdSize(double width, double height) {
    final profile = state.activeProfile;
    _updateActiveProfile(profile.copyWith(
      pfd: profile.pfd.copyWith(width: width, height: height),
    ));
  }

  /// Toggle PFD visibility.
  void togglePfd() {
    final profile = state.activeProfile;
    _updateActiveProfile(profile.copyWith(
      pfd: profile.pfd.copyWith(visible: !profile.pfd.visible),
    ));
  }

  /// Toggle telemetry strip visibility.
  void toggleTelemetryStrip() {
    final profile = state.activeProfile;
    _updateActiveProfile(profile.copyWith(
      telemetryStrip: profile.telemetryStrip.copyWith(
        visible: !profile.telemetryStrip.visible,
      ),
    ));
  }

  /// Toggle the message log overlay visibility.
  void toggleMessageLog() {
    final profile = state.activeProfile;
    _updateActiveProfile(
        profile.copyWith(showMessageLog: !profile.showMessageLog));
  }

  /// Toggle the flight action panel visibility.
  void toggleActionPanel() {
    final profile = state.activeProfile;
    _updateActiveProfile(
        profile.copyWith(showActionPanel: !profile.showActionPanel));
  }

  /// Toggle the servo output diagnostic panel visibility.
  void toggleServoPanel() {
    final profile = state.activeProfile;
    _updateActiveProfile(
        profile.copyWith(showServoPanel: !profile.showServoPanel));
  }

  /// Toggle the RC input diagnostic panel visibility.
  void toggleRcPanel() {
    final profile = state.activeProfile;
    _updateActiveProfile(
        profile.copyWith(showRcPanel: !profile.showRcPanel));
  }

  /// Toggle a PFD extra readout on/off.
  void togglePfdExtra(PfdExtra extra) {
    final profile = state.activeProfile;
    final extras = Set<PfdExtra>.from(profile.pfdExtras);
    if (extras.contains(extra)) {
      extras.remove(extra);
    } else {
      extras.add(extra);
    }
    _updateActiveProfile(profile.copyWith(pfdExtras: extras));
  }

  /// Replace the telemetry tile list for the active profile.
  void setTelemetryTiles(List<TelemetryTileConfig> tiles) {
    _updateActiveProfile(state.activeProfile.copyWith(telemetryTiles: tiles));
  }

  /// Create a new custom profile (copy of current).
  void createProfile(String name) {
    final copy = state.activeProfile.copyWith(name: name, isDefault: false);
    final profiles = [...state.profiles, copy];
    state = state.copyWith(profiles: profiles, activeProfileName: name);
    _save();
  }

  /// Delete a custom profile. Cannot delete defaults.
  void deleteProfile(String name) {
    final profile = state.profiles.firstWhere(
      (p) => p.name == name,
      orElse: () => defaultMultirotorProfile(),
    );
    if (profile.isDefault) return;

    final profiles = state.profiles.where((p) => p.name != name).toList();
    final newActive = state.activeProfileName == name
        ? profiles.first.name
        : state.activeProfileName;
    state = state.copyWith(profiles: profiles, activeProfileName: newActive);
    _save();
  }

  /// Reset the active profile to its default layout.
  void resetActiveProfile() {
    final profile = state.activeProfile;
    LayoutProfile? defaultProfile;
    switch (profile.vehicleType) {
      case VehicleType.multirotor:
        defaultProfile = defaultMultirotorProfile();
      case VehicleType.fixedWing:
        defaultProfile = defaultFixedWingProfile();
      case VehicleType.vtol:
        defaultProfile = defaultVtolProfile();
    }

    if (profile.isDefault) {
      _updateActiveProfile(defaultProfile);
    } else {
      // Custom profiles reset to multirotor defaults but keep name
      _updateActiveProfile(defaultMultirotorProfile().copyWith(
        name: profile.name,
        isDefault: false,
      ));
    }
  }

  void _updateActiveProfile(LayoutProfile updated) {
    final profiles = state.profiles.map((p) {
      return p.name == state.activeProfileName ? updated : p;
    }).toList();
    state = state.copyWith(profiles: profiles);
    _save();
  }
}

/// Layout state provider.
final layoutProvider = StateNotifierProvider<LayoutNotifier, LayoutState>(
  (ref) => LayoutNotifier(),
);

/// Convenience: active layout profile.
final activeLayoutProvider = Provider<LayoutProfile>(
  (ref) => ref.watch(layoutProvider).activeProfile,
);

/// Convenience: edit mode state.
final layoutEditModeProvider = Provider<bool>(
  (ref) => ref.watch(layoutProvider).editMode,
);
