import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/vehicle_state.dart';
import '../../shared/providers/providers.dart';
import 'widgets/chart_toolbar.dart';
import 'widgets/live_chart_widget.dart';
import 'widgets/vehicle_map.dart';
import '../../shared/theme/helios_colors.dart';
import '../../shared/theme/helios_typography.dart';
import '../../shared/widgets/connection_badge.dart';

/// Fly View — primary in-flight screen with live telemetry.
class FlyView extends ConsumerWidget {
  const FlyView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

class _DesktopFlyLayout extends ConsumerStatefulWidget {
  const _DesktopFlyLayout();

  @override
  ConsumerState<_DesktopFlyLayout> createState() => _DesktopFlyLayoutState();
}

class _DesktopFlyLayoutState extends ConsumerState<_DesktopFlyLayout> {
  final Set<ChartType> _activeCharts = {};
  final Map<ChartType, Offset> _chartPositions = {};

  // Default positions for each chart type
  Offset _defaultPosition(ChartType type) {
    const startX = 350.0;
    const startY = 12.0;
    const spacing = 160.0;
    final index = ChartType.values.indexOf(type);
    return Offset(startX, startY + index * spacing);
  }

  LiveChartConfig _buildConfig(ChartType type, VehicleState vehicle) {
    return switch (type) {
      ChartType.altitude => LiveChartConfig(
        title: 'Altitude',
        icon: Icons.height,
        unit: 'm',
        series: [
          LiveSeries(name: 'REL', color: HeliosColors.accent, getValue: () => vehicle.altitudeRel),
        ],
      ),
      ChartType.speed => LiveChartConfig(
        title: 'Speed',
        icon: Icons.speed,
        unit: 'm/s',
        series: [
          LiveSeries(name: 'IAS', color: HeliosColors.accent, getValue: () => vehicle.airspeed),
          LiveSeries(name: 'GS', color: HeliosColors.success, getValue: () => vehicle.groundspeed),
        ],
      ),
      ChartType.battery => LiveChartConfig(
        title: 'Battery',
        icon: Icons.battery_full,
        unit: 'V',
        series: [
          LiveSeries(name: 'V', color: HeliosColors.warning, getValue: () => vehicle.batteryVoltage),
        ],
      ),
      ChartType.attitude => LiveChartConfig(
        title: 'Attitude',
        icon: Icons.rotate_right,
        unit: '\u00B0',
        series: [
          LiveSeries(name: 'Roll', color: HeliosColors.accent, getValue: () => vehicle.roll * 57.2958),
          LiveSeries(name: 'Pitch', color: HeliosColors.warning, getValue: () => vehicle.pitch * 57.2958),
        ],
      ),
      ChartType.climbRate => LiveChartConfig(
        title: 'Climb Rate',
        icon: Icons.trending_up,
        unit: 'm/s',
        series: [
          LiveSeries(name: 'VS', color: HeliosColors.success, getValue: () => vehicle.climbRate),
        ],
      ),
      ChartType.vibration => LiveChartConfig(
        title: 'Vibration',
        icon: Icons.vibration,
        unit: '',
        series: [
          // Vibration data comes through the vehicle state indirectly;
          // for now show climb rate variation as a proxy
          LiveSeries(name: 'Z', color: HeliosColors.danger, getValue: () => vehicle.climbRate.abs() * 5),
        ],
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final linkState = ref.watch(connectionStatusProvider).linkState;
    final vehicle = ref.watch(vehicleStateProvider);

    return Row(
      children: [
        Expanded(
          child: Stack(
            children: [
              const VehicleMap(),
              // PFD overlay — bottom-left
              Positioned(
                left: 16,
                bottom: 16,
                child: Container(
                  width: 320,
                  height: 240,
                  decoration: BoxDecoration(
                    color: HeliosColors.surfaceDim.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: HeliosColors.border),
                  ),
                  child: _PfdWidget(
                    roll: vehicle.roll,
                    pitch: vehicle.pitch,
                    heading: vehicle.heading,
                  ),
                ),
              ),
              // Connection badge — top-right
              Positioned(
                top: 12,
                right: 12,
                child: ConnectionBadge(linkState: linkState),
              ),
              // Chart toolbar — top-left
              Positioned(
                top: 12,
                left: 16,
                child: ChartToolbar(
                  activeCharts: _activeCharts,
                  onToggle: (type) {
                    setState(() {
                      if (_activeCharts.contains(type)) {
                        _activeCharts.remove(type);
                      } else {
                        _activeCharts.add(type);
                      }
                    });
                  },
                ),
              ),
              // Live chart widgets
              for (final type in _activeCharts)
                LiveChartWidget(
                  key: ValueKey(type),
                  config: _buildConfig(type, vehicle),
                  initialPosition: _chartPositions[type] ?? _defaultPosition(type),
                  onPositionChanged: (pos) => _chartPositions[type] = pos,
                  onClose: () => setState(() => _activeCharts.remove(type)),
                ),
            ],
          ),
        ),
        SizedBox(
          width: 220,
          child: _TelemetryStrip(vehicle: vehicle),
        ),
      ],
    );
  }
}

class _TabletFlyLayout extends ConsumerWidget {
  const _TabletFlyLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            ],
          ),
        ),
        const Divider(height: 1, color: HeliosColors.border),
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
              color: HeliosColors.surfaceDim.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: HeliosColors.border),
            ),
            child: _PfdWidget(
              roll: vehicle.roll,
              pitch: vehicle.pitch,
              heading: vehicle.heading,
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
            color: HeliosColors.surface.withValues(alpha: 0.9),
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
                  label: 'GPS',
                  value: '${vehicle.satellites} sats',
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
// PFD Widget — simple attitude indicator using CustomPainter
// ---------------------------------------------------------------------------

class _PfdWidget extends StatelessWidget {
  const _PfdWidget({
    required this.roll,
    required this.pitch,
    required this.heading,
  });

  final double roll;
  final double pitch;
  final int heading;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CustomPaint(
        painter: _PfdPainter(roll: roll, pitch: pitch, heading: heading),
        child: Container(),
      ),
    );
  }
}

