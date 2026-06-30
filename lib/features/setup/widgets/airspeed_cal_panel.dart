import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calibration/airspeed_calibration.dart';
import '../../../core/calibration/calibration_service.dart';
import '../../../core/params/parameter_service.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';

/// Airspeed sensor calibration panel.
///
/// Two flows backed by the existing parameter and calibration plumbing:
///   1. A pre-flight **zero-offset** wizard — cover the pitot, command the zero
///      (`MAV_CMD_PREFLIGHT_CALIBRATION`), and watch live airspeed settle so the
///      captured `ARSPD_OFFSET` is visibly effective.
///   2. Editable sensor configuration (`ARSPD_TYPE/_BUS/_PIN`), the in-flight
///      `ARSPD_RATIO`, and the `ARSPD_AUTOCAL` toggle — each written through the
///      shared [ParameterService] and read back to confirm.
class AirspeedCalPanel extends ConsumerStatefulWidget {
  const AirspeedCalPanel({super.key});

  @override
  ConsumerState<AirspeedCalPanel> createState() => _AirspeedCalPanelState();
}

class _AirspeedCalPanelState extends ConsumerState<AirspeedCalPanel> {
  Map<String, Parameter> _params = {};
  final Map<String, double> _pending = {};
  bool _loading = false;
  String? _error;

  CalibrationService? _calService;
  StreamSubscription<CalibrationProgress>? _calSub;
  CalibrationProgress _zero = const CalibrationProgress();
  bool _zeroing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _calSub?.cancel();
    _calService?.dispose();
    super.dispose();
  }

  ({int sys, int comp})? get _target {
    final vehicle = ref.read(vehicleStateProvider);
    if (vehicle.systemId == 0) return null;
    return (sys: vehicle.systemId, comp: vehicle.componentId);
  }

  Future<void> _load() async {
    final svc = ref.read(connectionControllerProvider.notifier).paramService;
    if (svc == null) return;
    final vehicle = ref.read(vehicleStateProvider);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await svc.fetchAll(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
      );
      if (!mounted) return;
      setState(() {
        _params = {
          for (final id in AirspeedCalibration.paramIds)
            if (all.containsKey(id)) id: all[id]!,
        };
        _pending.clear();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _write(String id, double value) async {
    final svc = ref.read(connectionControllerProvider.notifier).paramService;
    final target = _target;
    if (svc == null || target == null) return;
    try {
      final confirmed = await svc.setParam(
        targetSystem: target.sys,
        targetComponent: target.comp,
        paramId: id,
        value: value,
        paramType: _params[id]?.type ?? AirspeedCalibration.paramTypeFor(id),
      );
      if (!mounted) return;
      // Read-back: trust the value the FC echoed, not the value we sent.
      setState(() {
        final existing = _params[id];
        if (existing != null) {
          _params[id] = existing.copyWith(value: confirmed);
        }
        _pending.remove(id);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to write $id: $e'),
            backgroundColor: context.hc.danger,
          ),
        );
      }
    }
  }

  Future<void> _writeAllPending() async {
    for (final entry in Map.of(_pending).entries) {
      await _write(entry.key, entry.value);
    }
  }

  void _startZero() {
    final mavlink =
        ref.read(connectionControllerProvider.notifier).mavlinkService;
    final target = _target;
    if (mavlink == null || target == null) return;

    _calService ??= CalibrationService(mavlink);
    _calSub?.cancel();
    _calSub = _calService!.progressStream.listen((p) {
      if (!mounted) return;
      setState(() {
        _zero = p;
        if (p.state == CalibrationState.success ||
            p.state == CalibrationState.failed) {
          _zeroing = false;
        }
      });
      if (p.state == CalibrationState.success) {
        // Re-read params so the captured ARSPD_OFFSET is shown.
        _load();
      }
    });

    setState(() {
      _zeroing = true;
      _zero = const CalibrationProgress(
        state: CalibrationState.running,
        type: CalibrationType.airspeed,
        message: 'Capturing airspeed zero offset…',
      );
    });

    _calService!.startAirspeedZeroCal(
      targetSystem: target.sys,
      targetComponent: target.comp,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final connection = ref.watch(connectionStatusProvider);
    final connected = connection.linkState == LinkState.connected ||
        connection.linkState == LinkState.degraded;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(connected: connected, onReload: connected ? _load : null),
          const SizedBox(height: 8),
          Text(
            'Calibrate the differential-pressure airspeed sensor for fixed-wing '
            'and VTOL forward flight.',
            style: TextStyle(color: hc.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (!connected) ...[
            const _Banner(
              icon: Icons.info_outline,
              tone: _BannerTone.warning,
              message: 'Connect to a vehicle to read and calibrate the airspeed '
                  'sensor.',
            ),
            const SizedBox(height: 16),
          ],
          _LiveAirspeedCard(airspeed: vehicle.airspeed, connected: connected),
          const SizedBox(height: 24),
          _ZeroOffsetSection(
            connected: connected,
            zeroing: _zeroing,
            progress: _zero,
            offset: _params[AirspeedCalibration.offsetParam]?.value,
            onStart: _startZero,
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            _Banner(
              icon: Icons.error_outline,
              tone: _BannerTone.danger,
              message: _error!,
            )
          else
            _ParamSection(
              params: _params,
              pending: _pending,
              connected: connected,
              onChanged: (id, v) => setState(() => _pending[id] = v),
              onWrite: _write,
              onWriteAll: _writeAllPending,
            ),
        ],
      ),
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.connected, required this.onReload});
  final bool connected;
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Row(
      children: [
        Text(
          'AIRSPEED CALIBRATION',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: hc.textTertiary,
            letterSpacing: 0.6,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.refresh, size: 18),
          tooltip: 'Reload parameters',
          onPressed: onReload,
        ),
      ],
    );
  }
}

