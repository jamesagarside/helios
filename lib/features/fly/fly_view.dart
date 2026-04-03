import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/telemetry/replay_service.dart';
import '../../shared/models/layout_profile.dart';
import '../../shared/models/vehicle_state.dart';
import '../../shared/providers/layout_provider.dart';
import '../../shared/providers/providers.dart';
import 'widgets/chart_toolbar.dart';
import 'widgets/gimbal_control.dart';
import 'widgets/layout_toolbar.dart';
import 'widgets/live_chart_widget.dart';
import 'widgets/replay_controls.dart';
import 'widgets/vehicle_map.dart';
import 'widgets/video_stream_widget.dart';
import '../../shared/theme/helios_colors.dart';
import '../../shared/theme/helios_typography.dart';
import '../../shared/providers/connection_settings_provider.dart';
import '../../shared/widgets/connection_badge.dart';
import 'widgets/action_panel.dart';
import 'widgets/ekf_status_strip.dart';
import 'widgets/message_log.dart';
import 'widgets/rc_input_panel.dart';
import 'widgets/servo_output_panel.dart';
import 'widgets/telemetry_panel.dart';

/// Fly View — primary in-flight screen with live telemetry.
///
/// When [replayActiveProvider] is true, the [ReplayService] drives
/// [vehicleStateProvider] instead of live MAVLink.
class FlyView extends ConsumerStatefulWidget {
  const FlyView({super.key});

  @override
  ConsumerState<FlyView> createState() => _FlyViewState();
}

class _FlyViewState extends ConsumerState<FlyView> {
  @override
  void initState() {
    super.initState();
    // Wire replay service → vehicle state provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final replay = ref.read(replayServiceProvider);
      replay.onStateUpdate = (VehicleState s) {
        if (mounted) {
          ref.read(vehicleStateProvider.notifier).applyReplayState(s);
        }
      };
      replay.onReplayStateChanged = (ReplayState rs) {
        if (mounted) {
          ref.read(replayActiveProvider.notifier).state =
              rs == ReplayState.playing || rs == ReplayState.paused;
        }
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    return Column(
      children: [
        Expanded(
          child: width >= 1200
              ? const _DesktopFlyLayout()
              : width >= 768
                  ? const _TabletFlyLayout()
                  : const _MobileFlyLayout(),
        ),
      ],
    );
  }
}

class _DesktopFlyLayout extends ConsumerWidget {
  const _DesktopFlyLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linkState = ref.watch(connectionStatusProvider).linkState;
    final vehicle = ref.watch(vehicleStateProvider);
    final layout = ref.watch(activeLayoutProvider);
    final editMode = ref.watch(layoutEditModeProvider);
    final notifier = ref.read(layoutProvider.notifier);

    final activeCharts = layout.activeCharts;
    final showVideo = layout.video.visible;
    final showPfd = layout.pfd.visible;
    final showStrip = layout.telemetryStrip.visible;
    final showMessageLog = layout.showMessageLog;
    final showActionPanel = layout.showActionPanel;
    final showServoPanel = layout.showServoPanel;
    final showRcPanel = layout.showRcPanel;

    return Row(
      children: [
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const VehicleMap(),
              // Edit mode grid overlay
              if (editMode) const _GridOverlay(),
              // PFD overlay — draggable when edit mode is on
              if (showPfd)
                _DraggablePfd(
                  vehicle: vehicle,
                  layout: layout,
                  editMode: editMode,
                  notifier: notifier,
                ),
              // Wind estimation chip — bottom-left, above PFD + extras
              const Positioned(
                left: 16,
                bottom: 300,
                child: _WindWidget(),
              ),
              // Gimbal control — bottom-right
              const Positioned(
                right: 16,
                bottom: 16,
                child: GimbalControl(),
              ),
              // Waypoint ETA strip — top-centre, only when mission active
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: const _WaypointEtaStrip(),
                ),
              ),
              // Connection badge + quick reconnect — top-right
              Positioned(
                top: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _ConnectionControls(linkState: linkState),
                    const SizedBox(height: 4),
                    const EkfStatusStrip(),
                  ],
                ),
              ),
              // Toolbars — top-left
              Positioned(
                top: 12,
                left: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Layout profile toolbar
                    const LayoutToolbar(),
                    const SizedBox(height: 8),
                    // Chart toggles + compact widget menu
                    Row(
                      children: [
                        ChartToolbar(
                          activeCharts: activeCharts,
                          onToggle: (type) => notifier.toggleChart(type),
                        ),
                        const SizedBox(width: 6),
                        // Widgets popup menu — replaces the long row of toggles
                        _WidgetMenuButton(
                          showVideo: showVideo,
                          showMessageLog: showMessageLog,
                          showActionPanel: showActionPanel,
                          showServoPanel: showServoPanel,
                          showRcPanel: showRcPanel,
                          showPfd: showPfd,
                          showStrip: showStrip,
                          editMode: editMode,
                          notifier: notifier,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Live chart widgets
              for (final type in activeCharts)
                LiveChartWidget(
                  key: ValueKey(type),
                  chartType: type,
                  initialPosition: _chartPosition(layout, type),
                  initialWidth: layout.charts[type.name]?.width ?? 280,
                  initialHeight: layout.charts[type.name]?.height ?? 150,
                  onPositionChanged: (pos) =>
                      notifier.updateChartPosition(type, pos.dx, pos.dy),
                  onSizeChanged: (w, h) =>
                      notifier.updateChartSize(type, w, h),
                  onClose: () => notifier.toggleChart(type),
                ),
              // Video stream PiP
              if (showVideo)
                VideoStreamWidget(
                  initialPosition: Offset(layout.video.x, layout.video.y),
                  onPositionChanged: (pos) =>
                      notifier.updateVideoPosition(pos.dx, pos.dy),
                  onClose: () => notifier.toggleVideo(),
                ),
              // Action panel — bottom-center
              if (showActionPanel)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(child: const ActionPanel()),
                ),
              // Message log — bottom-right above gimbal
              if (showMessageLog)
                const Positioned(
                  right: 16,
                  bottom: 80,
                  child: MessageLog(),
                ),
              // Servo output panel — left side, below toolbar area
              if (showServoPanel)
                const Positioned(
                  left: 16,
                  top: 80,
                  child: ServoOutputPanel(),
                ),
              // RC input panel — left side, below servo panel (or top if servo hidden)
              if (showRcPanel)
                Positioned(
                  left: showServoPanel ? 284 : 16,
                  top: 80,
                  child: const RcInputPanel(),
                ),
              // Replay controls bar (bottom of stack — visible when replaying)
              if (ref.watch(replayActiveProvider))
                const ReplayControls(),
            ],
          ),
        ),
        if (showStrip)
          SizedBox(
            width: 220,
            child: const TelemetryPanel(),
          ),
      ],
    );
  }

  Offset _chartPosition(LayoutProfile layout, ChartType type) {
    final config = layout.charts[type.name];
    if (config != null) return Offset(config.x, config.y);
    // Fallback: tile in 2 columns so charts stay on-screen
    final activeTypes = layout.activeCharts.toList();
    final index = activeTypes.indexOf(type).clamp(0, 5);
    final col = index % 2;
    final row = index ~/ 2;
    return Offset(350.0 + col * 300, 50.0 + row * 170.0);
  }
}

