import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/telemetry/analytics_templates.dart';
import '../../core/telemetry/telemetry_store.dart';
import '../../shared/providers/providers.dart';
import '../../shared/theme/helios_colors.dart';
import '../../shared/theme/helios_typography.dart';
import 'widgets/flight_charts.dart';

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
  bool _showSql = false; // false = Charts, true = SQL

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

  Future<void> _exportParquet() async {
    if (_selectedFlight == null) return;
    final store = ref.read(telemetryStoreProvider);
    try {
      final dir = _selectedFlight!.filePath.replaceAll('.duckdb', '_export');
      await store.exportParquet('attitude', '$dir/attitude.parquet');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported to $dir')),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Export failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
              selectedFlight: _selectedFlight,
              liveFilePath: ref.read(telemetryStoreProvider).isRecording
                  ? ref.read(telemetryStoreProvider).currentFilePath
                  : null,
              onRefresh: _refreshFlights,
              onSelect: _openFlight,
            ),
          ),
        if (showBrowser)
          const VerticalDivider(width: 1, color: HeliosColors.border),

        // Main area
        Expanded(
          child: Column(
            children: [
              // Mode toggle: Charts / SQL
              Container(
                height: 40,
                color: HeliosColors.surface,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _ModeTab(
                      label: 'Charts',
                      icon: Icons.bar_chart,
                      selected: !_showSql,
                      onTap: () => setState(() => _showSql = false),
                    ),
                    const SizedBox(width: 4),
                    _ModeTab(
                      label: 'SQL',
                      icon: Icons.code,
                      selected: _showSql,
                      onTap: () => setState(() => _showSql = true),
                    ),
                    if (_selectedFlight != null) ...[
                      const Spacer(),
                      Text(
                        _selectedFlight!.fileName.replaceAll('.duckdb', ''),
                        style: HeliosTypography.caption,
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1, color: HeliosColors.border),

              // Content based on mode
              if (!_showSql) ...[
                // Charts mode (default)
                Expanded(
                  child: _selectedFlight != null
                      ? FlightCharts(
                          key: ValueKey('${_selectedFlight!.filePath}_${_isLive}'),
                          store: ref.read(telemetryStoreProvider),
                          liveMode: _isLive,
                        )
                      : const Center(
                          child: Text(
                            'Select a flight to view charts',
                            style: TextStyle(color: HeliosColors.textTertiary, fontSize: 13),
                          ),
                        ),
                ),
              ] else ...[
                // SQL mode
                _TemplateBar(
                  onSelect: _selectedFlight != null ? _loadTemplate : null,
                ),
                const Divider(height: 1, color: HeliosColors.border),
                _SqlEditor(
                  controller: _sqlController,
                  onExecute: _selectedFlight != null ? _executeQuery : null,
                  onExport: _selectedFlight != null ? _exportParquet : null,
                  isQuerying: _isQuerying,
                ),
                const Divider(height: 1, color: HeliosColors.border),
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: HeliosColors.danger.withValues(alpha: 0.1),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: HeliosColors.danger, fontSize: 12, fontFamily: 'monospace'),
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
                            style: const TextStyle(color: HeliosColors.textTertiary, fontSize: 13),
                          ),
                        ),
                ),
                if (_queryResult != null)
                  Container(
                    height: 24,
                    color: HeliosColors.surface,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Text('${_queryResult!.rowCount} rows', style: HeliosTypography.caption),
                        const SizedBox(width: 16),
                        Text('${_queryResult!.executionTime.inMilliseconds}ms', style: HeliosTypography.caption),
                      ],
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
    required this.selectedFlight,
    this.liveFilePath,
    required this.onRefresh,
    required this.onSelect,
  });

  final List<FlightSummary> flights;
  final FlightSummary? selectedFlight;
  final String? liveFilePath;
  final VoidCallback onRefresh;
  final ValueChanged<FlightSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: HeliosColors.surface,
          child: Row(
            children: [
              Text('Flights', style: HeliosTypography.heading2),
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
        const Divider(height: 1, color: HeliosColors.border),
        Expanded(
          child: flights.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No recorded flights yet.\nConnect and start recording.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: HeliosColors.textTertiary, fontSize: 13),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: flights.length,
                  itemBuilder: (context, index) {
                    final flight = flights[index];
                    final isSelected = selectedFlight?.filePath == flight.filePath;
                    final isLive = flight.filePath == liveFilePath;
                    final sizeKb = (flight.fileSizeBytes / 1024).toStringAsFixed(0);

                    return ListTile(
                      dense: true,
                      selected: isSelected,
                      selectedTileColor: HeliosColors.accent.withValues(alpha: 0.1),
                      leading: Icon(
                        isLive ? Icons.fiber_manual_record : Icons.flight,
                        size: isLive ? 14 : 18,
                        color: isLive
                            ? HeliosColors.danger
                            : isSelected
                                ? HeliosColors.accent
                                : HeliosColors.textSecondary,
                      ),
                      title: Row(
                        children: [
                          if (isLive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: HeliosColors.danger.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  color: HeliosColors.danger,
                                ),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              flight.fileName.replaceAll('.duckdb', ''),
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected ? HeliosColors.accent : HeliosColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        '$sizeKb KB',
                        style: const TextStyle(fontSize: 12, color: HeliosColors.textTertiary),
                      ),
                      onTap: () => onSelect(flight),
                    );
                  },
                ),
        ),
      ],
    );
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
    return Container(
      height: 44,
      color: HeliosColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: AnalyticsTemplate.values.map((t) {
          return Padding(
            padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
            child: ActionChip(
              avatar: Icon(_icons[t] ?? Icons.query_stats, size: 14, color: HeliosColors.accent),
              label: Text(t.name, style: const TextStyle(fontSize: 12)),
              backgroundColor: HeliosColors.surfaceLight,
              side: const BorderSide(color: HeliosColors.border),
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
  final VoidCallback? onExport;
  final bool isQuerying;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      color: HeliosColors.surfaceDim,
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
              OutlinedButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.save_alt, size: 16),
                label: const Text('Export Parquet'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultsTable extends StatelessWidget {
  const _ResultsTable({required this.result});

  final QueryResult result;

  @override
  Widget build(BuildContext context) {
    if (result.rowCount == 0) {
      return const Center(
        child: Text('Query returned 0 rows', style: TextStyle(color: HeliosColors.textTertiary)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(HeliosColors.surface),
          dataRowColor: WidgetStateProperty.all(HeliosColors.background),
          border: TableBorder.all(color: HeliosColors.border, width: 0.5),
          columnSpacing: 16,
          headingRowHeight: 32,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 28,
          columns: result.columnNames
              .map((name) => DataColumn(
                    label: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: HeliosColors.accent,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? HeliosColors.accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? HeliosColors.accent.withValues(alpha: 0.3) : HeliosColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? HeliosColors.accent : HeliosColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? HeliosColors.accent : HeliosColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
