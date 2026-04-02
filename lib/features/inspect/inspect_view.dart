import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../shared/providers/providers.dart';
import '../../shared/theme/helios_colors.dart';
import '../../shared/theme/helios_typography.dart';
import 'widgets/mavlink_terminal.dart';

/// MAVLink Inspector + Terminal — tabbed view with live packet log and
/// interactive MAVLink command console.
class InspectView extends ConsumerStatefulWidget {
  const InspectView({super.key});

  @override
  ConsumerState<InspectView> createState() => _InspectViewState();
}

class _InspectViewState extends ConsumerState<InspectView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _filterController = TextEditingController();
  String _filter = '';
  String? _selectedType;
  AlertSeverity? _severityFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Modifying a provider in initState is disallowed during the build phase.
    // Deferring to the next microtask avoids the Riverpod assertion.
    Future(() {
      if (mounted) ref.read(inspectorActiveProvider.notifier).state = true;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    // Stop the inspector flush timer AND gate flag synchronously.
    ref.read(mavlinkInspectorProvider.notifier).stopTimer();
    ref.read(inspectorActiveProvider.notifier).state = false;
    _filterController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    return Column(
      children: [
        // Tab bar
        Container(
          height: 36,
          color: hc.surface,
          child: TabBar(
            controller: _tabController,
            labelColor: hc.accent,
            unselectedLabelColor: hc.textTertiary,
            indicatorColor: hc.accent,
            indicatorWeight: 2,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 12),
            tabs: const [
              Tab(text: 'Inspector'),
              Tab(text: 'Terminal'),
            ],
          ),
        ),
        Divider(height: 1, color: hc.border),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _InspectorTab(
                filter: _filter,
                selectedType: _selectedType,
                severityFilter: _severityFilter,
                filterController: _filterController,
                onFilterChanged: (v) => setState(() => _filter = v),
                onFilterCleared: () {
                  _filterController.clear();
                  setState(() => _filter = '');
                },
                onTypeToggled: (name) =>
                    setState(() => _selectedType = _selectedType == name ? null : name),
                onSeverityChanged: (s) => setState(() => _severityFilter = s),
              ),
              const MavlinkTerminal(),
            ],
          ),
        ),
      ],
    );
  }
}

/// The original inspector content, extracted to its own widget.
class _InspectorTab extends ConsumerWidget {
  const _InspectorTab({
    required this.filter,
    required this.selectedType,
    required this.severityFilter,
    required this.filterController,
    required this.onFilterChanged,
    required this.onFilterCleared,
    required this.onTypeToggled,
    required this.onSeverityChanged,
  });

  final String filter;
  final String? selectedType;
  final AlertSeverity? severityFilter;
  final TextEditingController filterController;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onFilterCleared;
  final ValueChanged<String> onTypeToggled;
  final ValueChanged<AlertSeverity?> onSeverityChanged;

