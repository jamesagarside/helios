import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/vehicle_state.dart';
import '../../shared/providers/providers.dart';
import '../../shared/providers/theme_mode_provider.dart';
import '../../shared/theme/helios_colors.dart';

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
    (icon: Icons.check_circle_outline, label: 'Pre-Arm'),
    (icon: Icons.security_outlined, label: 'Failsafes'),
    (icon: Icons.settings_remote_outlined, label: 'RC'),
    (icon: Icons.electric_bolt_outlined, label: 'Motors'),
    (icon: Icons.tune_outlined, label: 'Appearance'),
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
                      _PreArmTab(),
                      _FailsafesTab(),
                      _RcTab(),
                      _MotorsTab(),
                      _AppearanceTab(),
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
                      _PreArmTab(),
                      _FailsafesTab(),
                      _RcTab(),
                      _MotorsTab(),
                      _AppearanceTab(),
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

// ─── Pre-Arm Tab ─────────────────────────────────────────────────────────────

class _PreArmTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final connection = ref.watch(connectionStatusProvider);
    final connected = connection.linkState == LinkState.connected ||
        connection.linkState == LinkState.degraded;

    final checks = [
      _PreArmCheck(
        label: 'GPS Fix',
        passed: vehicle.gpsFix == GpsFix.fix3d ||
            vehicle.gpsFix == GpsFix.dgps ||
            vehicle.gpsFix == GpsFix.rtkFloat ||
            vehicle.gpsFix == GpsFix.rtkFixed,
        detail: switch (vehicle.gpsFix) {
          GpsFix.none => 'No GPS signal',
          GpsFix.noFix => 'Searching...',
          GpsFix.fix2d => '2D fix (poor)',
          GpsFix.fix3d => '3D fix — ${vehicle.satellites} sats',
          GpsFix.dgps => 'DGPS — ${vehicle.satellites} sats',
          GpsFix.rtkFloat => 'RTK float — ${vehicle.satellites} sats',
          GpsFix.rtkFixed => 'RTK fixed — ${vehicle.satellites} sats',
        },
      ),
      _PreArmCheck(
        label: 'EKF Status',
        passed: vehicle.ekfVelocityVar < 0.5 &&
            vehicle.ekfPosVertVar < 0.5 &&
            vehicle.ekfCompassVar < 0.5,
        detail: vehicle.ekfVelocityVar < 0.5
            ? 'OK'
            : 'Variance high (vel: ${vehicle.ekfVelocityVar.toStringAsFixed(2)})',
      ),
      _PreArmCheck(
        label: 'Battery',
        passed: vehicle.batteryRemaining > 20 ||
            vehicle.batteryRemaining == -1,
        detail: vehicle.batteryRemaining == -1
            ? 'Unknown'
            : vehicle.batteryVoltage == 0.0
                ? 'Not detected'
                : '${vehicle.batteryVoltage.toStringAsFixed(1)} V — ${vehicle.batteryRemaining}%',
      ),
      _PreArmCheck(
        label: 'Vehicle Disarmed',
        passed: !vehicle.armed,
        detail:
            vehicle.armed ? 'Vehicle is armed' : 'Safe to configure',
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section(
            title: 'PRE-ARM CHECKS',
            children: checks.asMap().entries.map((e) {
              final check = e.value;
              final isLast = e.key == checks.length - 1;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          check.passed
                              ? Icons.check_circle
                              : Icons.cancel,
                          size: 18,
                          color: check.passed
                              ? hc.success
                              : hc.danger,
                        ),
                        const SizedBox(width: 12),
                        Text(check.label,
                            style: TextStyle(
                                fontSize: 13,
                                color: hc.textPrimary)),
                        const Spacer(),
                        Text(
                          check.detail,
                          style: TextStyle(
                            fontSize: 12,
                            color: check.passed
                                ? hc.textSecondary
                                : hc.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast) const _RowDivider(),
                ],
              );
            }).toList(),
          ),
          if (!connected) ...[
            const SizedBox(height: 24),
            const _DisconnectedBanner(),
          ],
        ],
      ),
    );
  }
}

class _PreArmCheck {
  const _PreArmCheck(
      {required this.label, required this.passed, required this.detail});
  final String label;
  final bool passed;
  final String detail;
}

// ─── Failsafes Tab ───────────────────────────────────────────────────────────

class _FailsafesTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Section(
            title: 'FAILSAFE CONFIGURATION',
            children: [
              _InfoRow(label: 'Battery failsafe', value: 'RTL at 10.5V'),
              _RowDivider(),
              _InfoRow(label: 'GCS failsafe', value: 'RTL after 5s'),
              _RowDivider(),
              _InfoRow(label: 'RC failsafe', value: 'RTL after 1s'),
              _RowDivider(),
              _InfoRow(label: 'Geofence failsafe', value: 'RTL'),
            ],
          ),
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
                Icon(Icons.construction_outlined,
                    color: hc.warning, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Failsafe parameter editing coming in Sprint 3. Use the Parameter Editor in Setup for now.',
                    style: TextStyle(
                        color: hc.textSecondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── RC Tab ──────────────────────────────────────────────────────────────────

class _RcTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section(
            title: 'RC CHANNELS',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: vehicle.rssi == 0
                    ? Text('No RC signal detected',
                        style: TextStyle(
                            color: hc.textTertiary, fontSize: 13))
                    : _RcSignalBar(
                        label: 'RSSI',
                        value: vehicle.rssi / 255.0,
                        valueText: '${vehicle.rssi}/255',
                      ),
              ),
            ],
          ),
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
                Icon(Icons.construction_outlined,
                    color: hc.warning, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'RC channel calibration coming in Sprint 3. Live RC values require RC_CHANNELS message subscription.',
                    style: TextStyle(
                        color: hc.textSecondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

class _MotorsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (vehicle.armed)
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: hc.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: hc.danger.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber,
                      color: hc.danger, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Vehicle is armed. Disarm before running motor tests.',
                      style: TextStyle(
                          color: hc.danger,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          _Section(
            title: 'MOTOR TEST',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Motor test allows you to verify each motor spins in the correct direction. '
                      'The vehicle must be disarmed.',
                      style: TextStyle(
                          color: hc.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: hc.warning.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color:
                                hc.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.construction_outlined,
                              color: hc.warning, size: 18),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Motor test commands coming in Sprint 3 (MAV_CMD_DO_MOTOR_TEST).',
                              style: TextStyle(
                                  color: hc.textSecondary,
                                  fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
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

// ─── Appearance Tab ───────────────────────────────────────────────────────────

class _AppearanceTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section(
            title: 'THEME',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      'Colour scheme',
                      style: TextStyle(
                          fontSize: 13,
                          color: context.hc.textSecondary),
                    ),
                    const Spacer(),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined, size: 16),
                          label: Text('Dark'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined, size: 16),
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon:
                              Icon(Icons.brightness_auto_outlined, size: 16),
                          label: Text('Auto'),
                        ),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (modes) => ref
                          .read(themeModeProvider.notifier)
                          .setMode(modes.first),
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
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
