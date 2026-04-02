import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted video settings.
class VideoSettings {
  const VideoSettings({
    this.rtspUrl = 'rtsp://192.168.0.10:8554/main',
    this.autoConnect = false,
    this.lowLatency = true,
  });

  final String rtspUrl;
  final bool autoConnect;
  final bool lowLatency;

  VideoSettings copyWith({
    String? rtspUrl,
    bool? autoConnect,
    bool? lowLatency,
  }) {
    return VideoSettings(
      rtspUrl: rtspUrl ?? this.rtspUrl,
      autoConnect: autoConnect ?? this.autoConnect,
      lowLatency: lowLatency ?? this.lowLatency,
    );
  }
}

/// Shared video player — single instance used by both PiP and full-screen.
class VideoPlayerController extends StateNotifier<VideoSettings> {
  VideoPlayerController() : super(const VideoSettings()) {
    try {
      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 2 * 1024 * 1024,
        ),
      );
      _videoController = VideoController(_player);
      _available = true;
    } catch (_) {
      // media_kit native lib not available (e.g. in tests)
      _available = false;
    }
    _loadSettings();

    if (_available) {
      _player.stream.playing.listen((playing) {
        _isPlaying = playing;
      });

      _player.stream.error.listen((error) {
        _lastError = error;
        _isPlaying = false;
      });
    }
  }

  late final Player _player;
  late final VideoController _videoController;
  bool _available = false;
  bool _isPlaying = false;
  String? _lastError;

  bool get available => _available;
  Player get player => _player;
  VideoController get videoController => _videoController;
  bool get isPlaying => _available && _isPlaying;
  String? get lastError => _lastError;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    state = VideoSettings(
      rtspUrl: prefs.getString('video_rtsp_url') ?? state.rtspUrl,
      autoConnect: prefs.getBool('video_auto_connect') ?? state.autoConnect,
      lowLatency: prefs.getBool('video_low_latency') ?? state.lowLatency,
    );
  }

  Future<void> updateSettings(VideoSettings settings) async {
    state = settings;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('video_rtsp_url', settings.rtspUrl);
    await prefs.setBool('video_auto_connect', settings.autoConnect);
    await prefs.setBool('video_low_latency', settings.lowLatency);
  }

  Future<void> connect([String? url]) async {
    if (!_available) return;
    final rtspUrl = url ?? state.rtspUrl;
    _lastError = null;
    await _player.open(Media(rtspUrl), play: true);
  }

  Future<void> disconnect() async {
    if (!_available) return;
    await _player.stop();
    _isPlaying = false;
  }

  @override
  void dispose() {
    if (_available) _player.dispose();
    super.dispose();
  }
}

final videoPlayerProvider =
    StateNotifierProvider<VideoPlayerController, VideoSettings>(
  (ref) {
    final controller = VideoPlayerController();
    ref.onDispose(controller.dispose);
    return controller;
  },
);
