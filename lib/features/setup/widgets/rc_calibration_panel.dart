import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calibration/rc_calibration.dart';
import '../../../core/params/parameter_service.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// RC / radio calibration panel.
///
/// Shows live per-channel bars driven by `RC_CHANNELS` telemetry, captures
/// per-channel min/max/trim endpoints as the pilot sweeps every stick and
/// switch, supports channel reversal, and writes the results
/// (`RCx_MIN`/`RCx_MAX`/`RCx_TRIM`/`RCx_REVERSED`/`RCx_DZ`) plus `RCMAP_*`
/// channel-function assignments to the flight controller.
class RcCalibrationPanel extends ConsumerStatefulWidget {
  const RcCalibrationPanel({super.key});

  @override
  ConsumerState<RcCalibrationPanel> createState() => _RcCalibrationPanelState();
}

class _RcCalibrationPanelState extends ConsumerState<RcCalibrationPanel> {
  final RcEndpointCapture _capture = RcEndpointCapture();

  /// Captured calibration after a sweep, keyed by 1-based channel.
  final Map<int, RcChannelCalibration> _captured = {};

  /// RCMAP function → 1-based channel assignment edited by the user.
  final Map<RcFunction, int?> _assignments = {
    for (final fn in RcFunction.values) fn: null,
  };

  bool _assignmentsSeeded = false;
  bool _capturing = false;
  bool _writing = false;
  String? _error;
  String? _status;

  @override
  void dispose() {
    _capture.cancel();
    super.dispose();
  }

  // ─── Capture control ───────────────────────────────────────────────────────

  void _startCapture(VehicleState vehicle) {
    _capture.start(vehicle.rcChannels);
    setState(() {
      _capturing = true;
      _captured.clear();
      _error = null;
      _status = 'Move every stick and switch through its full range, then '
          'centre the sticks and stop.';
    });
  }

  void _finishCapture() {
    final result = _capture.finish(
      seedReversed: {
        for (final e in _captured.entries) e.key: e.value.reversed,
      },
      seedDeadzone: {
        for (final e in _captured.entries) e.key: e.value.deadzone,
      },
    );
    setState(() {
      _capturing = false;
      _captured
        ..clear()
        ..addEntries(result.map((c) => MapEntry(c.channel, c)));
      _status = result.isEmpty
          ? 'No channels captured — check the RC link.'
          : 'Captured ${result.length} channel${result.length == 1 ? '' : 's'}. '
              'Review, set reversal, then save.';
    });
  }

  void _cancelCapture() {
    _capture.cancel();
    setState(() {
      _capturing = false;
      _status = null;
    });
  }

  void _toggleReversed(int channel, bool reversed) {
    final existing = _captured[channel];
    if (existing == null) return;
    setState(() {
      _captured[channel] = existing.copyWith(reversed: reversed);
    });
  }

  // ─── Read back from FC ─────────────────────────────────────────────────────

  Map<String, double> _rawParamValues() {
    final params = ref.read(paramCacheProvider);
    return {for (final e in params.entries) e.key: e.value.value};
  }

  void _seedAssignmentsFromParams() {
    if (_assignmentsSeeded) return;
    final raw = _rawParamValues();
    if (raw.isEmpty) return;
    final read = readAssignments(raw);
    _assignmentsSeeded = true;
    _assignments
      ..clear()
      ..addAll(read);
  }

  void _loadFromFc() {
    final raw = _rawParamValues();
    final loaded = <int, RcChannelCalibration>{};
    for (var ch = 1; ch <= 18; ch++) {
      final cal = readChannelCalibration(ch, raw);
      if (cal != null) loaded[ch] = cal;
    }
    setState(() {
      _captured
        ..clear()
        ..addAll(loaded);
      _assignmentsSeeded = false;
      _seedAssignmentsFromParams();
      _status = loaded.isEmpty
          ? 'No stored RC calibration found in parameters.'
          : 'Loaded stored calibration for ${loaded.length} channel'
              '${loaded.length == 1 ? '' : 's'}.';
      _error = null;
    });
  }

