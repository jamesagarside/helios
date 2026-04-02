import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/mavlink/flight_modes.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Floating action panel for arming, mode control, and flight commands.
///
/// Shown on the Fly View map as a compact horizontal strip.
/// Provides: ARM/DISARM, flight mode selector, RTL, LAND, LOITER, AUTO,
/// and a contextual TAKEOFF button when the vehicle is on the ground.
class ActionPanel extends ConsumerWidget {
  const ActionPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(vehicleStateProvider);
    final hc = context.hc;
    final connected = ref.watch(connectionStatusProvider).transportState ==
        TransportState.connected;

    final onGround = !vehicle.armed || vehicle.altitudeRel.abs() < 1.5;
    final showTakeoff = vehicle.armed && onGround;

    return Container(
      decoration: BoxDecoration(
        color: hc.surfaceDim.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hc.border.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flight mode selector
          _ModePicker(vehicle: vehicle, connected: connected, hc: hc),
          _Divider(hc: hc),
          // ARM / DISARM
          _ArmButton(vehicle: vehicle, connected: connected, hc: hc),
          _Divider(hc: hc),
          // Contextual: TAKEOFF (armed, on ground) or BRAKE (airborne)
          if (showTakeoff)
            _ActionButton(
              label: 'TKOF',
              icon: Icons.flight_takeoff,
              color: hc.accent,
              enabled: connected,
              onTap: () => _showTakeoffDialog(context, ref),
            )
          else
            _ActionButton(
              label: 'BRAKE',
              icon: Icons.stop_circle_outlined,
              color: hc.warning,
              enabled: connected && vehicle.armed,
              onTap: () =>
                  ref.read(connectionControllerProvider.notifier).sendBrake(),
            ),
          // LOITER
          _ActionButton(
            label: 'LOITER',
            icon: Icons.loop,
            color: hc.textSecondary,
            enabled: connected && vehicle.armed,
            onTap: () =>
                ref.read(connectionControllerProvider.notifier).sendLoiter(),
          ),
          // AUTO
          _ActionButton(
            label: 'AUTO',
            icon: Icons.route,
            color: hc.accent,
            enabled: connected && vehicle.armed,
            onTap: () =>
                ref.read(connectionControllerProvider.notifier).sendAuto(),
          ),
          _Divider(hc: hc),
          // LAND
          _ActionButton(
            label: 'LAND',
            icon: Icons.flight_land,
            color: hc.warning,
            enabled: connected && vehicle.armed,
            onTap: () =>
                ref.read(connectionControllerProvider.notifier).sendLand(),
          ),
          // RTL
          _ActionButton(
            label: 'RTL',
            icon: Icons.home,
            color: hc.danger,
            enabled: connected && vehicle.armed,
            onTap: () =>
                ref.read(connectionControllerProvider.notifier).sendRtl(),
          ),
        ],
      ),
    );
  }

  void _showTakeoffDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: '10');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.hc.surface,
        title: Text('Takeoff Altitude', style: HeliosTypography.heading2),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: const TextStyle(fontSize: 18, fontFamily: 'monospace'),
          decoration: InputDecoration(
            suffixText: 'm AGL',
            suffixStyle: TextStyle(color: ctx.hc.textSecondary),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final alt = double.tryParse(controller.text);
              if (alt != null && alt > 0) {
                ref
                    .read(connectionControllerProvider.notifier)
                    .sendTakeoff(alt);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Takeoff'),
          ),
        ],
      ),
    );
  }
}

// ─── Mode Picker ─────────────────────────────────────────────────────────────

class _ModePicker extends ConsumerWidget {
  const _ModePicker({
    required this.vehicle,
    required this.connected,
    required this.hc,
  });

  final VehicleState vehicle;
  final bool connected;
  final HeliosColors hc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modeName = vehicle.flightMode.name.startsWith('MODE_')
        ? FlightModeRegistry.name(vehicle.vehicleType, vehicle.flightMode.number)
        : vehicle.flightMode.name;
    final category = vehicle.flightMode.category;

    final modeColor = switch (category) {
      'auto' => hc.accent,
      'assisted' => hc.textPrimary,
      _ => hc.textSecondary, // manual
    };

