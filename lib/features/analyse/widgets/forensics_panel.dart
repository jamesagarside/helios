import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/telemetry/forensics_service.dart';
import '../../../core/telemetry/telemetry_store.dart';
import '../../../shared/models/flight_metadata.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Cross-flight forensics panel — compares statistics across multiple flights.
///
/// Users select 2+ flights from the browser, pick a template (or write custom
/// SQL), and get a cross-flight comparison table.
class ForensicsPanel extends ConsumerStatefulWidget {
  const ForensicsPanel({
    super.key,
    required this.flights,
    required this.metadata,
  });

  final List<FlightSummary> flights;
  final Map<String, FlightMetadata> metadata;

  @override
  ConsumerState<ForensicsPanel> createState() => _ForensicsPanelState();
}

class _ForensicsPanelState extends ConsumerState<ForensicsPanel> {
  final ForensicsService _service = ForensicsService();
  final _sqlController = TextEditingController();

  Set<String> _selectedPaths = {};
  ForensicsTemplate _activeTemplate = ForensicsTemplate.flightComparison;
  ForensicsResult? _result;
  bool _running = false;
  String? _error;
  bool _showCustomSql = false;

  @override
  void initState() {
    super.initState();
    // Default: select all flights (up to 20)
    _selectedPaths = widget.flights
        .take(20)
        .map((f) => f.filePath)
        .toSet();
    _sqlController.text = _activeTemplate.sql.trim();
  }

