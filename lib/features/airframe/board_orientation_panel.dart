import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/airframe/board_orientation.dart';
import '../../core/params/parameter_service.dart';
import '../../shared/models/vehicle_state.dart';
import '../../shared/providers/providers.dart';
import '../../shared/theme/helios_colors.dart';

/// Board orientation editor: reads and writes the autopilot's
/// `AHRS_ORIENTATION` (and the legacy `COMPASS_ORIENT`) parameter from a
/// labelled list of standard rotations.
///
/// Co-located with the Airframe Model in the Orientation home: the pilot picks
/// the mounting rotation here, then physically moves the vehicle and confirms
/// the live model follows correctly. Writes are confirmed by parameter
/// read-back and surfaced to the user.
class BoardOrientationPanel extends ConsumerStatefulWidget {
  const BoardOrientationPanel({super.key});

  /// The primary orientation parameter on modern autopilots.
  static const String ahrsParam = 'AHRS_ORIENTATION';

  /// Legacy compass orientation parameter, kept in step where present.
  static const String compassParam = 'COMPASS_ORIENT';

  @override
  ConsumerState<BoardOrientationPanel> createState() =>
      _BoardOrientationPanelState();
}

enum _WriteOutcome { idle, success, error }

class _BoardOrientationPanelState extends ConsumerState<BoardOrientationPanel> {
  bool _writing = false;
  _WriteOutcome _outcome = _WriteOutcome.idle;
  String? _message;

  /// The currently effective orientation value from the param cache.
  int? _currentValue(Map<String, Parameter> params) =>
      BoardOrientations.resolveValue(
        ahrsOrientation: params[BoardOrientationPanel.ahrsParam]?.value,
        compassOrient: params[BoardOrientationPanel.compassParam]?.value,
      );

