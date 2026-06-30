import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calibration/flight_mode_setup.dart';
import '../../../core/mavlink/flight_modes.dart';
import '../../../core/params/parameter_service.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Flight-modes setup panel.
///
/// Assigns up to six flight modes to the PWM bands of the mode-selector channel
/// (`FLTMODE_CH`, `FLTMODE1`..`FLTMODE6`). The slot the live mode-channel PWM
/// currently selects is highlighted as the pilot flips switches, using the same
/// `RC_CHANNELS` plumbing as RC calibration. Mode choices come from the existing
/// [FlightModeRegistry] and adapt to the connected vehicle type.
class FlightModesPanel extends ConsumerStatefulWidget {
  const FlightModesPanel({super.key});

  @override
  ConsumerState<FlightModesPanel> createState() => _FlightModesPanelState();
}

class _FlightModesPanelState extends ConsumerState<FlightModesPanel> {
  /// Working assignment edited by the user. Seeded from FC params on first load.
  FlightModeAssignment _assignment = const FlightModeAssignment(
    channel: kDefaultFlightModeChannel,
    slotModes: {},
  );

  bool _seeded = false;
  bool _writing = false;
  String? _error;
  String? _status;

  // ─── Read back from FC ─────────────────────────────────────────────────────

  Map<String, double> _rawParamValues() {
    final params = ref.read(paramCacheProvider);
    return {for (final e in params.entries) e.key: e.value.value};
  }

  void _seedFromParams() {
    if (_seeded) return;
    final raw = _rawParamValues();
    if (raw.isEmpty) return;
    _seeded = true;
    _assignment = readFlightModeAssignment(raw);
  }

  void _loadFromFc() {
    final raw = _rawParamValues();
    setState(() {
      _assignment = readFlightModeAssignment(raw);
      _seeded = true;
      _status = raw.containsKey(kFlightModeChannelParam)
          ? 'Loaded flight-mode setup from the flight controller.'
          : 'No stored flight-mode setup found — defaults shown.';
      _error = null;
    });
  }

  // ─── Edits ─────────────────────────────────────────────────────────────────

  void _setChannel(int channel) {
    setState(() => _assignment = _assignment.copyWith(channel: channel));
  }

  void _setSlotMode(int slot, int? mode) {
    setState(() => _assignment = _assignment.withSlotMode(slot, mode));
  }

  // ─── Write to FC ───────────────────────────────────────────────────────────