  Future<void> _exportLog(BuildContext context, List<MavlinkPacketEntry> packets) async {
    if (packets.isEmpty) return;
    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final fname =
        'helios_inspect_${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}.txt';
    final path = p.join(dir.path, fname);

    final buf = StringBuffer()
      ..writeln('# Helios MAVLink Inspector Export')
      ..writeln('# Exported: $now')
      ..writeln('# Packets: ${packets.length}')
      ..writeln('#')
      ..writeln('# TIME           ID     NAME                            SYS/CMP  BYTES');

    for (final pk in packets) {
      final t =
          '${pk.timestamp.hour.toString().padLeft(2, '0')}:'
          '${pk.timestamp.minute.toString().padLeft(2, '0')}:'
          '${pk.timestamp.second.toString().padLeft(2, '0')}.'
          '${(pk.timestamp.millisecond ~/ 10).toString().padLeft(2, '0')}';
      buf.writeln(
        '$t  ${pk.msgId.toString().padLeft(5)}  '
        '${pk.msgName.padRight(32)}  '
        '${pk.systemId}/${pk.componentId}     '
        '${pk.payloadLength}',
      );
    }

    await File(path).writeAsString(buf.toString());

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved $fname'),
          backgroundColor: context.hc.success,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final packets = ref.watch(mavlinkInspectorProvider);
    final notifier = ref.read(mavlinkInspectorProvider.notifier);
    final isPaused = ref.watch(inspectorPausedProvider);

    // Apply text + type + severity filters
    final filtered = packets.where((pk) {
      final textMatch = filter.isEmpty ||
          pk.msgName.toLowerCase().contains(filter.toLowerCase()) ||
          pk.msgId.toString().contains(filter);
      final typeMatch = selectedType == null || pk.msgName == selectedType;
      final severityMatch =
          severityFilter == null || pk.severity == severityFilter;
      return textMatch && typeMatch && severityMatch;
    }).toList();

    // Count per type for the stats panel — sorted alphabetically so the sidebar
    // never reorders as counts change.
    final typeCounts = <String, int>{};
    for (final pk in packets) {
      typeCounts[pk.msgName] = (typeCounts[pk.msgName] ?? 0) + 1;
    }
    final sortedTypes = typeCounts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key)); // alphabetical, not by count

    return Column(
      children: [
        // ── Toolbar ───────────────────────────────────────────────────────────
        Container(
          height: 44,
          color: hc.surface,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // Filter field
              SizedBox(
                width: 220,
                height: 30,
                child: TextField(
                  controller: filterController,
                  style: TextStyle(fontSize: 13, color: hc.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Filter by name or ID…',
                    hintStyle: TextStyle(fontSize: 12, color: hc.textTertiary),
                    prefixIcon:
                        Icon(Icons.search, size: 16, color: hc.textTertiary),
                    suffixIcon: filter.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear,
                                size: 14, color: hc.textTertiary),
                            onPressed: onFilterCleared,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 24, minHeight: 24),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: hc.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: hc.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: hc.accent),
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  onChanged: onFilterChanged,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${filtered.length} / ${packets.length} packets',
                style:
                    HeliosTypography.caption.copyWith(color: hc.textTertiary),
              ),
              const SizedBox(width: 12),
              // Severity chips
              _SeverityChip(
                label: 'Errors',
                color: hc.danger,
                active: severityFilter == AlertSeverity.critical,
                onTap: () => onSeverityChanged(
                    severityFilter == AlertSeverity.critical
                        ? null
                        : AlertSeverity.critical),
              ),
              const SizedBox(width: 4),
              _SeverityChip(
                label: 'Warnings',
                color: hc.warning,
                active: severityFilter == AlertSeverity.warning,
                onTap: () => onSeverityChanged(
                    severityFilter == AlertSeverity.warning
                        ? null
                        : AlertSeverity.warning),
              ),
              const SizedBox(width: 4),
              _SeverityChip(
                label: 'Info',
                color: hc.accent,
                active: severityFilter == AlertSeverity.info,
                onTap: () => onSeverityChanged(
                    severityFilter == AlertSeverity.info
                        ? null
                        : AlertSeverity.info),
              ),
              const Spacer(),
              // Export
              if (filtered.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: () => _exportLog(context, filtered),
                  icon: Icon(Icons.download, size: 15, color: hc.textSecondary),
                  label: Text('Export',
                      style:
                          TextStyle(fontSize: 12, color: hc.textSecondary)),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 4),
                // Copy all visible
                _CopyAllButton(packets: filtered),
                const SizedBox(width: 8),
              ],
              // Pause / Resume
              TextButton.icon(
                onPressed: () {
                  if (isPaused) {
                    notifier.resume();
                    ref.read(inspectorPausedProvider.notifier).state = false;
                  } else {
                    notifier.pause();
                    ref.read(inspectorPausedProvider.notifier).state = true;
                  }
                },
                icon: Icon(
                  isPaused ? Icons.play_arrow : Icons.pause,
                  size: 16,
                  color: isPaused ? hc.success : hc.warning,
                ),
                label: Text(
                  isPaused ? 'Resume' : 'Pause',
                  style: TextStyle(
                    fontSize: 12,
                    color: isPaused ? hc.success : hc.warning,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              // Clear
              TextButton.icon(
                onPressed: () => notifier.clear(),
                icon: Icon(Icons.delete_outline,
                    size: 16, color: hc.textSecondary),
                label: Text('Clear',
                    style:
                        TextStyle(fontSize: 12, color: hc.textSecondary)),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: hc.border),

        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Main packet list
              Expanded(
                flex: 3,
                child: packets.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cable_outlined,
                                size: 48, color: hc.textTertiary),
                            const SizedBox(height: 12),
                            Text(
                              'No MAVLink packets yet',
                              style: TextStyle(
                                  color: hc.textTertiary, fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Connect to a vehicle to see live message traffic',
                              style: TextStyle(
                                  color: hc.textTertiary, fontSize: 11),
                            ),
                          ],
                        ),
                      )
                    : _PacketTable(packets: filtered),
              ),

              VerticalDivider(width: 1, color: hc.border),

              // Stats panel
              SizedBox(
                width: 220,
                child: _StatsPanel(
                  sortedTypes: sortedTypes,
                  total: packets.length,
                  selectedType: selectedType,
                  onTap: onTypeToggled,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Copy-all button (toolbar)
// ---------------------------------------------------------------------------

class _CopyAllButton extends StatefulWidget {
  const _CopyAllButton({required this.packets});
  final List<MavlinkPacketEntry> packets;

  @override
  State<_CopyAllButton> createState() => _CopyAllButtonState();
}

class _CopyAllButtonState extends State<_CopyAllButton> {
  bool _copied = false;

  Future<void> _copy() async {
    final buf = StringBuffer();
    for (final pk in widget.packets) {
      final t =
          '${pk.timestamp.hour.toString().padLeft(2, '0')}:'
          '${pk.timestamp.minute.toString().padLeft(2, '0')}:'
          '${pk.timestamp.second.toString().padLeft(2, '0')}.'
          '${(pk.timestamp.millisecond ~/ 10).toString().padLeft(2, '0')}';
      buf.writeln('$t  ${pk.msgId.toString().padLeft(5)}  ${pk.msgName}  '
          '${pk.systemId}/${pk.componentId}  ${pk.payloadLength}B');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Tooltip(
      message: 'Copy all visible packets',
      child: InkWell(
        onTap: _copy,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            _copied ? Icons.check : Icons.copy_outlined,
            size: 15,
            color: _copied ? hc.success : hc.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Packet table
// ---------------------------------------------------------------------------

class _PacketTable extends ConsumerStatefulWidget {
  const _PacketTable({required this.packets});

  final List<MavlinkPacketEntry> packets;

  @override
  ConsumerState<_PacketTable> createState() => _PacketTableState();
}

class _PacketTableState extends ConsumerState<_PacketTable> {
  final _scrollController = ScrollController();
  bool _tailing = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 24;
    if (_tailing != atBottom) {
      setState(() => _tailing = atBottom);
      // Scrolling away from bottom auto-pauses capture so the buffer and
      // sidebar freeze while the user browses.
      if (!atBottom) {
        ref.read(mavlinkInspectorProvider.notifier).pause();
      }
      // Scrolling back to the bottom is handled by _scrollToBottom (the FAB),
      // which also resumes capture.
    }
  }

  @override
  void didUpdateWidget(_PacketTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_tailing && !identical(widget.packets, oldWidget.packets)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    setState(() => _tailing = true);
    // Resume capture when the user deliberately scrolls back to live view.
    ref.read(mavlinkInspectorProvider.notifier).resume();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _copyRow(BuildContext context, MavlinkPacketEntry pk) {
    final t =
        '${pk.timestamp.hour.toString().padLeft(2, '0')}:'
        '${pk.timestamp.minute.toString().padLeft(2, '0')}:'
        '${pk.timestamp.second.toString().padLeft(2, '0')}.'
        '${(pk.timestamp.millisecond ~/ 10).toString().padLeft(2, '0')}';
    final text =
        '$t  ${pk.msgId}  ${pk.msgName}  '
        '${pk.systemId}/${pk.componentId}  ${pk.payloadLength}B';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied: ${pk.msgName}'),
        duration: const Duration(seconds: 1),
        backgroundColor: context.hc.surface,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          itemCount: widget.packets.length,
          itemBuilder: (context, i) {
            final pk = widget.packets[i];
            final timeStr =
                '${pk.timestamp.hour.toString().padLeft(2, '0')}:'
                '${pk.timestamp.minute.toString().padLeft(2, '0')}:'
                '${pk.timestamp.second.toString().padLeft(2, '0')}.'
                '${(pk.timestamp.millisecond ~/ 10).toString().padLeft(2, '0')}';

            final rowColor = i.isEven ? hc.background : hc.surface;

            return InkWell(
              onTap: () => _copyRow(context, pk),
              child: Container(
                height: 24,
                color: rowColor,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    // Timestamp
                    SizedBox(
                      width: 88,
                      child: Text(
                        timeStr,
                        style: HeliosTypography.sqlEditor.copyWith(
                            fontSize: 11, color: hc.textTertiary),
                      ),
                    ),
                    // Msg ID
                    SizedBox(
                      width: 48,
                      child: Text(
                        pk.msgId.toString(),
                        style: HeliosTypography.sqlEditor.copyWith(
                            fontSize: 11, color: hc.textSecondary),
                      ),
                    ),
                    // Msg name
                    Expanded(
                      child: Text(
                        pk.msgName,
                        style: HeliosTypography.sqlEditor.copyWith(
                          fontSize: 11,
                          color: _nameColor(context, pk.msgName),
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Sys/Comp
                    SizedBox(
                      width: 52,
                      child: Text(
                        '${pk.systemId}/${pk.componentId}',
                        style: HeliosTypography.sqlEditor.copyWith(
                            fontSize: 11, color: hc.textTertiary),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    // Bytes
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${pk.payloadLength}B',
                        style: HeliosTypography.sqlEditor.copyWith(
                            fontSize: 11, color: hc.textTertiary),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // Scroll to bottom / resume FAB
        if (!_tailing)
          Positioned(
            bottom: 12,
            right: 12,
            child: ElevatedButton.icon(
              onPressed: _scrollToBottom,
              icon: const Icon(Icons.arrow_downward, size: 14),
              label: const Text('Resume live'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 12),
                backgroundColor: context.hc.surface,
                foregroundColor: context.hc.textPrimary,
                side: BorderSide(color: context.hc.border),
                elevation: 2,
              ),
            ),
          ),
      ],
    );
  }

  Color _nameColor(BuildContext context, String name) {
    final hc = context.hc;
    return switch (name) {
      'HEARTBEAT' => hc.success,
      'ATTITUDE' ||
      'GLOBAL_POSITION_INT' ||
      'GPS_RAW_INT' ||
      'VFR_HUD' =>
        hc.accent,
      'STATUSTEXT' || 'COMMAND_ACK' => hc.warning,
      'SYS_STATUS' || 'EKF_STATUS_REPORT' => hc.accentDim,
      _ when name.startsWith('MISSION_') => hc.textSecondary,
      _ when name.startsWith('PARAM_') => hc.textSecondary,
      _ => hc.textPrimary,
    };
  }
}

// ---------------------------------------------------------------------------
// Stats panel — message type frequency (sorted alphabetically)
// ---------------------------------------------------------------------------

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({
    required this.sortedTypes,
    required this.total,
    required this.selectedType,
    required this.onTap,
  });

  final List<MapEntry<String, int>> sortedTypes;
  final int total;
  final String? selectedType;
  final void Function(String name) onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: hc.surface,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Message Types (${sortedTypes.length})',
                  style: HeliosTypography.caption,
                ),
              ),
              if (selectedType != null)
                GestureDetector(
                  onTap: () => onTap(selectedType!),
                  child:
                      Icon(Icons.filter_alt_off, size: 14, color: hc.accent),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: hc.border),
        Expanded(
          child: ListView.builder(
            itemCount: sortedTypes.length,
            itemBuilder: (context, i) {
              final entry = sortedTypes[i];
              final pct = total > 0 ? entry.value / total : 0.0;
              final isSelected = entry.key == selectedType;

              return InkWell(
                onTap: () => onTap(entry.key),
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color:
                      isSelected ? hc.accent.withValues(alpha: 0.15) : null,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected ? hc.accent : hc.textPrimary,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Mini bar (width tracks proportion, doesn't sort)
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: hc.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: pct.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: hc.accent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text(
                          entry.value.toString(),
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                isSelected ? hc.accent : hc.textTertiary,
                            fontFamily: 'monospace',
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Severity filter chip
// ---------------------------------------------------------------------------

class _SeverityChip extends StatelessWidget {
  const _SeverityChip({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
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
          color: active ? color.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? color : hc.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? color : hc.textTertiary,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