  Future<void> _select(int value) async {
    final controller = ref.read(connectionControllerProvider.notifier);
    final paramService = controller.paramService;
    if (paramService == null || _writing) return;

    final vehicle = ref.read(vehicleStateProvider);
    final params = ref.read(paramCacheProvider);
    final label = BoardOrientations.labelFor(value);

    setState(() {
      _writing = true;
      _outcome = _WriteOutcome.idle;
      _message = null;
    });

    try {
      // Write AHRS_ORIENTATION (the parameter that exists on modern firmware)
      // and, when the legacy COMPASS_ORIENT is present, keep it aligned. Each
      // write is confirmed via PARAM_VALUE read-back inside setParam.
      final written = <String, int>{};
      for (final name in const [
        BoardOrientationPanel.ahrsParam,
        BoardOrientationPanel.compassParam,
      ]) {
        final existing = params[name];
        if (existing == null) continue;
        final confirmed = await paramService.setParam(
          targetSystem: vehicle.systemId,
          targetComponent: vehicle.componentId,
          paramId: name,
          value: value.toDouble(),
          paramType: existing.type,
        );
        written[name] = confirmed.round();
      }

      if (written.isEmpty) {
        throw ParameterException(
          'Vehicle does not expose AHRS_ORIENTATION or COMPASS_ORIENT.',
        );
      }

      // Verify the read-back matches what we requested.
      final mismatched = written.entries
          .where((e) => e.value != value)
          .map((e) => '${e.key}=${e.value}')
          .toList();
      if (mismatched.isNotEmpty) {
        throw ParameterException(
          'Read-back differed: ${mismatched.join(', ')} '
          '(requested $value).',
        );
      }

      // Update the shared cache so the rest of the app sees the new value.
      final cache = Map<String, Parameter>.from(ref.read(paramCacheProvider));
      var changed = false;
      for (final name in written.keys) {
        final cached = cache[name];
        if (cached != null) {
          cache[name] = cached.copyWith(value: value.toDouble());
          changed = true;
        }
      }
      if (changed) {
        ref.read(paramCacheProvider.notifier).state = cache;
      }

      if (mounted) {
        setState(() {
          _outcome = _WriteOutcome.success;
          _message = 'Set to "$label" '
              '(${written.keys.join(', ')}). '
              'Move the vehicle to verify against the model.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _outcome = _WriteOutcome.error;
          _message = 'Failed to set orientation: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final params = ref.watch(paramCacheProvider);
    final vehicle = ref.watch(vehicleStateProvider);
    final connected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;
    final hasParam = params.containsKey(BoardOrientationPanel.ahrsParam) ||
        params.containsKey(BoardOrientationPanel.compassParam);
    final current = _currentValue(params);
    final enabled = connected && hasParam && !vehicle.armed && !_writing;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BOARD ORIENTATION',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: hc.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'How the flight controller board is mounted relative to the '
            'vehicle nose. Sets AHRS_ORIENTATION (and COMPASS_ORIENT when '
            'present). Pick a rotation, then move the vehicle and confirm the '
            'model beside this panel follows the real motion.',
            style: TextStyle(color: hc.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),

          if (vehicle.armed)
            _InlineNotice(
              hc: hc,
              color: hc.warning,
              icon: Icons.lock_outline,
              message: 'Vehicle is ARMED — disarm to change orientation.',
            ),
          if (!connected)
            _InlineNotice(
              hc: hc,
              color: hc.warning,
              icon: Icons.link_off,
              message: 'Connect to a vehicle to read or set orientation.',
            ),
          if (connected && !hasParam)
            _InlineNotice(
              hc: hc,
              color: hc.warning,
              icon: Icons.hourglass_empty,
              message: 'Waiting for parameters to load…',
            ),

          if (hasParam) ...[
            Row(
              children: [
                Icon(Icons.screen_rotation_outlined,
                    size: 18, color: hc.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    current == null
                        ? 'Current: unknown'
                        : 'Current: ${BoardOrientations.labelFor(current)}',
                    style: TextStyle(
                      color: hc.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _OrientationDropdown(
              hc: hc,
              value: current,
              enabled: enabled,
              onSelected: _select,
            ),
          ],

          if (_writing) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: hc.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Writing and confirming…',
                  style: TextStyle(color: hc.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ],

          if (!_writing && _outcome != _WriteOutcome.idle && _message != null)
            ...[
            const SizedBox(height: 12),
            _InlineNotice(
              hc: hc,
              color: _outcome == _WriteOutcome.success ? hc.success : hc.danger,
              icon: _outcome == _WriteOutcome.success
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              message: _message!,
            ),
          ],
        ],
      ),
    );
  }
}

class _OrientationDropdown extends StatelessWidget {
  const _OrientationDropdown({
    required this.hc,
    required this.value,
    required this.enabled,
    required this.onSelected,
  });

  final HeliosColors hc;
  final int? value;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    // Include a non-standard current value so the dropdown can show it.
    final items = [...BoardOrientations.all];
    if (value != null && BoardOrientations.byValue(value!) == null) {
      items.add(BoardOrientation(value!, BoardOrientations.labelFor(value!)));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: hc.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: value,
          hint: Text(
            'Select orientation…',
            style: TextStyle(color: hc.textTertiary, fontSize: 13),
          ),
          dropdownColor: hc.surface,
          iconEnabledColor: hc.textSecondary,
          style: TextStyle(color: hc.textPrimary, fontSize: 13),
          items: items
              .map(
                (o) => DropdownMenuItem<int>(
                  value: o.value,
                  child: Text(
                    '${o.label}  ·  ${o.value}',
                    style: TextStyle(color: hc.textPrimary, fontSize: 13),
                  ),
                ),
              )
              .toList(),
          onChanged: enabled
              ? (v) {
                  if (v != null && v != value) onSelected(v);
                }
              : null,
        ),
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.hc,
    required this.color,
    required this.icon,
    required this.message,
  });

  final HeliosColors hc;
  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: hc.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