class _PfdPainter extends CustomPainter {
  _PfdPainter({
    required this.roll,
    required this.pitch,
    required this.heading,
  });

  final double roll;
  final double pitch;
  final int heading;

  // Pre-allocated paints
  static final _skyPaint = Paint()..color = HeliosColors.sky;
  static final _groundPaint = Paint()..color = HeliosColors.ground;
  static final _horizonPaint = Paint()
    ..color = HeliosColors.horizon
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;
  static final _pitchLinePaint = Paint()
    ..color = HeliosColors.pitchLine
    ..strokeWidth = 1;
  static final _centerPaint = Paint()
    ..color = HeliosColors.warning
    ..strokeWidth = 2.5
    ..style = PaintingStyle.stroke;
  static final _headingBgPaint = Paint()
    ..color = HeliosColors.surfaceDim.withValues(alpha: 0.7);
  static final _headingTextStyle = TextStyle(
    color: HeliosColors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    fontFamily: 'monospace',
  );

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final pitchPixelsPerDeg = size.height / 60; // 60 degrees visible

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-roll);

    // Pitch offset
    final pitchOffset = pitch * (180 / math.pi) * pitchPixelsPerDeg;

    // Sky (upper half, shifted by pitch)
    canvas.drawRect(
      Rect.fromLTWH(-size.width, -size.height + pitchOffset, size.width * 2, size.height),
      _skyPaint,
    );

    // Ground (lower half, shifted by pitch)
    canvas.drawRect(
      Rect.fromLTWH(-size.width, pitchOffset, size.width * 2, size.height),
      _groundPaint,
    );

    // Horizon line
    canvas.drawLine(
      Offset(-size.width, pitchOffset),
      Offset(size.width, pitchOffset),
      _horizonPaint,
    );

    // Pitch ladder (every 10 degrees)
    for (var deg = -30; deg <= 30; deg += 10) {
      if (deg == 0) continue;
      final y = pitchOffset - deg * pitchPixelsPerDeg;
      final halfWidth = deg.abs() < 20 ? 30.0 : 20.0;
      canvas.drawLine(
        Offset(-halfWidth, y),
        Offset(halfWidth, y),
        _pitchLinePaint,
      );

      // Degree label
      final tp = TextPainter(
        text: TextSpan(
          text: '${deg.abs()}',
          style: TextStyle(color: HeliosColors.pitchLine, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(halfWidth + 4, y - tp.height / 2));
      tp.paint(canvas, Offset(-halfWidth - tp.width - 4, y - tp.height / 2));
    }

    canvas.restore();

    // Fixed aircraft symbol (W shape)
    final acPaint = Paint()
      ..color = HeliosColors.warning
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(cx - 40, cy)
      ..lineTo(cx - 15, cy)
      ..lineTo(cx, cy + 8)
      ..lineTo(cx + 15, cy)
      ..lineTo(cx + 40, cy);
    canvas.drawPath(path, acPaint);

    // Centre dot
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = HeliosColors.warning);

    // Roll indicator arc at top
    canvas.save();
    canvas.translate(cx, cy);
    final rollArcRadius = size.height * 0.38;
    final rollArcPaint = Paint()
      ..color = HeliosColors.textPrimary.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: rollArcRadius),
      -math.pi * 0.83, // start angle
      math.pi * 0.66,   // sweep
      false,
      rollArcPaint,
    );

    // Roll pointer (triangle at current roll)
    canvas.rotate(-roll);
    final pointerPath = Path()
      ..moveTo(0, -rollArcRadius - 6)
      ..lineTo(-5, -rollArcRadius + 2)
      ..lineTo(5, -rollArcRadius + 2)
      ..close();
    canvas.drawPath(pointerPath, Paint()..color = HeliosColors.warning);
    canvas.restore();

    // Heading readout at bottom
    final hdgRect = Rect.fromCenter(
      center: Offset(cx, size.height - 14),
      width: 60,
      height: 20,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(hdgRect, const Radius.circular(3)),
      _headingBgPaint,
    );
    final hdgTp = TextPainter(
      text: TextSpan(
        text: '${heading.toString().padLeft(3, '0')}\u00B0',
        style: _headingTextStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    hdgTp.paint(canvas, Offset(cx - hdgTp.width / 2, size.height - 14 - hdgTp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _PfdPainter oldDelegate) {
    return roll != oldDelegate.roll ||
        pitch != oldDelegate.pitch ||
        heading != oldDelegate.heading;
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
    return Container(
      color: HeliosColors.surface,
      child: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          _TelemetryCard(
            label: 'BATT',
            value: vehicle.batteryVoltage > 0
                ? '${vehicle.batteryVoltage.toStringAsFixed(1)}'
                : '--',
            unit: 'V',
            color: _batteryColor(vehicle.batteryVoltage),
          ),
          _TelemetryCard(
            label: 'BAT%',
            value: vehicle.batteryRemaining >= 0
                ? '${vehicle.batteryRemaining}'
                : '--',
            unit: '%',
            color: _batteryPctColor(vehicle.batteryRemaining),
          ),
          _TelemetryCard(
            label: 'GPS',
            value: _gpsFixLabel(vehicle.gpsFix),
            unit: '',
            color: _gpsColor(vehicle.gpsFix),
          ),
          _TelemetryCard(
            label: 'SATS',
            value: '${vehicle.satellites}',
            unit: '',
            color: vehicle.satellites >= 8
                ? HeliosColors.success
                : vehicle.satellites >= 5
                    ? HeliosColors.warning
                    : HeliosColors.danger,
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
                  ? HeliosColors.success
                  : vehicle.rssi > 50
                      ? HeliosColors.warning
                      : HeliosColors.danger,
            ),
        ],
      ),
    );
  }

  Color _batteryColor(double voltage) {
    if (voltage <= 0) return HeliosColors.textSecondary;
    if (voltage > 11.5) return HeliosColors.success;
    if (voltage > 10.5) return HeliosColors.warning;
    return HeliosColors.danger;
  }

  Color _batteryPctColor(int pct) {
    if (pct < 0) return HeliosColors.textSecondary;
    if (pct > 30) return HeliosColors.success;
    if (pct > 15) return HeliosColors.warning;
    return HeliosColors.danger;
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

  Color _gpsColor(GpsFix fix) {
    return switch (fix) {
      GpsFix.none || GpsFix.noFix => HeliosColors.danger,
      GpsFix.fix2d => HeliosColors.warning,
      GpsFix.fix3d || GpsFix.dgps || GpsFix.rtkFloat || GpsFix.rtkFixed => HeliosColors.success,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: HeliosColors.surfaceLight,
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
              color: color ?? HeliosColors.textPrimary,
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
        Text(label, style: HeliosTypography.caption.copyWith(fontSize: 9)),
        Text(value, style: HeliosTypography.telemetrySmall.copyWith(fontSize: 12)),
      ],
    );
  }
}

