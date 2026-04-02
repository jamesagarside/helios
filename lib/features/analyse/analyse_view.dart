import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/geotag/geotag_service.dart';
import '../../core/telemetry/analytics_templates.dart';
import '../../core/telemetry/nl_query_service.dart';
import '../../core/telemetry/replay_service.dart';
import '../../core/telemetry/telemetry_store.dart';
import '../../shared/models/flight_metadata.dart';
import '../../shared/providers/providers.dart';
import '../../shared/theme/helios_colors.dart';
import '../../shared/theme/helios_typography.dart';
import '../../shared/widgets/confirm_dialog.dart';
import 'widgets/fleet_dashboard_panel.dart';
import 'widgets/flight_charts.dart';
import 'widgets/flight_score_panel.dart';
import 'widgets/forensics_panel.dart';

enum _AnalyseMode { charts, sql, compare, score, fleet, geotag }

/// Analyse View — visual charts (default) + SQL editor for advanced users.
class AnalyseView extends ConsumerStatefulWidget {
  const AnalyseView({super.key});

  @override
  ConsumerState<AnalyseView> createState() => _AnalyseViewState();
}

class _AnalyseViewState extends ConsumerState<AnalyseView> {
  final _sqlController = TextEditingController(
    text: 'SELECT * FROM attitude LIMIT 100',
  );
  List<FlightSummary> _flights = [];
  FlightSummary? _selectedFlight;
  QueryResult? _queryResult;
  String? _errorMessage;
  bool _isQuerying = false;
  _AnalyseMode _mode = _AnalyseMode.charts;
  Map<String, FlightMetadata> _metadata = {};

  /// Whether the selected flight is the currently recording one.
  bool get _isLive {
    final store = ref.read(telemetryStoreProvider);
    return store.isRecording &&
        _selectedFlight != null &&
        store.currentFilePath == _selectedFlight!.filePath;
  }

  @override
  void initState() {
    super.initState();
    _autoSelectAndRefresh();
  }

  @override
  void dispose() {
    _sqlController.dispose();
    super.dispose();
  }

  /// On first load, refresh flights and auto-select the latest/live one.
  Future<void> _autoSelectAndRefresh() async {
    final store = ref.read(telemetryStoreProvider);
    final flights = await store.listFlights();

    if (!mounted) return;

    setState(() => _flights = flights);
    _loadAllMetadata(store, flights);

    if (_selectedFlight != null) return; // already selected

    // Priority 1: select the live recording (already open, no need to reopen)
    if (store.isRecording && store.currentFilePath != null) {
      final live = flights.where((f) => f.filePath == store.currentFilePath).firstOrNull;
      if (live != null) {
        setState(() {
          _selectedFlight = live;
          _errorMessage = null;
          _queryResult = null;
        });
        return;
      }
    }

    // Priority 2: select the most recent flight
    if (flights.isNotEmpty) {
      await _openFlight(flights.first);
    }
  }

  Future<void> _refreshFlights() async {
    final store = ref.read(telemetryStoreProvider);
    final flights = await store.listFlights();
    if (!mounted) return;
    setState(() => _flights = flights);
    await _loadAllMetadata(store, flights);
  }

  Future<void> _loadAllMetadata(
      TelemetryStore store, List<FlightSummary> flights) async {
    final map = <String, FlightMetadata>{};
    for (final flight in flights) {
      try {
        map[flight.filePath] = await store.getFlightMetadata(flight.filePath);
      } catch (_) {
        map[flight.filePath] = const FlightMetadata();
      }
    }
    if (mounted) setState(() => _metadata = map);
  }