/// Subtle grid overlay shown in edit mode.
class _GridOverlay extends StatelessWidget {
  const _GridOverlay();

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _GridPainter(accentColor: hc.accent),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.accentColor});
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accentColor.withValues(alpha: 0.06)
      ..strokeWidth = 0.5;

    for (var x = 0.0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => accentColor != old.accentColor;
}

/// Small toggle button for PFD/Strip visibility in edit mode.
/// Compact popup button that replaces the long row of widget toggles.
/// Shows a count of active panels and opens a popup menu to toggle each.
class _WidgetMenuButton extends StatelessWidget {
  const _WidgetMenuButton({
    required this.showVideo,
    required this.showMessageLog,
    required this.showActionPanel,
    required this.showServoPanel,
    required this.showRcPanel,
    required this.showPfd,
    required this.showStrip,
    required this.editMode,
    required this.notifier,
  });

  final bool showVideo;
  final bool showMessageLog;
  final bool showActionPanel;
  final bool showServoPanel;
  final bool showRcPanel;
  final bool showPfd;
  final bool showStrip;
  final bool editMode;
  final LayoutNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    // Count active widget panels
    final activeCount = [
      showVideo, showMessageLog, showActionPanel,
      showServoPanel, showRcPanel,
    ].where((v) => v).length;

    return PopupMenuButton<String>(
      tooltip: 'Toggle widgets',
      offset: const Offset(0, 32),
      color: hc.surfaceDim.withValues(alpha: 0.95),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: hc.border),
      ),
      onSelected: (value) {
        switch (value) {
          case 'VID': notifier.toggleVideo();
          case 'MSG': notifier.toggleMessageLog();
          case 'ACT': notifier.toggleActionPanel();
          case 'SRV': notifier.toggleServoPanel();
          case 'RC': notifier.toggleRcPanel();
          case 'PFD': notifier.togglePfd();
          case 'STRIP': notifier.toggleTelemetryStrip();
        }
      },
      itemBuilder: (_) => [
        _menuItem('VID', Icons.videocam, showVideo, hc),
        _menuItem('MSG', Icons.message_outlined, showMessageLog, hc),
        _menuItem('ACT', Icons.gamepad_outlined, showActionPanel, hc),
        _menuItem('SRV', Icons.settings_input_component, showServoPanel, hc),
        _menuItem('RC', Icons.radio, showRcPanel, hc),
        if (editMode) ...[
          const PopupMenuDivider(height: 8),
          _menuItem('PFD', Icons.speed, showPfd, hc),
          _menuItem('STRIP', Icons.view_column, showStrip, hc),
        ],
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: hc.surfaceDim.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: activeCount > 0
                ? hc.accent.withValues(alpha: 0.4)
                : hc.border.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.widgets_outlined, size: 13, color: hc.textSecondary),
            const SizedBox(width: 4),
            Text(
              '$activeCount',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: activeCount > 0 ? hc.accent : hc.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
      String value, IconData icon, bool active, HeliosColors hc) {
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_box : Icons.check_box_outline_blank,
            size: 16,
            color: active ? hc.accent : hc.textTertiary,
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 14, color: active ? hc.accent : hc.textSecondary),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? hc.accent : hc.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Draggable PFD wrapper — positioned from LayoutProfile, draggable in edit mode
// ---------------------------------------------------------------------------

class _DraggablePfd extends StatefulWidget {
  const _DraggablePfd({
    required this.vehicle,
    required this.layout,
    required this.editMode,
    required this.notifier,
  });

  final VehicleState vehicle;
  final LayoutProfile layout;
  final bool editMode;
  final LayoutNotifier notifier;

  @override
  State<_DraggablePfd> createState() => _DraggablePfdState();
}

class _DraggablePfdState extends State<_DraggablePfd> {
  late double _x;
  late double _y;
  late double _width;
  late double _height;
  bool _initialised = false;

  static const double _minWidth = 240;
  static const double _maxWidth = 500;
  static const double _minHeight = 180;
  static const double _maxHeight = 380;

