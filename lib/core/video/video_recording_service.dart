import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum RecordingState { idle, recording, stopping }

/// Manages video recording from an RTSP stream using ffmpeg.
///
/// Recordings are saved as .mp4 files in the app's documents directory.
/// Requires ffmpeg to be installed and accessible on PATH.
class VideoRecordingService {
  Process? _process;
  RecordingState _state = RecordingState.idle;
  String? _currentFile;
  String? _lastError;

  RecordingState get state => _state;
  String? get currentFile => _currentFile;
  String? get lastError => _lastError;
  bool get isRecording => _state == RecordingState.recording;

  /// Get the directory where recordings are saved.
  static Future<Directory> recordingsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'helios_recordings'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// List all recording files, newest first.
  static Future<List<File>> listRecordings() async {
    final dir = await recordingsDirectory();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.mp4') || f.path.endsWith('.mkv'))
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  /// Delete a recording file.
  static Future<void> deleteRecording(File file) async {
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// Start recording from [rtspUrl].
  /// Returns null on success, or an error message on failure.
  Future<String?> startRecording(String rtspUrl) async {
    if (_state != RecordingState.idle) return 'Already recording';
    if (rtspUrl.isEmpty) return 'No RTSP URL configured';

    // Validate RTSP URL scheme to prevent file:// or other protocol abuse.
    final uri = Uri.tryParse(rtspUrl);
    if (uri == null || !{'rtsp', 'rtsps'}.contains(uri.scheme.toLowerCase())) {
      return 'Invalid RTSP URL: must start with rtsp:// or rtsps://';
    }

    _lastError = null;

    // Check ffmpeg is available
    final ffmpegPath = await _findFfmpeg();
    if (ffmpegPath == null) {
      _lastError = 'ffmpeg not found. Install ffmpeg to enable recording.';
      return _lastError;
    }

    final dir = await recordingsDirectory();
    final timestamp = DateTime.now().toLocal();
    final filename =
        'recording_${timestamp.year}${_pad(timestamp.month)}${_pad(timestamp.day)}'
        '_${_pad(timestamp.hour)}${_pad(timestamp.minute)}${_pad(timestamp.second)}.mp4';
    final outputPath = p.join(dir.path, filename);

    try {
      _process = await Process.start(
        ffmpegPath,
        [
          '-rtsp_transport', 'tcp',
          '-i', rtspUrl,
          '-c', 'copy',
          '-y',
          outputPath,
        ],
        runInShell: false,
      );

      _state = RecordingState.recording;
      _currentFile = outputPath;

      // Monitor process exit
      _process!.exitCode.then((code) {
        if (_state == RecordingState.recording) {
          _state = RecordingState.idle;
          if (code != 0) {
            _lastError = 'Recording stopped unexpectedly (exit $code)';
          }
          _currentFile = null;
        }
      });

      return null;
    } catch (e) {
      _lastError = 'Failed to start ffmpeg: $e';
      _state = RecordingState.idle;
      return _lastError;
    }
  }

  /// Stop the current recording.
  Future<void> stopRecording() async {
    if (_state != RecordingState.recording) return;
    _state = RecordingState.stopping;

    try {
      _process?.stdin.write('q');
      await _process?.stdin.flush();
    } catch (_) {}

    // Give ffmpeg time to flush and finalize the file
    await Future.delayed(const Duration(seconds: 2));

    try {
      _process?.kill();
    } catch (_) {}

    await _process?.exitCode;
    _process = null;
    _state = RecordingState.idle;
    _currentFile = null;
  }

  /// Find ffmpeg on PATH.
  static Future<String?> _findFfmpeg() async {
    final candidates = Platform.isWindows
        ? ['ffmpeg.exe', 'ffmpeg']
        : ['ffmpeg'];

    for (final name in candidates) {
      try {
        final result = await Process.run('which', [name]);
        if (result.exitCode == 0) {
          return (result.stdout as String).trim();
        }
      } catch (_) {}
    }

    // Common macOS Homebrew path
    const homebrewPath = '/opt/homebrew/bin/ffmpeg';
    if (File(homebrewPath).existsSync()) return homebrewPath;

    const homebrewIntelPath = '/usr/local/bin/ffmpeg';
    if (File(homebrewIntelPath).existsSync()) return homebrewIntelPath;

    return null;
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
