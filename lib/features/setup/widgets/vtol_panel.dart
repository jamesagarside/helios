import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/params/parameter_service.dart';
import '../../../core/params/vtol_setup.dart';
import '../../../shared/models/vehicle_state.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';
import 'qautotune_section.dart';
import 'vtol_options_editor.dart';
import 'vtol_param_row.dart';

/// VTOL / Quadplane setup panel.
///
/// Gated on `Q_ENABLE` (never on MAV_TYPE — ArduPilot quadplanes report as
/// fixed-wing; see `docs/adr/0003-gate-vtol-panel-on-q-enable.md`). Presents
/// three tiers of progressive disclosure: Setup (always), Advanced tuning PIDs
/// (collapsed expander), and the QAUTOTUNE section. The gating predicate, the
/// `Q_OPTIONS` bitmask, and the param groups live in the tested core module
/// `lib/core/params/vtol_setup.dart`.
class VtolPanel extends ConsumerWidget {
  const VtolPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hc = context.hc;
    final params = ref.watch(paramCacheProvider);
    final gate = vtolGateFor(
      paramsLoaded: params.isNotEmpty,
      qEnable: params[kQEnableParam]?.value,
    );

    return switch (gate) {
      // Tab is hidden in fc_config_view for these states; render an info host
      // defensively in case the panel is reached directly.
      VtolGate.paramsUnloaded || VtolGate.hidden => _NoQuadplane(hc: hc),
      VtolGate.enablePrompt => const _EnablePrompt(),
      VtolGate.fullPanel => const _FullPanel(),
    };
  }
}

// ─── Enable prompt (Q_ENABLE == 0) ───────────────────────────────────────────

class _EnablePrompt extends ConsumerStatefulWidget {
  const _EnablePrompt();

  @override
  ConsumerState<_EnablePrompt> createState() => _EnablePromptState();
}

class _EnablePromptState extends ConsumerState<_EnablePrompt> {
  bool _writing = false;
  String? _error;

