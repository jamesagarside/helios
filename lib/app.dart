import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'shared/providers/display_provider.dart';
import 'shared/providers/providers.dart';
import 'shared/theme/helios_theme.dart';
import 'shared/widgets/responsive_scaffold.dart';
import 'shared/widgets/status_bar.dart';
import 'features/fly/fly_view.dart';
import 'features/plan/plan_view.dart';
import 'features/analyse/analyse_view.dart';
import 'features/video/video_view.dart';
import 'features/setup/setup_view.dart';

/// Helios GCS application root widget.
class HeliosApp extends ConsumerWidget {
  const HeliosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(displayScaleProvider);

    return MaterialApp(
      title: 'Helios GCS',
      debugShowCheckedModeBanner: false,
      theme: heliosTheme(),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        );
      },
      home: const _HeliosShell(),
    );
  }
}

/// Main shell with navigation and status bar.
class _HeliosShell extends ConsumerStatefulWidget {
  const _HeliosShell();

  @override
  ConsumerState<_HeliosShell> createState() => _HeliosShellState();
}

class _HeliosShellState extends ConsumerState<_HeliosShell> {
  int _selectedIndex = 0;

  // Views that don't need native libs — kept alive via IndexedStack.
  // Video and Setup (which references video provider) are lazy-loaded.
  static const _coreViews = <Widget>[
    FlyView(),
    PlanView(),
    AnalyseView(),
  ];

  Widget _buildBody() {
    if (_selectedIndex <= 2) {
      return IndexedStack(
        index: _selectedIndex,
        children: _coreViews,
      );
    }
    // Video and Setup are built on-demand (media_kit dependency)
    return switch (_selectedIndex) {
      3 => const VideoView(),
      4 => const SetupView(),
      _ => const SizedBox(),
    };
  }

  void _handleKeyPress(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    // Don't capture shortcuts when a text field has focus
    final focusNode = FocusManager.instance.primaryFocus;
    if (focusNode != null && focusNode.context != null) {
      final widget = focusNode.context!.widget;
      if (widget is EditableText) return;
    }

    final index = switch (event.logicalKey) {
      LogicalKeyboardKey.digit1 => 0,
      LogicalKeyboardKey.digit2 => 1,
      LogicalKeyboardKey.digit3 => 2,
      LogicalKeyboardKey.digit4 => 3,
      LogicalKeyboardKey.digit5 => 4,
      _ => null,
    };

    if (index != null && index != _selectedIndex) {
      setState(() => _selectedIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = ref.watch(vehicleStateProvider);
    final connection = ref.watch(connectionStatusProvider);
    final gpsLabel = ref.watch(gpsFixLabelProvider);
    final missionState = ref.watch(missionStateProvider);

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: _handleKeyPress,
      child: Column(
        children: [
          Expanded(
            child: ResponsiveScaffold(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) => setState(() => _selectedIndex = i),
              body: _buildBody(),
            ),
          ),
          StatusBar(
            flightMode: vehicle.flightMode.name,
            armed: vehicle.armed,
            flightTime: connection.connectedSince != null
                ? DateTime.now().difference(connection.connectedSince!)
                : Duration.zero,
            messageRate: connection.messageRate,
            gpsFixType: gpsLabel,
            satellites: vehicle.satellites,
            currentWaypoint: vehicle.currentWaypoint,
            totalWaypoints: missionState.waypointCount,
          ),
        ],
      ),
    );
  }
}
