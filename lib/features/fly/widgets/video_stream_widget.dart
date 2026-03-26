import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Draggable, resizable video stream widget for PiP on the Fly View.
///
/// Supports RTSP streams (Herelink, Siyi, IP cameras) and local test files.
class VideoStreamWidget extends StatefulWidget {
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
  State<VideoStreamWidget> createState() => _VideoStreamWidgetState();
}

class _VideoStreamWidgetState extends State<VideoStreamWidget> {
  late final Player _player;
  late final VideoController _videoController;
  late Offset _position;
  late double _width;
  late double _height;

  final _urlController = TextEditingController(
    text: 'rtsp://192.168.0.10:8554/main',
  );
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _showControls = true;
  bool _minimised = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _position = widget.initialPosition;
    _width = widget.initialWidth;
    _height = widget.initialHeight;

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 2 * 1024 * 1024, // 2MB buffer for low latency
      ),
    );
    _videoController = VideoController(_player);

    // Listen for errors
    _player.stream.error.listen((error) {
      if (mounted) {
        setState(() {
          _error = error;
          _isConnected = false;
          _isConnecting = false;
        });
      }
    });

    // Track playing state
    _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isConnected = playing;
          _isConnecting = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      await _player.open(
        Media(url),
        play: true,
      );
      // Hide controls after connecting
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isConnected) {
          setState(() => _showControls = false);
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isConnecting = false;
      });
    }
  }

  Future<void> _disconnect() async {
    await _player.stop();
    setState(() {
      _isConnected = false;
      _showControls = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() => _position += details.delta);
          widget.onPositionChanged?.call(_position);
        },
        onTap: () {
          if (_isConnected) {
            setState(() => _showControls = !_showControls);
          }
        },
        child: Container(
          width: _width,
          height: _minimised ? 36 : _height,
          decoration: BoxDecoration(
            color: HeliosColors.surfaceDim,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: HeliosColors.border.withValues(alpha: 0.6)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Column(
              children: [
                // Title bar
                _VideoTitleBar(
                  isConnected: _isConnected,
                  minimised: _minimised,
                  onMinimise: () => setState(() => _minimised = !_minimised),
                  onClose: widget.onClose,
                ),
                if (!_minimised)
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Video surface
                        if (_isConnected || _isConnecting)
                          Video(
                            controller: _videoController,
                            fill: Colors.black,
                          )
                        else
                          Container(
                            color: Colors.black,
                            child: const Center(
                              child: Icon(
                                Icons.videocam_off,
                                color: HeliosColors.textTertiary,
                                size: 40,
                              ),
                            ),
                          ),

                        // URL input overlay
                        if (_showControls || !_isConnected)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              color: HeliosColors.surfaceDim.withValues(alpha: 0.85),
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_error != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: HeliosColors.danger,
                                          fontSize: 12,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SizedBox(
                                          height: 30,
                                          child: TextField(
                                            controller: _urlController,
                                            style: HeliosTypography.sqlEditor.copyWith(fontSize: 12),
                                            decoration: InputDecoration(
                                              hintText: 'rtsp://ip:port/stream',
                                              hintStyle: const TextStyle(fontSize: 12),
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      SizedBox(
                                        height: 30,
                                        child: _isConnected
                                            ? OutlinedButton(
                                                onPressed: _disconnect,
                                                child: const Text('Stop', style: TextStyle(fontSize: 12)),
                                              )
                                            : ElevatedButton(
                                                onPressed: _isConnecting ? null : _connect,
                                                child: Text(
                                                  _isConnecting ? '...' : 'Play',
                                                  style: const TextStyle(fontSize: 12),
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // Resize handle (bottom-right corner)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              setState(() {
                                _width = (_width + details.delta.dx).clamp(240, 800);
                                _height = (_height + details.delta.dy).clamp(160, 600);
                              });
                            },
                            child: Container(
                              width: 16,
                              height: 16,
                              alignment: Alignment.bottomRight,
                              child: const Icon(
                                Icons.drag_handle,
                                size: 12,
                                color: HeliosColors.textTertiary,
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
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: HeliosColors.surface.withValues(alpha: 0.7),
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
            color: isConnected ? HeliosColors.success : HeliosColors.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            isConnected ? 'Video Stream' : 'Video (disconnected)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isConnected ? HeliosColors.textPrimary : HeliosColors.textTertiary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onMinimise,
            child: Icon(
              minimised ? Icons.expand_more : Icons.expand_less,
              size: 14,
              color: HeliosColors.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          if (onClose != null)
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close, size: 12, color: HeliosColors.textSecondary),
            ),
        ],
      ),
    );
  }
}