// ─── Live airspeed ───────────────────────────────────────────────────────────

class _LiveAirspeedCard extends StatelessWidget {
  const _LiveAirspeedCard({required this.airspeed, required this.connected});
  final double airspeed;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: Row(
        children: [
          Icon(Icons.air, color: hc.accent, size: 22),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('LIVE AIRSPEED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: hc.textTertiary,
                    letterSpacing: 0.6,
                  )),
              const SizedBox(height: 2),
              Text(
                connected
                    ? 'From VFR_HUD telemetry'
                    : 'Awaiting connection',
                style: TextStyle(fontSize: 11, color: hc.textTertiary),
              ),
            ],
          ),
          const Spacer(),
          Text(
            connected ? airspeed.toStringAsFixed(1) : '—',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: hc.textPrimary,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('m/s',
                style: TextStyle(fontSize: 13, color: hc.textTertiary)),
          ),
          if (connected) ...[
            const SizedBox(width: 12),
            Text(
              '${(airspeed * 3.6).toStringAsFixed(0)} km/h',
              style: TextStyle(fontSize: 13, color: hc.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Zero-offset wizard ──────────────────────────────────────────────────────

class _ZeroOffsetSection extends StatelessWidget {
  const _ZeroOffsetSection({
    required this.connected,
    required this.zeroing,
    required this.progress,
    required this.offset,
    required this.onStart,
  });

  final bool connected;
  final bool zeroing;
  final CalibrationProgress progress;
  final double? offset;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final state = progress.state;
    final (tone, statusText) = switch (state) {
      CalibrationState.success => (_BannerTone.success, 'Zero offset captured.'),
      CalibrationState.failed => (_BannerTone.danger, 'Zero calibration failed.'),
      CalibrationState.running ||
      CalibrationState.waitingOrientation =>
        (_BannerTone.accent, 'Capturing…'),
      CalibrationState.idle => (_BannerTone.neutral, ''),
    };

    return _Card(
      title: 'PRE-FLIGHT ZERO OFFSET',
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cover the pitot tube so no air can flow through it, then '
                'capture the zero. The static differential-pressure reading is '
                'stored as ARSPD_OFFSET and live airspeed should fall to near '
                'zero.',
                style: TextStyle(color: hc.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('ARSPD_OFFSET',
                      style: TextStyle(
                        fontSize: 12,
                        color: hc.textTertiary,
                        fontFamily: 'monospace',
                      )),
                  const Spacer(),
                  Text(
                    offset == null ? '—' : offset!.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: hc.textPrimary,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('Pa',
                      style: TextStyle(fontSize: 12, color: hc.textTertiary)),
                ],
              ),
              const SizedBox(height: 14),
              if (state != CalibrationState.idle &&
                  progress.message.isNotEmpty) ...[
                _Banner(
                  icon: switch (state) {
                    CalibrationState.success => Icons.check_circle,
                    CalibrationState.failed => Icons.error_outline,
                    _ => Icons.sensors,
                  },
                  tone: tone,
                  message: progress.message,
                  title: statusText.isEmpty ? null : statusText,
                ),
                const SizedBox(height: 14),
              ],
              if (zeroing)
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text('Capturing zero offset…',
                        style: TextStyle(color: hc.textSecondary)),
                  ],
                )
              else
                FilledButton.icon(
                  onPressed: connected ? onStart : null,
                  icon: const Icon(Icons.adjust, size: 18),
                  label: Text(state == CalibrationState.success
                      ? 'Re-capture zero offset'
                      : 'Capture zero offset'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Parameter table ─────────────────────────────────────────────────────────

class _ParamSection extends StatelessWidget {
  const _ParamSection({
    required this.params,
    required this.pending,
    required this.connected,
    required this.onChanged,
    required this.onWrite,
    required this.onWriteAll,
  });

  final Map<String, Parameter> params;
  final Map<String, double> pending;
  final bool connected;
  final void Function(String id, double value) onChanged;
  final Future<void> Function(String id, double value) onWrite;
  final Future<void> Function() onWriteAll;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    // Sensor config + ratio + autocal (everything except the offset, which has
    // its own wizard section above).
    final rows = AirspeedCalibration.params
        .where((p) => p.id != AirspeedCalibration.offsetParam)
        .toList();

    return _Card(
      title: 'SENSOR CONFIGURATION',
      trailing: pending.isEmpty
          ? null
          : FilledButton.tonal(
              onPressed: onWriteAll,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Write ${pending.length} change${pending.length > 1 ? 's' : ''}',
              ),
            ),
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          _ParamRow(
            descriptor: rows[i],
            param: params[rows[i].id],
            pendingValue: pending[rows[i].id],
            onChanged: (v) => onChanged(rows[i].id, v),
            onWrite: () {
              final v = pending[rows[i].id] ?? params[rows[i].id]?.value;
              if (v != null) onWrite(rows[i].id, v);
            },
          ),
          if (i != rows.length - 1)
            Divider(
              height: 1,
              thickness: 1,
              color: hc.border,
              indent: 16,
            ),
        ],
      ],
    );
  }
}

class _ParamRow extends StatelessWidget {
  const _ParamRow({
    required this.descriptor,
    required this.param,
    required this.pendingValue,
    required this.onChanged,
    required this.onWrite,
  });

  final AirspeedParam descriptor;
  final Parameter? param;
  final double? pendingValue;
  final ValueChanged<double> onChanged;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final displayVal = pendingValue ?? param?.value;
    final hasPending = pendingValue != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(descriptor.label,
                    style: TextStyle(fontSize: 13, color: hc.textPrimary)),
                Text(descriptor.id,
                    style: TextStyle(
                      fontSize: 11,
                      color: hc.textTertiary,
                      fontFamily: 'monospace',
                    )),
                if (descriptor.helpText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(descriptor.helpText,
                      style: TextStyle(fontSize: 11, color: hc.textTertiary)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (param == null || displayVal == null)
            Text('—', style: TextStyle(color: hc.textTertiary, fontSize: 13))
          else if (descriptor.kind == AirspeedFieldKind.enumeration)
            _EnumPicker(
              value: displayVal.round(),
              options: descriptor.options,
              hasPending: hasPending,
              onChanged: (v) => onChanged(v.toDouble()),
              onWrite: onWrite,
            )
          else
            _NumberEditor(
              value: displayVal,
              unit: descriptor.unit,
              decimals: descriptor.decimals,
              hasPending: hasPending,
              onChanged: onChanged,
              onWrite: onWrite,
            ),
        ],
      ),
    );
  }
}