    return InkWell(
      onTap: connected
          ? () => _showModePicker(context, ref, vehicle)
          : null,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(10),
        bottomLeft: Radius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune, size: 13, color: modeColor),
            const SizedBox(width: 5),
            Text(
              modeName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: modeColor,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.arrow_drop_down, size: 14, color: hc.textTertiary),
          ],
        ),
      ),
    );
  }

  void _showModePicker(
    BuildContext context,
    WidgetRef ref,
    VehicleState vehicle,
  ) {
    final hc = context.hc;
    final modes = FlightModeRegistry.modesFor(vehicle.vehicleType);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: hc.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _ModePickerSheet(
        modes: modes,
        currentMode: vehicle.flightMode.number,
        onSelect: (modeNumber) {
          ref
              .read(connectionControllerProvider.notifier)
              .setFlightMode(modeNumber);
        },
      ),
    );
  }
}

class _ModePickerSheet extends StatelessWidget {
  const _ModePickerSheet({
    required this.modes,
    required this.currentMode,
    required this.onSelect,
  });

  final List<FlightModeInfo> modes;
  final int currentMode;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    // Group by category
    final manual = modes.where((m) => m.category == 'manual').toList();
    final assisted = modes.where((m) => m.category == 'assisted').toList();
    final auto = modes.where((m) => m.category == 'auto').toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Select Flight Mode', style: HeliosTypography.heading2),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              if (auto.isNotEmpty) ...[
                _CategoryHeader(label: 'AUTO', color: hc.accent),
                ..._modeItems(context, auto),
              ],
              if (assisted.isNotEmpty) ...[
                _CategoryHeader(label: 'ASSISTED', color: hc.textPrimary),
                ..._modeItems(context, assisted),
              ],
              if (manual.isNotEmpty) ...[
                _CategoryHeader(label: 'MANUAL', color: hc.textSecondary),
                ..._modeItems(context, manual),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _modeItems(BuildContext context, List<FlightModeInfo> modes) {
    final hc = context.hc;
    return modes.map((m) {
      final isCurrent = m.number == currentMode;
      return ListTile(
        dense: true,
        title: Text(
          m.name,
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
            color: isCurrent ? hc.accent : hc.textPrimary,
            fontSize: 14,
          ),
        ),
        trailing: isCurrent
            ? Icon(Icons.check, size: 16, color: hc.accent)
            : null,
        onTap: () {
          Navigator.pop(context);
          onSelect(m.number);
        },
      );
    }).toList();
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color.withValues(alpha: 0.7),
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ─── ARM Button ──────────────────────────────────────────────────────────────

class _ArmButton extends ConsumerWidget {
  const _ArmButton({
    required this.vehicle,
    required this.connected,
    required this.hc,
  });

  final VehicleState vehicle;
  final bool connected;
  final HeliosColors hc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isArmed = vehicle.armed;

    return InkWell(
      onTap: connected
          ? () => isArmed
              ? _confirmDisarm(context, ref)
              : _confirmArm(context, ref)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isArmed ? Icons.lock_open : Icons.lock,
              size: 13,
              color: isArmed ? hc.danger : hc.success,
            ),
            const SizedBox(width: 5),
            Text(
              isArmed ? 'DISARM' : 'ARM',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isArmed ? hc.danger : hc.success,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmArm(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: hc.surface,
        title: Text('Arm Vehicle?', style: HeliosTypography.heading2),
        content: Text(
          'The vehicle will arm and become ready to fly. '
          'Ensure the area is clear before arming.',
          style: TextStyle(color: hc.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: hc.success),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(connectionControllerProvider.notifier).setArmed(true);
            },
            child: const Text('Arm'),
          ),
        ],
      ),
    );
  }

  void _confirmDisarm(BuildContext _, WidgetRef ref) {
    ref.read(connectionControllerProvider.notifier).setArmed(false);
  }
}

// ─── Individual Action Button ─────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final effectiveColor = enabled ? color : hc.textTertiary;

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: effectiveColor),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: effectiveColor,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.hc});
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: hc.border.withValues(alpha: 0.5),
      ),
    );
  }
}