  Future<void> _renameFlight(FlightSummary flight) async {
    final store = ref.read(telemetryStoreProvider);
    final meta =
        _metadata[flight.filePath] ?? const FlightMetadata();
    final controller = TextEditingController(text: meta.name ?? '');

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final hc = ctx.hc;
        return AlertDialog(
        backgroundColor: hc.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: hc.border),
        ),
        title: Text('Rename Flight',
            style: TextStyle(
                color: hc.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: hc.textPrimary),
          decoration: InputDecoration(
            hintText: _formatFlightDate(flight),
            hintStyle: TextStyle(color: hc.textTertiary),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: hc.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      );},
    );
    controller.dispose();

    if (name == null || !mounted) return;
    final updated = meta.copyWith(name: name);
    await store.setFlightMetadata(flight.filePath, updated);
    setState(() => _metadata[flight.filePath] = updated);
  }

  Future<void> _editNotes(FlightSummary flight) async {
    final store = ref.read(telemetryStoreProvider);
    final meta =
        _metadata[flight.filePath] ?? const FlightMetadata();
    final controller = TextEditingController(text: meta.notes ?? '');

    final notes = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final hc = ctx.hc;
        return AlertDialog(
        backgroundColor: hc.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: hc.border),
        ),
        title: Text('Flight Notes',
            style: TextStyle(
                color: hc.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 300,
          height: 150,
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(color: hc.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Add notes about this flight...',
              hintStyle: TextStyle(color: hc.textTertiary),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: hc.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      );},
    );
    controller.dispose();

    if (notes == null || !mounted) return;
    final updated = meta.copyWith(notes: notes);
    await store.setFlightMetadata(flight.filePath, updated);
    setState(() => _metadata[flight.filePath] = updated);
  }

  /// Load a flight into the ReplayService and switch to the Fly View.
  Future<void> _launchReplay(FlightSummary flight) async {
    final replay = ref.read(replayServiceProvider);
    if (replay.state == ReplayState.playing || replay.state == ReplayState.paused) {
      replay.stop();
    }

    // Show loading indicator briefly
    final hc = context.hc;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Loading replay: ${_displayName(flight)}',
          style: TextStyle(color: hc.textPrimary),
        ),
        backgroundColor: hc.surface,
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      await replay.loadFlight(flight.filePath);
      if (!mounted) return;

      // Switch to Fly View (tab index 0)
      // Navigate via the app's tab controller by popping context if needed.
      // We signal via replayActiveProvider which FlyView watches.
      ref.read(replayActiveProvider.notifier).state = true;
      replay.play();

      // Switch tab — find the tab controller in the widget tree
      DefaultTabController.maybeOf(context)?.animateTo(0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Replay error: $e')),
        );
      }
    }
  }

  Future<void> _deleteFlight(FlightSummary flight) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete Flight',
      message:
          'Permanently delete "${_displayName(flight)}"?\nThis cannot be undone.',
      confirmLabel: 'Delete',
      isDangerous: true,
    );
    if (!confirmed || !mounted) return;

    final store = ref.read(telemetryStoreProvider);
    await store.deleteFlight(flight.filePath);
    _metadata.remove(flight.filePath);
    if (_selectedFlight?.filePath == flight.filePath) {
      _selectedFlight = null;
      _queryResult = null;
    }
    await _refreshFlights();
  }

  String _displayName(FlightSummary flight) {
    final meta = _metadata[flight.filePath];
    if (meta != null && meta.hasName) return meta.name!;
    return _formatFlightDate(flight);
  }

  String _formatFlightDate(FlightSummary flight) {
    if (flight.startTime != null) {
      final t = flight.startTime!;
      return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
          '${t.day.toString().padLeft(2, '0')} '
          '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
    }
    return flight.fileName.replaceAll('.duckdb', '');
  }

  Future<void> _openFlight(FlightSummary flight) async {
    final store = ref.read(telemetryStoreProvider);

    // If this IS the live recording, don't reopen (would kill the recording).
    // The store already has the connection open.
    if (store.isRecording && store.currentFilePath == flight.filePath) {
      setState(() {
        _selectedFlight = flight;
        _errorMessage = null;
        _queryResult = null;
      });
      return;
    }

    // Otherwise open the flight file for read-only analysis.
    try {
      await store.openFlight(flight.filePath);
      setState(() {
        _selectedFlight = flight;
        _errorMessage = null;
        _queryResult = null;
      });
    } catch (e) {
      setState(() => _errorMessage = 'Failed to open: $e');
    }
  }

  Future<void> _executeQuery() async {
    final store = ref.read(telemetryStoreProvider);
    final sql = _sqlController.text.trim();
    if (sql.isEmpty) return;

    setState(() {
      _isQuerying = true;
      _errorMessage = null;
    });

    try {
      final result = await store.query(sql);
      setState(() {
        _queryResult = result;
        _isQuerying = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _queryResult = null;
        _isQuerying = false;
      });
    }
  }

  void _loadTemplate(AnalyticsTemplate template) {
    _sqlController.text = template.sql.trim();
    _executeQuery();
  }

  Future<void> _exportData(_ExportFormat format) async {
    if (_selectedFlight == null) return;
    final store = ref.read(telemetryStoreProvider);
    try {
      final base = _selectedFlight!.filePath.replaceAll('.duckdb', '_export');
      final query = _sqlController.text.trim().isNotEmpty
          ? _sqlController.text.trim()
          : 'attitude';
      String path;
      switch (format) {
        case _ExportFormat.csv:
          path = '$base/query_result.csv';
          await store.exportCsv(query, path);
        case _ExportFormat.json:
          path = '$base/query_result.json';
          await store.exportJson(query, path);
        case _ExportFormat.parquet:
          final table = query.toUpperCase().startsWith('SELECT') ? 'attitude' : query;
          path = '$base/$table.parquet';
          await store.exportParquet(table, path);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported to $path')),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Export failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final width = MediaQuery.sizeOf(context).width;
    final showBrowser = width >= 768;

    return Row(
      children: [
        // Flight browser panel
        if (showBrowser)
          SizedBox(
            width: 260,
            child: _FlightBrowser(
              flights: _flights,
              metadata: _metadata,
              selectedFlight: _selectedFlight,
              liveFilePath: ref.read(telemetryStoreProvider).isRecording
                  ? ref.read(telemetryStoreProvider).currentFilePath
                  : null,
              onRefresh: _refreshFlights,
              onSelect: _openFlight,
              onRename: _renameFlight,
              onEditNotes: _editNotes,
              onDelete: _deleteFlight,
              onReplay: _launchReplay,
            ),
          ),
        if (showBrowser)
          VerticalDivider(width: 1, color: hc.border),

        // Main area
        Expanded(
          child: Column(
            children: [
              // Mode toggle: Charts / SQL / Compare
              Container(
                height: 40,
                color: hc.surface,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _ModeTab(
                      label: 'Charts',
                      icon: Icons.bar_chart,
                      selected: _mode == _AnalyseMode.charts,
                      onTap: () => setState(() => _mode = _AnalyseMode.charts),
                    ),
                    const SizedBox(width: 4),
                    _ModeTab(
                      label: 'SQL',
                      icon: Icons.code,
                      selected: _mode == _AnalyseMode.sql,
                      onTap: () => setState(() => _mode = _AnalyseMode.sql),
                    ),
                    const SizedBox(width: 4),
                    _ModeTab(
                      label: 'Compare',
                      icon: Icons.compare_arrows,
                      selected: _mode == _AnalyseMode.compare,
                      onTap: () => setState(() => _mode = _AnalyseMode.compare),
                    ),
                    const SizedBox(width: 4),
                    _ModeTab(
                      label: 'Score',
                      icon: Icons.military_tech_outlined,
                      selected: _mode == _AnalyseMode.score,
                      onTap: () => setState(() => _mode = _AnalyseMode.score),
                    ),
                    const SizedBox(width: 4),
                    _ModeTab(
                      label: 'Fleet',
                      icon: Icons.dataset_outlined,
                      selected: _mode == _AnalyseMode.fleet,
                      onTap: () => setState(() => _mode = _AnalyseMode.fleet),
                    ),
                    const SizedBox(width: 4),
                    _ModeTab(
                      label: 'Geotag',
                      icon: Icons.add_location_alt_outlined,
                      selected: _mode == _AnalyseMode.geotag,
                      onTap: () => setState(() => _mode = _AnalyseMode.geotag),
                    ),
                    if (_selectedFlight != null &&
                        _mode != _AnalyseMode.compare) ...[
                      const Spacer(),
                      Text(
                        _selectedFlight!.fileName.replaceAll('.duckdb', ''),
                        style: HeliosTypography.caption,
                      ),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, color: hc.border),

              // Content based on mode
              if (_mode == _AnalyseMode.charts) ...[
                // Charts mode (default)
                Expanded(
                  child: _selectedFlight != null
                      ? FlightCharts(
                          key: ValueKey(
                              '${_selectedFlight!.filePath}_$_isLive'),
                          store: ref.read(telemetryStoreProvider),
                          liveMode: _isLive,
                        )
                      : Center(
                          child: Text(
                            'Select a flight to view charts',
                            style: TextStyle(
                                color: hc.textTertiary, fontSize: 13),
                          ),
                        ),
                ),
              ] else if (_mode == _AnalyseMode.sql) ...[
                // SQL mode
                _TemplateBar(
                  onSelect: _selectedFlight != null ? _loadTemplate : null,
                ),
                Divider(height: 1, color: hc.border),
                _NlQueryBar(
                  enabled: _selectedFlight != null,
                  onQuery: (String sql) {
                    setState(() => _sqlController.text = sql);
                    if (_selectedFlight != null) _executeQuery();
                  },
                ),
                Divider(height: 1, color: hc.border),
                _SqlEditor(
                  controller: _sqlController,
                  onExecute: _selectedFlight != null ? _executeQuery : null,
                  onExport: _selectedFlight != null ? _exportData : null,
                  isQuerying: _isQuerying,
                ),
                Divider(height: 1, color: hc.border),
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: hc.danger.withValues(alpha: 0.1),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                          color: hc.danger,
                          fontSize: 12,
                          fontFamily: 'monospace'),
                    ),
                  ),
                Expanded(
                  child: _queryResult != null
                      ? _ResultsTable(result: _queryResult!)
                      : Center(
                          child: Text(
                            _selectedFlight == null
                                ? 'Select a flight to begin analysis'
                                : 'Run a query to see results',
                            style: TextStyle(
                                color: hc.textTertiary, fontSize: 13),
                          ),
                        ),
                ),
                if (_queryResult != null)
                  Container(
                    height: 24,
                    color: hc.surface,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Text('${_queryResult!.rowCount} rows',
                            style: HeliosTypography.caption),
                        const SizedBox(width: 16),
                        Text(
                            '${_queryResult!.executionTime.inMilliseconds}ms',
                            style: HeliosTypography.caption),
                      ],
                    ),
                  ),
              ] else if (_mode == _AnalyseMode.compare) ...[
                // Compare mode — cross-flight forensics
                Expanded(
                  child: ForensicsPanel(
                    flights: _flights,
                    metadata: _metadata,
                  ),
                ),
              ] else if (_mode == _AnalyseMode.score) ...[
                // Score mode — auto-generated flight scorecard
                Expanded(
                  child: _selectedFlight != null
                      ? FlightScorePanel(
                          key: ValueKey(_selectedFlight!.filePath),
                          store: ref.read(telemetryStoreProvider),
                          filePath: _selectedFlight!.filePath,
                        )
                      : Center(
                          child: Text(
                            'Select a flight to view its score',
                            style: TextStyle(
                                color: hc.textTertiary, fontSize: 13),
                          ),
                        ),
                ),
              ] else if (_mode == _AnalyseMode.geotag) ...[
                // Geotag mode — match photos to flight GPS track
                Expanded(
                  child: _GeotagPanel(
                    selectedFlight: _selectedFlight,
                  ),
                ),
              ] else ...[
                // Fleet mode — aggregate stats across all flights
                Expanded(
                  child: FleetDashboardPanel(
                    key: ValueKey(_flights.length),
                    store: ref.read(telemetryStoreProvider),
                    flights: _flights,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FlightBrowser extends StatelessWidget {
  const _FlightBrowser({
    required this.flights,
    required this.metadata,
    required this.selectedFlight,
    this.liveFilePath,
    required this.onRefresh,
    required this.onSelect,
    required this.onRename,
    required this.onEditNotes,
    required this.onDelete,
    required this.onReplay,
  });

  final List<FlightSummary> flights;
  final Map<String, FlightMetadata> metadata;
  final FlightSummary? selectedFlight;
  final String? liveFilePath;
  final VoidCallback onRefresh;
  final ValueChanged<FlightSummary> onSelect;
  final ValueChanged<FlightSummary> onRename;
  final ValueChanged<FlightSummary> onEditNotes;
  final ValueChanged<FlightSummary> onDelete;
  final ValueChanged<FlightSummary> onReplay;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: hc.surface,
          child: Row(
            children: [
              const Text('Flights', style: HeliosTypography.heading2),
              const SizedBox(width: 4),
              Text('(${flights.length})',
                  style: HeliosTypography.caption
                      .copyWith(color: hc.textTertiary)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: onRefresh,
                tooltip: 'Refresh',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: hc.border),
        Expanded(
          child: flights.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No recorded flights yet.\nConnect and start recording.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: hc.textTertiary, fontSize: 13),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: flights.length,
                  itemBuilder: (context, index) {
                    final hc = context.hc;
                    final flight = flights[index];
                    final meta = metadata[flight.filePath];
                    final isSelected =
                        selectedFlight?.filePath == flight.filePath;
                    final isLive = flight.filePath == liveFilePath;
                    final sizeKb =
                        (flight.fileSizeBytes / 1024).toStringAsFixed(0);

                    // Display name: user-assigned or formatted date
                    final displayName = meta?.hasName == true
                        ? meta!.name!
                        : _formatDate(flight);

                    // Subtitle: date + size (or just size if name is the date)
                    final subtitle = meta?.hasName == true
                        ? '${_formatDate(flight)} \u2022 $sizeKb KB'
                        : '$sizeKb KB';

                    return GestureDetector(
                      onSecondaryTapDown: (details) {
                        _showContextMenu(
                            context, details.globalPosition, flight, isLive);
                      },
                      child: ListTile(
                        dense: true,
                        selected: isSelected,
                        selectedTileColor:
                            hc.accent.withValues(alpha: 0.1),
                        leading: Icon(
                          isLive ? Icons.fiber_manual_record : Icons.flight,
                          size: isLive ? 14 : 18,
                          color: isLive
                              ? hc.danger
                              : isSelected
                                  ? hc.accent
                                  : hc.textSecondary,
                        ),
                        title: Row(
                          children: [
                            if (isLive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color: hc.danger.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: Text(
                                  'LIVE',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: hc.danger,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: meta?.hasName == true
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isSelected
                                      ? hc.accent
                                      : hc.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(subtitle,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: hc.textTertiary)),
                            if (meta?.hasNotes == true)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  meta!.notes!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: hc.textTertiary,
                                      fontStyle: FontStyle.italic),
                                ),
                              ),
                            if (meta?.hasTags == true)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Wrap(
                                  spacing: 4,
                                  children: meta!.tags
                                      .take(3)
                                      .map((t) => Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: hc.accent
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(2),
                                              border: Border.all(
                                                  color: hc.accent
                                                      .withValues(alpha: 0.3)),
                                            ),
                                            child: Text(t,
                                                style: TextStyle(
                                                    fontSize: 9,
                                                    color: hc.accent)),
                                          ))
                                      .toList(),
                                ),
                              ),
                          ],
                        ),
                        trailing: !isLive
                            ? Tooltip(
                                message: 'Replay in Fly View',
                                child: InkWell(
                                  onTap: () => onReplay(flight),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.play_circle_outline,
                                      size: 16,
                                      color: hc.textTertiary,
                                    ),
                                  ),
                                ),
                              )
                            : null,
                        onTap: () => onSelect(flight),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showContextMenu(BuildContext context, Offset position,
      FlightSummary flight, bool isLive) {
    final hc = context.hc;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      color: hc.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: hc.border),
      ),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit, size: 14, color: hc.textSecondary),
              const SizedBox(width: 8),
              const Text('Rename', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'notes',
          child: Row(
            children: [
              Icon(Icons.note_add, size: 14, color: hc.textSecondary),
              const SizedBox(width: 8),
              const Text('Edit Notes', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        if (!isLive)
          PopupMenuItem(
            value: 'replay',
            child: Row(
              children: [
                Icon(Icons.play_circle_outline, size: 14, color: hc.accent),
                const SizedBox(width: 8),
                Text('Replay in Fly View',
                    style: TextStyle(fontSize: 13, color: hc.accent)),
              ],
            ),
          ),
        if (!isLive)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 14, color: hc.danger),
                const SizedBox(width: 8),
                Text('Delete',
                    style: TextStyle(fontSize: 13, color: hc.danger)),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value == 'rename') onRename(flight);
      if (value == 'notes') onEditNotes(flight);
      if (value == 'replay') onReplay(flight);
      if (value == 'delete') onDelete(flight);
    });
  }

  String _formatDate(FlightSummary flight) {
    if (flight.startTime != null) {
      final t = flight.startTime!;
      return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
          '${t.day.toString().padLeft(2, '0')} '
          '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
    }
    return flight.fileName.replaceAll('.duckdb', '');
  }
}

class _TemplateBar extends StatelessWidget {
  const _TemplateBar({required this.onSelect});

  final ValueChanged<AnalyticsTemplate>? onSelect;

  static const _icons = {
    AnalyticsTemplate.vibrationAnalysis: Icons.vibration,
    AnalyticsTemplate.batteryDischarge: Icons.battery_full,
    AnalyticsTemplate.gpsQuality: Icons.gps_fixed,
    AnalyticsTemplate.altitudeProfile: Icons.height,
    AnalyticsTemplate.anomalyDetection: Icons.warning_amber,
    AnalyticsTemplate.flightSummary: Icons.summarize,
    AnalyticsTemplate.modeTimeline: Icons.timeline,
  };

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      height: 44,
      color: hc.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: AnalyticsTemplate.values.map((t) {
          return Padding(
            padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
            child: ActionChip(
              avatar: Icon(_icons[t] ?? Icons.query_stats, size: 14, color: hc.accent),
              label: Text(t.name, style: const TextStyle(fontSize: 12)),
              backgroundColor: hc.surfaceLight,
              side: BorderSide(color: hc.border),
              onPressed: onSelect != null ? () => onSelect!(t) : null,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SqlEditor extends StatelessWidget {
  const _SqlEditor({
    required this.controller,
    required this.onExecute,
    required this.onExport,
    required this.isQuerying,
  });

  final TextEditingController controller;
  final VoidCallback? onExecute;
  final ValueChanged<_ExportFormat>? onExport;
  final bool isQuerying;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      height: 140,
      color: hc.surfaceDim,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: null,
              style: HeliosTypography.sqlEditor,
              decoration: const InputDecoration(
                hintText: 'Enter SQL query...',
                border: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: isQuerying ? null : onExecute,
                icon: isQuerying
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow, size: 16),
                label: const Text('Run'),
              ),
              const SizedBox(width: 8),
              // Export dropdown
              MenuAnchor(
                menuChildren: [
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.table_chart_outlined, size: 16),
                    onPressed: onExport != null ? () => onExport!(_ExportFormat.csv) : null,
                    child: const Text('Export CSV'),
                  ),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.data_object, size: 16),
                    onPressed: onExport != null ? () => onExport!(_ExportFormat.json) : null,
                    child: const Text('Export JSON'),
                  ),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.save_alt, size: 16),
                    onPressed: onExport != null ? () => onExport!(_ExportFormat.parquet) : null,
                    child: const Text('Export Parquet'),
                  ),
                ],
                builder: (_, ctrl, child) => OutlinedButton.icon(
                  onPressed: onExport != null ? () {
                    if (ctrl.isOpen) { ctrl.close(); } else { ctrl.open(); }
                  } : null,
                  icon: const Icon(Icons.save_alt, size: 16),
                  label: const Text('Export ▾'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _ExportFormat { csv, json, parquet }

class _ResultsTable extends StatelessWidget {
  const _ResultsTable({required this.result});

  final QueryResult result;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    if (result.rowCount == 0) {
      return Center(
        child: Text('Query returned 0 rows', style: TextStyle(color: hc.textTertiary)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(hc.surface),
          dataRowColor: WidgetStateProperty.all(hc.background),
          border: TableBorder.all(color: hc.border, width: 0.5),
          columnSpacing: 16,
          headingRowHeight: 32,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 28,
          columns: result.columnNames
              .map((name) => DataColumn(
                    label: Text(
                      name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: hc.accent,
                      ),
                    ),
                  ))
              .toList(),
          rows: result.rows.take(500).map((row) {
            return DataRow(
              cells: row.map((cell) {
                final display = cell == null
                    ? 'NULL'
                    : cell is double
                        ? cell.toStringAsFixed(4)
                        : cell.toString();
                return DataCell(
                  Text(
                    display,
                    style: HeliosTypography.sqlEditor.copyWith(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? hc.accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? hc.accent.withValues(alpha: 0.3) : hc.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? hc.accent : hc.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? hc.accent : hc.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Natural Language Query Bar ──────────────────────────────────────────────

class _NlQueryBar extends StatefulWidget {
  const _NlQueryBar({required this.enabled, required this.onQuery});

  final bool enabled;
  final void Function(String sql) onQuery;

  @override
  State<_NlQueryBar> createState() => _NlQueryBarState();
}

class _NlQueryBarState extends State<_NlQueryBar> {
  final _ctrl = TextEditingController();
  String? _lastDescription;
  bool _noMatch = false;

  static const _service = NlQueryService();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final result = _service.translate(text);
    if (result == null) {
      setState(() { _noMatch = true; _lastDescription = null; });
    } else {
      setState(() { _noMatch = false; _lastDescription = result.description; });
      widget.onQuery(result.sql);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      color: hc.surfaceLight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: hc.accent),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: TextField(
                    controller: _ctrl,
                    enabled: widget.enabled,
                    style: TextStyle(color: hc.textPrimary, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Ask a question… e.g. "max altitude", "battery over time"',
                      hintStyle: TextStyle(color: hc.textTertiary, fontSize: 12),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 30,
                child: ElevatedButton(
                  onPressed: widget.enabled ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Ask', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          if (_lastDescription != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 20),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 12, color: hc.success),
                  const SizedBox(width: 4),
                  Text(
                    _lastDescription!,
                    style: TextStyle(color: hc.textTertiary, fontSize: 11),
                  ),
                ],
              ),
            ),
          if (_noMatch)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 20),
              child: Row(
                children: [
                  Icon(Icons.help_outline, size: 12, color: hc.textTertiary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'I didn\'t understand that. Try: "max altitude", "battery over time", "flight summary"',
                      style: TextStyle(color: hc.textTertiary, fontSize: 11),
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

// ---------------------------------------------------------------------------
// Geotag panel
// ---------------------------------------------------------------------------

class _GeotagPanel extends StatefulWidget {
  const _GeotagPanel({this.selectedFlight});

  final FlightSummary? selectedFlight;

  @override
  State<_GeotagPanel> createState() => _GeotagPanelState();
}

class _GeotagPanelState extends State<_GeotagPanel> {
  final _service = GeotagService();
  List<GeotagResult> _results = [];
  bool _running = false;
  int _timeOffset = 0;
  String? _error;

  Future<void> _run() async {
    if (widget.selectedFlight == null) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg'],
      allowMultiple: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    final paths = picked.files
        .map((f) => f.path)
        .whereType<String>()
        .toList();
    if (paths.isEmpty) return;

    setState(() {
      _running = true;
      _error = null;
      _results = [];
    });

    try {
      final results = await _service.geotag(
        imagePaths: paths,
        dbPath: widget.selectedFlight!.filePath,
        timeOffsetSecs: _timeOffset,
      );
      setState(() {
        _results = results;
        _running = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final successCount = _results.where((r) => r.success).length;

    return Column(
      children: [
        // Toolbar
        Container(
          height: 44,
          color: hc.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (widget.selectedFlight == null)
                Text(
                  'Select a flight from the left panel first',
                  style: TextStyle(color: hc.textTertiary, fontSize: 12),
                )
              else
                Text(
                  'Flight: ${widget.selectedFlight!.fileName.replaceAll('.duckdb', '')}',
                  style: TextStyle(color: hc.textSecondary, fontSize: 12),
                ),
              const SizedBox(width: 24),
              Text('Camera offset:', style: TextStyle(color: hc.textTertiary, fontSize: 12)),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                height: 28,
                child: TextFormField(
                  initialValue: '0',
                  keyboardType: TextInputType.number,
                  style: TextStyle(fontSize: 12, color: hc.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    suffixText: 's',
                    suffixStyle: TextStyle(fontSize: 11, color: hc.textTertiary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: hc.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: hc.border),
                    ),
                  ),
                  onChanged: (v) => _timeOffset = int.tryParse(v) ?? 0,
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: (_running || widget.selectedFlight == null) ? null : _run,
                icon: _running
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_location_alt, size: 14),
                label: Text(_running ? 'Running…' : 'Pick Images & Geotag', style: const TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (_results.isNotEmpty) ...[
                const SizedBox(width: 16),
                Text(
                  '$successCount/${_results.length} tagged',
                  style: TextStyle(
                    color: successCount == _results.length ? hc.success : hc.warning,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        Divider(height: 1, color: hc.border),

        // Results or empty state
        Expanded(
          child: _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: TextStyle(color: hc.danger, fontSize: 12),
                  ),
                )
              : _results.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_location_alt_outlined, size: 48, color: hc.textTertiary),
                          const SizedBox(height: 12),
                          Text(
                            'Geotag Images',
                            style: TextStyle(color: hc.textSecondary, fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Select a flight and pick JPEG images.\nHelios will match each photo to the GPS track\nby EXIF timestamp and write coordinates into the file.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: hc.textTertiary, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final r = _results[i];
                        return Container(
                          height: 36,
                          color: i.isEven ? hc.background : hc.surface,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Icon(
                                r.success ? Icons.check_circle_outline : Icons.error_outline,
                                size: 16,
                                color: r.success ? hc.success : hc.danger,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  r.filename,
                                  style: TextStyle(fontSize: 12, color: hc.textPrimary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (r.success)
                                Text(
                                  '${r.lat!.toStringAsFixed(5)}, ${r.lon!.toStringAsFixed(5)}  ${r.altM!.toStringAsFixed(0)}m',
                                  style: TextStyle(fontSize: 11, color: hc.textSecondary, fontFamily: 'monospace'),
                                )
                              else
                                Text(
                                  r.errorMessage ?? 'Failed',
                                  style: TextStyle(fontSize: 11, color: hc.danger),
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