class _EnumPicker extends StatelessWidget {
  const _EnumPicker({
    required this.value,
    required this.options,
    required this.hasPending,
    required this.onChanged,
    required this.onWrite,
  });
  final int value;
  final Map<int, String> options;
  final bool hasPending;
  final ValueChanged<int> onChanged;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    // Ensure the current value is selectable even if it is outside the
    // documented enum range reported by the FC.
    final items = Map<int, String>.from(options);
    items.putIfAbsent(value, () => 'Value $value');
    final keys = items.keys.toList()..sort();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasPending)
          IconButton(
            icon: Icon(Icons.check_circle, color: hc.accent, size: 18),
            tooltip: 'Write to FC',
            onPressed: onWrite,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        DropdownButton<int>(
          value: value,
          items: [
            for (final k in keys)
              DropdownMenuItem(value: k, child: Text(items[k]!)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          style: TextStyle(fontSize: 13, color: hc.textPrimary),
          underline: const SizedBox(),
          isDense: true,
          dropdownColor: hc.surface,
        ),
      ],
    );
  }
}

class _NumberEditor extends StatefulWidget {
  const _NumberEditor({
    required this.value,
    required this.unit,
    required this.decimals,
    required this.hasPending,
    required this.onChanged,
    required this.onWrite,
  });
  final double value;
  final String unit;
  final int decimals;
  final bool hasPending;
  final ValueChanged<double> onChanged;
  final VoidCallback onWrite;

