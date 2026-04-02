import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/params/parameter_service.dart';
import '../../../core/params/param_meta.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Failsafe configuration panel — reads/writes ArduPilot failsafe parameters.
class FailsafePanel extends ConsumerStatefulWidget {
  const FailsafePanel({super.key});

  @override
  ConsumerState<FailsafePanel> createState() => _FailsafePanelState();
}

class _FailsafePanelState extends ConsumerState<FailsafePanel> {
  /// Local edits not yet written to the FC. Key = param name, value = new value.
  final _modified = <String, double>{};
  bool _writing = false;
  String? _error;

  double _paramValue(String name) {
    if (_modified.containsKey(name)) return _modified[name]!;
    final params = ref.read(paramCacheProvider);
    return params[name]?.value ?? 0;
  }

  void _setLocal(String name, double value) {
    setState(() {
      final params = ref.read(paramCacheProvider);
      final current = params[name]?.value ?? 0;
      if (value == current) {
        _modified.remove(name);
      } else {
        _modified[name] = value;
      }
    });
  }

  Future<void> _writeChanges() async {
    if (_modified.isEmpty) return;
    final controller = ref.read(connectionControllerProvider.notifier);
    final paramService = controller.paramService;
    if (paramService == null) return;

    final vehicle = ref.read(vehicleStateProvider);
    setState(() {
      _writing = true;
      _error = null;
    });

    final toWrite = Map<String, double>.from(_modified);
    final params = ref.read(paramCacheProvider);

    for (final entry in toWrite.entries) {
      try {
        await paramService.setParam(
          targetSystem: vehicle.systemId,
          targetComponent: vehicle.componentId,
          paramId: entry.key,
          value: entry.value,
          paramType: params[entry.key]?.type ?? 9,
        );
        if (mounted) {
          setState(() => _modified.remove(entry.key));
          // Update cache
          final cached = ref.read(paramCacheProvider);
          if (cached.containsKey(entry.key)) {
            final updated = Map<String, Parameter>.from(cached);
            updated[entry.key] = updated[entry.key]!.copyWith(value: entry.value);
            ref.read(paramCacheProvider.notifier).state = updated;
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _error = 'Failed to write ${entry.key}: $e');
          break;
        }
      }
    }

    if (mounted) setState(() => _writing = false);
  }

