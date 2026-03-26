import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../shared/providers/video_provider.dart';
import '../../../shared/theme/helios_colors.dart';

/// Draggable, resizable video stream widget for PiP on the Fly View.
///
/// Uses the shared [videoPlayerProvider] so the RTSP URL and player state
/// are consistent with the Video tab and Setup tab.
class VideoStreamWidget extends ConsumerStatefulWidget {
  const VideoStreamWidget({
    super.key,
    required this.initialPosition,
    this.initialWidth = 400,
    this.initialHeight = 240,
    this.onClose,
    this.onPositionChanged,
  });

  final Offset initialPosition;
  final double initialWidth;
  final double initialHeight;
  final VoidCallback? onClose;
  final ValueChanged<Offset>? onPositionChanged;

  @override
  ConsumerState<VideoStreamWidget> createState() => _VideoStreamWidgetState();
}

class _VideoStreamWidgetState extends ConsumerState<VideoStreamWidget> {
  late Offset _position;
  late double _width;
  late double _height;
  bool _showControls = true;
  bool _minimised = false;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _width = widget.initialWidth;
    _height = widget.initialHeight;
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    late final VideoPlayerController videoCtrl;
    late final VideoSettings settings;
    late final bool isPlaying;

    try {
      videoCtrl = ref.watch(videoPlayerProvider.notifier);
      settings = ref.watch(videoPlayerProvider);
      isPlaying = videoCtrl.isPlaying;
    } catch (_) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() => _position += details.delta);
          widget.onPositionChanged?.call(_position);
        },
        onTap: () {
          if (isPlaying) {
            setState(() => _showControls = !_showControls);
          }
        },
        child: Container(
          width: _width,
          height: _minimised ? 36 : _height,
          decoration: BoxDecoration(
            color: hc.surfaceDim,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: hc.border.withValues(alpha: 0.6)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Column(
              children: [
                // Title bar
                _VideoTitleBar(
                  isConnected: isPlaying,
                  minimised: _minimised,
                  onMinimise: () =>
                      setState(() => _minimised = !_minimised),
                  onClose: widget.onClose,
                ),
                if (!_minimised)
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Video surface
                        if (isPlaying)
                          Video(
                            controller: videoCtrl.videoController,
                            fill: Colors.black,
                          )
                        else
                          Container(
                            color: Colors.black,
                            child: Center(
                              child: Icon(
                                Icons.videocam_off,
                                color: hc.textTertiary,
                                size: 40,
                              ),
                            ),
                          ),

                        // Controls overlay
                        if (_showControls || !isPlaying)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              color: hc.surfaceDim
                                  .withValues(alpha: 0.85),
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      settings.rtspUrl,
                                      style: TextStyle(
                                        color: hc.textTertiary,
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    height: 28,
                                    child: isPlaying
                                        ? OutlinedButton(
                                            onPressed: () =>
                                                videoCtrl.disconnect(),
                                            child: const Text('Stop',
                                                style:
                                                    TextStyle(fontSize: 11)),
                                          )
                                        : ElevatedButton(
                                            onPressed: () =>
                                                videoCtrl.connect(),
                                            child: const Text('Play',
                                                style:
                                                    TextStyle(fontSize: 11)),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Resize handle
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              setState(() {
                                _width = (_width + details.delta.dx)
                                    .clamp(240, 800);
                                _height = (_height + details.delta.dy)
                                    .clamp(160, 600);
                              });
                            },
                            child: Container(
                              width: 16,
                              height: 16,
                              alignment: Alignment.bottomRight,
                              child: Icon(
                                Icons.drag_handle,
                                size: 12,
                                color: hc.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoTitleBar extends StatelessWidget {
  const _VideoTitleBar({
    required this.isConnected,
    required this.minimised,
    required this.onMinimise,
    required this.onClose,
  });

  final bool isConnected;
  final bool minimised;
  final VoidCallback onMinimise;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: hc.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.vertical(
          top: const Radius.circular(6),
          bottom: minimised ? const Radius.circular(6) : Radius.zero,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.videocam : Icons.videocam_off,
            size: 12,
            color: isConnected ? hc.success : hc.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            isConnected ? 'Video Stream' : 'Video (disconnected)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isConnected ? hc.textPrimary : hc.textTertiary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onMinimise,
            child: Icon(
              minimised ? Icons.expand_more : Icons.expand_less,
              size: 14,
              color: hc.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          if (onClose != null)
            GestureDetector(
              onTap: onClose,
              child: Icon(Icons.close,
                  size: 12, color: hc.textSecondary),
            ),
        ],
      ),
    );
  }
}
