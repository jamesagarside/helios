import 'package:equatable/equatable.dart';

/// State of telemetry recording to DuckDB.
class RecordingState extends Equatable {
  const RecordingState({
    this.isRecording = false,
    this.currentFilePath,
    this.recordingStarted,
    this.rowsWritten = 0,
    this.bytesWritten = 0,
    this.autoRecordOnArm = true,
  });

  final bool isRecording;
  final String? currentFilePath;
  final DateTime? recordingStarted;
  final int rowsWritten;
  final int bytesWritten;
  final bool autoRecordOnArm;

  Duration get recordingDuration {
    if (recordingStarted == null) return Duration.zero;
    return DateTime.now().difference(recordingStarted!);
  }

  RecordingState copyWith({
    bool? isRecording,
    String? currentFilePath,
    DateTime? recordingStarted,
    int? rowsWritten,
    int? bytesWritten,
    bool? autoRecordOnArm,
  }) {
    return RecordingState(
      isRecording: isRecording ?? this.isRecording,
      currentFilePath: currentFilePath ?? this.currentFilePath,
      recordingStarted: recordingStarted ?? this.recordingStarted,
      rowsWritten: rowsWritten ?? this.rowsWritten,
      bytesWritten: bytesWritten ?? this.bytesWritten,
      autoRecordOnArm: autoRecordOnArm ?? this.autoRecordOnArm,
    );
  }

  @override
  List<Object?> get props => [
        isRecording, currentFilePath, recordingStarted,
        rowsWritten, bytesWritten, autoRecordOnArm,
      ];
}
