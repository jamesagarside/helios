import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../shared/models/vehicle_state.dart';
import '../../shared/providers/providers.dart';
import '../../shared/providers/video_provider.dart';
import '../../shared/providers/video_recording_provider.dart';
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
  late TextEditingController _urlController;
  bool _urlFocused = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ref.read(videoPlayerProvider).rtspUrl);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initialized = true;
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
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
        child: Center(
          child: Text('Video not available', style: TextStyle(color: context.hc.textTertiary)),
        ),
      );
    }

    // Sync URL field when settings change externally (e.g. persisted state reload),
    // but only when the user isn't actively editing it.
    ref.listen<VideoSettings>(videoPlayerProvider, (_, next) {
      if (!_urlFocused && _urlController.text != next.rtspUrl) {
        _urlController.text = next.rtspUrl;
      }
    });

    final hc = context.hc;
    final vehicle = ref.watch(vehicleStateProvider);
    final recordingState = ref.watch(videoRecordingProvider);
    final recordingNotifier = ref.read(videoRecordingProvider.notifier);

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
                    Icon(Icons.videocam_off, color: hc.textTertiary, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'No video stream',
                      style: TextStyle(color: hc.textTertiary, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 360,
                      child: Focus(
                        onFocusChange: (f) => _urlFocused = f,
                        child: TextField(
                        controller: _urlController,
                        style: TextStyle(
                            color: hc.textPrimary,
                            fontSize: 13,
                            fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          labelText: 'RTSP URL',
                          labelStyle: TextStyle(
                              color: hc.textTertiary, fontSize: 12),
                          hintText: 'rtsp://127.0.0.1:8554/stream',
                          hintStyle: TextStyle(
                              color: hc.textTertiary),
                          filled: true,
                          fillColor: hc.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                BorderSide(color: hc.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                BorderSide(color: hc.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                BorderSide(color: hc.accent),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        onSubmitted: (url) {
                          videoCtrl.updateSettings(
                              settings.copyWith(rtspUrl: url));
                          videoCtrl.connect(url);
                        },
                      ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        final url = _urlController.text.trim();
                        if (url.isNotEmpty) {
                          videoCtrl.updateSettings(
                              settings.copyWith(rtspUrl: url));
                          videoCtrl.connect(url);
                        }
                      },
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Connect'),
                    ),
                    if (videoCtrl.lastError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        videoCtrl.lastError!,
                        style: TextStyle(color: hc.danger, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (recordingState.lastError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        recordingState.lastError!,
                        style: TextStyle(color: hc.warning, fontSize: 12),
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
                      color: isPlaying ? hc.success : hc.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      settings.rtspUrl,
                      style: TextStyle(color: hc.textSecondary, fontSize: 12),
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
                    const SizedBox(width: 8),
                    if (isPlaying)
                      _ControlButton(
                        icon: recordingState.isRecording
                            ? Icons.stop_circle
                            : Icons.fiber_manual_record,
                        label: recordingState.isRecording ? 'Stop Rec' : 'Record',
                        active: recordingState.isRecording,
                        onTap: () {
                          if (recordingState.isRecording) {
                            recordingNotifier.stopRecording();
                          } else {
                            recordingNotifier.startRecording(settings.rtspUrl);
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),

          // Recordings panel (when not streaming)
          if (!isPlaying && _showControls)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _RecordingsPanel(
                recordings: recordingState.recordings,
                onDelete: recordingNotifier.deleteRecording,
                onPlay: (file) {
                  videoCtrl.connect(file.path);
                },
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
    final hc = context.hc;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? hc.accent.withValues(alpha: 0.2)
              : hc.surfaceDim.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: active ? hc.accent : hc.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active ? hc.accent : hc.textSecondary,
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
    final hc = context.hc;
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
                  color: hc.accent,
                ),
                const SizedBox(width: 8),
                _HudBadge(
                  text: vehicle.armed ? 'ARMED' : 'DISARMED',
                  color: vehicle.armed ? hc.danger : hc.success,
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
    final hc = context.hc;
    return Container(
      width: 70,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: hc.textPrimary.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: hc.textPrimary.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: hc.textPrimary,
            ),
          ),
          Text(
            unit,
            style: TextStyle(
              fontSize: 12,
              color: hc.textPrimary.withValues(alpha: 0.5),
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
    final hc = context.hc;
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
                color: hc.textPrimary.withValues(alpha: 0.5),
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
              color: hc.textPrimary,
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
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _RecordingsPanel extends StatelessWidget {
  const _RecordingsPanel({
    required this.recordings,
    required this.onDelete,
    required this.onPlay,
  });

  final List<File> recordings;
  final void Function(File) onDelete;
  final void Function(File) onPlay;

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (recordings.isEmpty) return const SizedBox.shrink();
    final hc = context.hc;

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              'Recordings',
              style: TextStyle(
                color: hc.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: recordings.length,
              itemBuilder: (_, i) {
                final file = recordings[i];
                final name = file.path.split('/').last;
                final size = file.existsSync() ? file.lengthSync() : 0;
                final modified =
                    file.existsSync() ? file.lastModifiedSync() : DateTime.now();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.movie_outlined,
                          size: 14, color: hc.textTertiary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                  color: hc.textPrimary, fontSize: 12),
                            ),
                            Text(
                              '${_formatDate(modified)} · ${_formatSize(size)}',
                              style: TextStyle(
                                  color: hc.textTertiary, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.play_circle_outline, size: 18),
                        color: hc.accent,
                        onPressed: () => onPlay(file),
                        tooltip: 'Play recording',
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: hc.textTertiary,
                        onPressed: () => onDelete(file),
                        tooltip: 'Delete',
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
