import 'dart:math' as math;

import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/mavlink/flight_modes.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';
import '../../../shared/widgets/notification_overlay.dart';

/// Extended flight commands panel that provides context-sensitive controls
/// for GUIDED and AUTO modes. Supplements the main ActionPanel.
class GuidedCommandsPanel extends ConsumerStatefulWidget {
  const GuidedCommandsPanel({super.key});

  @override
  ConsumerState<GuidedCommandsPanel> createState() =>
      _GuidedCommandsPanelState();
}

class _GuidedCommandsPanelState extends ConsumerState<GuidedCommandsPanel> {
  // Orbit parameters
  double _orbitRadius = 50;
  double _orbitSpeed = 3;
  bool _orbitCw = true;

  // Change altitude
  final _altController = TextEditingController(text: '30');

  // Change speed
  final _speedController = TextEditingController(text: '5');

  @override
  void dispose() {
    _altController.dispose();
    _speedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final connected = ref.watch(connectionStatusProvider).transportState ==
        TransportState.connected;

    final modeName = vehicle.flightMode.name.startsWith('MODE_')
        ? FlightModeRegistry.name(
            vehicle.vehicleType, vehicle.flightMode.number)
        : vehicle.flightMode.name;
    final isGuided = modeName.toUpperCase() == 'GUIDED';
    final isAuto = modeName.toUpperCase() == 'AUTO';

    if (!connected || !vehicle.armed || (!isGuided && !isAuto)) {
      return const SizedBox.shrink();
    }

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: hc.surfaceDim.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hc.border.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: hc.accent.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Text(
              isGuided ? 'GUIDED COMMANDS' : 'MISSION COMMANDS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: hc.accent,
                letterSpacing: 1.0,
              ),
            ),
          ),

          if (isGuided) ...[
            _buildGuidedSection(hc, vehicle, ref),
          ] else if (isAuto) ...[
            _buildAutoSection(hc, vehicle, ref),
          ],

          // ROI section (available in both modes)
          _buildRoiSection(hc, vehicle, ref),
        ],
      ),
    );
  }

  Widget _buildGuidedSection(
      HeliosColors hc, VehicleState vehicle, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Orbit ──
          _sectionLabel('Orbit', hc),
          const SizedBox(height: 4),
          _sliderRow(
            hc: hc,
            label: 'R',
            value: _orbitRadius,
            min: 10,
            max: 500,
            unit: 'm',
            onChanged: (v) => setState(() => _orbitRadius = v),
          ),
          _sliderRow(
            hc: hc,
            label: 'V',
            value: _orbitSpeed,
            min: 1,
            max: 10,
            unit: 'm/s',
            onChanged: (v) => setState(() => _orbitSpeed = v),
          ),
          Row(
            children: [
              _directionChip(hc, 'CW', _orbitCw, () {
                setState(() => _orbitCw = true);
              }),
              const SizedBox(width: 4),
              _directionChip(hc, 'CCW', !_orbitCw, () {
                setState(() => _orbitCw = false);
              }),
              const Spacer(),
              _miniButton(hc, 'ORBIT', hc.accent, () {
                _sendOrbit(ref, vehicle);
              }),
            ],
          ),
          const SizedBox(height: 8),

          // ── Change Altitude ──
          _sectionLabel('Change Altitude', hc),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _compactField(
                  hc: hc,
                  controller: _altController,
                  suffix: 'm',
                ),
              ),
              const SizedBox(width: 6),
              _miniButton(hc, 'GO', hc.accent, () {
                _sendChangeAlt(ref, vehicle);
              }),
            ],
          ),
          const SizedBox(height: 8),

          // ── Change Speed ──
          _sectionLabel('Change Speed', hc),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _compactField(
                  hc: hc,
                  controller: _speedController,
                  suffix: 'm/s',
                ),
              ),
              const SizedBox(width: 6),
              _miniButton(hc, 'APPLY', hc.accent, () {
                _sendChangeSpeed(ref);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAutoSection(
      HeliosColors hc, VehicleState vehicle, WidgetRef ref) {
    final wp = vehicle.currentWaypoint;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Mission Control', hc),
          const SizedBox(height: 6),
          // Current waypoint indicator
          if (wp >= 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Current WP: $wp',
                style: HeliosTypography.telemetrySmall.copyWith(
                  color: hc.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: _miniButton(hc, 'PAUSE', hc.warning, () {
                  _sendPauseContinue(ref, pause: true);
                }),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _miniButton(hc, 'RESUME', hc.success, () {
                  _sendPauseContinue(ref, pause: false);
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _miniButton(hc, 'SKIP WP', hc.textSecondary, () {
                  _sendSkipWaypoint(ref, vehicle);
                }),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _miniButton(hc, 'RESTART', hc.textSecondary, () {
                  _sendRestartMission(ref);
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoiSection(
      HeliosColors hc, VehicleState vehicle, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: hc.border.withValues(alpha: 0.3), height: 12),
          _sectionLabel('Region of Interest', hc),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _miniButton(hc, 'SET ROI HERE', hc.accent, () {
                  _sendSetRoi(ref, vehicle);
                }),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _miniButton(hc, 'CLEAR ROI', hc.textSecondary, () {
                  _sendClearRoi(ref);
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Command implementations ───────────────────────────────────────────────

  void _sendOrbit(WidgetRef ref, VehicleState vehicle) {
    // MAV_CMD_DO_ORBIT (command 34)
    // param1 = radius (negative for counter-clockwise)
    // param2 = velocity
    // param3 = yaw behavior (0=pointed at center)
    // param5 = lat (0=current), param6 = lon (0=current), param7 = alt (0=current)
    final radius = _orbitCw ? _orbitRadius : -_orbitRadius;
    ref.read(connectionControllerProvider.notifier).sendCommandWithRetry(
          command: 34, // MAV_CMD_DO_ORBIT
          param1: radius,
          param2: _orbitSpeed,
          param3: 0, // Point at center
        );
    ref.read(notificationProvider.notifier).add(
          'Orbit: ${_orbitRadius.round()}m, ${_orbitSpeed.toStringAsFixed(1)}m/s ${_orbitCw ? "CW" : "CCW"}',
          NotificationSeverity.info,
        );
  }

  void _sendChangeAlt(WidgetRef ref, VehicleState vehicle) {
    final alt = double.tryParse(_altController.text);
    if (alt == null || alt <= 0) return;

    // Send position target with current lat/lon but new altitude.
    ref.read(connectionControllerProvider.notifier).sendClickGo(
          lat: vehicle.latitude,
          lon: vehicle.longitude,
          altAgl: alt,
        );
    ref.read(notificationProvider.notifier).add(
          'Altitude target: ${alt.toStringAsFixed(0)}m AGL',
          NotificationSeverity.info,
        );
  }

  void _sendChangeSpeed(WidgetRef ref) {
    final speed = double.tryParse(_speedController.text);
    if (speed == null || speed <= 0) return;

    // MAV_CMD_DO_CHANGE_SPEED (178)
    // param1 = speed type (0=airspeed, 1=ground speed)
    // param2 = speed (-1 to keep, else m/s)
    // param3 = throttle (-1 to keep, else %)
    ref.read(connectionControllerProvider.notifier).sendCommandWithRetry(
          command: MavCmd.doChangeSpeed,
          param1: 1, // ground speed
          param2: speed,
          param3: -1, // don't change throttle
        );
    ref.read(notificationProvider.notifier).add(
          'Speed target: ${speed.toStringAsFixed(1)} m/s',
          NotificationSeverity.info,
        );
  }

  void _sendPauseContinue(WidgetRef ref, {required bool pause}) {
    // MAV_CMD_DO_PAUSE_CONTINUE (193)
    // param1: 0=pause, 1=continue
    ref.read(connectionControllerProvider.notifier).sendCommandWithRetry(
          command: MavCmd.doPauseContinue,
          param1: pause ? 0 : 1,
        );
    ref.read(notificationProvider.notifier).add(
          pause ? 'Mission paused' : 'Mission resumed',
          pause ? NotificationSeverity.warning : NotificationSeverity.success,
        );
  }

  void _sendSkipWaypoint(WidgetRef ref, VehicleState vehicle) {
    final nextWp = vehicle.currentWaypoint + 1;
    // Use MAV_CMD_DO_SET_MISSION_CURRENT approach: set to next waypoint.
    // We re-use command 224 (DO_SET_MISSION_CURRENT) via sendCommandWithRetry.
    // param1 = mission item sequence number
    ref.read(connectionControllerProvider.notifier).sendCommandWithRetry(
          command: 224, // MAV_CMD_DO_SET_MISSION_CURRENT
          param1: nextWp.toDouble(),
        );
    ref.read(notificationProvider.notifier).add(
          'Skipped to waypoint $nextWp',
          NotificationSeverity.info,
        );
  }

  void _sendRestartMission(WidgetRef ref) {
    // Set current waypoint back to 0 (start of mission).
    ref.read(connectionControllerProvider.notifier).sendCommandWithRetry(
          command: 224, // MAV_CMD_DO_SET_MISSION_CURRENT
          param1: 0,
        );
    ref.read(notificationProvider.notifier).add(
          'Mission restarted from beginning',
          NotificationSeverity.info,
        );
  }

  void _sendSetRoi(WidgetRef ref, VehicleState vehicle) {
    if (!vehicle.hasPosition) return;

    // Set ROI at a point 100m ahead of the vehicle's current heading.
    final headingRad = vehicle.heading * math.pi / 180.0;
    const offsetM = 100.0;
    final dLat = offsetM * math.cos(headingRad) / 111320.0;
    final dLon = offsetM * math.sin(headingRad) /
        (111320.0 * math.cos(vehicle.latitude * math.pi / 180.0));

    // MAV_CMD_DO_SET_ROI_LOCATION (195)
    // param5=lat, param6=lon, param7=alt
    ref.read(connectionControllerProvider.notifier).sendCommandWithRetry(
          command: 195, // MAV_CMD_DO_SET_ROI_LOCATION
          param5: vehicle.latitude + dLat,
          param6: vehicle.longitude + dLon,
          param7: vehicle.altitudeRel,
        );
    ref.read(notificationProvider.notifier).add(
          'ROI set 100m ahead',
          NotificationSeverity.info,
        );
  }

  void _sendClearRoi(WidgetRef ref) {
    // MAV_CMD_DO_SET_ROI_NONE (197)
    ref.read(connectionControllerProvider.notifier).sendCommandWithRetry(
          command: MavCmd.doSetRoiNone,
        );
    ref.read(notificationProvider.notifier).add(
          'ROI cleared',
          NotificationSeverity.info,
        );
  }

  // ─── UI helpers ────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text, HeliosColors hc) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: hc.textTertiary,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _sliderRow({
    required HeliosColors hc,
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: hc.textTertiary,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: hc.accent,
              inactiveTrackColor: hc.border,
              thumbColor: hc.accent,
              overlayColor: hc.accent.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            '${value.round()}$unit',
            style: HeliosTypography.telemetrySmall.copyWith(
              color: hc.textPrimary,
              fontSize: 10,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _directionChip(
      HeliosColors hc, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? hc.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected
                ? hc.accent.withValues(alpha: 0.5)
                : hc.border.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: selected ? hc.accent : hc.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _miniButton(
      HeliosColors hc, String label, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactField({
    required HeliosColors hc,
    required TextEditingController controller,
    required String suffix,
  }) {
    return SizedBox(
      height: 28,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: HeliosTypography.telemetrySmall.copyWith(
          color: hc.textPrimary,
          fontSize: 12,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          suffixText: suffix,
          suffixStyle: TextStyle(color: hc.textTertiary, fontSize: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(color: hc.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(color: hc.border.withValues(alpha: 0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: BorderSide(color: hc.accent),
          ),
        ),
      ),
    );
  }
}
