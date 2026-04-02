import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/mavlink/flight_modes.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Compact horizontal strip showing flight mode, armed state, flight timer,
/// and GPS status. Provides quick-switch buttons for safe mode transitions.
class FlightModeStrip extends ConsumerStatefulWidget {
  const FlightModeStrip({super.key});

  @override
  ConsumerState<FlightModeStrip> createState() => _FlightModeStripState();
}

class _FlightModeStripState extends ConsumerState<FlightModeStrip> {
  DateTime? _armedSince;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final connected = ref.watch(connectionStatusProvider).transportState ==
        TransportState.connected;

    // Track armed time.
    if (vehicle.armed && _armedSince == null) {
      _armedSince = DateTime.now();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!vehicle.armed && _armedSince != null) {
      _armedSince = null;
      _timer?.cancel();
      _timer = null;
    }

    final modeName = vehicle.flightMode.name.startsWith('MODE_')
        ? FlightModeRegistry.name(
            vehicle.vehicleType, vehicle.flightMode.number)
        : vehicle.flightMode.name;

    final modeColor = _modeColor(modeName, hc);
    final quickModes = _quickModes(modeName);

    final flightTime = _armedSince != null
        ? _formatDuration(DateTime.now().difference(_armedSince!))
        : '--:--';

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: hc.surfaceDim.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Current mode badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: modeColor.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(8),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_modeIcon(modeName), size: 14, color: modeColor),
                const SizedBox(width: 5),
                Text(
                  modeName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                    color: modeColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          _divider(hc),

          // Quick-switch buttons
          for (final mode in quickModes) ...[
            _QuickModeButton(
              label: mode,
              color: _modeColor(mode, hc),
              enabled: connected && vehicle.armed,
              onTap: () => _switchMode(ref, vehicle.vehicleType, mode),
            ),
          ],

          if (quickModes.isNotEmpty) _divider(hc),

          // Armed indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: vehicle.armed ? hc.danger : hc.success,
                    boxShadow: [
                      BoxShadow(
                        color: (vehicle.armed ? hc.danger : hc.success)
                            .withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  vehicle.armed ? 'ARMED' : 'DISARMED',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: vehicle.armed ? hc.danger : hc.success,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          _divider(hc),

          // Flight timer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_outlined, size: 12, color: hc.textSecondary),
                const SizedBox(width: 3),
                Text(
                  flightTime,
                  style: HeliosTypography.telemetrySmall.copyWith(
                    color: hc.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _divider(hc),

          // GPS indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _gpsIcon(vehicle.gpsFix),
                  size: 13,
                  color: _gpsColor(vehicle.gpsFix, hc),
                ),
                const SizedBox(width: 3),
                Text(
                  '${vehicle.satellites}',
                  style: HeliosTypography.telemetrySmall.copyWith(
                    color: _gpsColor(vehicle.gpsFix, hc),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(HeliosColors hc) {
    return SizedBox(
      height: 20,
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: hc.border.withValues(alpha: 0.4),
      ),
    );
  }

  Color _modeColor(String mode, HeliosColors hc) {
    return switch (mode.toUpperCase()) {
      'AUTO' => hc.accent,
      'GUIDED' => const Color(0xFFAB7DF6),
      'RTL' || 'SMART_RTL' || 'AUTO_RTL' || 'QRTL' => hc.danger,
      'LAND' || 'QLAND' => hc.warning,
      'LOITER' || 'POSHOLD' || 'HOLD' || 'QLOITER' || 'QHOVER' =>
        const Color(0xFF56D4DD),
      'STABILIZE' || 'QSTABILIZE' || 'ALT_HOLD' => hc.success,
      'BRAKE' => hc.warning,
      _ => hc.textSecondary,
    };
  }

  IconData _modeIcon(String mode) {
    return switch (mode.toUpperCase()) {
      'AUTO' => Icons.route,
      'GUIDED' => Icons.gps_fixed,
      'RTL' || 'SMART_RTL' || 'AUTO_RTL' || 'QRTL' => Icons.home,
      'LAND' || 'QLAND' => Icons.flight_land,
      'LOITER' || 'POSHOLD' || 'HOLD' || 'QLOITER' || 'QHOVER' => Icons.loop,
      'STABILIZE' || 'QSTABILIZE' || 'ALT_HOLD' => Icons.straighten,
      'BRAKE' => Icons.stop_circle_outlined,
      _ => Icons.tune,
    };
  }

  IconData _gpsIcon(GpsFix fix) {
    return switch (fix) {
      GpsFix.none || GpsFix.noFix => Icons.gps_off,
      GpsFix.fix2d => Icons.gps_not_fixed,
      _ => Icons.gps_fixed,
    };
  }

  Color _gpsColor(GpsFix fix, HeliosColors hc) {
    return switch (fix) {
      GpsFix.none || GpsFix.noFix => hc.danger,
      GpsFix.fix2d => hc.warning,
      GpsFix.fix3d => hc.success,
      GpsFix.dgps || GpsFix.rtkFloat || GpsFix.rtkFixed => hc.accent,
    };
  }

  /// Returns a list of quick-switch mode names based on the current mode.
  List<String> _quickModes(String current) {
    final c = current.toUpperCase();
    return switch (c) {
      'GUIDED' => ['LOITER', 'AUTO', 'RTL'],
      'AUTO' => ['LOITER', 'GUIDED', 'RTL'],
      'STABILIZE' || 'ALT_HOLD' || 'ACRO' => ['LOITER', 'GUIDED', 'RTL'],
      'RTL' || 'SMART_RTL' => ['LOITER', 'LAND'],
      'LAND' => ['LOITER', 'RTL'],
      'LOITER' || 'POSHOLD' || 'HOLD' => ['AUTO', 'RTL', 'LAND'],
      'BRAKE' => ['LOITER', 'RTL', 'LAND'],
      _ => ['LOITER', 'RTL', 'LAND'],
    };
  }

  void _switchMode(WidgetRef ref, VehicleType vehicleType, String modeName) {
    final modeNumber = switch (modeName.toUpperCase()) {
      'AUTO' => FlightModeRegistry.autoMode(vehicleType),
      'GUIDED' => FlightModeRegistry.guidedMode(vehicleType),
      'RTL' => FlightModeRegistry.rtlMode(vehicleType),
      'LAND' => FlightModeRegistry.landMode(vehicleType),
      'LOITER' => FlightModeRegistry.loiterMode(vehicleType),
      'BRAKE' => FlightModeRegistry.brakeMode(vehicleType),
      _ => -1,
    };
    if (modeNumber >= 0) {
      ref.read(connectionControllerProvider.notifier).setFlightMode(modeNumber);
    }
  }
}

// ─── Quick Mode Button ──────────────────────────────────────────────────────

class _QuickModeButton extends StatelessWidget {
  const _QuickModeButton({
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        enabled ? color : context.hc.textTertiary.withValues(alpha: 0.5);

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: effectiveColor,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
