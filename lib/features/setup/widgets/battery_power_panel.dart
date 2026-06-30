import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calibration/battery_calibration.dart';
import '../../../core/params/parameter_service.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

part 'battery_power_widgets.dart';

/// Battery / power-monitor setup and calibration panel.
///
/// Lets the pilot pick the monitor type (`BATT_MONITOR`), edit the voltage and
/// current sense pins and multipliers, calibrate the voltage/current
/// multipliers against a trusted measurement, set the pack capacity, and verify
/// the result against live `SYS_STATUS` voltage/current telemetry.
class BatteryPowerPanel extends ConsumerStatefulWidget {
  const BatteryPowerPanel({super.key});

  @override
  ConsumerState<BatteryPowerPanel> createState() => _BatteryPowerPanelState();
}

class _BatteryPowerPanelState extends ConsumerState<BatteryPowerPanel> {
  /// Local edits not yet written to the FC. Key = param name, value = new value.
  final _modified = <String, double>{};
  bool _writing = false;
  String? _error;

  double _paramValue(String name) {
    if (_modified.containsKey(name)) return _modified[name]!;
    final params = ref.read(paramCacheProvider);
    return params[name]?.value ?? 0;
  }

  bool _hasParam(String name) =>
      _modified.containsKey(name) ||
      ref.read(paramCacheProvider).containsKey(name);

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
        // setParam echoes back the FC-confirmed value (read-back confirmation).
        final confirmed = await paramService.setParam(
          targetSystem: vehicle.systemId,
          targetComponent: vehicle.componentId,
          paramId: entry.key,
          value: entry.value,
          paramType: params[entry.key]?.type ?? 9,
        );
        if (mounted) {
          setState(() => _modified.remove(entry.key));
          final cached = ref.read(paramCacheProvider);
          if (cached.containsKey(entry.key)) {
            final updated = Map<String, Parameter>.from(cached);
            updated[entry.key] =
                updated[entry.key]!.copyWith(value: confirmed);
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

  void _resetChanges() {
    setState(() {
      _modified.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final params = ref.watch(paramCacheProvider);
    final vehicle = ref.watch(vehicleStateProvider);
    final connected =
        ref.watch(connectionControllerProvider).transportState ==
            TransportState.connected;
    final hasParams = params.isNotEmpty;
    final monitorEnabled = _paramValue('BATT_MONITOR').toInt() != 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select the power monitor, calibrate the voltage and current '
            'sensors against trusted measurements, and set the pack capacity. '
            'Live readings below confirm the calibration takes effect.',
            style: HeliosTypography.small.copyWith(color: hc.textSecondary),
          ),
          const SizedBox(height: 16),

          if (!connected || !hasParams)
            _InfoBanner(
              hc: hc,
              message: !connected
                  ? 'Connect to a vehicle to configure the power monitor.'
                  : 'Waiting for parameters to load...',
            ),

          // Live readouts are always shown so the pilot can watch them change.
          _LiveReadouts(hc: hc, vehicle: vehicle, connected: connected),
          const SizedBox(height: 12),

          if (hasParams) ...[
            // Monitor selection
            _SectionCard(
              hc: hc,
              icon: Icons.battery_charging_full,
              title: 'Power Monitor',
              children: [
                _DropdownParam(
                  hc: hc,
                  paramName: 'BATT_MONITOR',
                  label: 'Monitor Type',
                  value: _paramValue('BATT_MONITOR').toInt(),
                  options: const {
                    0: 'Disabled',
                    3: 'Analog Voltage Only',
                    4: 'Analog Voltage and Current',
                    5: 'Solo',
                    6: 'Bebop',
                    7: 'SMBus-Generic',
                    8: 'DroneCAN-BatteryInfo',
                    9: 'ESC',
                    10: 'Sum Of Selected Monitors',
                    11: 'FuelFlow',
                    12: 'FuelLevelPWM',
                  },
                  onChanged: (v) =>
                      _setLocal('BATT_MONITOR', v.toDouble()),
                ),
                if (_paramValue('BATT_MONITOR').toInt() == 0)
                  _Hint(
                    hc: hc,
                    text:
                        'Monitor is disabled — no voltage or current will be '
                        'reported. Pick a type to enable sensing.',
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Sense pins
            if (_hasParam('BATT_VOLT_PIN') ||
                _hasParam('BATT_CURR_PIN')) ...[
              _SectionCard(
                hc: hc,
                icon: Icons.cable,
                title: 'Sense Pins',
                children: [
                  if (_hasParam('BATT_VOLT_PIN'))
                    _NumberParam(
                      hc: hc,
                      paramName: 'BATT_VOLT_PIN',
                      label: 'Voltage Pin',
                      value: _paramValue('BATT_VOLT_PIN'),
                      decimals: 0,
                      onChanged: (v) => _setLocal('BATT_VOLT_PIN', v),
                    ),
                  if (_hasParam('BATT_CURR_PIN'))
                    _NumberParam(
                      hc: hc,
                      paramName: 'BATT_CURR_PIN',
                      label: 'Current Pin',
                      value: _paramValue('BATT_CURR_PIN'),
                      decimals: 0,
                      onChanged: (v) => _setLocal('BATT_CURR_PIN', v),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Voltage calibration
            _SectionCard(
              hc: hc,
              icon: Icons.bolt,
              title: 'Voltage Calibration',
              children: [
                _NumberParam(
                  hc: hc,
                  paramName: 'BATT_VOLT_MULT',
                  label: 'Voltage Multiplier',
                  value: _paramValue('BATT_VOLT_MULT'),
                  decimals: 4,
                  onChanged: (v) => _setLocal('BATT_VOLT_MULT', v),
                ),
                _MeasurementCalibrator(
                  hc: hc,
                  label: 'Measured Voltage',
                  unit: 'V',
                  hintText:
                      'Measure the pack with a multimeter and enter it to '
                      'compute BATT_VOLT_MULT.',
                  enabled: monitorEnabled,
                  compute: (measured) {
                    final res = computeVoltageMultiplier(
                      currentMultiplier: _paramValue('BATT_VOLT_MULT'),
                      reportedVoltage: vehicle.batteryVoltage,
                      measuredVoltage: measured,
                    );
                    return res.valid ? res.value : null;
                  },
                  onApply: (newMult) =>
                      _setLocal('BATT_VOLT_MULT', newMult),
                  resultLabel: 'New BATT_VOLT_MULT',
                  resultDecimals: 4,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Current calibration
            _SectionCard(
              hc: hc,
              icon: Icons.electrical_services,
              title: 'Current Calibration',
              children: [
                _NumberParam(
                  hc: hc,
                  paramName: 'BATT_AMP_PERVLT',
                  label: 'Amps per Volt',
                  value: _paramValue('BATT_AMP_PERVLT'),
                  decimals: 4,
                  onChanged: (v) => _setLocal('BATT_AMP_PERVLT', v),
                ),
                if (_hasParam('BATT_AMP_OFFSET'))
                  _NumberParam(
                    hc: hc,
                    paramName: 'BATT_AMP_OFFSET',
                    label: 'Amp Offset',
                    value: _paramValue('BATT_AMP_OFFSET'),
                    decimals: 4,
                    onChanged: (v) => _setLocal('BATT_AMP_OFFSET', v),
                  ),
                _MeasurementCalibrator(
                  hc: hc,
                  label: 'Measured Current',
                  unit: 'A',
                  hintText:
                      'With a steady load drawing current, enter the clamp-'
                      'meter reading to compute BATT_AMP_PERVLT.',
                  enabled: monitorEnabled,
                  compute: (measured) {
                    final res = computeCurrentPerVolt(
                      currentPerVolt: _paramValue('BATT_AMP_PERVLT'),
                      reportedCurrent: vehicle.batteryCurrent,
                      measuredCurrent: measured,
                    );
                    return res.valid ? res.value : null;
                  },
                  onApply: (newPerVolt) =>
                      _setLocal('BATT_AMP_PERVLT', newPerVolt),
                  resultLabel: 'New BATT_AMP_PERVLT',
                  resultDecimals: 4,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Capacity
            _SectionCard(
              hc: hc,
              icon: Icons.battery_full,
              title: 'Pack Capacity',
              children: [
                _NumberParam(
                  hc: hc,
                  paramName: 'BATT_CAPACITY',
                  label: 'Capacity',
                  unit: 'mAh',
                  value: _paramValue('BATT_CAPACITY'),
                  decimals: 0,
                  onChanged: (v) => _setLocal('BATT_CAPACITY', v),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Write / Reset
            if (_modified.isNotEmpty || _error != null)
              _WriteBar(
                hc: hc,
                modifiedCount: _modified.length,
                error: _error,
                writing: _writing,
                onWrite: _writeChanges,
                onReset: _resetChanges,
              ),
          ],
        ],
      ),
    );
  }
}
