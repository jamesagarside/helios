import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/telemetry/replay_service.dart';
import '../../../shared/providers/providers.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Overlay controls shown on the Fly View when flight replay is active.
///
/// Displays a bottom bar with play/pause, speed control, timeline scrub,
/// and a prominent "REPLAY" indicator so the user knows they're watching
/// recorded data, not a live vehicle.
class ReplayControls extends ConsumerStatefulWidget {
  const ReplayControls({super.key});

  @override
  ConsumerState<ReplayControls> createState() => _ReplayControlsState();
}

class _ReplayControlsState extends ConsumerState<ReplayControls> {
  double _currentTime = 0;
  double _totalDuration = 1;
  ReplayState _replayState = ReplayState.idle;
  ReplaySpeed _speed = ReplaySpeed.normal;
  bool _isScrubbing = false;
  double _scrubTime = 0;

  @override
  void initState() {
    super.initState();
    final replay = ref.read(replayServiceProvider);
    replay.onTimeUpdate = _onTimeUpdate;
    replay.onReplayStateChanged = _onReplayStateChanged;
    _replayState = replay.state;
    _speed = replay.speed;
    _totalDuration = replay.totalDuration > 0 ? replay.totalDuration : 1;
  }

  void _onTimeUpdate(double time, double total) {
    if (!mounted || _isScrubbing) return;
    setState(() {
      _currentTime = time;
      _totalDuration = total > 0 ? total : 1;
    });
  }

  void _onReplayStateChanged(ReplayState state) {
    if (!mounted) return;
    setState(() => _replayState = state);
  }

  @override
  Widget build(BuildContext context) {
    if (_replayState == ReplayState.idle ||
        _replayState == ReplayState.loading) {
      return const SizedBox.shrink();
    }

    final replay = ref.read(replayServiceProvider);
    final displayTime = _isScrubbing ? _scrubTime : _currentTime;

    final hc = context.hc;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: hc.surfaceDim.withValues(alpha: 0.95),
          border: Border(
            top: BorderSide(color: hc.border),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // REPLAY banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 2),
              color: hc.warning.withValues(alpha: 0.15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.replay, size: 12, color: hc.warning),
                  const SizedBox(width: 4),
                  Text(
                    'REPLAY — ${replay.flightName}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: hc.warning,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

            // Timeline scrub bar
            SizedBox(
              height: 24,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  activeTrackColor: hc.accent,
                  inactiveTrackColor: hc.border,
                  thumbColor: hc.accent,
                  overlayColor: hc.accent.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: displayTime.clamp(0, _totalDuration),
                  min: 0,
                  max: _totalDuration,
                  onChangeStart: (_) => setState(() => _isScrubbing = true),
                  onChanged: (value) {
                    setState(() => _scrubTime = value);
                  },
                  onChangeEnd: (value) {
                    replay.seekTo(value);
                    setState(() {
                      _isScrubbing = false;
                      _currentTime = value;
                    });
                  },
                ),
              ),
            ),

            // Controls row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  // Time display
                  SizedBox(
                    width: 100,
                    child: Text(
                      '${_formatTime(displayTime)} / ${_formatTime(_totalDuration)}',
                      style: HeliosTypography.caption.copyWith(
                        fontFamily: 'monospace',
                        color: hc.textSecondary,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Step backward
                  _ControlButton(
                    icon: Icons.skip_previous,
                    onPressed: _replayState == ReplayState.paused
                        ? () => replay.stepBackward()
                        : null,
                    size: 20,
                  ),
                  const SizedBox(width: 4),

                  // Play/Pause
                  _ControlButton(
                    icon: _replayState == ReplayState.playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    onPressed: () => replay.togglePlayPause(),
                    size: 32,
                    color: hc.accent,
                  ),
                  const SizedBox(width: 4),

                  // Step forward
                  _ControlButton(
                    icon: Icons.skip_next,
                    onPressed: _replayState == ReplayState.paused
                        ? () => replay.stepForward()
                        : null,
                    size: 20,
                  ),

                  const Spacer(),

                  // Speed selector
                  PopupMenuButton<ReplaySpeed>(
                    initialValue: _speed,
                    onSelected: (speed) {
                      replay.setSpeed(speed);
                      setState(() => _speed = speed);
                    },
                    color: hc.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: BorderSide(color: hc.border),
                    ),
                    itemBuilder: (_) => ReplaySpeed.values.map((s) {
                      return PopupMenuItem(
                        value: s,
                        child: Text(
                          s.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: s == _speed
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: s == _speed
                                ? hc.accent
                                : hc.textPrimary,
                          ),
                        ),
                      );
                    }).toList(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: hc.border),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _speed.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: hc.accent,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Stop replay
                  _ControlButton(
                    icon: Icons.stop_circle_outlined,
                    onPressed: () {
                      replay.stop();
                      ref.read(vehicleStateProvider.notifier).reset();
                    },
                    size: 20,
                    color: hc.danger,
                    tooltip: 'Stop Replay',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(double seconds) {
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.onPressed,
    this.size = 24,
    this.color,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final button = IconButton(
      icon: Icon(icon, size: size),
      onPressed: onPressed,
      color: onPressed != null
          ? (color ?? hc.textPrimary)
          : hc.textTertiary,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: size + 8, minHeight: size + 8),
      splashRadius: size * 0.8,
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
