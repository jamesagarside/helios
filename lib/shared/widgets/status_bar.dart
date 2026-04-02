import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../theme/helios_colors.dart';

/// Bottom status bar showing vehicle state summary.
class StatusBar extends ConsumerWidget {
  const StatusBar({
    super.key,
    this.flightMode = 'UNKNOWN',
    this.armed = false,
    this.flightTime = Duration.zero,
    this.messageRate = 0.0,
    this.gpsFixType = 'No Fix',
    this.satellites = 0,
    this.currentWaypoint = -1,
    this.totalWaypoints = 0,
    this.alertCount = 0,
    this.batteryVoltage = 0.0,
    this.batteryRemaining = -1,
    this.homeDistance = 0.0,
    this.hasHome = false,
  });

  final String flightMode;
  final bool armed;
  final Duration flightTime;
  final double messageRate;
  final String gpsFixType;
  final int satellites;
  final int currentWaypoint;
  final int totalWaypoints;
  final int alertCount;
  final double batteryVoltage;
  final int batteryRemaining;   // -1 = unknown
  final double homeDistance;    // metres
  final bool hasHome;

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  Color _gpsColor(HeliosColors hc) {
    if (gpsFixType.contains('RTK')) return hc.success;
    if (gpsFixType.contains('3D') || gpsFixType.contains('DGPS')) {
      return hc.success;
    }
    if (gpsFixType.contains('2D')) return hc.warning;
    return hc.danger;
  }

  Color _linkColor(HeliosColors hc) {
    if (messageRate > 5) return hc.success;
    if (messageRate > 0) return hc.warning;
    return hc.textTertiary;
  }

  Color _batteryColor(HeliosColors hc) {
    if (batteryRemaining < 0) return hc.textTertiary;
    if (batteryRemaining <= 10) return hc.danger;
    if (batteryRemaining <= 25) return hc.warning;
    return hc.success;
  }

  String _batteryLabel() {
    if (batteryRemaining >= 0) {
      return '$batteryRemaining%  ${batteryVoltage.toStringAsFixed(1)}V';
    }
    if (batteryVoltage > 0) return '${batteryVoltage.toStringAsFixed(1)}V';
    return '—';
  }

  String _homeDistLabel() {
    if (!hasHome) return '—';
    if (homeDistance >= 1000) {
      return '${(homeDistance / 1000).toStringAsFixed(1)}km';
    }
    return '${homeDistance.round()}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final alerts = ref.watch(alertHistoryProvider);
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: hc.surfaceLight,
        border: Border(
          top: BorderSide(color: hc.accent, width: 1),
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Armed state — most critical
              _StatusChip(
                icon: armed ? Icons.warning_amber : Icons.shield,
                label: armed ? 'ARMED' : 'DISARMED',
                color: armed ? hc.danger : hc.success,
                bold: true,
              ),
              _Separator(color: hc.border),
              // Flight mode
              _StatusChip(
                icon: Icons.flight,
                label: flightMode,
                color: hc.accent,
              ),
              _Separator(color: hc.border),
              // GPS
              _StatusChip(
                icon: Icons.satellite_alt,
                label: '$gpsFixType  $satellites sats',
                color: _gpsColor(hc),
              ),
              // Mission waypoint
              if (totalWaypoints > 0) ...[
                _Separator(color: hc.border),
                _StatusChip(
                  icon: Icons.route,
                  label: currentWaypoint >= 0
                      ? 'WP ${currentWaypoint + 1}/$totalWaypoints'
                      : '$totalWaypoints WPs',
                  color: currentWaypoint >= 0
                      ? hc.warning
                      : hc.textSecondary,
                ),
              ],
              _Separator(color: hc.border),
              // Flight time
              _StatusChip(
                icon: Icons.timer,
                label: _formatDuration(flightTime),
                color: hc.textPrimary,
                mono: true,
              ),
              _Separator(color: hc.border),
              // Link health
              _StatusChip(
                icon: Icons.cell_tower,
                label: '${messageRate.toStringAsFixed(0)} msg/s',
                color: _linkColor(hc),
                mono: true,
              ),
              // Battery
              _Separator(color: hc.border),
              _StatusChip(
                icon: batteryRemaining > 20 || batteryRemaining < 0
                    ? Icons.battery_full
                    : batteryRemaining > 10
                        ? Icons.battery_3_bar
                        : Icons.battery_alert,
                label: _batteryLabel(),
                color: _batteryColor(hc),
                mono: true,
              ),
              // Home distance
              if (hasHome) ...[
                _Separator(color: hc.border),
                _StatusChip(
                  icon: Icons.home_outlined,
                  label: _homeDistLabel(),
                  color: hc.textPrimary,
                  mono: true,
                ),
              ],
              // STATUSTEXT alert history badge (tappable)
              if (alerts.isNotEmpty) ...[
                _Separator(color: hc.border),
                GestureDetector(
                  onTap: () => _showAlertDrawer(context, alerts),
                  child: _StatusChip(
                    icon: alerts.any((a) => a.severity == AlertSeverity.critical)
                        ? Icons.error_outline
                        : Icons.warning_amber,
                    label: '${alerts.length} msg${alerts.length == 1 ? '' : 's'}',
                    color: alerts.any((a) => a.severity == AlertSeverity.critical)
                        ? hc.danger
                        : hc.warning,
                    bold: true,
                  ),
                ),
              ],
              // Maintenance alerts badge
              if (alertCount > 0) ...[
                _Separator(color: hc.border),
                _StatusChip(
                  icon: Icons.build_outlined,
                  label: '$alertCount alert${alertCount == 1 ? '' : 's'}',
                  color: hc.warning,
                  bold: true,
                ),
              ],
            ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAlertDrawer(BuildContext context, List<AlertEntry> alerts) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
      ),
      builder: (_) => _AlertDrawer(alerts: alerts),
    );
  }
}

