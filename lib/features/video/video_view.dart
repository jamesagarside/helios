import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../shared/models/vehicle_state.dart';
import '../../shared/providers/providers.dart';
import '../../shared/providers/video_provider.dart';
import '../../shared/theme/helios_colors.dart';

/// Full-screen video view with transparent HUD overlay.
///
/// Defers media_kit player creation until first build to avoid
/// errors when the widget is in an IndexedStack but not visible.
class VideoView extends ConsumerStatefulWidget {
  const VideoView({super.key});

  @override
  ConsumerState<VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends ConsumerState<VideoView> {
  bool _showHud = true;
  bool _showControls = true;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const ColoredBox(color: Colors.black, child: SizedBox.expand());
    }

    late final VideoPlayerController videoCtrl;
    late final VideoSettings settings;
    late final bool isPlaying;

    try {
      videoCtrl = ref.watch(videoPlayerProvider.notifier);
      settings = ref.watch(videoPlayerProvider);
      isPlaying = videoCtrl.isPlaying;
    } catch (_) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text('Video not available', style: TextStyle(color: HeliosColors.textTertiary)),
        ),
      );
    }

    final vehicle = ref.watch(vehicleStateProvider);

    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video surface (full screen)
          if (isPlaying)
            Video(
              controller: videoCtrl.videoController,
              fill: Colors.black,
            )
          else
            Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.videocam_off, color: HeliosColors.textTertiary, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      isPlaying ? 'Connecting...' : 'No video stream',
                      style: const TextStyle(color: HeliosColors.textTertiary, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      settings.rtspUrl,
                      style: const TextStyle(color: HeliosColors.textTertiary, fontSize: 12),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => videoCtrl.connect(),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Connect'),
                    ),
                    if (videoCtrl.lastError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        videoCtrl.lastError!,
                        style: const TextStyle(color: HeliosColors.danger, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // HUD overlay
          if (_showHud && isPlaying)
            _HudOverlay(vehicle: vehicle),

          // Top controls bar
          if (_showControls)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPlaying ? Icons.videocam : Icons.videocam_off,
                      size: 16,
                      color: isPlaying ? HeliosColors.success : HeliosColors.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      settings.rtspUrl,
                      style: const TextStyle(color: HeliosColors.textSecondary, fontSize: 11),
                    ),
                    const Spacer(),
                    // HUD toggle
                    _ControlButton(
                      icon: Icons.dashboard,
                      label: 'HUD',
                      active: _showHud,
                      onTap: () => setState(() => _showHud = !_showHud),
                    ),
                    const SizedBox(width: 8),
                    // Connect/Disconnect
                    if (isPlaying)
                      _ControlButton(
                        icon: Icons.stop,
                        label: 'Stop',
                        active: false,
                        onTap: () => videoCtrl.disconnect(),
                      )
                    else
                      _ControlButton(
                        icon: Icons.play_arrow,
                        label: 'Play',
                        active: false,
                        onTap: () => videoCtrl.connect(),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? HeliosColors.accent.withValues(alpha: 0.2)
              : HeliosColors.surfaceDim.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: active ? HeliosColors.accent : HeliosColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: active ? HeliosColors.accent : HeliosColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Transparent HUD overlay showing flight data on top of video.
class _HudOverlay extends StatelessWidget {
  const _HudOverlay({required this.vehicle});

  final VehicleState vehicle;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Left column — speed
        Positioned(
          left: 24,
          top: 0,
          bottom: 0,
          child: Center(
            child: _HudTape(
              value: vehicle.airspeed,
              label: 'IAS',
              unit: 'm/s',
              showOnLeft: true,
            ),
          ),
        ),

        // Right column — altitude
        Positioned(
          right: 24,
          top: 0,
          bottom: 0,
          child: Center(
            child: _HudTape(
              value: vehicle.altitudeRel,
              label: 'ALT',
              unit: 'm',
              showOnLeft: false,
            ),
          ),
        ),

        // Top centre — heading
        Positioned(
          top: 48,
          left: 0,
          right: 0,
          child: Center(
            child: _HudValue(
              label: 'HDG',
              value: '${vehicle.heading}\u00B0',
              large: true,
            ),
          ),
        ),

        // Bottom centre — mode + arm state
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HudBadge(
                  text: vehicle.flightMode.name,
                  color: HeliosColors.accent,
                ),
                const SizedBox(width: 8),
                _HudBadge(
                  text: vehicle.armed ? 'ARMED' : 'DISARMED',
                  color: vehicle.armed ? HeliosColors.danger : HeliosColors.success,
                ),
              ],
            ),
          ),
        ),

        // Bottom-left — battery
        Positioned(
          bottom: 24,
          left: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HudValue(
                label: 'BAT',
                value: '${vehicle.batteryVoltage.toStringAsFixed(1)}V',
              ),
              _HudValue(
                label: '',
                value: vehicle.batteryRemaining >= 0
                    ? '${vehicle.batteryRemaining}%'
                    : '--%',
              ),
            ],
          ),
        ),

        // Bottom-right — GPS
        Positioned(
          bottom: 24,
          right: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _HudValue(label: 'GPS', value: '${vehicle.satellites} sats'),
              _HudValue(label: 'GS', value: '${vehicle.groundspeed.toStringAsFixed(1)} m/s'),
            ],
          ),
        ),

        // Centre — climb rate
        Positioned(
          right: 80,
          top: 0,
          bottom: 0,
          child: Center(
            child: _HudValue(
              label: 'VS',
              value: '${vehicle.climbRate >= 0 ? '+' : ''}${vehicle.climbRate.toStringAsFixed(1)}',
            ),
          ),
        ),
      ],
    );
  }
}

/// Speed/altitude tape display for HUD.
class _HudTape extends StatelessWidget {
  const _HudTape({
    required this.value,
    required this.label,
    required this.unit,
    required this.showOnLeft,
  });

  final double value;
  final String label;
  final String unit;
  final bool showOnLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: HeliosColors.textPrimary.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: HeliosColors.textPrimary.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: HeliosColors.textPrimary,
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              fontSize: 10,
              color: HeliosColors.textPrimary.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _HudValue extends StatelessWidget {
  const _HudValue({
    required this.label,
    required this.value,
    this.large = false,
  });

  final String label;
  final String value;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label.isNotEmpty) ...[
            Text(
              label,
              style: TextStyle(
                fontSize: large ? 11 : 9,
                color: HeliosColors.textPrimary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            value,
            style: TextStyle(
              fontSize: large ? 18 : 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: HeliosColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HudBadge extends StatelessWidget {
  const _HudBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