  @override
  State<_NumberEditor> createState() => _NumberEditorState();
}

class _NumberEditorState extends State<_NumberEditor> {
  late final TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(_NumberEditor old) {
    super.didUpdateWidget(old);
    if (!_editing && old.value != widget.value) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _fmt(double v) => v.toStringAsFixed(widget.decimals);

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.hasPending)
          IconButton(
            icon: Icon(Icons.check_circle, color: hc.accent, size: 18),
            tooltip: 'Write to FC',
            onPressed: widget.onWrite,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        SizedBox(
          width: 90,
          child: TextField(
            controller: _ctrl,
            style: TextStyle(fontSize: 13, color: hc.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              suffixText: widget.unit.isEmpty ? null : widget.unit,
              suffixStyle: TextStyle(fontSize: 11, color: hc.textTertiary),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: hc.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: hc.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: hc.accent),
              ),
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onTap: () => setState(() => _editing = true),
            onSubmitted: (s) {
              setState(() => _editing = false);
              final v = double.tryParse(s);
              if (v != null) widget.onChanged(v);
            },
            onTapOutside: (_) {
              if (!_editing) return;
              setState(() => _editing = false);
              final v = double.tryParse(_ctrl.text);
              if (v != null) widget.onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

// ─── Shared UI primitives ────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.children,
    this.trailing,
  });
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: hc.textTertiary,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const Spacer(),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: trailing!,
              ),
          ],
        ),
        Container(
          decoration: BoxDecoration(
            color: hc.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: hc.border),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

enum _BannerTone { neutral, accent, success, warning, danger }

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.tone,
    required this.message,
    this.title,
  });
  final IconData icon;
  final _BannerTone tone;
  final String message;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final color = switch (tone) {
      _BannerTone.neutral => hc.textSecondary,
      _BannerTone.accent => hc.accent,
      _BannerTone.success => hc.success,
      _BannerTone.warning => hc.warning,
      _BannerTone.danger => hc.danger,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(title!,
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      )),
                if (title != null) const SizedBox(height: 4),
                Text(message,
                    style: TextStyle(color: hc.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
