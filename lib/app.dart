import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'shared/models/vehicle_state.dart';
import 'shared/providers/display_provider.dart';
import 'shared/providers/providers.dart';
import 'shared/providers/theme_mode_provider.dart';
import 'shared/theme/helios_colors.dart';
import 'shared/theme/helios_theme.dart';
import 'shared/widgets/quick_connection_bar.dart';
import 'shared/widgets/responsive_scaffold.dart';
import 'shared/widgets/splash_screen.dart';
import 'shared/widgets/status_bar.dart';
import 'features/fly/fly_view.dart';
import 'features/plan/plan_view.dart';
import 'features/analyse/analyse_view.dart';
import 'features/video/video_view.dart';
import 'features/setup/setup_view.dart';
import 'features/config/fc_config_view.dart';
import 'features/inspect/inspect_view.dart';

/// Helios GCS application root widget.
class HeliosApp extends ConsumerWidget {
  const HeliosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(displayScaleProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Helios GCS',
      debugShowCheckedModeBanner: false,
      theme: heliosLightTheme(),
      darkTheme: heliosTheme(),
      themeMode: themeMode,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        );
      },
      home: const _AppEntry(),
    );
  }
}

/// Shows the splash screen on first launch, then hands off to [_HeliosShell].
class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    if (_splashDone) return const _HeliosShell();

    return SplashScreen(
      onComplete: () => setState(() => _splashDone = true),
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
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
    // Start serial port monitoring for auto-connect
    Future(() => ref.read(serialPortMonitorProvider));
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

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
    // On web: Video tab is hidden, so indices shift down by 1.
    // Native: Fly(0) Plan(1) Data(2) Video(3) Config(4) Inspect(5) Setup(6)
    // Web:    Fly(0) Plan(1) Data(2)          Config(3) Inspect(4) Setup(5)
    if (kIsWeb) {
      return switch (_selectedIndex) {
        3 => const FcConfigView(),
        4 => const InspectView(),
        5 => const SetupView(),
        _ => const SizedBox(),
      };
    }
    return switch (_selectedIndex) {
      3 => const VideoView(),
      4 => const FcConfigView(),
      5 => const InspectView(),
      6 => const SetupView(),
      _ => const SizedBox(),
    };
  }

  void _handleKeyPress(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    // Don't capture shortcuts when a text field has focus
    final focusNode = FocusManager.instance.primaryFocus;
    if (focusNode != null && focusNode.context != null) {
      bool isTextField = false;
      focusNode.context!.visitAncestorElements((element) {
        if (element.widget is EditableText || element.widget is TextField) {
          isTextField = true;
          return false; // stop walking
        }
        return true;
      });
      if (isTextField || focusNode.context!.widget is EditableText) return;
    }

    final index = switch (event.logicalKey) {
      LogicalKeyboardKey.digit1 => 0,
      LogicalKeyboardKey.digit2 => 1,
      LogicalKeyboardKey.digit3 => 2,
      LogicalKeyboardKey.digit4 => 3,
      LogicalKeyboardKey.digit5 => 4,
      LogicalKeyboardKey.digit6 when !kIsWeb => 5,
      LogicalKeyboardKey.digit7 when !kIsWeb => 6,
      _ => null,
    };

    if (index != null && index != _selectedIndex) {
      setState(() => _selectedIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final connection = ref.watch(connectionStatusProvider);
    final gpsLabel = ref.watch(gpsFixLabelProvider);
    final missionState = ref.watch(missionStateProvider);

    final maintenanceAlerts = ref.watch(maintenanceAlertsProvider);
    final vehicleCount = ref.watch(vehicleCountProvider);
    final activeId = ref.watch(activeVehicleIdProvider);
    final registry = ref.watch(vehicleRegistryProvider);

    final body = KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyPress,
      child: Column(
        children: [
          // Vehicle selector (only shown with 2+ vehicles)
          if (vehicleCount > 1)
            Container(
              height: 32,
              color: hc.surfaceDim,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.multiple_stop,
                      size: 14, color: hc.textTertiary),
                  const SizedBox(width: 6),
                  Text('$vehicleCount vehicles',
                      style: TextStyle(
                          fontSize: 12, color: hc.textTertiary)),
                  const SizedBox(width: 12),
                  ...registry.entries.map((entry) {
                    final isActive = entry.key == activeId;
                    final v = entry.value;
                    final label = v.vehicleType != VehicleType.unknown
                        ? 'V${entry.key} (${v.vehicleType.name})'
                        : 'Vehicle ${entry.key}';
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => ref
                            .read(activeVehicleIdProvider.notifier)
                            .state = entry.key,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isActive
                                ? hc.accent.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isActive
                                  ? hc.accent
                                  : hc.border,
                            ),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isActive
                                  ? hc.accent
                                  : hc.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          Expanded(
            child: ResponsiveScaffold(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) => setState(() => _selectedIndex = i),
              body: _buildBody(),
              header: const QuickConnectionBar(),
              footer: StatusBar(
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
                alertCount: maintenanceAlerts.valueOrNull?.length ?? 0,
                batteryVoltage: vehicle.batteryVoltage,
                batteryRemaining: vehicle.batteryRemaining,
                homeDistance: vehicle.distanceToHome,
                hasHome: vehicle.hasHome,
              ),
            ),
          ),
        ],
      ),
    );

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return body;

    // macOS menu bar: live flight status in the system menu bar.
    // Labels update each time the widget rebuilds (state change).
    final connStr = connection.linkState == LinkState.connected
        ? 'Connected'
        : connection.linkState == LinkState.degraded
            ? 'Link Degraded'
            : 'Disconnected';
    final battStr = vehicle.batteryRemaining >= 0
        ? 'Battery: ${vehicle.batteryRemaining}%  ${vehicle.batteryVoltage.toStringAsFixed(1)} V'
        : 'Battery: —';
    final altStr = vehicle.altitudeRel > 0
        ? 'Altitude: ${vehicle.altitudeRel.toStringAsFixed(1)} m AGL'
        : 'Altitude: —';
    final modeStr = 'Mode: ${vehicle.flightMode.name}${vehicle.armed ? "  ●ARMED" : ""}';

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'Helios',
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(label: connStr),
                PlatformMenuItem(label: modeStr),
                PlatformMenuItem(label: battStr),
                PlatformMenuItem(label: altStr),
              ],
            ),
          ],
        ),
      ],
      child: body,
    );
  }
}