  void _resetToDefaults() {
    setState(() {
      _modified.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final params = ref.watch(paramCacheProvider);
    final meta = ref.watch(paramMetadataProvider);
    final connected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;
    final hasParams = params.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Configure failsafe actions for battery, RC loss, GCS loss, '
            'EKF failure, and geofence breaches.',
            style: HeliosTypography.small.copyWith(color: hc.textSecondary),
          ),
          const SizedBox(height: 16),

          if (!connected || !hasParams)
            _InfoBanner(
              hc: hc,
              message: !connected
                  ? 'Connect to a vehicle to configure failsafes.'
                  : 'Waiting for parameters to load...',
            ),

          if (hasParams) ...[
            // Battery failsafe
            _SectionCard(
              hc: hc,
              icon: Icons.battery_alert,
              title: 'Battery Failsafe',
              children: [
                _DropdownParam(
                  hc: hc,
                  paramName: 'FS_BATT_ENABLE',
                  label: 'Action',
                  value: _paramValue('FS_BATT_ENABLE').toInt(),
                  options: const {
                    0: 'Disabled',
                    1: 'Land',
                    2: 'RTL',
                    3: 'SmartRTL or RTL',
                  },
                  description: _desc(meta, 'FS_BATT_ENABLE'),
                  onChanged: (v) => _setLocal('FS_BATT_ENABLE', v.toDouble()),
                ),
                _SliderParam(
                  hc: hc,
                  paramName: 'FS_BATT_VOLTAGE',
                  label: 'Low Voltage Threshold',
                  value: _paramValue('FS_BATT_VOLTAGE'),
                  min: 0,
                  max: 42,
                  divisions: 420,
                  unit: 'V',
                  decimals: 1,
                  description: _desc(meta, 'FS_BATT_VOLTAGE'),
                  onChanged: (v) => _setLocal('FS_BATT_VOLTAGE', v),
                ),
                _SliderParam(
                  hc: hc,
                  paramName: 'FS_BATT_MAH',
                  label: 'Low mAh Threshold',
                  value: _paramValue('FS_BATT_MAH'),
                  min: 0,
                  max: 10000,
                  divisions: 100,
                  unit: 'mAh',
                  decimals: 0,
                  description: _desc(meta, 'FS_BATT_MAH'),
                  onChanged: (v) => _setLocal('FS_BATT_MAH', v),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // RC failsafe
            _SectionCard(
              hc: hc,
              icon: Icons.settings_remote,
              title: 'RC Failsafe',
              children: [
                _DropdownParam(
                  hc: hc,
                  paramName: 'FS_THR_ENABLE',
                  label: 'Action',
                  value: _paramValue('FS_THR_ENABLE').toInt(),
                  options: const {
                    0: 'Disabled',
                    1: 'RTL',
                    2: 'Continue Mission',
                    3: 'Land',
                  },
                  description: _desc(meta, 'FS_THR_ENABLE'),
                  onChanged: (v) => _setLocal('FS_THR_ENABLE', v.toDouble()),
                ),
                _SliderParam(
                  hc: hc,
                  paramName: 'FS_THR_VALUE',
                  label: 'PWM Threshold',
                  value: _paramValue('FS_THR_VALUE'),
                  min: 900,
                  max: 1100,
                  divisions: 200,
                  unit: 'us',
                  decimals: 0,
                  description: _desc(meta, 'FS_THR_VALUE'),
                  onChanged: (v) => _setLocal('FS_THR_VALUE', v),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // GCS failsafe
            _SectionCard(
              hc: hc,
              icon: Icons.computer,
              title: 'GCS Failsafe',
              children: [
                _DropdownParam(
                  hc: hc,
                  paramName: 'FS_GCS_ENABLE',
                  label: 'Action',
                  value: _paramValue('FS_GCS_ENABLE').toInt(),
                  options: const {
                    0: 'Disabled',
                    1: 'RTL',
                    2: 'Continue Mission',
                    3: 'Land',
                  },
                  description: _desc(meta, 'FS_GCS_ENABLE'),
                  onChanged: (v) => _setLocal('FS_GCS_ENABLE', v.toDouble()),
                ),
                _SliderParam(
                  hc: hc,
                  paramName: 'FS_GCS_TIMEOUT',
                  label: 'Timeout',
                  value: _paramValue('FS_GCS_TIMEOUT'),
                  min: 0,
                  max: 60,
                  divisions: 60,
                  unit: 's',
                  decimals: 0,
                  description: _desc(meta, 'FS_GCS_TIMEOUT'),
                  onChanged: (v) => _setLocal('FS_GCS_TIMEOUT', v),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // EKF failsafe
            _SectionCard(
              hc: hc,
              icon: Icons.navigation,
              title: 'EKF / Inertial Nav Failsafe',
              children: [
                _DropdownParam(
                  hc: hc,
                  paramName: 'FS_EKF_ACTION',
                  label: 'Action',
                  value: _paramValue('FS_EKF_ACTION').toInt(),
                  options: const {
                    1: 'Land',
                    2: 'AltHold',
                    3: 'Land (even in Stabilize)',
                  },
                  description: _desc(meta, 'FS_EKF_ACTION'),
                  onChanged: (v) => _setLocal('FS_EKF_ACTION', v.toDouble()),
                ),
                _SliderParam(
                  hc: hc,
                  paramName: 'FS_EKF_THRESH',
                  label: 'Variance Threshold',
                  value: _paramValue('FS_EKF_THRESH'),
                  min: 0.6,
                  max: 1.0,
                  divisions: 40,
                  unit: '',
                  decimals: 2,
                  description: _desc(meta, 'FS_EKF_THRESH'),
                  onChanged: (v) => _setLocal('FS_EKF_THRESH', v),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Geofence
            _SectionCard(
              hc: hc,
              icon: Icons.fence,
              title: 'Geofence',
              children: [
                _DropdownParam(
                  hc: hc,
                  paramName: 'FENCE_ENABLE',
                  label: 'Enable',
                  value: _paramValue('FENCE_ENABLE').toInt(),
                  options: const {0: 'Disabled', 1: 'Enabled'},
                  description: _desc(meta, 'FENCE_ENABLE'),
                  onChanged: (v) => _setLocal('FENCE_ENABLE', v.toDouble()),
                ),
                _DropdownParam(
                  hc: hc,
                  paramName: 'FENCE_ACTION',
                  label: 'Breach Action',
                  value: _paramValue('FENCE_ACTION').toInt(),
                  options: const {
                    0: 'Report Only',
                    1: 'RTL',
                    2: 'Land',
                    3: 'SmartRTL or RTL',
                  },
                  description: _desc(meta, 'FENCE_ACTION'),
                  onChanged: (v) => _setLocal('FENCE_ACTION', v.toDouble()),
                ),
                _SliderParam(
                  hc: hc,
                  paramName: 'FENCE_ALT_MAX',
                  label: 'Max Altitude',
                  value: _paramValue('FENCE_ALT_MAX'),
                  min: 0,
                  max: 1000,
                  divisions: 200,
                  unit: 'm',
                  decimals: 0,
                  description: _desc(meta, 'FENCE_ALT_MAX'),
                  onChanged: (v) => _setLocal('FENCE_ALT_MAX', v),
                ),
                _SliderParam(
                  hc: hc,
                  paramName: 'FENCE_RADIUS',
                  label: 'Max Radius',
                  value: _paramValue('FENCE_RADIUS'),
                  min: 0,
                  max: 10000,
                  divisions: 200,
                  unit: 'm',
                  decimals: 0,
                  description: _desc(meta, 'FENCE_RADIUS'),
                  onChanged: (v) => _setLocal('FENCE_RADIUS', v),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Write / Reset buttons
            if (_modified.isNotEmpty || _error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: hc.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: hc.warning.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_modified.length} parameter(s) modified',
                      style: HeliosTypography.caption
                          .copyWith(color: hc.warning),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _error!,
                        style: HeliosTypography.small
                            .copyWith(color: hc.danger),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _writing ? null : _writeChanges,
                            icon: _writing
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: hc.textPrimary,
                                    ),
                                  )
                                : const Icon(Icons.save, size: 16),
                            label: Text(
                                _writing ? 'Writing...' : 'Write Changes'),
                            style: FilledButton.styleFrom(
                              backgroundColor: hc.accent,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: _writing ? null : _resetToDefaults,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: hc.border),
                            foregroundColor: hc.textSecondary,
                          ),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _desc(Map<String, ParamMeta> meta, String name) {
    return meta[name]?.description ?? '';
  }
}

// ─── Info Banner ────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.hc, required this.message});
  final HeliosColors hc;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hc.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: hc.textTertiary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: HeliosTypography.small.copyWith(color: hc.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section Card ───────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.hc,
    required this.icon,
    required this.title,
    required this.children,
  });

  final HeliosColors hc;
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: hc.accent),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: HeliosTypography.heading2
                      .copyWith(color: hc.textPrimary),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: hc.border),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1) const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dropdown Param ─────────────────────────────────────────────────────────

class _DropdownParam extends StatelessWidget {
  const _DropdownParam({
    required this.hc,
    required this.paramName,
    required this.label,
    required this.value,
    required this.options,
    required this.description,
    required this.onChanged,
  });

  final HeliosColors hc;
  final String paramName;
  final String label;
  final int value;
  final Map<int, String> options;
  final String description;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: HeliosTypography.body
                        .copyWith(color: hc.textPrimary),
                  ),
                  Text(
                    paramName,
                    style: HeliosTypography.small.copyWith(
                      color: hc.textTertiary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: hc.surfaceLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: hc.border),
              ),
              child: DropdownButton<int>(
                value: options.containsKey(value) ? value : options.keys.first,
                items: options.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(
                            e.value,
                            style: HeliosTypography.caption
                                .copyWith(color: hc.textPrimary),
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
                underline: const SizedBox.shrink(),
                dropdownColor: hc.surface,
                iconEnabledColor: hc.textSecondary,
                isDense: true,
              ),
            ),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            description,
            style: HeliosTypography.small.copyWith(color: hc.textTertiary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

// ─── Slider Param ───────────────────────────────────────────────────────────

class _SliderParam extends StatelessWidget {
  const _SliderParam({
    required this.hc,
    required this.paramName,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.unit,
    required this.decimals,
    required this.description,
    required this.onChanged,
  });

  final HeliosColors hc;
  final String paramName;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final int decimals;
  final String description;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style:
                        HeliosTypography.body.copyWith(color: hc.textPrimary),
                  ),
                  Text(
                    paramName,
                    style: HeliosTypography.small.copyWith(
                      color: hc.textTertiary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${clamped.toStringAsFixed(decimals)}$unit',
              style: HeliosTypography.telemetryMedium
                  .copyWith(color: hc.accent, fontSize: 14),
            ),
          ],
        ),
        Slider(
          value: clamped,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: hc.accent,
          inactiveColor: hc.border,
          onChanged: onChanged,
        ),
        if (description.isNotEmpty)
          Text(
            description,
            style: HeliosTypography.small.copyWith(color: hc.textTertiary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}
