import 'dart:io';
import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/params/parameter_service.dart';
import '../../../core/params/param_meta.dart';
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

/// Parameter prefixes (case-insensitive) that require an FC reboot.
///
/// Based on ArduPilot parameter documentation. The list is intentionally
/// conservative — it covers the most common hardware-config params without
/// trying to enumerate every single one.
const _rebootPrefixes = [
  'SERIAL',   // serial port baud/protocol
  'BRD_',     // board hardware config
  'INS_',     // IMU / gyro initialisation
  'COMPASS_DEV_ID', 'COMPASS_PRIO', 'COMPASS_USE',
  'GPS_TYPE', 'GPS_GNSS_MODE', 'GPS_COM_PORT',
  'CAN_',     // CAN bus / UAVCAN config
  'SRV_CHAN', // servo channel assignment (mixer reset)
  'FRAME_',   // frame class / type
  'MOT_SPIN_ARM', 'MOT_SPIN_MIN',
  'BARO_',    // barometer configuration
  'NTF_LED_OVERRIDE',
  'ARMING_CHECK',
  'LOG_BITMASK',
  'SCHED_LOOP_RATE',
];

bool _needsReboot(String paramId) {
  final upper = paramId.toUpperCase();
  return _rebootPrefixes.any((p) => upper.startsWith(p.toUpperCase()));
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
  bool _rebootRequired = false; // set when a reboot-required param is written
  bool _standardOnly = false; // show only Standard user-level params

  @override
  void initState() {
    super.initState();
    // Pick up any params already prefetched in the background.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cached = ref.read(paramCacheProvider);
      if (cached.isNotEmpty) {
        setState(() => _params = Map.from(cached));
      }
    });
  }

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
        ref.read(paramCacheProvider.notifier).state = params;
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
          if (_needsReboot(paramId)) _rebootRequired = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: context.hc.danger),
        );
      }
    }
  }

  Future<void> _rebootFc() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final hc = ctx.hc;
        return AlertDialog(
          backgroundColor: hc.surface,
          title: Text('Reboot Flight Controller',
              style: TextStyle(color: hc.textPrimary, fontSize: 15)),
          content: Text(
            'This will reboot the FC immediately. Ensure the vehicle is on the ground and disarmed.',
            style: TextStyle(color: hc.textSecondary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: hc.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ctx.hc.warning),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reboot'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final controller = ref.read(connectionControllerProvider.notifier);
    final service = controller.mavlinkService;
    if (service == null) return;

    final vehicle = ref.read(vehicleStateProvider);
    await service.sendCommand(
      targetSystem: vehicle.systemId,
      targetComponent: vehicle.componentId,
      command: MavCmd.preflightRebootShutdown,
      param1: 1, // reboot autopilot
    );

    if (mounted) {
      setState(() => _rebootRequired = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Reboot command sent'),
          backgroundColor: context.hc.success,
        ),
      );
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
        SnackBar(content: Text('Saved to $fileName'), backgroundColor: context.hc.success),
      );
    }
  }

  // ── Profiles ─────────────────────────────────────────────────────────────

  Future<Directory> _profilesDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'param_profiles'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _saveProfile(String name) async {
    final controller = ref.read(connectionControllerProvider.notifier);
    final paramService = controller.paramService;
    if (paramService == null || _params.isEmpty) return;

    final dir = await _profilesDir();
    final safeName = name.trim().replaceAll(RegExp(r'[^\w\- ]'), '_').replaceAll(' ', '_');
    if (safeName.isEmpty) return;
    final filePath = p.join(dir.path, '$safeName.param');
    await paramService.saveToFile(filePath);
  }

  void _applyProfileToEditor(List<(String, double)> entries) {
    setState(() {
      for (final (name, value) in entries) {
        if (_params.containsKey(name)) {
          final current = _params[name]!.value;
          if ((value - current).abs() > 0.0001) {
            _modified[name] = value;
          }
        }
      }
    });
  }

  Future<void> _showProfilesDialog() async {
    final dir = await _profilesDir();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ProfilesDialog(
        profilesDir: dir,
        currentParams: _params,
        hasParams: _params.isNotEmpty,
        onSaveProfile: (name) async {
          await _saveProfile(name);
        },
        onApplyProfile: (entries) {
          _applyProfileToEditor(entries);
        },
      ),
    );
  }

  List<Parameter> _filteredParams(Map<String, ParamMeta> meta) {
    var list = _params.values.toList();

    // Standard-only filter using metadata when available.
    if (_standardOnly && meta.isNotEmpty) {
      list = list.where((p) => meta[p.id]?.isStandard == true).toList();
    }

    // Group filter (uses meta group when available, else param prefix).
    if (_selectedGroup != null) {
      list = list.where((param) {
        final g = meta[param.id]?.group;
        return (g != null && g.isNotEmpty ? g : param.group) == _selectedGroup;
      }).toList();
    }

    // Search: param ID, display name, or first 100 chars of description.
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((param) {
        if (param.id.toLowerCase().contains(q)) return true;
        final m = meta[param.id];
        if (m == null) return false;
        if (m.displayName.toLowerCase().contains(q)) return true;
        final desc = m.description.length > 100
            ? m.description.substring(0, 100)
            : m.description;
        return desc.toLowerCase().contains(q);
      }).toList();
    }

    list.sort((a, b) => a.index.compareTo(b.index));
    return list;
  }

  List<String> _groups(Map<String, ParamMeta> meta) {
    final seen = <String>{};
    for (final param in _params.values) {
      final g = meta[param.id]?.group;
      seen.add(
          (g != null && g.isNotEmpty) ? g : param.group);
    }
    return seen.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final isConnected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;
    final prefetchProgress = ref.watch(paramFetchProgressProvider);
    final isPrefetching = prefetchProgress != null && !prefetchProgress.done && _params.isEmpty;
    final meta = ref.watch(paramMetadataProvider);
    final metaLoading = ref.watch(paramMetaLoadingProvider);

    // Sync with background prefetch: update whenever cache changes (e.g. on
    // reconnect the new prefetch replaces stale params from the last session).
    ref.listen<Map<String, Parameter>>(paramCacheProvider, (prev, cached) {
      if (cached.isNotEmpty && mounted && !_fetching) {
        setState(() => _params = Map.from(cached));
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with fetch/write/export
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: isConnected && !_fetching && !isPrefetching ? _fetchParams : null,
              icon: (_fetching || isPrefetching)
                  ? SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: hc.textPrimary),
                    )
                  : const Icon(Icons.download, size: 16),
              label: Text(
                _fetching
                    ? '${(_fetchProgress * 100).toInt()}%'
                    : isPrefetching
                        ? '${(prefetchProgress.progress * 100).toInt()}%'
                        : 'Fetch All',
              ),
            ),
            const SizedBox(width: 8),
            if (_modified.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _writeAllModified,
                icon: const Icon(Icons.upload, size: 16),
                label: Text('Write ${_modified.length} Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hc.warningDim,
                ),
              ),
            const SizedBox(width: 8),
            if (_params.isNotEmpty)
              OutlinedButton.icon(
                onPressed: _exportParams,
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Export .param'),
              ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _showProfilesDialog,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Profiles'),
            ),
            const Spacer(),
            // Metadata status indicator
            if (metaLoading)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: hc.textTertiary,
                  ),
                ),
              )
            else if (meta.isNotEmpty && _params.isNotEmpty) ...[
              Text(
                '${_params.length} params, ${meta.length} with descriptions',
                style: TextStyle(color: hc.textTertiary, fontSize: 11),
              ),
              const SizedBox(width: 8),
            ] else if (_params.isNotEmpty) ...[
              Text(
                '${_params.length} params',
                style: HeliosTypography.caption,
              ),
              const SizedBox(width: 8),
            ],
            if (isConnected) ...[
              OutlinedButton.icon(
                onPressed: _rebootFc,
                icon: Icon(Icons.restart_alt, size: 16, color: hc.warning),
                label: Text('Reboot FC',
                    style: TextStyle(color: hc.warning)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: hc.warning),
                ),
              ),
            ],
          ],
        ),
        // Reboot-required banner
        if (_rebootRequired)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: hc.warning.withValues(alpha: 0.12),
              border: Border.all(color: hc.warning.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(Icons.restart_alt, size: 16, color: hc.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reboot required — one or more written parameters will not take effect until the FC is rebooted.',
                    style: TextStyle(color: hc.warning, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _rebootFc,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Reboot Now',
                      style: TextStyle(color: hc.warning, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: TextStyle(color: hc.danger, fontSize: 12)),
          ),

        if (_params.isEmpty && !_fetching)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Connect to a vehicle and tap "Fetch All" to load parameters.',
                style: TextStyle(color: hc.textTertiary, fontSize: 13),
              ),
            ),
          ),

        if (_params.isNotEmpty) ...[
          // Standard/All filter chips + search + group filter
          Row(
            children: [
              // Standard/All toggle (only visible when meta is available)
              if (meta.isNotEmpty) ...[
                _FilterChip(
                  label: 'All',
                  selected: !_standardOnly,
                  onTap: () => setState(() => _standardOnly = false),
                ),
                const SizedBox(width: 4),
                _FilterChip(
                  label: 'Standard',
                  selected: _standardOnly,
                  onTap: () => setState(() => _standardOnly = true),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: hc.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search parameters...',
                      hintStyle: TextStyle(color: hc.textTertiary),
                      prefixIcon: Icon(Icons.search, size: 18, color: hc.textTertiary),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: hc.border),
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
                      hintStyle: TextStyle(color: hc.textTertiary, fontSize: 12),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: hc.border),
                      ),
                    ),
                    dropdownColor: hc.surfaceLight,
                    style: TextStyle(color: hc.textPrimary, fontSize: 12),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Groups')),
                      ..._groups(meta).map((g) => DropdownMenuItem(value: g, child: Text(g))),
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
            child: _buildParamTable(meta),
          ),
        ],
      ],
    );
  }

  Widget _buildParamTable(Map<String, ParamMeta> meta) {
    final filtered = _filteredParams(meta);

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (ctx, index) {
        final hc = ctx.hc;
        final param = filtered[index];
        final paramMeta = meta[param.id];
        final isModified = _modified.containsKey(param.id);
        final displayValue = isModified ? _modified[param.id]! : param.value;
        final rebootParam = _needsReboot(param.id);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isModified
                ? hc.warning.withValues(alpha: 0.08)
                : (index.isEven
                    ? Colors.transparent
                    : hc.surfaceLight.withValues(alpha: 0.3)),
            border: Border(
              bottom: BorderSide(color: hc.border, width: 0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Param identity column
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ID row with reboot indicator
                    Row(
                      children: [
                        if (rebootParam)
                          Tooltip(
                            message: 'Requires reboot to take effect',
                            child: Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.restart_alt,
                                  size: 11,
                                  color: hc.warning.withValues(alpha: 0.7)),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            param.id,
                            style: TextStyle(
                              color: isModified
                                  ? hc.warning
                                  : hc.textSecondary,
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: isModified
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (paramMeta != null && paramMeta.units.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(
                            paramMeta.units,
                            style: TextStyle(
                                color: hc.textTertiary, fontSize: 10),
                          ),
                        ],
                      ],
                    ),
                    // Display name (bolder, from humanName)
                    if (paramMeta != null &&
                        paramMeta.displayName.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        paramMeta.displayName,
                        style: TextStyle(
                          color: isModified ? hc.warning : hc.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    // Description (2-line clipped)
                    if (paramMeta != null &&
                        paramMeta.description.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        paramMeta.description,
                        style: TextStyle(
                            color: hc.textTertiary, fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Value editor column
              SizedBox(
                width: 160,
                child: paramMeta != null && paramMeta.hasEnumValues
                    ? _ParamEnumField(
                        value: displayValue,
                        enumValues: paramMeta.values,
                        onChanged: (newVal) {
                          setState(() {
                            if (newVal == param.value) {
                              _modified.remove(param.id);
                            } else {
                              _modified[param.id] = newVal;
                            }
                          });
                        },
                      )
                    : _ParamValueField(
                        value: displayValue,
                        isInteger: param.isInteger,
                        rangeMin: paramMeta?.rangeMin,
                        rangeMax: paramMeta?.rangeMax,
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
              // Bitmask info button
              if (paramMeta != null && paramMeta.isBitmask)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.grid_on,
                        size: 14, color: hc.accent.withValues(alpha: 0.8)),
                    tooltip: 'Bitmask breakdown',
                    onPressed: () => _showBitmaskDialog(
                      context: ctx,
                      param: param,
                      meta: paramMeta,
                      currentValue: displayValue,
                      onApply: (newVal) {
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
                )
              else
                const SizedBox(width: 28),
              // Write button (per-param)
              if (isModified)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.check, size: 14, color: hc.success),
                    onPressed: () =>
                        _writeParam(param.id, _modified[param.id]!),
                    tooltip: 'Write',
                  ),
                )
              else
                const SizedBox(width: 28),
            ],
          ),
        );
      },
    );
  }

  void _showBitmaskDialog({
    required BuildContext context,
    required Parameter param,
    required ParamMeta meta,
    required double currentValue,
    required void Function(double) onApply,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _BitmaskDialog(
        paramId: param.id,
        displayName: meta.displayName,
        bits: meta.bitmaskBits,
        currentValue: currentValue.toInt(),
        onApply: (newInt) {
          onApply(newInt.toDouble());
          Navigator.pop(ctx);
        },
      ),
    );
  }
}

// ─── Filter chip ─────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? hc.accent.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(
            color: selected ? hc.accent : hc.border,
            width: selected ? 1 : 0.5,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? hc.accent : hc.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ─── Enum dropdown field ─────────────────────────────────────────────────────

/// Shows a labelled dropdown for known enum values PLUS a compact text field
/// so the user can type a raw number directly (e.g. for undocumented values).
class _ParamEnumField extends StatefulWidget {
  const _ParamEnumField({
    required this.value,
    required this.enumValues,
    required this.onChanged,
  });

  final double value;
  final Map<int, String> enumValues;
  final void Function(double) onChanged;

  @override
  State<_ParamEnumField> createState() => _ParamEnumFieldState();
}

class _ParamEnumFieldState extends State<_ParamEnumField> {
  late TextEditingController _textController;
  bool _textFocused = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.value.toInt().toString(),
    );
  }

  @override
  void didUpdateWidget(_ParamEnumField old) {
    super.didUpdateWidget(old);
    // Keep text field in sync when value changes externally (e.g. dropdown),
    // but only when the text field is not actively being edited.
    if (!_textFocused && old.value != widget.value) {
      _textController.text = widget.value.toInt().toString();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final intVal = widget.value.toInt();
    final currentKey =
        widget.enumValues.containsKey(intVal) ? intVal : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Labelled dropdown
        SizedBox(
          height: 26,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: currentKey,
              isExpanded: true,
              isDense: true,
              dropdownColor: hc.surfaceLight,
              style: TextStyle(color: hc.textPrimary, fontSize: 12),
              hint: Text(
                intVal.toString(),
                style: TextStyle(color: hc.textTertiary, fontSize: 12),
              ),
              items: widget.enumValues.entries.map((e) {
                return DropdownMenuItem<int>(
                  value: e.key,
                  child: Text(
                    '${e.key}: ${e.value}',
                    style: TextStyle(color: hc.textPrimary, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  _textController.text = v.toString();
                  widget.onChanged(v.toDouble());
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 3),
        // Raw number entry
        SizedBox(
          height: 24,
          child: Focus(
            onFocusChange: (focused) => setState(() => _textFocused = focused),
            child: TextField(
              controller: _textController,
              keyboardType:
                  const TextInputType.numberWithOptions(signed: true),
              style: TextStyle(
                  color: hc.textSecondary,
                  fontSize: 11,
                  fontFamily: 'monospace'),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                hintText: 'number',
                hintStyle:
                    TextStyle(color: hc.textTertiary, fontSize: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: hc.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide:
                      BorderSide(color: hc.border.withValues(alpha: 0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: hc.accent),
                ),
              ),
              onSubmitted: (text) {
                final parsed = int.tryParse(text.trim());
                if (parsed != null) {
                  widget.onChanged(parsed.toDouble());
                } else {
                  // Reset to current value if invalid
                  _textController.text =
                      widget.value.toInt().toString();
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Bitmask dialog ──────────────────────────────────────────────────────────

class _BitmaskDialog extends StatefulWidget {
  const _BitmaskDialog({
    required this.paramId,
    required this.displayName,
    required this.bits,
    required this.currentValue,
    required this.onApply,
  });

  final String paramId;
  final String displayName;
  final Map<int, String> bits;
  final int currentValue;
  final void Function(int) onApply;

  @override
  State<_BitmaskDialog> createState() => _BitmaskDialogState();
}

class _BitmaskDialogState extends State<_BitmaskDialog> {
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.currentValue;
  }

  bool _isSet(int bit) => (_value & (1 << bit)) != 0;

  void _toggle(int bit) {
    setState(() {
      if (_isSet(bit)) {
        _value &= ~(1 << bit);
      } else {
        _value |= (1 << bit);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final sortedBits = widget.bits.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return AlertDialog(
      backgroundColor: hc.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.paramId,
            style: TextStyle(
                color: hc.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace'),
          ),
          if (widget.displayName.isNotEmpty)
            Text(
              widget.displayName,
              style: TextStyle(
                  color: hc.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Current value display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: hc.surfaceLight,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: hc.border),
              ),
              child: Text(
                'Value: $_value',
                style: TextStyle(
                    color: hc.textPrimary,
                    fontSize: 13,
                    fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 8),
            // Bit checkboxes
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  children: sortedBits.map((e) {
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _isSet(e.key),
                      onChanged: (_) => _toggle(e.key),
                      title: Text(
                        'Bit ${e.key}: ${e.value}',
                        style: TextStyle(
                            color: hc.textPrimary, fontSize: 12),
                      ),
                      checkColor: hc.background,
                      activeColor: hc.accent,
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: hc.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () => widget.onApply(_value),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _ParamValueField extends StatefulWidget {
  const _ParamValueField({
    required this.value,
    required this.isInteger,
    required this.onChanged,
    this.rangeMin,
    this.rangeMax,
  });

  final double value;
  final bool isInteger;
  final double? rangeMin;
  final double? rangeMax;
  final void Function(double) onChanged;

  @override
  State<_ParamValueField> createState() => _ParamValueFieldState();
}

class _ParamValueFieldState extends State<_ParamValueField> {
  late TextEditingController _ctrl;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _format(widget.value));
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit(_ctrl.text);
  }

  void _commit(String text) {
    final v = double.tryParse(text);
    if (v != null) widget.onChanged(v);
  }

  @override
  void didUpdateWidget(_ParamValueField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focus.hasFocus) {
      _ctrl.text = _format(widget.value);
    }
  }

  String _format(double v) =>
      widget.isInteger ? v.toInt().toString() : v.toStringAsFixed(4);

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  String? get _rangeHint {
    final min = widget.rangeMin;
    final max = widget.rangeMax;
    if (min == null && max == null) return null;
    String fmt(double v) =>
        v == v.toInt() ? v.toInt().toString() : v.toStringAsFixed(4);
    if (min != null && max != null) return '${fmt(min)} – ${fmt(max)}';
    if (min != null) return '≥ ${fmt(min)}';
    return '≤ ${fmt(max!)}';
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return SizedBox(
      height: 26,
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        style: TextStyle(
          color: hc.textPrimary,
          fontSize: 12,
          fontFamily: 'monospace',
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: _rangeHint,
          hintStyle: TextStyle(color: hc.textTertiary, fontSize: 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: BorderSide(color: hc.border, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: BorderSide(color: hc.border, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(3),
            borderSide: BorderSide(color: hc.accent, width: 1),
          ),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onSubmitted: _commit,
      ),
    );
  }
}

// ─── Parameter Profiles Dialog ───────────────────────────────────────────────

class _ProfilesDialog extends StatefulWidget {
  const _ProfilesDialog({
    required this.profilesDir,
    required this.currentParams,
    required this.hasParams,
    required this.onSaveProfile,
    required this.onApplyProfile,
  });

  final Directory profilesDir;
  final Map<String, Parameter> currentParams;
  final bool hasParams;
  final Future<void> Function(String name) onSaveProfile;
  final void Function(List<(String, double)> entries) onApplyProfile;

  @override
  State<_ProfilesDialog> createState() => _ProfilesDialogState();
}

class _ProfilesDialogState extends State<_ProfilesDialog> {
  List<File> _profiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final entities = await widget.profilesDir.list().toList();
    final files = entities
        .whereType<File>()
        .where((f) => f.path.endsWith('.param'))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    if (mounted) setState(() { _profiles = files; _loading = false; });
  }

  Future<void> _promptSave() async {
    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final hc = ctx.hc;
        return AlertDialog(
          backgroundColor: hc.surface,
          title: Text('Save Profile', style: TextStyle(color: hc.textPrimary, fontSize: 15)),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            style: TextStyle(color: hc.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Profile name',
              hintStyle: TextStyle(color: hc.textTertiary),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(borderSide: BorderSide(color: hc.border)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: hc.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && nameCtrl.text.trim().isNotEmpty) {
      await widget.onSaveProfile(nameCtrl.text.trim());
      setState(() => _loading = true);
      await _loadProfiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile "${nameCtrl.text.trim()}" saved'),
            backgroundColor: context.hc.success,
          ),
        );
      }
    }
    nameCtrl.dispose();
  }

  Future<void> _deleteProfile(File file) async {
    final name = p.basenameWithoutExtension(file.path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final hc = ctx.hc;
        return AlertDialog(
          backgroundColor: hc.surface,
          title: Text('Delete Profile', style: TextStyle(color: hc.textPrimary, fontSize: 15)),
          content: Text('Delete "$name"?', style: TextStyle(color: hc.textSecondary, fontSize: 13)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: hc.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: ctx.hc.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await file.delete();
      setState(() => _loading = true);
      await _loadProfiles();
    }
  }

  Future<void> _viewDiff(File file) async {
    final content = await file.readAsString();
    final entries = ParameterService.parseParamFile(content);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => _ProfileDiffDialog(
        profileName: p.basenameWithoutExtension(file.path),
        profileEntries: entries,
        currentParams: widget.currentParams,
        onApply: (toApply) {
          widget.onApplyProfile(toApply);
          Navigator.pop(ctx);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Dialog(
      backgroundColor: hc.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.folder_open, size: 18, color: hc.accent),
                  const SizedBox(width: 8),
                  Text('Parameter Profiles',
                      style: TextStyle(color: hc.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: hc.textTertiary),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Divider(height: 20, color: hc.border),

            // Save button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton.icon(
                onPressed: widget.hasParams ? _promptSave : null,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Save Current as Profile'),
              ),
            ),
            if (!widget.hasParams)
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 6),
                child: Text('Fetch parameters first to save a profile.',
                    style: TextStyle(color: hc.textTertiary, fontSize: 11)),
              ),

            const SizedBox(height: 12),

            // Profile list
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _profiles.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                          child: Text(
                            'No profiles saved yet.',
                            style: TextStyle(color: hc.textTertiary, fontSize: 13),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          itemCount: _profiles.length,
                          separatorBuilder: (_, _) => Divider(height: 1, color: hc.border),
                          itemBuilder: (ctx, i) {
                            final file = _profiles[i];
                            final name = p.basenameWithoutExtension(file.path);
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: Icon(Icons.tune, size: 16, color: hc.textTertiary),
                              title: Text(name,
                                  style: TextStyle(color: hc.textPrimary, fontSize: 13)),
                              subtitle: FutureBuilder<FileStat>(
                                future: file.stat(),
                                builder: (_, snap) {
                                  if (!snap.hasData) return const SizedBox.shrink();
                                  final m = snap.data!.modified;
                                  return Text(
                                    '${m.year}-${m.month.toString().padLeft(2,'0')}-${m.day.toString().padLeft(2,'0')}',
                                    style: TextStyle(color: hc.textTertiary, fontSize: 11),
                                  );
                                },
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () => _viewDiff(file),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text('Load', style: TextStyle(color: hc.accent, fontSize: 12)),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, size: 16, color: hc.textTertiary),
                                    onPressed: () => _deleteProfile(file),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Delete',
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Profile Diff Dialog ─────────────────────────────────────────────────────

class _ProfileDiffDialog extends StatelessWidget {
  const _ProfileDiffDialog({
    required this.profileName,
    required this.profileEntries,
    required this.currentParams,
    required this.onApply,
  });

  final String profileName;
  final List<(String, double)> profileEntries;
  final Map<String, Parameter> currentParams;
  final void Function(List<(String, double)> toApply) onApply;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    // Compute diff
    final changed = <(String, double, double)>[]; // name, old, new
    final added = <(String, double)>[];            // in profile, not in current

    for (final (name, value) in profileEntries) {
      if (currentParams.containsKey(name)) {
        final current = currentParams[name]!.value;
        if ((value - current).abs() > 0.0001) {
          changed.add((name, current, value));
        }
      } else {
        added.add((name, value));
      }
    }

    final toApply = [
      ...changed.map((c) => (c.$1, c.$3)),
      ...added,
    ];

    Widget section(String title, List<Widget> rows) {
      if (rows.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: hc.textTertiary, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ...rows,
          const SizedBox(height: 12),
        ],
      );
    }

    String fmt(double v) => v == v.toInt() ? v.toInt().toString() : v.toStringAsFixed(4);

    return Dialog(
      backgroundColor: hc.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.compare_arrows, size: 18, color: hc.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Profile: $profileName',
                      style: TextStyle(
                          color: hc.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: hc.textTertiary),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Divider(height: 20, color: hc.border),

            // Diff content
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: toApply.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline, size: 16, color: hc.success),
                            const SizedBox(width: 8),
                            Text(
                              'No differences — profile matches current parameters.',
                              style: TextStyle(color: hc.textSecondary, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          section(
                            'CHANGED (${changed.length})',
                            changed.map((c) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 200,
                                      child: Text(
                                        c.$1,
                                        style: TextStyle(
                                            color: hc.textPrimary,
                                            fontSize: 12,
                                            fontFamily: 'monospace'),
                                      ),
                                    ),
                                    Text(fmt(c.$2),
                                        style: TextStyle(
                                            color: hc.textTertiary, fontSize: 12,
                                            fontFamily: 'monospace')),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Icon(Icons.arrow_forward,
                                          size: 12, color: hc.textTertiary),
                                    ),
                                    Text(fmt(c.$3),
                                        style: TextStyle(
                                            color: hc.warning, fontSize: 12,
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                          section(
                            'IN PROFILE ONLY (${added.length})',
                            added.map((a) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 200,
                                      child: Text(
                                        a.$1,
                                        style: TextStyle(
                                            color: hc.textTertiary,
                                            fontSize: 12,
                                            fontFamily: 'monospace'),
                                      ),
                                    ),
                                    Text(fmt(a.$2),
                                        style: TextStyle(
                                            color: hc.textTertiary,
                                            fontSize: 12,
                                            fontFamily: 'monospace')),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
              ),
            ),

            Divider(height: 16, color: hc.border),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  if (toApply.isNotEmpty)
                    Text(
                      '${toApply.length} param${toApply.length == 1 ? '' : 's'} will be staged for write',
                      style: TextStyle(color: hc.textTertiary, fontSize: 11),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: hc.textSecondary)),
                  ),
                  if (toApply.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => onApply(toApply),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Apply to Editor'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