  void _initPosition(BoxConstraints constraints) {
    if (_initialised) return;
    _initialised = true;
    final pfd = widget.layout.pfd;
    _width = (pfd.width ?? 320).clamp(_minWidth, _maxWidth);
    _height = (pfd.height ?? 240).clamp(_minHeight, _maxHeight);
    _x = pfd.x;
    // y == -1 means "bottom-left" default
    _y = pfd.y < 0
        ? constraints.maxHeight - _height - 16
        : pfd.y;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _initPosition(constraints);
        return Positioned(
          left: _x,
          top: _y,
          child: GestureDetector(
            onPanUpdate: widget.editMode
                ? (details) {
                    setState(() {
                      _x = (_x + details.delta.dx)
                          .clamp(0, constraints.maxWidth - _width);
                      _y = (_y + details.delta.dy)
                          .clamp(0, constraints.maxHeight - _height);
                    });
                  }
                : null,
            onPanEnd: widget.editMode
                ? (_) => widget.notifier.updatePfdPosition(_x, _y)
                : null,
            child: Stack(
              children: [
                SizedBox(
                  width: _width,
                  height: _height + 30, // extra space for readout chips
                  child: _PfdOverlay(
                    vehicle: widget.vehicle,
                    pfdExtras: widget.layout.pfdExtras,
                    editMode: widget.editMode,
                    onToggleExtra: (extra) =>
                        widget.notifier.togglePfdExtra(extra),
                    width: _width,
                    height: _height,
                  ),
                ),
                // Resize handle — bottom-right (only in edit mode)
                if (widget.editMode)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          _width = (_width + details.delta.dx)
                              .clamp(_minWidth, _maxWidth);
                          _height = (_height + details.delta.dy)
                              .clamp(_minHeight, _maxHeight);
                        });
                      },
                      onPanEnd: (_) =>
                          widget.notifier.updatePfdSize(_width, _height),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeDownRight,
                        child: Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.drag_handle,
                            size: 12,
                            color: context.hc.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// PFD Overlay — PFD + extra readouts + settings gear
// ---------------------------------------------------------------------------

class _PfdOverlay extends StatefulWidget {
  const _PfdOverlay({
    required this.vehicle,
    required this.pfdExtras,
    required this.editMode,
    required this.onToggleExtra,
    this.width = 320,
    this.height = 240,
  });

  final VehicleState vehicle;
  final Set<PfdExtra> pfdExtras;
  final bool editMode;
  final ValueChanged<PfdExtra> onToggleExtra;
  final double width;
  final double height;

  @override
  State<_PfdOverlay> createState() => _PfdOverlayState();
}

class _PfdOverlayState extends State<_PfdOverlay> {
  bool _showSettings = false;

  String _extraValue(PfdExtra extra) {
    final v = widget.vehicle;
    switch (extra) {
      case PfdExtra.groundspeed:
        return '${v.groundspeed.toStringAsFixed(1)} m/s';
      case PfdExtra.battery:
        if (v.batteryRemaining >= 0) {
          return '${v.batteryVoltage.toStringAsFixed(1)}V ${v.batteryRemaining}%';
        }
        return v.batteryVoltage > 0
            ? '${v.batteryVoltage.toStringAsFixed(1)}V'
            : '--';
      case PfdExtra.throttle:
        return '${v.throttle}%';
      case PfdExtra.satellites:
        return '${v.satellites}';
      case PfdExtra.distance:
        if (!v.hasPosition || !v.hasHome) return '--';
        final d = _haversine(
          v.latitude, v.longitude, v.homeLatitude, v.homeLongitude,
        );
        return d >= 1000
            ? '${(d / 1000).toStringAsFixed(1)} km'
            : '${d.round()} m';
    }
  }

  static double _haversine(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.pow(math.sin(dLon / 2), 2) *
            math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180);
    return r * 2.0 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final extras = widget.pfdExtras.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // PFD + gear button
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: widget.width,
              height: widget.height,
              decoration: BoxDecoration(
                color: hc.surfaceDim.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.editMode
                      ? hc.accent.withValues(alpha: 0.3)
                      : hc.border,
                ),
              ),
              child: _PfdWidget(
                roll: widget.vehicle.roll,
                pitch: widget.vehicle.pitch,
                heading: widget.vehicle.heading,
                airspeed: widget.vehicle.airspeed,
                altitude: widget.vehicle.altitudeMsl,
                altitudeRel: widget.vehicle.altitudeRel,
                climbRate: widget.vehicle.climbRate,
              ),
            ),
            // Settings gear — top-right of PFD
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => setState(() => _showSettings = !_showSettings),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: hc.surfaceDim.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    Icons.tune,
                    size: 14,
                    color: _showSettings ? hc.accent : hc.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
        // Extra readout chips — below PFD
        if (extras.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: extras.map((extra) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: hc.surfaceDim.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color: hc.border.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        extra.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: hc.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _extraValue(extra),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: hc.textPrimary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        // Settings popup — toggle extras
        if (_showSettings)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: hc.surfaceDim.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: hc.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PFD READOUTS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: hc.textTertiary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: PfdExtra.values.map((extra) {
                      final active =
                          widget.pfdExtras.contains(extra);
                      return GestureDetector(
                        onTap: () => widget.onToggleExtra(extra),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: active
                                ? hc.accent.withValues(alpha: 0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: active
                                  ? hc.accent.withValues(alpha: 0.4)
                                  : hc.border.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            extra.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color:
                                  active ? hc.accent : hc.textTertiary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TabletFlyLayout extends ConsumerWidget {
  const _TabletFlyLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final linkState = ref.watch(connectionStatusProvider).linkState;
    final vehicle = ref.watch(vehicleStateProvider);

    return Column(
      children: [
        Expanded(
          flex: 6,
          child: Stack(
            children: [
              const VehicleMap(),
              Positioned(
                top: 12,
                right: 12,
                child: ConnectionBadge(linkState: linkState),
              ),
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Center(child: const _WaypointEtaStrip()),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: hc.border),
        Expanded(
          flex: 4,
          child: Row(
            children: [
              Container(
                width: 240,
                padding: const EdgeInsets.all(8),
                child: _PfdWidget(
                  roll: vehicle.roll,
                  pitch: vehicle.pitch,
                  heading: vehicle.heading,
                  airspeed: vehicle.airspeed,
                  altitude: vehicle.altitudeMsl,
                  altitudeRel: vehicle.altitudeRel,
                  climbRate: vehicle.climbRate,
                ),
              ),
              Expanded(child: _TelemetryStrip(vehicle: vehicle)),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileFlyLayout extends ConsumerWidget {
  const _MobileFlyLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final linkState = ref.watch(connectionStatusProvider).linkState;
    final vehicle = ref.watch(vehicleStateProvider);

    return Stack(
      children: [
        const VehicleMap(),
        Positioned(
          left: 8,
          top: 8,
          child: Container(
            width: 160,
            height: 120,
            decoration: BoxDecoration(
              color: hc.surfaceDim.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: hc.border),
            ),
            child: _PfdWidget(
              roll: vehicle.roll,
              pitch: vehicle.pitch,
              heading: vehicle.heading,
              airspeed: vehicle.airspeed,
              altitude: vehicle.altitudeMsl,
              altitudeRel: vehicle.altitudeRel,
              climbRate: vehicle.climbRate,
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: ConnectionBadge(linkState: linkState),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            height: 44,
            color: hc.surface.withValues(alpha: 0.9),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _MiniTelemetryItem(label: 'MODE', value: vehicle.flightMode.name),
                _MiniTelemetryItem(
                  label: 'BATT',
                  value: vehicle.batteryVoltage > 0
                      ? '${vehicle.batteryVoltage.toStringAsFixed(1)}V'
                      : '--V',
                ),
                _MiniTelemetryItem(
                  label: 'IAS',
                  value: '${vehicle.airspeed.toStringAsFixed(1)} m/s',
                ),
                _MiniTelemetryItem(
                  label: 'ALT',
                  value: '${vehicle.altitudeRel.toStringAsFixed(0)}m',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Waypoint ETA strip
// ---------------------------------------------------------------------------

/// Horizontal strip shown when an auto mission is active.
/// Displays current waypoint, total, distance, bearing, and ETA.
class _WaypointEtaStrip extends ConsumerWidget {
  const _WaypointEtaStrip();

  static double _haversine(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.pow(math.sin(dLon / 2), 2) *
            math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180);
    return r * 2.0 * math.asin(math.sqrt(a.clamp(0.0, 1.0)));
  }

  static double _bearing(
      double lat1, double lon1, double lat2, double lon2) {
    final dLon = (lon2 - lon1) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2 * math.pi / 180);
    final x = math.cos(lat1 * math.pi / 180) *
            math.sin(lat2 * math.pi / 180) -
        math.sin(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(vehicleStateProvider);
    final items = ref.watch(missionItemsProvider);
    final currentWp = vehicle.currentWaypoint;

    // Only show during active auto mission
    if (currentWp < 0 || items.isEmpty) return const SizedBox.shrink();

    final navItems = items.where((i) => i.isNavCommand).toList();
    if (navItems.isEmpty) return const SizedBox.shrink();

    // Find the current and next target waypoint
    final wpIdx = navItems.indexWhere((i) => i.seq == currentWp);
    final target = wpIdx >= 0 ? navItems[wpIdx] : navItems.last;
    final total = navItems.length;
    final displayed = wpIdx >= 0 ? wpIdx + 1 : total;

    // Distance + bearing + ETA
    double? distM;
    double? etaSec;
    double? bearing;
    if (vehicle.hasPosition) {
      distM = _haversine(
        vehicle.latitude, vehicle.longitude,
        target.latitude, target.longitude,
      );
      bearing = _bearing(
        vehicle.latitude, vehicle.longitude,
        target.latitude, target.longitude,
      );
      if (vehicle.groundspeed > 0.5) {
        etaSec = distM / vehicle.groundspeed;
      }
    }

    final hc = context.hc;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: hc.surfaceDim.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.route, size: 13, color: hc.warning),
          const SizedBox(width: 6),
          Text(
            'WP $displayed/$total',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: hc.warning,
            ),
          ),
          if (distM != null) ...[
            const SizedBox(width: 10),
            _EtaChip(
              label: distM >= 1000
                  ? '${(distM / 1000).toStringAsFixed(2)} km'
                  : '${distM.round()} m',
              hc: hc,
            ),
          ],
          if (bearing != null) ...[
            const SizedBox(width: 8),
            _EtaChip(label: '${bearing.round()}°', hc: hc),
          ],
          if (etaSec != null) ...[
            const SizedBox(width: 8),
            _EtaChip(
              label: etaSec < 60
                  ? 'ETA ${etaSec.round()}s'
                  : 'ETA ${(etaSec / 60).ceil()}min',
              hc: hc,
              accent: true,
            ),
          ],
          // Compact progress dots
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(total.clamp(0, 8), (i) {
              final done = i < displayed - 1;
              final curr = i == displayed - 1;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Container(
                  width: curr ? 8 : 5,
                  height: curr ? 8 : 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done
                        ? hc.success.withValues(alpha: 0.7)
                        : curr
                            ? hc.warning
                            : hc.textTertiary.withValues(alpha: 0.4),
                  ),
                ),
              );
            }),
          ),
          if (total > 8) ...[
            const SizedBox(width: 4),
            Text(
              '+${total - 8}',
              style: TextStyle(fontSize: 10, color: hc.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _EtaChip extends StatelessWidget {
  const _EtaChip({required this.label, required this.hc, this.accent = false});
  final String label;
  final HeliosColors hc;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: accent ? hc.accent : hc.textPrimary,
        fontFamily: 'monospace',
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wind estimation chip
// ---------------------------------------------------------------------------

/// Overlay chip showing estimated or measured wind speed and direction.
///
/// Uses the WIND message (msg_id=168) when available. Falls back to the
/// headwind/tailwind scalar derived from airspeed minus groundspeed.
/// Only visible when connected and speed data is present.
class _WindWidget extends ConsumerWidget {
  const _WindWidget();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(vehicleStateProvider);
    final hc = context.hc;

    final hasSpeedData = vehicle.airspeed > 0 || vehicle.groundspeed > 0;
    final showWind = vehicle.hasWind || hasSpeedData;

    if (!showWind) return const SizedBox.shrink();

    // Prefer direct WIND message data; fall back to scalar estimate
    final double displaySpeed;
    final double? arrowDirection;
    final bool isEstimate;

    if (vehicle.hasWind) {
      displaySpeed = vehicle.windSpeed;
      arrowDirection = vehicle.windDirection;
      isEstimate = false;
    } else {
      // Headwind = airspeed - groundspeed (positive = headwind, negative = tailwind)
      displaySpeed = (vehicle.airspeed - vehicle.groundspeed).abs();
      arrowDirection = null;
      isEstimate = true;
    }

    // Choose colour based on wind type and magnitude
    final Color chipColor;
    if (vehicle.hasWind) {
      if (displaySpeed > 5.0) {
        chipColor = hc.warning; // amber for strong headwind/notable wind
      } else {
        chipColor = hc.textPrimary; // white/neutral for light wind
      }
    } else {
      final headwind = vehicle.airspeed - vehicle.groundspeed;
      if (headwind > 5.0) {
        chipColor = hc.warning; // amber for strong headwind
      } else if (headwind < -1.0) {
        chipColor = hc.success; // green for tailwind
      } else {
        chipColor = hc.textPrimary;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: hc.surfaceDim.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: chipColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Rotated arrow if we have a direction, otherwise static icon
          if (arrowDirection != null)
            Transform.rotate(
              angle: arrowDirection * math.pi / 180.0,
              child: Icon(Icons.navigation, size: 13, color: chipColor),
            )
          else
            Icon(Icons.air, size: 13, color: chipColor),
          const SizedBox(width: 5),
          Text(
            '${displaySpeed.toStringAsFixed(1)} m/s',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: chipColor,
              fontFamily: 'monospace',
            ),
          ),
          if (isEstimate) ...[
            const SizedBox(width: 4),
            Text(
              vehicle.airspeed - vehicle.groundspeed >= 0 ? 'HW' : 'TW',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: chipColor.withValues(alpha: 0.7),
              ),
            ),
          ],
          if (!isEstimate && vehicle.windDirection > 0) ...[
            const SizedBox(width: 4),
            Text(
              '${vehicle.windDirection.round()}°',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: chipColor.withValues(alpha: 0.7),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Connection controls — badge + quick reconnect
// ---------------------------------------------------------------------------

class _ConnectionControls extends ConsumerWidget {
  const _ConnectionControls({required this.linkState});
  final LinkState linkState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final connection = ref.watch(connectionStatusProvider);
    final savedConfig = ref.watch(connectionSettingsProvider);
    final isConnected =
        connection.transportState == TransportState.connected;
    final isConnecting =
        connection.transportState == TransportState.connecting;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Quick reconnect / disconnect button
        if (!isConnected && savedConfig != null && !isConnecting)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Material(
              color: hc.surface.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => ref
                    .read(connectionControllerProvider.notifier)
                    .connect(savedConfig),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link, size: 13, color: hc.accent),
                      const SizedBox(width: 4),
                      Text(
                        ref.read(connectionSettingsProvider.notifier).label,
                        style: TextStyle(
                          color: hc.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (isConnecting)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: hc.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: hc.accent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Connecting...',
                    style: TextStyle(
                      color: hc.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ConnectionBadge(linkState: linkState),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// PFD Widget — compound glass cockpit instrument
// ---------------------------------------------------------------------------

/// Compound PFD with speed tape (left), attitude indicator (centre),
/// altitude tape (right), and heading readout (bottom).
///
/// Uses a Ticker to lerp values at 60fps for glass-smooth motion.
class _PfdWidget extends StatefulWidget {
  const _PfdWidget({
    required this.roll,
    required this.pitch,
    required this.heading,
    this.airspeed = 0.0,
    this.altitude = 0.0,
    this.altitudeRel = 0.0,
    this.climbRate = 0.0,
  });

  final double roll;
  final double pitch;
  final int heading;
  final double airspeed;
  final double altitude;
  final double altitudeRel;
  final double climbRate;

  @override
  State<_PfdWidget> createState() => _PfdWidgetState();
}

class _PfdWidgetState extends State<_PfdWidget>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  bool _tickerActive = false;

  double _roll = 0, _pitch = 0, _heading = 0;
  double _speed = 0, _alt = 0, _altRel = 0, _vs = 0;

  // Fast tracking — 0.7 = ~3 frames to settle at 60fps (~50ms)
  static const double _k = 0.7;
  static const double _eps = 0.001;

  @override
  void initState() {
    super.initState();
    _roll = widget.roll;
    _pitch = widget.pitch;
    _heading = widget.heading.toDouble();
    _speed = widget.airspeed;
    _alt = widget.altitude;
    _altRel = widget.altitudeRel;
    _vs = widget.climbRate;
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(covariant _PfdWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.roll != oldWidget.roll ||
        widget.pitch != oldWidget.pitch ||
        widget.heading != oldWidget.heading ||
        widget.airspeed != oldWidget.airspeed ||
        widget.altitude != oldWidget.altitude) {
      if (!_tickerActive) {
        _ticker.start();
        _tickerActive = true;
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double _lerp(double current, double target) =>
      current + (target - current) * _k;

  void _onTick(Duration elapsed) {
    _roll = _lerp(_roll, widget.roll);
    _pitch = _lerp(_pitch, widget.pitch);
    _speed = _lerp(_speed, widget.airspeed);
    _alt = _lerp(_alt, widget.altitude);
    _altRel = _lerp(_altRel, widget.altitudeRel);
    _vs = _lerp(_vs, widget.climbRate);

    // Heading — shortest path
    final targetH = widget.heading.toDouble();
    var dh = targetH - _heading;
    if (dh > 180) dh -= 360;
    if (dh < -180) dh += 360;
    _heading += dh * _k;
    if (_heading < 0) _heading += 360;
    if (_heading >= 360) _heading -= 360;

    // Stop when converged
    final converged = (widget.roll - _roll).abs() < _eps &&
        (widget.pitch - _pitch).abs() < _eps &&
        dh.abs() < _eps &&
        (widget.airspeed - _speed).abs() < 0.01 &&
        (widget.altitude - _alt).abs() < 0.01;

    if (converged) {
      _roll = widget.roll;
      _pitch = widget.pitch;
      _heading = targetH;
      _speed = widget.airspeed;
      _alt = widget.altitude;
      _altRel = widget.altitudeRel;
      _vs = widget.climbRate;
      _ticker.stop();
      _tickerActive = false;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CustomPaint(
        painter: _PfdPainter(
          roll: _roll,
          pitch: _pitch,
          heading: _heading.round(),
          airspeed: _speed,
          altitude: _alt,
          altitudeRel: _altRel,
          climbRate: _vs,
          colors: context.hc,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _PfdPainter extends CustomPainter {
  _PfdPainter({
    required this.roll,
    required this.pitch,
    required this.heading,
    required this.airspeed,
    required this.altitude,
    required this.altitudeRel,
    required this.climbRate,
    required this.colors,
  });

  final double roll, pitch, airspeed, altitude, altitudeRel, climbRate;
  final int heading;
  final HeliosColors colors;

  // Layout constants — tape widths
  static const double _tapeWidth = 48.0;

  // Instance paints (theme-dependent)
  Paint get _skyPaint => Paint()..color = colors.sky;
  Paint get _groundPaint => Paint()..color = colors.ground;
  Paint get _horizonPaint => Paint()
    ..color = colors.horizon
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;
  Paint get _tapeBgPaint => Paint()
    ..color = colors.surfaceDim.withValues(alpha: 0.75);
  Paint get _tapeLinePaint => Paint()
    ..color = colors.textTertiary
    ..strokeWidth = 0.5;
  Paint get _readoutBgPaint => Paint()
    ..color = colors.surfaceDim.withValues(alpha: 0.9);
  Paint get _readoutBorderPaint => Paint()
    ..color = colors.textPrimary
    ..strokeWidth = 1.5
    ..style = PaintingStyle.stroke;

  TextStyle get _tapeTextStyle => TextStyle(
    color: colors.textSecondary,
    fontSize: 12,
    fontFamily: 'monospace',
  );
  TextStyle get _readoutTextStyle => TextStyle(
    color: colors.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    fontFamily: 'monospace',
  );
  TextStyle get _labelTextStyle => TextStyle(
    color: colors.textTertiary,
    fontSize: 8,
    fontFamily: 'monospace',
  );

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Regions
    final attitudeRect = Rect.fromLTWH(_tapeWidth, 0, w - _tapeWidth * 2, h);
    final speedTapeRect = Rect.fromLTWH(0, 0, _tapeWidth, h);
    final altTapeRect = Rect.fromLTWH(w - _tapeWidth, 0, _tapeWidth, h);

    // --- Attitude indicator (centre) ---
    canvas.save();
    canvas.clipRect(attitudeRect);

    final cx = attitudeRect.center.dx;
    final cy = attitudeRect.center.dy;
    final pitchPpd = h / 60;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-roll);

    final po = pitch * (180 / math.pi) * pitchPpd;

    canvas.drawRect(Rect.fromLTWH(-w, -h + po, w * 2, h), _skyPaint);
    canvas.drawRect(Rect.fromLTWH(-w, po, w * 2, h), _groundPaint);
    canvas.drawLine(Offset(-w, po), Offset(w, po), _horizonPaint);

    // Pitch ladder — 5° and 10° lines
    for (var deg = -30; deg <= 30; deg += 5) {
      if (deg == 0) continue;
      final y = po - deg * pitchPpd;
      final major = deg % 10 == 0;
      final hw = major ? 28.0 : 14.0;
      final paint = Paint()
        ..color = colors.pitchLine
        ..strokeWidth = major ? 1.0 : 0.5;
      canvas.drawLine(Offset(-hw, y), Offset(hw, y), paint);

      if (major) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${deg.abs()}',
            style: TextStyle(color: colors.pitchLine, fontSize: 8),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(hw + 3, y - tp.height / 2));
        tp.paint(canvas, Offset(-hw - tp.width - 3, y - tp.height / 2));
      }
    }

    canvas.restore();

    // Aircraft symbol
    final acPaint = Paint()
      ..color = colors.warning
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(cx - 35, cy)
        ..lineTo(cx - 12, cy)
        ..lineTo(cx, cy + 7)
        ..lineTo(cx + 12, cy)
        ..lineTo(cx + 35, cy),
      acPaint,
    );
    canvas.drawCircle(Offset(cx, cy), 2.5, Paint()..color = colors.warning);

    // Roll arc + pointer
    canvas.save();
    canvas.translate(cx, cy);
    final rr = h * 0.36;
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: rr),
      -math.pi * 0.83,
      math.pi * 0.66,
      false,
      Paint()
        ..color = colors.textPrimary.withValues(alpha: 0.4)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );

    // Bank angle tick marks (10° increments)
    for (final deg in [-30, -20, -10, 0, 10, 20, 30]) {
      final a = (-90 + deg) * math.pi / 180;
      final inner = rr - (deg == 0 ? 8 : 5);
      canvas.drawLine(
        Offset(math.cos(a) * inner, math.sin(a) * inner),
        Offset(math.cos(a) * rr, math.sin(a) * rr),
        Paint()
          ..color = colors.textPrimary.withValues(alpha: 0.5)
          ..strokeWidth = deg == 0 ? 1.5 : 0.8,
      );
    }

    canvas.rotate(-roll);
    canvas.drawPath(
      Path()
        ..moveTo(0, -rr - 5)
        ..lineTo(-4, -rr + 3)
        ..lineTo(4, -rr + 3)
        ..close(),
      Paint()..color = colors.warning,
    );
    canvas.restore();

    // Heading readout
    final hdgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, h - 12), width: 52, height: 18),
      const Radius.circular(3),
    );
    canvas.drawRRect(hdgRect, _readoutBgPaint);
    canvas.drawRRect(hdgRect, Paint()
      ..color = colors.border
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke);
    _drawText(canvas, '${heading.toString().padLeft(3, '0')}\u00B0',
        _readoutTextStyle.copyWith(fontSize: 12), Offset(cx, h - 12));

    canvas.restore(); // attitude clip

    // --- Speed tape (left) ---
    canvas.save();
    canvas.clipRect(speedTapeRect);
    canvas.drawRect(speedTapeRect, _tapeBgPaint);
    _drawTape(canvas, speedTapeRect, airspeed, step: 5, majorEvery: 2);

    // Speed readout box
    _drawReadoutBox(canvas, speedTapeRect.center, '${airspeed.toStringAsFixed(0)}');

    // "IAS" label
    _drawText(canvas, 'IAS', _labelTextStyle,
        Offset(speedTapeRect.center.dx, 10));
    canvas.restore();

    // --- Altitude tape (right) ---
    canvas.save();
    canvas.clipRect(altTapeRect);
    canvas.drawRect(altTapeRect, _tapeBgPaint);
    _drawTape(canvas, altTapeRect, altitude, step: 10, majorEvery: 2, alignRight: true);

    // Alt readout box
    _drawReadoutBox(canvas, altTapeRect.center, '${altitude.toStringAsFixed(0)}');

    // REL alt below readout
    _drawText(canvas, 'R ${altitudeRel.toStringAsFixed(0)}m',
        _labelTextStyle.copyWith(color: colors.accent, fontSize: 12),
        Offset(altTapeRect.center.dx, altTapeRect.center.dy + 16));

    // VS arrow
    if (climbRate.abs() > 0.3) {
      final vsY = altTapeRect.center.dy + 30;
      final arrow = climbRate > 0 ? '\u25B2' : '\u25BC';
      final vsColor = climbRate > 0 ? colors.success : colors.warning;
      _drawText(canvas, '$arrow${climbRate.abs().toStringAsFixed(1)}',
          _labelTextStyle.copyWith(color: vsColor, fontSize: 12),
          Offset(altTapeRect.center.dx, vsY));
    }

    // "ALT" label
    _drawText(canvas, 'ALT', _labelTextStyle,
        Offset(altTapeRect.center.dx, 10));
    canvas.restore();
  }

  void _drawTape(Canvas canvas, Rect rect, double value, {
    required int step,
    int majorEvery = 2,
    bool alignRight = false,
  }) {
    final pixelsPerUnit = rect.height / 12; // Show ~12 steps visible
    final cy = rect.center.dy;

    // Range of values visible on tape
    final minVal = value - 6 * step;
    final maxVal = value + 6 * step;
    final firstTick = (minVal / step).floor() * step;

    for (var v = firstTick; v <= maxVal; v += step) {
      final y = cy - (v - value) * pixelsPerUnit / step;
      if (y < rect.top - 10 || y > rect.bottom + 10) continue;

      final tickIndex = (v / step).round();
      final isMajor = tickIndex % majorEvery == 0;
      final tickLen = isMajor ? 8.0 : 4.0;

      if (alignRight) {
        canvas.drawLine(
          Offset(rect.left, y),
          Offset(rect.left + tickLen, y),
          _tapeLinePaint,
        );
      } else {
        canvas.drawLine(
          Offset(rect.right - tickLen, y),
          Offset(rect.right, y),
          _tapeLinePaint,
        );
      }

      if (isMajor && v >= 0) {
        final tp = TextPainter(
          text: TextSpan(text: '${v.round()}', style: _tapeTextStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final x = alignRight
            ? rect.left + tickLen + 3
            : rect.right - tickLen - tp.width - 3;
        tp.paint(canvas, Offset(x, y - tp.height / 2));
      }
    }
  }

  void _drawReadoutBox(Canvas canvas, Offset center, String text) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 42, height: 20),
      const Radius.circular(3),
    );
    canvas.drawRRect(rrect, _readoutBgPaint);
    canvas.drawRRect(rrect, _readoutBorderPaint);
    _drawText(canvas, text, _readoutTextStyle, center);
  }

  void _drawText(Canvas canvas, String text, TextStyle style, Offset center) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _PfdPainter old) {
    return roll != old.roll || pitch != old.pitch || heading != old.heading ||
        airspeed != old.airspeed || altitude != old.altitude ||
        altitudeRel != old.altitudeRel || climbRate != old.climbRate ||
        colors != old.colors;
  }
}

// ---------------------------------------------------------------------------
// Telemetry Strip — live data cards
// ---------------------------------------------------------------------------

class _TelemetryStrip extends StatelessWidget {
  const _TelemetryStrip({required this.vehicle});

  final VehicleState vehicle;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      color: hc.surface,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _TelemetryCard(
            label: 'BATT',
            value: vehicle.batteryVoltage > 0
                ? '${vehicle.batteryVoltage.toStringAsFixed(1)}'
                : '--',
            unit: 'V',
            color: _batteryColor(vehicle.batteryVoltage, hc),
          ),
          _TelemetryCard(
            label: 'BAT%',
            value: vehicle.batteryRemaining >= 0
                ? '${vehicle.batteryRemaining}'
                : '--',
            unit: '%',
            color: _batteryPctColor(vehicle.batteryRemaining, hc),
          ),
          _TelemetryCard(
            label: 'GPS',
            value: _gpsFixLabel(vehicle.gpsFix),
            unit: '',
            color: _gpsColor(vehicle.gpsFix, hc),
          ),
          _TelemetryCard(
            label: 'SATS',
            value: '${vehicle.satellites}',
            unit: '',
            color: vehicle.satellites >= 8
                ? hc.success
                : vehicle.satellites >= 5
                    ? hc.warning
                    : hc.danger,
          ),
          _TelemetryCard(
            label: 'HDOP',
            value: vehicle.hdop < 50
                ? vehicle.hdop.toStringAsFixed(1)
                : '--',
            unit: '',
          ),
          _TelemetryCard(
            label: 'IAS',
            value: vehicle.airspeed.toStringAsFixed(1),
            unit: 'm/s',
          ),
          _TelemetryCard(
            label: 'GS',
            value: vehicle.groundspeed.toStringAsFixed(1),
            unit: 'm/s',
          ),
          _TelemetryCard(
            label: 'ALT',
            value: vehicle.altitudeRel.toStringAsFixed(1),
            unit: 'm',
          ),
          _TelemetryCard(
            label: 'MSL',
            value: vehicle.altitudeMsl.toStringAsFixed(0),
            unit: 'm',
          ),
          _TelemetryCard(
            label: 'VS',
            value: '${vehicle.climbRate >= 0 ? '+' : ''}${vehicle.climbRate.toStringAsFixed(1)}',
            unit: 'm/s',
          ),
          _TelemetryCard(
            label: 'HDG',
            value: '${vehicle.heading}',
            unit: '\u00B0',
          ),
          _TelemetryCard(
            label: 'THR',
            value: '${vehicle.throttle}',
            unit: '%',
          ),
          if (vehicle.rssi > 0)
            _TelemetryCard(
              label: 'RSSI',
              value: '${vehicle.rssi}',
              unit: '',
              color: vehicle.rssi > 150
                  ? hc.success
                  : vehicle.rssi > 50
                      ? hc.warning
                      : hc.danger,
            ),
        ],
      ),
    );
  }

  Color _batteryColor(double voltage, HeliosColors hc) {
    if (voltage <= 0) return hc.textSecondary;
    if (voltage > 11.5) return hc.success;
    if (voltage > 10.5) return hc.warning;
    return hc.danger;
  }

  Color _batteryPctColor(int pct, HeliosColors hc) {
    if (pct < 0) return hc.textSecondary;
    if (pct > 30) return hc.success;
    if (pct > 15) return hc.warning;
    return hc.danger;
  }

  String _gpsFixLabel(GpsFix fix) {
    return switch (fix) {
      GpsFix.none || GpsFix.noFix => 'No Fix',
      GpsFix.fix2d => '2D Fix',
      GpsFix.fix3d => '3D Fix',
      GpsFix.dgps => 'DGPS',
      GpsFix.rtkFloat => 'RTK Flt',
      GpsFix.rtkFixed => 'RTK Fix',
    };
  }

  Color _gpsColor(GpsFix fix, HeliosColors hc) {
    return switch (fix) {
      GpsFix.none || GpsFix.noFix => hc.danger,
      GpsFix.fix2d => hc.warning,
      GpsFix.fix3d || GpsFix.dgps || GpsFix.rtkFloat || GpsFix.rtkFixed => hc.success,
    };
  }
}

class _TelemetryCard extends StatelessWidget {
  const _TelemetryCard({
    required this.label,
    required this.value,
    required this.unit,
    this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: hc.surfaceLight,
        borderRadius: BorderRadius.circular(4),
        border: color != null
            ? Border(left: BorderSide(color: color!, width: 3))
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: HeliosTypography.caption),
          Text(
            '$value $unit'.trim(),
            style: HeliosTypography.telemetrySmall.copyWith(
              color: color ?? hc.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTelemetryItem extends StatelessWidget {
  const _MiniTelemetryItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: HeliosTypography.caption.copyWith(fontSize: 12)),
        Text(value, style: HeliosTypography.telemetrySmall.copyWith(fontSize: 12)),
      ],
    );
  }
}

