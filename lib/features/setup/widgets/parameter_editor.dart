import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/params/parameter_service.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Full-screen parameter editor for flight controller configuration.
class ParameterEditor extends ConsumerStatefulWidget {
  const ParameterEditor({super.key});

  @override
  ConsumerState<ParameterEditor> createState() => _ParameterEditorState();
}

class _ParameterEditorState extends ConsumerState<ParameterEditor> {
  Map<String, Parameter> _params = {};
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedGroup;
  bool _fetching = false;
  double _fetchProgress = 0;
  String? _error;
  final _modified = <String, double>{}; // param_id -> new value

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchParams() async {
    final controller = ref.read(connectionControllerProvider.notifier);
    final paramService = controller.paramService;
    if (paramService == null) return;

    final vehicle = ref.read(vehicleStateProvider);
    setState(() {
      _fetching = true;
      _fetchProgress = 0;
      _error = null;
      _modified.clear();
    });

    final sub = paramService.progressStream.listen((progress) {
      if (mounted) {
        setState(() => _fetchProgress = progress.progress);
      }
    });

    try {
      final params = await paramService.fetchAll(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
      );
      if (mounted) {
        setState(() {
          _params = params;
          _fetching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fetching = false;
          _error = e.toString();
        });
      }
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _writeParam(String paramId, double value) async {
    final controller = ref.read(connectionControllerProvider.notifier);
    final paramService = controller.paramService;
    if (paramService == null) return;

    final vehicle = ref.read(vehicleStateProvider);
    try {
      final confirmed = await paramService.setParam(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
        paramId: paramId,
        value: value,
        paramType: _params[paramId]?.type ?? 9,
      );
      if (mounted) {
        setState(() {
          _params[paramId] = _params[paramId]!.copyWith(value: confirmed);
          _modified.remove(paramId);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: HeliosColors.danger),
        );
      }
    }
  }

  Future<void> _writeAllModified() async {
    final entries = Map<String, double>.from(_modified);
    for (final entry in entries.entries) {
      await _writeParam(entry.key, entry.value);
    }
  }

  Future<void> _exportParams() async {
    final controller = ref.read(connectionControllerProvider.notifier);
    final paramService = controller.paramService;
    if (paramService == null || _params.isEmpty) return;

    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final fileName = 'helios_params_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.param';
    final filePath = p.join(dir.path, fileName);
    await paramService.saveToFile(filePath);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to $fileName'), backgroundColor: HeliosColors.success),
      );
    }
  }

  List<Parameter> get _filteredParams {
    var list = _params.values.toList();
    if (_selectedGroup != null) {
      list = list.where((p) => p.group == _selectedGroup).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toUpperCase();
      list = list.where((p) => p.id.toUpperCase().contains(q)).toList();
    }
    list.sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  List<String> get _groups {
    final g = _params.values.map((p) => p.group).toSet().toList()..sort();
    return g;
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with fetch/write/export
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: isConnected && !_fetching ? _fetchParams : null,
              icon: _fetching
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: HeliosColors.textPrimary),
                    )
                  : const Icon(Icons.download, size: 16),
              label: Text(_fetching
                  ? '${(_fetchProgress * 100).toInt()}%'
                  : 'Fetch All'),
            ),
            const SizedBox(width: 8),
            if (_modified.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _writeAllModified,
                icon: const Icon(Icons.upload, size: 16),
                label: Text('Write ${_modified.length} Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HeliosColors.warningDim,
                ),
              ),
            const SizedBox(width: 8),
            if (_params.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _exportParams,
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Export .param'),
              ),
            const Spacer(),
            if (_params.isNotEmpty)
              Text(
                '${_params.length} params',
                style: HeliosTypography.caption,
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: const TextStyle(color: HeliosColors.danger, fontSize: 12)),
          ),

        if (_params.isEmpty && !_fetching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Connect to a vehicle and tap "Fetch All" to load parameters.',
                style: TextStyle(color: HeliosColors.textTertiary, fontSize: 13),
              ),
            ),
          ),

        if (_params.isNotEmpty) ...[
          // Search + group filter
          Row(
            children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: HeliosColors.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search parameters...',
                      hintStyle: const TextStyle(color: HeliosColors.textTertiary),
                      prefixIcon: const Icon(Icons.search, size: 18, color: HeliosColors.textTertiary),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: HeliosColors.border),
                      ),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedGroup,
                    decoration: InputDecoration(
                      hintText: 'Group',
                      hintStyle: const TextStyle(color: HeliosColors.textTertiary, fontSize: 12),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: HeliosColors.border),
                      ),
                    ),
                    dropdownColor: HeliosColors.surfaceLight,
                    style: const TextStyle(color: HeliosColors.textPrimary, fontSize: 12),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Groups')),
                      ..._groups.map((g) => DropdownMenuItem(value: g, child: Text(g))),
                    ],
                    onChanged: (v) => setState(() => _selectedGroup = v),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Parameter table
          Expanded(
            child: _buildParamTable(),
          ),
        ],
      ],
    );
  }

  Widget _buildParamTable() {
    final filtered = _filteredParams;

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (ctx, index) {
        final param = filtered[index];
        final isModified = _modified.containsKey(param.id);
        final displayValue = isModified ? _modified[param.id]! : param.value;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isModified
                ? HeliosColors.warning.withValues(alpha: 0.08)
                : (index.isEven ? Colors.transparent : HeliosColors.surfaceLight.withValues(alpha: 0.3)),
            border: const Border(
              bottom: BorderSide(color: HeliosColors.border, width: 0.3),
            ),
          ),
          child: Row(
            children: [
              // Param name
              Expanded(
                flex: 3,
                child: Text(
                  param.id,
                  style: TextStyle(
                    color: isModified ? HeliosColors.warning : HeliosColors.textPrimary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: isModified ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              // Value editor
              SizedBox(
                width: 120,
                child: _ParamValueField(
                  value: displayValue,
                  isInteger: param.isInteger,
                  onChanged: (newVal) {
                    setState(() {
                      if (newVal == param.value) {
                        _modified.remove(param.id);
                      } else {
                        _modified[param.id] = newVal;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Write button (per-param)
              if (isModified)
                SizedBox(
                  width: 28,
                  height: 24,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.check, size: 14, color: HeliosColors.success),
                    onPressed: () => _writeParam(param.id, _modified[param.id]!),
                    tooltip: 'Write',
                  ),
                ),
              if (!isModified) const SizedBox(width: 28),
            ],
          ),
        );
      },
    );
  }
}

class _ParamValueField extends StatefulWidget {
  const _ParamValueField({
    required this.value,
    required this.isInteger,
    required this.onChanged,
  });

  final double value;
  final bool isInteger;
  final void Function(double) onChanged;

  @override
  State<_ParamValueField> createState() => _ParamValueFieldState();
}

class _ParamValueFieldState extends State<_ParamValueField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(_ParamValueField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _ctrl.text = _format(widget.value);
    }
  }

  String _format(double v) =>
      widget.isInteger ? v.toInt().toString() : v.toStringAsFixed(4);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: TextField(
        controller: _ctrl,
        style: const TextStyle(
          color: HeliosColors.textPrimary,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: const BorderSide(color: HeliosColors.border, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: const BorderSide(color: HeliosColors.border, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: const BorderSide(color: HeliosColors.accent, width: 1),
          ),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onSubmitted: (text) {
          final v = double.tryParse(text);
          if (v != null) widget.onChanged(v);
        },
      ),
    );
  }
}