  @override
  void dispose() {
    _sqlController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final selected = widget.flights
        .where((f) => _selectedPaths.contains(f.filePath))
        .toList();

    if (selected.length < 2) {
      setState(() => _error = 'Select at least 2 flights to compare');
      return;
    }

    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });

    try {
      final sql =
          _showCustomSql ? _sqlController.text.trim() : _activeTemplate.sql.trim();
      final result = await _service.query(selected, sql: sql);
      setState(() {
        _result = result;
        _running = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _running = false;
      });
    }
  }

  String _displayName(FlightSummary flight) {
    final meta = widget.metadata[flight.filePath];
    if (meta != null && meta.hasName) return meta.name!;
    if (flight.startTime != null) {
      final t = flight.startTime!;
      return '${t.month.toString().padLeft(2, '0')}-'
          '${t.day.toString().padLeft(2, '0')} '
          '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
    }
    return flight.fileName.replaceAll('.duckdb', '');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Template selector bar
        Container(
          height: 44,
          color: HeliosColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: ForensicsTemplate.values.map((t) {
                    final active = t == _activeTemplate && !_showCustomSql;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
                      child: ActionChip(
                        label: Text(t.name, style: const TextStyle(fontSize: 12)),
                        backgroundColor: active
                            ? HeliosColors.accent.withValues(alpha: 0.15)
                            : HeliosColors.surfaceLight,
                        side: BorderSide(
                          color: active ? HeliosColors.accent : HeliosColors.border,
                        ),
                        onPressed: () {
                          setState(() {
                            _activeTemplate = t;
                            _showCustomSql = false;
                            _sqlController.text = t.sql.trim();
                          });
                          _run();
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 6),
              // Custom SQL toggle
              ActionChip(
                avatar: const Icon(Icons.code, size: 14),
                label: const Text('Custom', style: TextStyle(fontSize: 12)),
                backgroundColor: _showCustomSql
                    ? HeliosColors.accent.withValues(alpha: 0.15)
                    : HeliosColors.surfaceLight,
                side: BorderSide(
                  color: _showCustomSql ? HeliosColors.accent : HeliosColors.border,
                ),
                onPressed: () {
                  setState(() => _showCustomSql = !_showCustomSql);
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: HeliosColors.border),

        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Flight selector (left panel)
              SizedBox(
                width: 180,
                child: _FlightSelector(
                  flights: widget.flights,
                  selectedPaths: _selectedPaths,
                  onChanged: (paths) => setState(() => _selectedPaths = paths),
                  displayName: _displayName,
                ),
              ),
              const VerticalDivider(width: 1, color: HeliosColors.border),

              // Main content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Custom SQL editor (when shown)
                    if (_showCustomSql) ...[
                      Container(
                        height: 120,
                        color: HeliosColors.surfaceDim,
                        padding: const EdgeInsets.all(10),
                        child: TextField(
                          controller: _sqlController,
                          maxLines: null,
                          style: HeliosTypography.sqlEditor,
                          decoration: const InputDecoration(
                            hintText: 'SELECT ... FROM flight_stats ORDER BY ...',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      const Divider(height: 1, color: HeliosColors.border),
                    ],

                    // Run bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      color: HeliosColors.surface,
                      child: Row(
                        children: [
                          Text(
                            '${_selectedPaths.length} flights selected',
                            style: HeliosTypography.caption,
                          ),
                          const Spacer(),
                          if (_result != null)
                            Text(
                              '${_result!.rowCount} rows • ${_result!.executionTime.inMilliseconds}ms',
                              style: HeliosTypography.caption
                                  .copyWith(color: HeliosColors.textTertiary),
                            ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _running ? null : _run,
                            icon: _running
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.compare_arrows, size: 16),
                            label: const Text('Compare'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: HeliosColors.border),

                    // Template description
                    if (!_showCustomSql)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                        child: Text(
                          _activeTemplate.description,
                          style: HeliosTypography.caption
                              .copyWith(color: HeliosColors.textTertiary),
                        ),
                      ),

                    // Error
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: HeliosColors.danger.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: HeliosColors.danger.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              color: HeliosColors.danger,
                              fontSize: 12,
                              fontFamily: 'monospace'),
                        ),
                      ),

                    // Results table
                    if (_result != null && _result!.rowCount > 0)
                      Expanded(
                        child: _ForensicsTable(result: _result!),
                      )
                    else if (!_running && _result == null && _error == null)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.analytics_outlined,
                                  size: 40, color: HeliosColors.textTertiary),
                              const SizedBox(height: 8),
                              Text(
                                'Select flights and click Compare',
                                style: HeliosTypography.caption
                                    .copyWith(color: HeliosColors.textTertiary),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FlightSelector extends StatelessWidget {
  const _FlightSelector({
    required this.flights,
    required this.selectedPaths,
    required this.onChanged,
    required this.displayName,
  });

  final List<FlightSummary> flights;
  final Set<String> selectedPaths;
  final ValueChanged<Set<String>> onChanged;
  final String Function(FlightSummary) displayName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: HeliosColors.surface,
          child: Row(
            children: [
              const Text('Flights', style: HeliosTypography.caption),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  if (selectedPaths.length == flights.length) {
                    onChanged({});
                  } else {
                    onChanged(flights.map((f) => f.filePath).toSet());
                  }
                },
                child: Text(
                  selectedPaths.length == flights.length ? 'None' : 'All',
                  style: HeliosTypography.caption
                      .copyWith(color: HeliosColors.accent),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: HeliosColors.border),
        Expanded(
          child: ListView.builder(
            itemCount: flights.length,
            itemBuilder: (context, index) {
              final flight = flights[index];
              final selected = selectedPaths.contains(flight.filePath);
              return CheckboxListTile(
                dense: true,
                value: selected,
                activeColor: HeliosColors.accent,
                side: const BorderSide(color: HeliosColors.textTertiary),
                title: Text(
                  displayName(flight),
                  style: TextStyle(
                    fontSize: 11,
                    color: selected
                        ? HeliosColors.textPrimary
                        : HeliosColors.textTertiary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                onChanged: (_) {
                  final updated = Set<String>.from(selectedPaths);
                  if (selected) {
                    updated.remove(flight.filePath);
                  } else {
                    updated.add(flight.filePath);
                  }
                  onChanged(updated);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ForensicsTable extends StatelessWidget {
  const _ForensicsTable({required this.result});

  final ForensicsResult result;

  @override
  Widget build(BuildContext context) {
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
          columns: result.columnNames.map((name) {
            return DataColumn(
              label: Text(
                name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: HeliosColors.accent,
                ),
              ),
            );
          }).toList(),
          rows: result.rows.map((row) {
            return DataRow(
              cells: result.columnNames.map((col) {
                final cell = row[col];
                final display = cell == null
                    ? 'NULL'
                    : cell is double
                        ? cell.toStringAsFixed(3)
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
