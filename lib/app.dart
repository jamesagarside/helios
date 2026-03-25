import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'shared/models/vehicle_state.dart';
import 'shared/providers/providers.dart';
import 'shared/theme/helios_theme.dart';
import 'shared/widgets/responsive_scaffold.dart';
import 'shared/widgets/status_bar.dart';
import 'features/fly/fly_view.dart';
import 'features/plan/plan_view.dart';
import 'features/analyse/analyse_view.dart';
import 'features/setup/setup_view.dart';

/// Helios GCS application root widget.
class HeliosApp extends StatelessWidget {
  const HeliosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Helios GCS',
      debugShowCheckedModeBanner: false,
      theme: heliosTheme(),
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

  static const _views = <Widget>[
    FlyView(),
    PlanView(),
    AnalyseView(),
    SetupView(),
  ];

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

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: _handleKeyPress,
      child: Column(
        children: [
          Expanded(
            child: ResponsiveScaffold(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) => setState(() => _selectedIndex = i),
              body: IndexedStack(
                index: _selectedIndex,
                children: _views,
              ),
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
          ),
        ],
      ),
    );
  }
}