  Future<void> _enable() async {
    final controller = ref.read(connectionControllerProvider.notifier);
    final paramService = controller.paramService;
    if (paramService == null) return;
    final vehicle = ref.read(vehicleStateProvider);
    final params = ref.read(paramCacheProvider);
    setState(() {
      _writing = true;
      _error = null;
    });
    try {
      await paramService.setParam(
        targetSystem: vehicle.systemId,
        targetComponent: vehicle.componentId,
        paramId: kQEnableParam,
        value: 1,
        paramType: params[kQEnableParam]?.type ?? 6,
      );
      final cached = Map<String, Parameter>.from(ref.read(paramCacheProvider));
      if (cached.containsKey(kQEnableParam)) {
        cached[kQEnableParam] = cached[kQEnableParam]!.copyWith(value: 1);
        ref.read(paramCacheProvider.notifier).state = cached;
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to set Q_ENABLE: $e');
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final connected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;
    final canEnable = connected && !vehicle.armed && !_writing;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VTOL / Quadplane',
              style:
                  HeliosTypography.heading1.copyWith(color: hc.textPrimary)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: hc.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This is an ArduPilot Plane firmware with quadplane support '
                  'available but turned off (Q_ENABLE = 0). Enable it to set up '
                  'VTOL lift motors, transition, tilt and tuning.',
                  style: HeliosTypography.small
                      .copyWith(color: hc.textSecondary),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: canEnable ? _enable : null,
                      icon: _writing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.power_settings_new, size: 16),
                      label: const Text('Enable quadplane (Q_ENABLE = 1)'),
                      style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                    ),
                    const SizedBox(width: 12),
                    if (!connected)
                      Text('Connect to a vehicle first.',
                          style: HeliosTypography.small
                              .copyWith(color: hc.textTertiary))
                    else if (vehicle.armed)
                      Text('Disarm to change Q_ENABLE.',
                          style: HeliosTypography.small
                              .copyWith(color: hc.warning)),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style:
                          HeliosTypography.small.copyWith(color: hc.danger)),
                ],
                const SizedBox(height: 12),
                Text(
                  'Enabling quadplane mode adds a full set of Q_* parameters '
                  'and typically requires a flight controller reboot to take '
                  'full effect.',
                  style: HeliosTypography.small.copyWith(color: hc.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Full panel (Q_ENABLE == 1) ──────────────────────────────────────────────

class _FullPanel extends ConsumerStatefulWidget {
  const _FullPanel();

  @override
  ConsumerState<_FullPanel> createState() => _FullPanelState();
}

class _FullPanelState extends ConsumerState<_FullPanel> {
  bool _showTiltOverride = false;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final params = ref.watch(paramCacheProvider);
    final connected = ref.watch(connectionControllerProvider).transportState ==
        TransportState.connected;
    final tiltAuto = tiltAutoVisible(params[kQTiltMaskParam]?.value);
    final showTilt = tiltAuto || _showTiltOverride;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VTOL / Quadplane Setup',
              style:
                  HeliosTypography.heading1.copyWith(color: hc.textPrimary)),
          const SizedBox(height: 4),
          Text(
            'Quadplane is enabled (Q_ENABLE = 1). Configure VTOL frame, '
            'transition, behaviour, tilt and tuning below.',
            style: HeliosTypography.small.copyWith(color: hc.textSecondary),
          ),
          const SizedBox(height: 16),

          if (!connected)
            _Banner(
              hc: hc,
              color: hc.warning,
              icon: Icons.info_outline,
              message: 'Connect to a vehicle to read and edit VTOL settings.',
            ),
          if (vehicle.armed)
            _Banner(
              hc: hc,
              color: hc.danger,
              icon: Icons.warning_amber_rounded,
              message: 'Vehicle is ARMED. Disarm before changing setup '
                  'parameters.',
            ),

          // ── Setup tier: frame ──────────────────────────────────────────────
          _SectionTitle('VTOL FRAME', hc: hc),
          const SizedBox(height: 8),
          const VtolParamGroup(
            params: [
              VtolParam('Q_FRAME_CLASS', 'VTOL frame class', '',
                  enumOptions: qFrameClasses),
              VtolParam('Q_FRAME_TYPE', 'VTOL frame type', '',
                  enumOptions: qFrameTypes),
            ],
          ),
          const SizedBox(height: 24),

          // ── Setup tier: transition & assist ────────────────────────────────
          _SectionTitle('TRANSITION & ASSIST', hc: hc),
          const SizedBox(height: 8),
          const VtolParamGroup(params: qTransitionAssistParams),
          const SizedBox(height: 24),

          // ── Setup tier: Q_OPTIONS bitmask ──────────────────────────────────
          const VtolOptionsEditor(),
          const SizedBox(height: 24),

          // ── Setup tier: conditional tilt ───────────────────────────────────
          _SectionTitle('TILTROTOR', hc: hc),
          const SizedBox(height: 8),
          if (showTilt)
            const VtolParamGroup(params: qTiltParams)
          else
            _TiltHidden(
              hc: hc,
              onShow: () => setState(() => _showTiltOverride = true),
            ),
          const SizedBox(height: 24),

          // ── Advanced tuning tier (collapsed expander + caution) ────────────
          _AdvancedTuning(hc: hc),
          const SizedBox(height: 24),

          // ── QAUTOTUNE section ──────────────────────────────────────────────
          const QAutotuneSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Tilt-hidden affordance ──────────────────────────────────────────────────

class _TiltHidden extends StatelessWidget {
  const _TiltHidden({required this.hc, required this.onShow});
  final HeliosColors hc;
  final VoidCallback onShow;

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
              'No tiltrotor detected (Q_TILT_MASK = 0). Tilt settings are '
              'hidden.',
              style: HeliosTypography.small.copyWith(color: hc.textSecondary),
            ),
          ),
          TextButton(
            onPressed: onShow,
            child: const Text('Show tilt settings anyway'),
          ),
        ],
      ),
    );
  }
}

// ─── Advanced tuning expander ────────────────────────────────────────────────

class _AdvancedTuning extends StatelessWidget {
  const _AdvancedTuning({required this.hc});
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.tune, color: hc.warning),
          title: Text('Advanced VTOL tuning (PIDs)',
              style:
                  HeliosTypography.heading2.copyWith(color: hc.textPrimary)),
          subtitle: Text(
            'Manual rate/angle gains. QAUTOTUNE below is the recommended route '
            '— hand-edit only to finish what it found.',
            style: HeliosTypography.small.copyWith(color: hc.textTertiary),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            _Banner(
              hc: hc,
              color: hc.warning,
              icon: Icons.warning_amber_rounded,
              message: 'Editing these gains by hand can make the aircraft '
                  'unstable in VTOL flight. Change one value at a time and '
                  'test carefully.',
            ),
            const SizedBox(height: 16),
            _SectionTitle('RATE PIDS (Q_A_RAT_*)', hc: hc),
            const SizedBox(height: 8),
            const VtolParamGroup(params: qRatePidParams),
            const SizedBox(height: 16),
            _SectionTitle('ANGLE P (Q_A_ANG_*)', hc: hc),
            const SizedBox(height: 8),
            const VtolParamGroup(params: qAnglePidParams),
          ],
        ),
      ),
    );
  }
}

// ─── No-quadplane fallback ───────────────────────────────────────────────────

class _NoQuadplane extends StatelessWidget {
  const _NoQuadplane({required this.hc});
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'VTOL setup is only available on ArduPilot quadplane firmware.',
          style: HeliosTypography.small.copyWith(color: hc.textTertiary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ─── Shared bits ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.hc});
  final String text;
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: hc.textTertiary,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
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