  Future<void> _save() async {
    final controller = ref.read(connectionControllerProvider.notifier);
    final paramService = controller.paramService;
    if (paramService == null) return;
    final vehicle = ref.read(vehicleStateProvider);

    final writes = buildFlightModeWrites(_assignment);
    setState(() {
      _writing = true;
      _error = null;
      _status = 'Writing ${writes.length} parameters...';
    });

    final cache = Map<String, Parameter>.from(ref.read(paramCacheProvider));
    try {
      for (final entry in writes.entries) {
        await paramService.setParam(
          targetSystem: vehicle.systemId,
          targetComponent: vehicle.componentId,
          paramId: entry.key,
          value: entry.value,
          paramType: cache[entry.key]?.type ?? 9,
        );
        if (cache.containsKey(entry.key)) {
          cache[entry.key] = cache[entry.key]!.copyWith(value: entry.value);
        }
      }
      ref.read(paramCacheProvider.notifier).state = cache;

      // Read-back confirmation: compare what's now in the cache to what we sent.
      final readBack = readFlightModeAssignment(
        {for (final e in cache.entries) e.key: e.value.value},
      );
      if (mounted) {
        final ok = readBack == _assignment;
        setState(() {
          _status = ok
              ? 'Flight-mode setup written and confirmed by read-back.'
              : 'Written, but read-back differs — verify on the flight '
                  'controller.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Write failed: $e');
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final connected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;
    final params = ref.watch(paramCacheProvider);

    _seedFromParams();

    final channels = vehicle.rcChannels;
    final chIndex = _assignment.channel - 1;
    final hasPwm = chIndex >= 0 && chIndex < channels.length;
    final pwm = hasPwm ? channels[chIndex] : 0;
    final activeSlot = hasPwm ? slotForPwm(pwm) : null;

    final modes = FlightModeRegistry.modesFor(vehicle.vehicleType);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assign a flight mode to each of the six positions of the '
            'mode-selector channel. The active position is highlighted live as '
            'you flip the transmitter switch.',
            style: HeliosTypography.small.copyWith(color: hc.textSecondary),
          ),
          const SizedBox(height: 12),

          if (!connected)
            _Banner(
              hc: hc,
              icon: Icons.info_outline,
              color: hc.warning,
              message: 'Connect to a vehicle to configure flight modes.',
            )
          else if (params.isEmpty)
            _Banner(
              hc: hc,
              icon: Icons.info_outline,
              color: hc.warning,
              message: 'Parameters not loaded yet — load them to read the '
                  'current flight-mode setup.',
            ),

          const SizedBox(height: 12),
          _controls(hc, connected, params.isNotEmpty),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!,
                style: HeliosTypography.small.copyWith(color: hc.textSecondary)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _Banner(
              hc: hc,
              icon: Icons.error_outline,
              color: hc.danger,
              message: _error!,
            ),
          ],

          const SizedBox(height: 20),
          _SectionLabel('MODE CHANNEL (FLTMODE_CH)', hc: hc),
          const SizedBox(height: 8),
          _channelSelector(hc, vehicle, hasPwm, pwm, activeSlot),

          const SizedBox(height: 20),
          _SectionLabel('FLIGHT MODES', hc: hc),
          const SizedBox(height: 8),
          _slotList(hc, modes, vehicle.vehicleType, activeSlot, hasPwm),
        ],
      ),
    );
  }

  Widget _controls(HeliosColors hc, bool connected, bool hasParams) {
    final canSave = connected && !_writing;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: hasParams ? _loadFromFc : null,
          icon: const Icon(Icons.download, size: 16),
          label: const Text('Load from FC'),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
        FilledButton.icon(
          onPressed: canSave ? _save : null,
          icon: _writing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save, size: 16),
          label: const Text('Save flight modes'),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Widget _channelSelector(
    HeliosColors hc,
    VehicleState vehicle,
    bool hasPwm,
    int pwm,
    int? activeSlot,
  ) {
    final count = vehicle.rcChannelCount;
    final maxCh = count > 0 ? count : 16;
    final options = [for (var c = 1; c <= maxCh; c++) c];

    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Selector channel',
              style: HeliosTypography.body.copyWith(color: hc.textPrimary),
            ),
          ),
          if (hasPwm) ...[
            Text(
              '$pwm µs',
              style: HeliosTypography.telemetrySmall
                  .copyWith(color: hc.textSecondary),
            ),
            const SizedBox(width: 6),
            _SlotChip(
              label: activeSlot != null ? 'POS $activeSlot' : '—',
              active: activeSlot != null,
              hc: hc,
            ),
            const SizedBox(width: 12),
          ],
          DropdownButton<int>(
            value: options.contains(_assignment.channel)
                ? _assignment.channel
                : null,
            underline: const SizedBox(),
            isDense: true,
            dropdownColor: hc.surface,
            style: HeliosTypography.small.copyWith(color: hc.textPrimary),
            items: [
              for (final c in options)
                DropdownMenuItem<int>(value: c, child: Text('CH$c')),
            ],
            onChanged: (v) {
              if (v != null) _setChannel(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _slotList(
    HeliosColors hc,
    List<FlightModeInfo> modes,
    VehicleType vehicleType,
    int? activeSlot,
    bool hasPwm,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: Column(
        children: [
          for (var slot = 1; slot <= kFlightModeSlotCount; slot++) ...[
            if (slot > 1)
              Divider(height: 1, thickness: 1, color: hc.border, indent: 16),
            _SlotRow(
              hc: hc,
              slot: slot,
              band: bandForSlot(slot)!,
              modes: modes,
              vehicleType: vehicleType,
              selectedMode: _assignment.modeForSlot(slot),
              active: hasPwm && activeSlot == slot,
              onChanged: (mode) => _setSlotMode(slot, mode),
            ),
          ],
        ],
      ),
    );
  }
}

/// A single mode slot row: the PWM band, an active highlight, and a mode picker.
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.hc,
    required this.slot,
    required this.band,
    required this.modes,
    required this.vehicleType,
    required this.selectedMode,
    required this.active,
    required this.onChanged,
  });

  final HeliosColors hc;
  final int slot;
  final FlightModeBand band;
  final List<FlightModeInfo> modes;
  final VehicleType vehicleType;
  final int? selectedMode;
  final bool active;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    // Ensure a stored mode number that isn't in the registry list is still
    // selectable so we don't silently drop an unknown value.
    final hasSelected = selectedMode != null;
    final knownNumbers = modes.map((m) => m.number).toSet();
    final showExtra = hasSelected && !knownNumbers.contains(selectedMode);

    return Container(
      color: active ? hc.accent.withValues(alpha: 0.12) : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _SlotChip(label: 'POS $slot', active: active, hc: hc),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: Text(
              '${band.lower}-${band.upper} µs',
              style: HeliosTypography.telemetrySmall
                  .copyWith(color: hc.textTertiary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: DropdownButton<int?>(
                value: selectedMode,
                hint: Text('—',
                    style: HeliosTypography.small
                        .copyWith(color: hc.textTertiary)),
                underline: const SizedBox(),
                isDense: true,
                dropdownColor: hc.surface,
                style: HeliosTypography.small.copyWith(color: hc.textPrimary),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text('—',
                        style: HeliosTypography.small
                            .copyWith(color: hc.textTertiary)),
                  ),
                  for (final m in modes)
                    DropdownMenuItem<int?>(
                      value: m.number,
                      child: Text(m.name),
                    ),
                  if (showExtra)
                    DropdownMenuItem<int?>(
                      value: selectedMode,
                      child: Text(
                        FlightModeRegistry.name(vehicleType, selectedMode!),
                      ),
                    ),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small pill showing a slot/position label, accented when active.
class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.label,
    required this.active,
    required this.hc,
  });

  final String label;
  final bool active;
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? hc.accent.withValues(alpha: 0.18) : hc.surfaceDim,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: active ? hc.accent : hc.border),
      ),
      child: Text(
        label,
        style: HeliosTypography.small.copyWith(
          color: active ? hc.accent : hc.textTertiary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.hc});
  final String text;
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: hc.textTertiary,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.hc,
    required this.icon,
    required this.color,
    required this.message,
  });
  final HeliosColors hc;
  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: HeliosTypography.small.copyWith(color: hc.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