class _AlertDrawer extends StatefulWidget {
  const _AlertDrawer({required this.alerts});
  final List<AlertEntry> alerts;

  @override
  State<_AlertDrawer> createState() => _AlertDrawerState();
}

class _AlertDrawerState extends State<_AlertDrawer> {
  AlertSeverity? _filter;

  List<AlertEntry> get _filtered {
    if (_filter == null) return widget.alerts;
    return widget.alerts.where((a) => a.severity == _filter).toList();
  }

  String _formatAll() {
    return _filtered.reversed.map((e) {
      final hh = e.timestamp.hour.toString().padLeft(2, '0');
      final mm = e.timestamp.minute.toString().padLeft(2, '0');
      final ss = e.timestamp.second.toString().padLeft(2, '0');
      final level = switch (e.severity) {
        AlertSeverity.critical => 'ERROR',
        AlertSeverity.warning  => 'WARN ',
        AlertSeverity.info     => 'INFO ',
      };
      return '$hh:$mm:$ss [$level] ${e.message}';
    }).join('\n');
  }

  int _countSeverity(AlertSeverity s) =>
      widget.alerts.where((a) => a.severity == s).length;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final filtered = _filtered;
    final reversed = filtered.reversed.toList();
    return Column(
      children: [
        // Header
        Container(
          height: 48,
          color: hc.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('Flight Messages',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: hc.textPrimary)),
              const Spacer(),
              Text('${reversed.length} / ${widget.alerts.length}',
                  style: TextStyle(fontSize: 12, color: hc.textTertiary)),
              const SizedBox(width: 8),
              _CopyButton(
                tooltip: 'Copy all visible messages',
                textToCopy: _formatAll(),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.of(context).pop(),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        // Severity filter chips
        Container(
          height: 36,
          color: hc.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _FilterChip(
                label: 'All',
                count: widget.alerts.length,
                color: hc.textPrimary,
                active: _filter == null,
                onTap: () => setState(() => _filter = null),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Errors',
                count: _countSeverity(AlertSeverity.critical),
                color: hc.danger,
                active: _filter == AlertSeverity.critical,
                onTap: () => setState(() =>
                    _filter = _filter == AlertSeverity.critical
                        ? null
                        : AlertSeverity.critical),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Warnings',
                count: _countSeverity(AlertSeverity.warning),
                color: hc.warning,
                active: _filter == AlertSeverity.warning,
                onTap: () => setState(() =>
                    _filter = _filter == AlertSeverity.warning
                        ? null
                        : AlertSeverity.warning),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Info',
                count: _countSeverity(AlertSeverity.info),
                color: hc.accent,
                active: _filter == AlertSeverity.info,
                onTap: () => setState(() =>
                    _filter = _filter == AlertSeverity.info
                        ? null
                        : AlertSeverity.info),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: hc.border),
        // Message list
        Expanded(
          child: reversed.isEmpty
              ? Center(
                  child: Text(
                    _filter != null ? 'No messages with this severity' : 'No messages yet',
                    style: TextStyle(fontSize: 12, color: hc.textTertiary),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: reversed.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: hc.border, indent: 16),
                  itemBuilder: (_, i) {
                    final entry = reversed[i];
                    final color = switch (entry.severity) {
                      AlertSeverity.critical => hc.danger,
                      AlertSeverity.warning => hc.warning,
                      AlertSeverity.info => hc.textSecondary,
                    };
                    final icon = switch (entry.severity) {
                      AlertSeverity.critical => Icons.error_outline,
                      AlertSeverity.warning => Icons.warning_amber_outlined,
                      AlertSeverity.info => Icons.info_outline,
                    };
                    final sevLabel = switch (entry.severity) {
                      AlertSeverity.critical => 'ERR',
                      AlertSeverity.warning => 'WRN',
                      AlertSeverity.info => 'INF',
                    };
                    final hh = entry.timestamp.hour.toString().padLeft(2, '0');
                    final mm = entry.timestamp.minute.toString().padLeft(2, '0');
                    final ss = entry.timestamp.second.toString().padLeft(2, '0');
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, size: 16, color: color),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 28,
                            child: Text(
                              sevLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: color,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: SelectableText(
                              entry.message,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: hc.textPrimary,
                                  fontFamily: 'monospace'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text('$hh:$mm:$ss',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: hc.textTertiary,
                                  fontFamily: 'monospace')),
                          const SizedBox(width: 4),
                          _CopyButton(
                            tooltip: 'Copy message',
                            textToCopy:
                                '$hh:$mm:$ss [$sevLabel] ${entry.message}',
                            size: 14,
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? color : hc.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: active ? color : hc.textTertiary,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  color: active ? color : hc.textTertiary,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({
    required this.tooltip,
    required this.textToCopy,
    this.size = 16,
  });

  final String tooltip;
  final String textToCopy;
  final double size;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.textToCopy));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Tooltip(
      message: widget.tooltip,
      child: InkWell(
        onTap: _copy,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            _copied ? Icons.check : Icons.copy_outlined,
            size: widget.size,
            color: _copied ? hc.success : hc.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
    this.bold = false,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool bold;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            fontFamily: mono ? 'monospace' : null,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        height: 16,
        child: VerticalDivider(
          width: 1,
          color: color,
        ),
      ),
    );
  }
}
