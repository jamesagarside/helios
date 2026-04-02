import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/video/video_recording_service.dart';

/// State snapshot for the recording UI.
class VideoRecordingState {
  const VideoRecordingState({
    this.recordingState = RecordingState.idle,
    this.lastError,
    this.recordings = const [],
  });

  final RecordingState recordingState;
  final String? lastError;
  final List<File> recordings;

  bool get isRecording => recordingState == RecordingState.recording;

  VideoRecordingState copyWith({
    RecordingState? recordingState,
    String? lastError,
    List<File>? recordings,
  }) {
    return VideoRecordingState(
      recordingState: recordingState ?? this.recordingState,
      lastError: lastError,
      recordings: recordings ?? this.recordings,
    );
  }
}

class VideoRecordingNotifier extends StateNotifier<VideoRecordingState> {
  VideoRecordingNotifier() : super(const VideoRecordingState()) {
    _refreshRecordings();
  }

  final _service = VideoRecordingService();

  Future<void> startRecording(String rtspUrl) async {
    state = state.copyWith(recordingState: RecordingState.recording, lastError: null);
    final error = await _service.startRecording(rtspUrl);
    if (error != null) {
      state = state.copyWith(
        recordingState: RecordingState.idle,
        lastError: error,
      );
    } else {
      state = state.copyWith(recordingState: RecordingState.recording);
    }
  }

  Future<void> stopRecording() async {
    state = state.copyWith(recordingState: RecordingState.stopping);
    await _service.stopRecording();
    await _refreshRecordings();
    state = state.copyWith(recordingState: RecordingState.idle);
  }

  Future<void> deleteRecording(File file) async {
    await VideoRecordingService.deleteRecording(file);
    await _refreshRecordings();
  }

  Future<void> _refreshRecordings() async {
    final files = await VideoRecordingService.listRecordings();
    state = state.copyWith(recordings: files);
  }

  Future<String> get recordingsPath async {
    final dir = await VideoRecordingService.recordingsDirectory();
    return dir.path;
  }
}

final videoRecordingProvider =
    StateNotifierProvider<VideoRecordingNotifier, VideoRecordingState>(
  (ref) => VideoRecordingNotifier(),
);
