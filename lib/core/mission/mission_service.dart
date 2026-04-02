import 'dart:async';
import 'package:dart_mavlink/dart_mavlink.dart';
import '../../shared/models/mission_item.dart';
import '../mavlink/mavlink_service.dart';

/// Mission protocol service — handles download/upload of mission items
/// using the MAVLink mission microservice protocol.
///
/// Download flow: GCS sends REQUEST_LIST → vehicle replies COUNT →
///   GCS sends REQUEST_INT(0) → vehicle replies ITEM_INT(0) → ... → GCS sends ACK
///
/// Upload flow: GCS sends COUNT → vehicle replies REQUEST_INT(0) →
///   GCS sends ITEM_INT(0) → vehicle replies REQUEST_INT(1) → ... → vehicle sends ACK
class MissionService {
  MissionService(this._mavlink);

  final MavlinkService _mavlink;

  static const _timeout = Duration(seconds: 3);
  static const _maxRetries = 3;

  StreamSubscription<MavlinkMessage>? _sub;

  /// Download mission from vehicle.
  ///
  /// Calls [onProgress] with 0.0-1.0 during transfer.
  /// Returns the list of mission items on success.
  Future<List<MissionItem>> download({
    required int targetSystem,
    required int targetComponent,
    void Function(double progress)? onProgress,
  }) async {
    final completer = Completer<List<MissionItem>>();
    final items = <int, MissionItem>{};
    int expectedCount = -1;
    int retries = 0;

    void cleanup() {
      _sub?.cancel();
      _sub = null;
    }

    Timer? timeoutTimer;

    void resetTimeout(void Function() onTimeout) {
      timeoutTimer?.cancel();
      timeoutTimer = Timer(_timeout, onTimeout);
    }

    void handleMessage(MavlinkMessage msg) {
      if (msg.systemId != targetSystem) return;

      if (msg is MissionCountMessage && expectedCount < 0) {
        expectedCount = msg.count;
        if (expectedCount == 0) {
          timeoutTimer?.cancel();
          cleanup();
          completer.complete([]);
          return;
        }
        onProgress?.call(0.0);
        // Request first item
        _requestItem(targetSystem, targetComponent, 0);
        resetTimeout(() => _retryOrFail(
          completer, cleanup, timeoutTimer,
          retries++, 'Download timeout waiting for item 0',
          () => _requestItem(targetSystem, targetComponent, 0),
        ));
      } else if (msg is MissionItemIntMessage && expectedCount > 0) {
        items[msg.seq] = MissionItem.fromMessage(msg);
        onProgress?.call(items.length / expectedCount);
        retries = 0;

        if (items.length >= expectedCount) {
          // All items received — send ACK
          timeoutTimer?.cancel();
          _sendAck(targetSystem, targetComponent, MavMissionResult.accepted);
          cleanup();
          final sorted = List<MissionItem>.generate(
            expectedCount,
            (i) => items[i]!,
          );
          completer.complete(sorted);
        } else {
          // Request next missing item
          final nextSeq = _nextMissing(items, expectedCount);
          _requestItem(targetSystem, targetComponent, nextSeq);
          resetTimeout(() => _retryOrFail(
            completer, cleanup, timeoutTimer,
            retries++, 'Download timeout waiting for item $nextSeq',
            () => _requestItem(targetSystem, targetComponent, nextSeq),
          ));
        }
      }
    }

    _sub = _mavlink.messageStream.listen(handleMessage);

    // Send MISSION_REQUEST_LIST
    final frame = _mavlink.frameBuilder.buildMissionRequestList(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
    );
    await _mavlink.sendRaw(frame);

    resetTimeout(() {
      if (retries < _maxRetries) {
        retries++;
        _mavlink.sendRaw(frame);
        resetTimeout(() => _retryOrFail(
          completer, cleanup, timeoutTimer,
          _maxRetries, 'Download timeout waiting for MISSION_COUNT',
          () {},
        ));
      } else {
        cleanup();
        timeoutTimer?.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            MissionProtocolException('Download timeout: no MISSION_COUNT received'),
          );
        }
      }
    });

    return completer.future;
  }

  /// Upload mission items to vehicle.
  ///
  /// Calls [onProgress] with 0.0-1.0 during transfer.
  Future<void> upload({
    required int targetSystem,
    required int targetComponent,
    required List<MissionItem> items,
    void Function(double progress)? onProgress,
  }) async {
    if (items.isEmpty) {
      // Send count of 0 to clear mission
      final frame = _mavlink.frameBuilder.buildMissionCount(
        targetSystem: targetSystem,
        targetComponent: targetComponent,
        count: 0,
      );
      await _mavlink.sendRaw(frame);
      return;
    }

    final completer = Completer<void>();
    int retries = 0;

    void cleanup() {
      _sub?.cancel();
      _sub = null;
    }

    Timer? timeoutTimer;

    void resetTimeout(void Function() onTimeout) {
      timeoutTimer?.cancel();
      timeoutTimer = Timer(_timeout, onTimeout);
    }

    void sendItem(int seq) {
      final item = items[seq];
      final frame = _mavlink.frameBuilder.buildMissionItemInt(
        targetSystem: targetSystem,
        targetComponent: targetComponent,
        seq: seq,
        frame: item.frame,
        command: item.command,
        current: seq == 0 ? 1 : 0,
        autocontinue: item.autocontinue,
        param1: item.param1,
        param2: item.param2,
        param3: item.param3,
        param4: item.param4,
        x: item.latE7,
        y: item.lonE7,
        z: item.altitude,
      );
      _mavlink.sendRaw(frame);
    }

    void handleMessage(MavlinkMessage msg) {
      if (msg.systemId != targetSystem) return;

      if (msg is MissionRequestIntMessage) {
        final seq = msg.seq;
        if (seq < items.length) {
          onProgress?.call(seq / items.length);
          sendItem(seq);
          retries = 0;
          resetTimeout(() => _retryOrFail(
            completer, cleanup, timeoutTimer,
            retries++, 'Upload timeout after sending item $seq',
            () => sendItem(seq),
          ));
        }
      } else if (msg is MissionAckMessage) {
        timeoutTimer?.cancel();
        cleanup();
        if (msg.accepted) {
          onProgress?.call(1.0);
          completer.complete();
        } else {
          completer.completeError(
            MissionProtocolException(
              'Upload rejected: result=${msg.type}',
            ),
          );
        }
      }
    }

    _sub = _mavlink.messageStream.listen(handleMessage);

    // Send MISSION_COUNT to initiate upload
    final frame = _mavlink.frameBuilder.buildMissionCount(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      count: items.length,
    );
    await _mavlink.sendRaw(frame);
    onProgress?.call(0.0);

    resetTimeout(() {
      if (retries < _maxRetries) {
        retries++;
        _mavlink.sendRaw(frame);
        resetTimeout(() => _retryOrFail(
          completer, cleanup, timeoutTimer,
          _maxRetries, 'Upload timeout: no REQUEST_INT received',
          () {},
        ));
      } else {
        cleanup();
        timeoutTimer?.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            MissionProtocolException('Upload timeout: vehicle did not request items'),
          );
        }
      }
    });

    return completer.future;
  }

  /// Clear mission on vehicle (upload empty mission).
  Future<void> clearMission({
    required int targetSystem,
    required int targetComponent,
  }) async {
    return upload(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      items: [],
    );
  }

  /// Set the current/active mission item on the vehicle.
  Future<void> setCurrentItem({
    required int targetSystem,
    required int targetComponent,
    required int seq,
  }) async {
    await _mavlink.sendCommand(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      command: MavCmd.missionStart,
      param1: seq.toDouble(),
      param2: 0,
    );
  }

  void _requestItem(int targetSystem, int targetComponent, int seq) {
    final frame = _mavlink.frameBuilder.buildMissionRequestInt(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      seq: seq,
    );
    _mavlink.sendRaw(frame);
  }

  void _sendAck(int targetSystem, int targetComponent, int result) {
    final frame = _mavlink.frameBuilder.buildMissionAck(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      type: result,
    );
    _mavlink.sendRaw(frame);
  }

  int _nextMissing(Map<int, MissionItem> received, int total) {
    for (var i = 0; i < total; i++) {
      if (!received.containsKey(i)) return i;
    }
    return total - 1;
  }

  void _retryOrFail(
    Completer<Object?> completer,
    void Function() cleanup,
    Timer? timeoutTimer,
    int retryCount,
    String errorMessage,
    void Function() retryAction,
  ) {
    if (retryCount < _maxRetries) {
      retryAction();
    } else {
      cleanup();
      timeoutTimer?.cancel();
      if (!completer.isCompleted) {
        completer.completeError(MissionProtocolException(errorMessage));
      }
    }
  }

  /// Cancel any in-progress transfer.
  void cancel() {
    _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    cancel();
  }
}

/// Exception for mission protocol errors.
class MissionProtocolException implements Exception {
  MissionProtocolException(this.message);
  final String message;

  @override
  String toString() => 'MissionProtocolException: $message';
}
