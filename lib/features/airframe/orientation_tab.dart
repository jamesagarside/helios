import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/airframe/airframe_config.dart';
import '../../core/airframe/attitude_source.dart';
import '../../shared/models/vehicle_state.dart';
import '../../shared/providers/providers.dart';
import '../../shared/theme/helios_colors.dart';
import 'airframe_model_widget.dart';
import 'airframe_providers.dart';
import 'board_orientation_panel.dart';

/// The Orientation home: a live Airframe Model the pilot can use to verify the
/// flight controller's mounting/orientation by moving the vehicle and watching
/// the model follow.
///
/// Owns the high-rate `ATTITUDE_QUATERNION` lifecycle: it [acquire]s the rate
/// on mount and [release]s it on dispose, so the FC is only firehosing while
/// this screen is visible.
class OrientationTab extends ConsumerStatefulWidget {
  const OrientationTab({super.key});

  @override
  ConsumerState<OrientationTab> createState() => _OrientationTabState();
}

class _OrientationTabState extends ConsumerState<OrientationTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(airframeAttitudeControllerProvider).acquire();
    });
  }

  @override
  void dispose() {
    // Read without listening — safe in dispose.
    ref.read(airframeAttitudeControllerProvider).release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final controller = ref.watch(airframeAttitudeControllerProvider);
    final config = ref.watch(airframeConfigProvider);
    final connection = ref.watch(connectionStatusProvider);
    final connected = connection.linkState == LinkState.connected ||
        connection.linkState == LinkState.degraded;
    final source = controller.source;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ORIENTATION',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: hc.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Move the vehicle and confirm the model follows. If it rolls or '
            'pitches the wrong way, the flight controller is mounted in the '
            'wrong orientation.',
            style: TextStyle(color: hc.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (!connected)
            _Banner(
              hc: hc,
              icon: Icons.info_outline,
              color: hc.warning,
              message:
                  'Connect to a vehicle in the Setup tab to see live attitude.',
            ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final model = _ModelPanel(hc: hc, source: source, config: config);
              const editor = BoardOrientationPanel();
              final summary = _ConfigSummary(config: config, source: source != null);
              // Side-by-side when there's room; the model is the verification
              // tool the pilot watches while changing the orientation editor.
              if (constraints.maxWidth >= 720) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          model,
                          const SizedBox(height: 16),
                          summary,
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    const Expanded(child: editor),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  model,
                  const SizedBox(height: 16),
                  editor,
                  const SizedBox(height: 16),
                  summary,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The 3D Airframe Model panel — the live verification view.
class _ModelPanel extends StatelessWidget {
  const _ModelPanel({
    required this.hc,
    required this.source,
    required this.config,
  });

  final HeliosColors hc;
  final AttitudeSource? source;
  final AirframeConfig config;

  @override
  Widget build(BuildContext context) {
    final src = source;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        child: AspectRatio(
          aspectRatio: 1.2,
          child: Container(
            decoration: BoxDecoration(
              color: hc.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: hc.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: src == null
                ? _NoSource(hc: hc)
                : AirframeModelWidget(
                    source: src,
                    config: config,
                  ),
          ),
        ),
      ),
    );
  }
}

class _ConfigSummary extends StatelessWidget {
  const _ConfigSummary({required this.config, required this.source});
  final AirframeConfig config;
  final bool source;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final shape = switch (config.archetype) {
      AirframeArchetype.multirotor => '${config.motorCount}-motor multirotor',
      AirframeArchetype.fixedWing => 'Fixed-wing',
      AirframeArchetype.quadplane =>
        'Quadplane / VTOL (${config.motorCount} lift motors)',
    };
    final src = config.fromParams
        ? 'FRAME_CLASS / FRAME_TYPE'
        : 'MAV_TYPE (generic — load parameters for exact shape)';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Model: $shape',
              style: TextStyle(color: hc.textPrimary, fontSize: 13)),
          const SizedBox(height: 4),
          Text('Shape from: $src',
              style: TextStyle(color: hc.textTertiary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _NoSource extends StatelessWidget {
  const _NoSource({required this.hc});
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_off, size: 36, color: hc.textTertiary),
          const SizedBox(height: 10),
          Text('Not connected',
              style: TextStyle(color: hc.textTertiary, fontSize: 13)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.hc,
    required this.icon,
    required this.color,
    required this.message,
  });
  final HeliosColors hc;
  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: TextStyle(color: hc.textSecondary, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
