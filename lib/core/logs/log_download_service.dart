import 'dart:async';
import 'dart:io';
import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../mavlink/mavlink_service.dart';

/// Metadata for an onboard log file.
class LogInfo {
  LogInfo({required this.id, required this.numLogs, required this.size, this.dateTime});
  final int id;
  final int numLogs;
  final int size;
  final DateTime? dateTime;

  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Service for listing and downloading onboard dataflash logs.
class LogDownloadService {
  LogDownloadService(this._mavlink);

  final MavlinkService _mavlink;
  StreamSubscription<MavlinkMessage>? _sub;

  /// List all onboard logs.
  Future<List<LogInfo>> listLogs({
    required int targetSystem,
    required int targetComponent,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final logs = <int, LogInfo>{};
    final completer = Completer<List<LogInfo>>();
    Timer? timeoutTimer;
    Timer? gapTimer;

    void cleanup() {
      _sub?.cancel();
      _sub = null;
      timeoutTimer?.cancel();
      gapTimer?.cancel();
    }

    _sub = _mavlink.messagesOf<LogEntryMessage>().listen((msg) {
      logs[msg.id] = LogInfo(
        id: msg.id,
        numLogs: msg.numLogs,
        size: msg.size,
        dateTime: msg.dateTime,
      );

      gapTimer?.cancel();
      gapTimer = Timer(const Duration(seconds: 2), () {
        cleanup();
        if (!completer.isCompleted) {
          completer.complete(logs.values.toList()..sort((a, b) => a.id.compareTo(b.id)));
        }
      });

      // Check if we have all logs
      if (logs.length >= msg.numLogs) {
        cleanup();
        if (!completer.isCompleted) {
          completer.complete(logs.values.toList()..sort((a, b) => a.id.compareTo(b.id)));
        }
      }
    });

    await _mavlink.sendRaw(_mavlink.frameBuilder.buildLogRequestList(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
    ));

    timeoutTimer = Timer(timeout, () {
      cleanup();
      if (!completer.isCompleted) {
        if (logs.isEmpty) {
          completer.completeError(LogDownloadException('No logs found'));
        } else {
          completer.complete(logs.values.toList()..sort((a, b) => a.id.compareTo(b.id)));
        }
      }
    });

    return completer.future;
  }

  /// Download a specific log to a file.
  /// Returns the file path. Calls [onProgress] with 0.0-1.0.
  Future<String> downloadLog({
    required int targetSystem,
    required int targetComponent,
    required int logId,
    required int logSize,
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getApplicationSupportDirectory();
    final logsDir = Directory(p.join(dir.path, 'logs'));
    if (!logsDir.existsSync()) logsDir.createSync(recursive: true);
    final filePath = p.join(logsDir.path, 'log_$logId.bin');
    final file = File(filePath);
    final sink = file.openWrite();

    final completer = Completer<String>();
    int bytesReceived = 0;
    Timer? timeoutTimer;

    void cleanup() {
      _sub?.cancel();
      _sub = null;
      timeoutTimer?.cancel();
      sink.close();
    }

    void requestChunk(int offset) {
      final remaining = logSize - offset;
      final chunkSize = remaining > 512 ? 512 : remaining;
      _mavlink.sendRaw(_mavlink.frameBuilder.buildLogRequestData(
        targetSystem: targetSystem,
        targetComponent: targetComponent,
        logId: logId,
        offset: offset,
        count: chunkSize,
      ));
    }

    _sub = _mavlink.messagesOf<LogDataMessage>().listen((msg) {
      if (msg.id != logId) return;

      if (msg.count == 0) {
        // End of log
        cleanup();
        onProgress?.call(1.0);
        if (!completer.isCompleted) completer.complete(filePath);
        return;
      }

      sink.add(msg.data);
      bytesReceived += msg.count;
      onProgress?.call(logSize > 0 ? bytesReceived / logSize : 0);

      // Reset timeout
      timeoutTimer?.cancel();
      timeoutTimer = Timer(const Duration(seconds: 5), () {
        // Retry the last chunk
        requestChunk(bytesReceived);
      });

      // Request next chunk
      if (bytesReceived < logSize) {
        requestChunk(bytesReceived);
      } else {
        cleanup();
        onProgress?.call(1.0);
        if (!completer.isCompleted) completer.complete(filePath);
      }
    });

    // Start download
    requestChunk(0);

    // Absolute timeout
    final absTimeout = Timer(Duration(seconds: (logSize / 1000).clamp(30, 600).toInt()), () {
      cleanup();
      if (!completer.isCompleted) {
        if (bytesReceived > 0) {
          completer.complete(filePath); // partial download
        } else {
          completer.completeError(LogDownloadException('Download timeout'));
        }
      }
    });

    return completer.future.whenComplete(() => absTimeout.cancel());
  }

  /// Send LOG_REQUEST_END to stop log operations.
  Future<void> endLogRequest({
    required int targetSystem,
    required int targetComponent,
  }) async {
    await _mavlink.sendRaw(_mavlink.frameBuilder.buildLogRequestEnd(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
    ));
  }

  void cancel() {
    _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    cancel();
  }
}

class LogDownloadException implements Exception {
  LogDownloadException(this.message);
  final String message;
  @override
  String toString() => 'LogDownloadException: $message';
}
