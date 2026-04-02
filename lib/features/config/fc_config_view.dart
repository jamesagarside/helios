import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/params/parameter_service.dart';
import '../../shared/models/vehicle_state.dart';
import '../../shared/providers/providers.dart';
import '../../shared/theme/helios_colors.dart';
import '../setup/widgets/calibration_wizard.dart';
import '../setup/widgets/failsafe_panel.dart';
import '../setup/widgets/frame_type_panel.dart';
import '../setup/widgets/motor_test_panel.dart';
import '../setup/widgets/parameter_editor.dart';
import '../setup/widgets/prearm_panel.dart';

class FcConfigView extends ConsumerStatefulWidget {
  const FcConfigView({super.key});

  @override
  ConsumerState<FcConfigView> createState() => _FcConfigViewState();
}

class _FcConfigViewState extends ConsumerState<FcConfigView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = [
    (icon: Icons.info_outline, label: 'Firmware'),
    (icon: Icons.sensors_outlined, label: 'Calibration'),
    (icon: Icons.shield_outlined, label: 'Safety'),
    (icon: Icons.grid_view_outlined, label: 'Frame'),
    (icon: Icons.propane_outlined, label: 'Motors'),
    (icon: Icons.settings_remote_outlined, label: 'RC'),
    (icon: Icons.checklist_outlined, label: 'Pre-Arm'),
    (icon: Icons.list_alt_outlined, label: 'Parameters'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;

    return Scaffold(
      backgroundColor: hc.background,
      body: isDesktop
          ? Row(
              children: [
                // Vertical tab list
                Container(
                  width: 160,
                  color: hc.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: Text(
                          'FC Config',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: hc.textTertiary,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListenableBuilder(
                          listenable: _tabController,
                          builder: (_, _) {
                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: _tabs.length,
                              itemBuilder: (_, i) {
                                final tab = _tabs[i];
                                return _SidebarTabItem(
                                  icon: tab.icon,
                                  label: tab.label,
                                  selected: _tabController.index == i,
                                  onTap: () => _tabController.animateTo(i),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                VerticalDivider(
                    width: 1, thickness: 1, color: hc.border),
                // Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _FirmwareTab(),
                      const CalibrationWizard(),
                      const FailsafePanel(),
                      const FrameTypePanel(),
                      const MotorTestPanel(),
                      _RcTab(),
                      const PreArmPanel(),
                      _ParametersTab(),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              children: [
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: hc.accent,
                  unselectedLabelColor: hc.textSecondary,
                  indicatorColor: hc.accent,
                  tabs: _tabs
                      .map((t) => Tab(
                          icon: Icon(t.icon, size: 18), text: t.label))
                      .toList(),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _FirmwareTab(),
                      const CalibrationWizard(),
                      const FailsafePanel(),
                      const FrameTypePanel(),
                      const MotorTestPanel(),
                      _RcTab(),
                      const PreArmPanel(),
                      _ParametersTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SidebarTabItem extends StatelessWidget {
  const _SidebarTabItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? hc.accent.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(icon,
                    size: 16,
                    color: selected
                        ? hc.accent
                        : hc.textSecondary),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? hc.accent
                        : hc.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Section helpers ────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: hc.textSecondary)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: valueColor ?? hc.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
        height: 1,
        thickness: 1,
        color: context.hc.border,
        indent: 16,
        endIndent: 0);
  }
}

// ─── Firmware Tab ────────────────────────────────────────────────────────────

class _FirmwareTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          _Section(
            title: 'AUTOPILOT',
            children: [
              _InfoRow(
                label: 'Firmware',
                value: vehicle.firmwareVersionString.isEmpty
                    ? (connected ? 'Detecting...' : 'Not connected')
                    : vehicle.firmwareVersionString,
              ),
              const _RowDivider(),
              _InfoRow(
                label: 'Autopilot',
                value: switch (vehicle.autopilotType) {
                  AutopilotType.ardupilot => 'ArduPilot',
                  AutopilotType.px4 => 'PX4',
                  AutopilotType.betaflight => 'Betaflight',
                  AutopilotType.inav => 'iNav',
                  AutopilotType.unknown => 'Unknown',
                },
              ),
              const _RowDivider(),
              _InfoRow(
                label: 'Vehicle type',
                value: switch (vehicle.vehicleType) {
                  VehicleType.fixedWing => 'Fixed Wing',
                  VehicleType.quadrotor => 'Quadrotor',
                  VehicleType.vtol => 'VTOL',
                  VehicleType.helicopter => 'Helicopter',
                  VehicleType.rover => 'Rover',
                  VehicleType.boat => 'Boat',
                  VehicleType.unknown => 'Unknown',
                },
              ),
              const _RowDivider(),
              _InfoRow(
                label: 'System ID',
                value: vehicle.systemId == 0 ? '—' : '${vehicle.systemId}',
              ),
              const _RowDivider(),
              _InfoRow(
                label: 'Component ID',
                value: vehicle.componentId == 0
                    ? '—'
                    : '${vehicle.componentId}',
              ),
            ],
          ),
          const SizedBox(height: 24),
          _Section(
            title: 'LINK STATUS',
            children: [
              _InfoRow(
                label: 'Link state',
                value: switch (connection.linkState) {
                  LinkState.connected => 'Connected',
                  LinkState.degraded => 'Degraded',
                  LinkState.lost => 'Lost',
                  LinkState.disconnected => 'Disconnected',
                },
                valueColor: switch (connection.linkState) {
                  LinkState.connected => hc.success,
                  LinkState.degraded => hc.warning,
                  LinkState.lost ||
                  LinkState.disconnected =>
                    hc.danger,
                },
              ),
              const _RowDivider(),
              _InfoRow(
                label: 'Message rate',
                value:
                    '${connection.messageRate.toStringAsFixed(0)} msg/s',
              ),
              const _RowDivider(),
              _InfoRow(
                label: 'RSSI',
                value: vehicle.rssi == 0 ? '—' : '${vehicle.rssi} dBm',
              ),
            ],
          ),
          if (!connected) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: hc.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: hc.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: hc.warning, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Connect to a vehicle in the Setup tab to see firmware details.',
                      style: TextStyle(
                          color: hc.textSecondary, fontSize: 13),
                    ),
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

// ─── Failsafes Tab ───────────────────────────────────────────────────────────

/// Failsafe parameters we expose for editing.
/// Each entry: (paramId, label, unit, isEnum, enumOptions)
const _kFailsafeParams = [
  _FsParam('FS_BATT_ENABLE',   'Battery failsafe action', '', true,
      {0: 'Disabled', 1: 'Land', 2: 'RTL', 3: 'SmartRTL', 4: 'SmartRTL/RTL', 5: 'Terminate'}),
  _FsParam('FS_BATT_VOLTAGE',  'Battery failsafe voltage', 'V', false, {}),
  _FsParam('FS_BATT_MAH',      'Battery failsafe mAh', 'mAh', false, {}),
  _FsParam('FS_GCS_ENABLE',    'GCS failsafe action', '', true,
      {0: 'Disabled', 1: 'RTL', 2: 'SmartRTL', 3: 'SmartRTL/RTL', 4: 'Land', 5: 'SmartRTL/Land'}),
  _FsParam('FS_LONG_TIMEOUT',  'GCS long timeout', 's', false, {}),
  _FsParam('FS_THR_ENABLE',    'RC throttle failsafe', '', true,
      {0: 'Disabled', 1: 'Enabled (always)', 2: 'Enabled (continue if auto)'}),
  _FsParam('FS_THR_VALUE',     'RC failsafe PWM threshold', 'µs', false, {}),
  _FsParam('FENCE_ACTION',     'Geofence action', '', true,
      {0: 'Report only', 1: 'RTL or Land', 2: 'Always Land', 3: 'SmartRTL', 4: 'Brake'}),
];

class _FsParam {
  const _FsParam(this.id, this.label, this.unit, this.isEnum, this.options);
  final String id;
  final String label;
  final String unit;
  final bool isEnum;
  final Map<int, String> options;
}

class _FailsafesTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_FailsafesTab> createState() => _FailsafesTabState();
}

class _FailsafesTabState extends ConsumerState<_FailsafesTab> {
  Map<String, Parameter> _params = {};
  bool _loading = false;
  String? _error;
  final _pending = <String, double>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final svc = ref.read(connectionControllerProvider.notifier).paramService;
    if (svc == null) return;
    final vehicle = ref.read(vehicleStateProvider);
    setState(() { _loading = true; _error = null; });
    try {
      final all = await svc.fetchAll(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
      );
      if (mounted) {
        setState(() {
          _params = {
            for (final p in _kFailsafeParams)
              if (all.containsKey(p.id)) p.id: all[p.id]!,
          };
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _write(String paramId, double value) async {
    final svc = ref.read(connectionControllerProvider.notifier).paramService;
    if (svc == null) return;
    final vehicle = ref.read(vehicleStateProvider);
    try {
      final confirmed = await svc.setParam(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
        paramId: paramId,
        value: value,
        paramType: _params[paramId]?.type ?? 9,
      );
      if (mounted) {
        setState(() {
          _params[paramId] = _params[paramId]!.copyWith(value: confirmed);
          _pending.remove(paramId);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to write $paramId: $e'),
            backgroundColor: context.hc.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final connection = ref.watch(connectionStatusProvider);
    final connected = connection.linkState == LinkState.connected ||
        connection.linkState == LinkState.degraded;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!connected) ...[
            const _DisconnectedBanner(),
            const SizedBox(height: 24),
          ],
          Row(
            children: [
              Text('FAILSAFE CONFIGURATION',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: hc.textTertiary,
                      letterSpacing: 0.6)),
              const Spacer(),
              if (_pending.isNotEmpty)
                FilledButton.tonal(
                  onPressed: () async {
                    for (final e in Map.of(_pending).entries) {
                      await _write(e.key, e.value);
                    }
                  },
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text('Write ${_pending.length} change${_pending.length > 1 ? 's' : ''}'),
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Reload parameters',
                onPressed: connected ? _load : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ))
          else if (_error != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: hc.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: hc.danger.withValues(alpha: 0.3)),
              ),
              child: Text(_error!, style: TextStyle(color: hc.danger, fontSize: 13)),
            )
          else if (_params.isEmpty && connected)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No failsafe parameters loaded. Tap refresh.',
                    style: TextStyle(color: hc.textTertiary, fontSize: 13)),
              ),
            )
          else ...[
            Container(
              decoration: BoxDecoration(
                color: hc.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: hc.border),
              ),
              child: Column(
                children: _kFailsafeParams.asMap().entries.map((e) {
                  final meta = e.value;
                  final param = _params[meta.id];
                  final isLast = e.key == _kFailsafeParams.length - 1;
                  final pendingVal = _pending[meta.id];
                  final displayVal = pendingVal ?? param?.value;

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(meta.label,
                                      style: TextStyle(fontSize: 13, color: hc.textPrimary)),
                                  Text(meta.id,
                                      style: TextStyle(fontSize: 11, color: hc.textTertiary,
                                          fontFamily: 'monospace')),
                                ],
                              ),
                            ),
                            if (param == null)
                              Text('—', style: TextStyle(color: hc.textTertiary, fontSize: 13))
                            else if (meta.isEnum)
                              _FsEnumPicker(
                                value: (displayVal ?? param.value).round(),
                                options: meta.options,
                                hasPendingChange: pendingVal != null,
                                onChanged: (v) => setState(() => _pending[meta.id] = v.toDouble()),
                                onWrite: () => _write(meta.id, (displayVal ?? param.value)),
                              )
                            else
                              _FsValueEditor(
                                value: displayVal ?? param.value,
                                unit: meta.unit,
                                hasPendingChange: pendingVal != null,
                                onChanged: (v) => setState(() => _pending[meta.id] = v),
                                onWrite: () => _write(meta.id, displayVal ?? param.value),
                              ),
                          ],
                        ),
                      ),
                      if (!isLast) const _RowDivider(),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FsEnumPicker extends StatelessWidget {
  const _FsEnumPicker({
    required this.value,
    required this.options,
    required this.hasPendingChange,
    required this.onChanged,
    required this.onWrite,
  });
  final int value;
  final Map<int, String> options;
  final bool hasPendingChange;
  final ValueChanged<int> onChanged;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasPendingChange)
          IconButton(
            icon: Icon(Icons.check_circle, color: hc.accent, size: 18),
            tooltip: 'Write to FC',
            onPressed: onWrite,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        DropdownButton<int>(
          value: options.containsKey(value) ? value : options.keys.first,
          items: options.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
          style: TextStyle(fontSize: 13, color: hc.textPrimary),
          underline: const SizedBox(),
          isDense: true,
          dropdownColor: hc.surface,
        ),
      ],
    );
  }
}

class _FsValueEditor extends StatefulWidget {
  const _FsValueEditor({
    required this.value,
    required this.unit,
    required this.hasPendingChange,
    required this.onChanged,
    required this.onWrite,
  });
  final double value;
  final String unit;
  final bool hasPendingChange;
  final ValueChanged<double> onChanged;
  final VoidCallback onWrite;

  @override
  State<_FsValueEditor> createState() => _FsValueEditorState();
}

class _FsValueEditorState extends State<_FsValueEditor> {
  late final TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(_FsValueEditor old) {
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

  String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.hasPendingChange)
          IconButton(
            icon: Icon(Icons.check_circle, color: hc.accent, size: 18),
            tooltip: 'Write to FC',
            onPressed: widget.onWrite,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        SizedBox(
          width: 80,
          child: TextField(
            controller: _ctrl,
            style: TextStyle(fontSize: 13, color: hc.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              suffixText: widget.unit,
              suffixStyle: TextStyle(fontSize: 11, color: hc.textTertiary),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onTap: () => setState(() => _editing = true),
            onSubmitted: (s) {
              setState(() => _editing = false);
              final v = double.tryParse(s);
              if (v != null) widget.onChanged(v);
            },
            onTapOutside: (_) {
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

// ─── RC Tab ──────────────────────────────────────────────────────────────────

class _RcTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final channels = vehicle.rcChannels;
    final count = vehicle.rcChannelCount;
    final hasSignal = count > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section(
            title: 'SIGNAL',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: hasSignal
                    ? _RcSignalBar(
                        label: 'RSSI',
                        value: vehicle.rssi / 255.0,
                        valueText: '${vehicle.rssi}/255',
                      )
                    : Text('No RC signal detected',
                        style: TextStyle(color: hc.textTertiary, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _Section(
            title: 'CHANNELS ($count active)',
            children: [
              if (!hasSignal)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Connect and arm RC transmitter to see live values.',
                      style: TextStyle(color: hc.textTertiary, fontSize: 13)),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      for (int i = 0; i < count && i < channels.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _RcChannelRow(
                          channelNum: i + 1,
                          pwm: channels[i],
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RcChannelRow extends StatelessWidget {
  const _RcChannelRow({required this.channelNum, required this.pwm});
  final int channelNum;
  final int pwm;

  static const _kMin = 1000;
  static const _kMax = 2000;

  // 0 means channel not connected in MAVLink spec
  bool get _active => pwm >= 900 && pwm <= 2200;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final normalised = _active
        ? ((pwm - _kMin) / (_kMax - _kMin)).clamp(0.0, 1.0)
        : 0.0;

    Color barColor;
    if (!_active) {
      barColor = hc.textTertiary;
    } else if (normalised < 0.15 || normalised > 0.85) {
      barColor = hc.warning;
    } else {
      barColor = hc.accent;
    }

    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text('CH$channelNum',
              style: TextStyle(fontSize: 11, color: hc.textTertiary,
                  fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: normalised,
              backgroundColor: hc.surfaceDim,
              color: barColor,
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 50,
          child: Text(
            _active ? '$pwm µs' : '—',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: hc.textSecondary,
                fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}

class _RcSignalBar extends StatelessWidget {
  const _RcSignalBar(
      {required this.label,
      required this.value,
      required this.valueText});
  final String label;
  final double value;
  final String valueText;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, color: hc.textSecondary)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              backgroundColor: hc.surfaceDim,
              color: hc.accent,
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(valueText,
            style: TextStyle(
                fontSize: 12, color: hc.textTertiary)),
      ],
    );
  }
}

// ─── Motors Tab ──────────────────────────────────────────────────────────────

class _MotorsTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_MotorsTab> createState() => _MotorsTabState();
}

class _MotorsTabState extends ConsumerState<_MotorsTab> {
  double _throttle = 5.0; // percent — low default for safety
  int? _runningMotor;
  bool _testing = false;

  Future<void> _runMotor(int motorIndex) async {
    if (_testing) return;
    setState(() { _runningMotor = motorIndex; _testing = true; });
    try {
      await ref.read(connectionControllerProvider.notifier).testMotor(
        motorIndex: motorIndex,
        throttlePct: _throttle,
        durationSec: 2.0,
      );
    } finally {
      if (mounted) {
        // Give a brief visual indication then clear
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) setState(() { _runningMotor = null; _testing = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final connection = ref.watch(connectionStatusProvider);
    final connected = connection.linkState == LinkState.connected ||
        connection.linkState == LinkState.degraded;
    final canTest = connected && !vehicle.armed;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Armed warning
          if (vehicle.armed)
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: hc.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: hc.danger.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: hc.danger, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Vehicle is armed — disarm before running motor tests.',
                      style: TextStyle(color: hc.danger, fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          if (!connected)
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              child: const _DisconnectedBanner(),
            ),

          // Throttle control
          _Section(
            title: 'TEST THROTTLE',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Text('${_throttle.round()}%',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: _throttle > 30 ? hc.warning : hc.textPrimary,
                            fontFamily: 'monospace')),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Slider(
                        value: _throttle,
                        min: 0,
                        max: 100,
                        divisions: 20,
                        activeColor: _throttle > 30 ? hc.warning : hc.accent,
                        onChanged: canTest ? (v) => setState(() => _throttle = v) : null,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Keep throttle low (5–15%) for direction checks. '
                  'Each motor runs for 2 seconds then stops automatically.',
                  style: TextStyle(color: hc.textTertiary, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Motor buttons
          _Section(
            title: 'MOTORS',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(8, (i) {
                    final motorNum = i + 1;
                    final isRunning = _runningMotor == motorNum;
                    return _MotorButton(
                      motorNum: motorNum,
                      isRunning: isRunning,
                      enabled: canTest && !_testing,
                      onPressed: () => _runMotor(motorNum),
                    );
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MotorButton extends StatelessWidget {
  const _MotorButton({
    required this.motorNum,
    required this.isRunning,
    required this.enabled,
    required this.onPressed,
  });
  final int motorNum;
  final bool isRunning;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: isRunning
            ? hc.accent.withValues(alpha: 0.15)
            : hc.surfaceDim,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRunning ? hc.accent : hc.border,
          width: isRunning ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onPressed : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.rotate_right,
                size: 22,
                color: isRunning
                    ? hc.accent
                    : enabled
                        ? hc.textSecondary
                        : hc.textTertiary,
              ),
              const SizedBox(height: 4),
              Text(
                'M$motorNum',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isRunning
                      ? hc.accent
                      : enabled
                          ? hc.textPrimary
                          : hc.textTertiary,
                ),
              ),
              if (isRunning)
                Text('running',
                    style: TextStyle(fontSize: 9, color: hc.accent)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Parameters Tab ──────────────────────────────────────────────────────────

class _ParametersTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ParameterEditor();
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _DisconnectedBanner extends StatelessWidget {
  const _DisconnectedBanner();

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hc.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: hc.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: hc.warning, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Connect to a vehicle in the Setup tab to see live data.',
              style:
                  TextStyle(color: hc.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