  // ─── Write to FC ───────────────────────────────────────────────────────────

  Future<void> _save() async {
    const bounds = RcCalibrationBounds();
    final issues = validateCalibration(_captured.values, bounds: bounds);
    if (issues.isNotEmpty) {
      setState(() => _error =
          'Cannot save — invalid ranges:\n${issues.join('\n')}');
      return;
    }

    final controller = ref.read(connectionControllerProvider.notifier);
    final paramService = controller.paramService;
    if (paramService == null) return;
    final vehicle = ref.read(vehicleStateProvider);

    final writes = buildParameterWrites(_captured.values, _assignments);
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
      if (mounted) {
        setState(() => _status = 'Calibration written to flight controller.');
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

    // Keep the capture buffer fed while a sweep is active.
    if (_capturing) {
      _capture.addSample(vehicle.rcChannels);
    }
    _seedAssignmentsFromParams();

    final count = vehicle.rcChannelCount;
    final channels = vehicle.rcChannels;
    final hasSignal = count > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Calibrate the radio: sweep every stick and switch to capture the '
            'endpoints, set channel reversal, and assign which channel drives '
            'each control function.',
            style: HeliosTypography.small.copyWith(color: hc.textSecondary),
          ),
          const SizedBox(height: 12),

          if (!connected)
            _Banner(
              hc: hc,
              icon: Icons.info_outline,
              color: hc.warning,
              message: 'Connect to a vehicle to calibrate the radio.',
            ),
          if (connected && vehicle.armed)
            _Banner(
              hc: hc,
              icon: Icons.warning_amber,
              color: hc.danger,
              message: 'Vehicle is ARMED — disarm before calibrating RC.',
            ),
          if (connected && !hasSignal)
            _Banner(
              hc: hc,
              icon: Icons.sensors_off,
              color: hc.warning,
              message:
                  'No RC signal. Power on the transmitter and bind the receiver.',
            ),

          const SizedBox(height: 8),
          _controls(hc, connected, vehicle, params.isNotEmpty),
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
          _SectionLabel('LIVE CHANNELS ($count active)', hc: hc),
          const SizedBox(height: 8),
          _channelList(hc, channels, count, hasSignal),

          const SizedBox(height: 20),
          _SectionLabel('CHANNEL FUNCTION (RCMAP)', hc: hc),
          const SizedBox(height: 8),
          _rcMap(hc, count, hasSignal || _captured.isNotEmpty),
        ],
      ),
    );
  }

  Widget _controls(
    HeliosColors hc,
    bool connected,
    VehicleState vehicle,
    bool hasParams,
  ) {
    final canCapture = connected && !vehicle.armed && vehicle.rcChannelCount > 0;
    final canSave = connected &&
        !vehicle.armed &&
        !_capturing &&
        _captured.isNotEmpty &&
        !_writing;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!_capturing)
          FilledButton.icon(
            onPressed: canCapture ? () => _startCapture(vehicle) : null,
            icon: const Icon(Icons.fiber_manual_record, size: 16),
            label: const Text('Start capture'),
            style: FilledButton.styleFrom(
              backgroundColor: hc.danger,
              visualDensity: VisualDensity.compact,
            ),
          )
        else ...[
          FilledButton.icon(
            onPressed: _finishCapture,
            icon: const Icon(Icons.stop, size: 16),
            label: const Text('Finish'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
          OutlinedButton(
            onPressed: _cancelCapture,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Cancel'),
          ),
        ],
        OutlinedButton.icon(
          onPressed: hasParams && !_capturing ? _loadFromFc : null,
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
          label: const Text('Save calibration'),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Widget _channelList(
    HeliosColors hc,
    List<int> channels,
    int count,
    bool hasSignal,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      padding: const EdgeInsets.all(16),
      child: !hasSignal
          ? Text('No live RC channels.',
              style: HeliosTypography.small.copyWith(color: hc.textTertiary))
          : Column(
              children: [
                for (int i = 0; i < count && i < channels.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _RcCalibChannelRow(
                    channel: i + 1,
                    pwm: channels[i],
                    captured: _captured[i + 1],
                    onReverse: _captured.containsKey(i + 1)
                        ? (v) => _toggleReversed(i + 1, v)
                        : null,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _rcMap(HeliosColors hc, int count, bool enabled) {
    // Offer the observed channels, falling back to a sensible default range.
    final maxCh = count > 0 ? count : 8;
    final options = [for (var c = 1; c <= maxCh; c++) c];

    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < RcFunction.values.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: hc.border, indent: 16),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      RcFunction.values[i].label,
                      style: HeliosTypography.body
                          .copyWith(color: hc.textPrimary),
                    ),
                  ),
                  DropdownButton<int?>(
                    value: _assignments[RcFunction.values[i]],
                    hint: Text('—',
                        style: HeliosTypography.small
                            .copyWith(color: hc.textTertiary)),
                    underline: const SizedBox(),
                    isDense: true,
                    dropdownColor: hc.surface,
                    style:
                        HeliosTypography.small.copyWith(color: hc.textPrimary),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text('—',
                            style: HeliosTypography.small
                                .copyWith(color: hc.textTertiary)),
                      ),
                      for (final c in options)
                        DropdownMenuItem<int?>(
                          value: c,
                          child: Text('CH$c'),
                        ),
                    ],
                    onChanged: enabled
                        ? (v) => setState(
                            () => _assignments[RcFunction.values[i]] = v)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A live RC channel row with the current PWM bar plus captured endpoint
/// markers and a reversal toggle once a calibration exists.
class _RcCalibChannelRow extends StatelessWidget {
  const _RcCalibChannelRow({
    required this.channel,
    required this.pwm,
    required this.captured,
    required this.onReverse,
  });

  final int channel;
  final int pwm;
  final RcChannelCalibration? captured;
  final ValueChanged<bool>? onReverse;

  static const _kFloor = 900;
  static const _kCeil = 2100;

  bool get _active => pwm >= _kFloor && pwm <= _kCeil;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final cal = captured;
    final normalised = _active
        ? ((pwm - _kFloor) / (_kCeil - _kFloor)).clamp(0.0, 1.0)
        : 0.0;

    double markerFor(int v) =>
        ((v - _kFloor) / (_kCeil - _kFloor)).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text('CH$channel',
              style: HeliosTypography.small.copyWith(
                  color: hc.textTertiary, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 16,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: normalised,
                        backgroundColor: hc.surfaceDim,
                        color: _active ? hc.accent : hc.textTertiary,
                        minHeight: 8,
                      ),
                    ),
                    if (cal != null) ...[
                      _Marker(left: markerFor(cal.min) * w, color: hc.warning),
                      _Marker(left: markerFor(cal.max) * w, color: hc.warning),
                      _Marker(
                          left: markerFor(cal.trim) * w, color: hc.success),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 56,
          child: Text(
            _active ? '$pwm µs' : '—',
            textAlign: TextAlign.right,
            style: HeliosTypography.telemetrySmall
                .copyWith(color: hc.textSecondary),
          ),
        ),
        if (onReverse != null) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: 'Reverse channel',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('REV',
                    style: HeliosTypography.small.copyWith(
                        color: cal?.reversed == true
                            ? hc.accent
                            : hc.textTertiary,
                        fontWeight: FontWeight.w600)),
                Switch(
                  value: cal?.reversed ?? false,
                  onChanged: onReverse,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A thin vertical marker drawn over a channel bar (min/max/trim).
class _Marker extends StatelessWidget {
  const _Marker({required this.left, required this.color});
  final double left;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left.clamp(0.0, double.infinity),
      top: -2,
      child: Container(width: 2, height: 12, color: color),
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
