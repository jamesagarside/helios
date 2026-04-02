import 'dart:async';
import 'package:dart_mavlink/dart_mavlink.dart';
import '../../shared/models/rally_point.dart';
import '../mavlink/mavlink_service.dart';

/// Service for uploading/downloading rally points.
///
/// Uses the MAVLink mission microservice with MavMissionType.rally (2).
///
/// Download flow: GCS sends MISSION_REQUEST_LIST(rally) → vehicle replies
///   MISSION_COUNT(rally) → GCS requests each MISSION_ITEM_INT → ACK
///
/// Upload flow: GCS sends MISSION_COUNT(rally) → vehicle replies
///   MISSION_REQUEST_INT per item → GCS sends MISSION_ITEM_INT → vehicle ACK
class RallyService {
  RallyService(this._mavlink);

  final MavlinkService _mavlink;

  static const _timeout = Duration(seconds: 3);
  static const _maxRetries = 3;

  StreamSubscription<MavlinkMessage>? _sub;

  /// Download rally points from vehicle.
  ///
  /// Calls [onProgress] with 0.0–1.0 during transfer.
  /// Returns the list of rally points on success.
  Future<List<RallyPoint>> download({
    required int targetSystem,
    required int targetComponent,
    void Function(double progress)? onProgress,
  }) async {
    final completer = Completer<List<RallyPoint>>();
    final items = <int, RallyPoint>{};
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

    void requestItem(int seq) {
      final frame = _mavlink.frameBuilder.buildMissionRequestInt(
        targetSystem: targetSystem,
        targetComponent: targetComponent,
        seq: seq,
        missionType: MavMissionType.rally,
      );
      _mavlink.sendRaw(frame);
    }

    void handleMessage(MavlinkMessage msg) {
      if (msg.systemId != targetSystem) return;

      if (msg is MissionCountMessage &&
          msg.missionType == MavMissionType.rally &&
          expectedCount < 0) {
        expectedCount = msg.count;
        if (expectedCount == 0) {
          timeoutTimer?.cancel();
          cleanup();
          completer.complete([]);
          return;
        }
        onProgress?.call(0.0);
        requestItem(0);
        resetTimeout(() => _retryOrFail(
          completer, cleanup, timeoutTimer,
          retries++, 'Rally download timeout waiting for item 0',
          () => requestItem(0),
        ));
      } else if (msg is MissionItemIntMessage &&
          msg.missionType == MavMissionType.rally &&
          expectedCount > 0) {
        items[msg.seq] = RallyPoint(
          seq: msg.seq,
          latitude: msg.latDeg,
          longitude: msg.lonDeg,
          altitude: msg.z,
        );
        onProgress?.call(items.length / expectedCount);
        retries = 0;

        if (items.length >= expectedCount) {
          timeoutTimer?.cancel();
          _sendAck(targetSystem, targetComponent, MavMissionResult.accepted);
          cleanup();
          final sorted = List<RallyPoint>.generate(
            expectedCount,
            (i) => items[i]!,
          );
          completer.complete(sorted);
        } else {
          final nextSeq = _nextMissing(items, expectedCount);
          requestItem(nextSeq);
          resetTimeout(() => _retryOrFail(
            completer, cleanup, timeoutTimer,
            retries++, 'Rally download timeout waiting for item $nextSeq',
            () => requestItem(nextSeq),
          ));
        }
      }
    }

    _sub = _mavlink.messageStream.listen(handleMessage);

    final frame = _mavlink.frameBuilder.buildMissionRequestList(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      missionType: MavMissionType.rally,
    );
    await _mavlink.sendRaw(frame);

    resetTimeout(() {
      if (retries < _maxRetries) {
        retries++;
        _mavlink.sendRaw(frame);
        resetTimeout(() => _retryOrFail(
          completer, cleanup, timeoutTimer,
          _maxRetries, 'Rally download timeout: no MISSION_COUNT received',
          () {},
        ));
      } else {
        cleanup();
        timeoutTimer?.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            RallyProtocolException(
              'Rally download timeout: no MISSION_COUNT received',
            ),
          );
        }
      }
    });

    return completer.future;
  }

  /// Upload rally points to vehicle.
  ///
  /// Calls [onProgress] with 0.0–1.0 during transfer.
  Future<void> upload({
    required int targetSystem,
    required int targetComponent,
    required List<RallyPoint> points,
    void Function(double progress)? onProgress,
  }) async {
    if (points.isEmpty) {
      // Send count of 0 to clear rally points
      final frame = _mavlink.frameBuilder.buildMissionCount(
        targetSystem: targetSystem,
        targetComponent: targetComponent,
        count: 0,
        missionType: MavMissionType.rally,
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
      final point = points[seq];
      final frame = _mavlink.frameBuilder.buildMissionItemInt(
        targetSystem: targetSystem,
        targetComponent: targetComponent,
        seq: seq,
        frame: MavFrame.globalRelativeAlt,
        command: MavCmd.navRallyPoint,
        current: 0,
        autocontinue: 1,
        param1: 0,
        param2: 0,
        param3: 0,
        param4: 0,
        x: (point.latitude * 1e7).round(),
        y: (point.longitude * 1e7).round(),
        z: point.altitude,
        missionType: MavMissionType.rally,
      );
      _mavlink.sendRaw(frame);
    }

    void handleMessage(MavlinkMessage msg) {
      if (msg.systemId != targetSystem) return;

      if (msg is MissionRequestIntMessage &&
          msg.missionType == MavMissionType.rally) {
        final seq = msg.seq;
        if (seq < points.length) {
          onProgress?.call(seq / points.length);
          sendItem(seq);
          retries = 0;
          resetTimeout(() => _retryOrFail(
            completer, cleanup, timeoutTimer,
            retries++, 'Rally upload timeout after sending item $seq',
            () => sendItem(seq),
          ));
        }
      } else if (msg is MissionAckMessage &&
          msg.missionType == MavMissionType.rally) {
        timeoutTimer?.cancel();
        cleanup();
        if (msg.accepted) {
          onProgress?.call(1.0);
          completer.complete();
        } else {
          completer.completeError(
            RallyProtocolException(
              'Rally upload rejected: result=${msg.type}',
            ),
          );
        }
      }
    }

    _sub = _mavlink.messageStream.listen(handleMessage);

    final frame = _mavlink.frameBuilder.buildMissionCount(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      count: points.length,
      missionType: MavMissionType.rally,
    );
    await _mavlink.sendRaw(frame);
    onProgress?.call(0.0);

    resetTimeout(() {
      if (retries < _maxRetries) {
        retries++;
        _mavlink.sendRaw(frame);
        resetTimeout(() => _retryOrFail(
          completer, cleanup, timeoutTimer,
          _maxRetries, 'Rally upload timeout: vehicle did not request items',
          () {},
        ));
      } else {
        cleanup();
        timeoutTimer?.cancel();
        if (!completer.isCompleted) {
          completer.completeError(
            RallyProtocolException(
              'Rally upload timeout: vehicle did not request items',
            ),
          );
        }
      }
    });

    return completer.future;
  }

  /// Cancel any in-progress transfer.
  void cancel() {
    _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    cancel();
  }

  void _sendAck(int targetSystem, int targetComponent, int result) {
    final frame = _mavlink.frameBuilder.buildMissionAck(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      type: result,
      missionType: MavMissionType.rally,
    );
    _mavlink.sendRaw(frame);
  }

  int _nextMissing(Map<int, RallyPoint> received, int total) {
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
        completer.completeError(RallyProtocolException(errorMessage));
      }
    }
  }
}

/// Exception for rally protocol errors.
class RallyProtocolException implements Exception {
  RallyProtocolException(this.message);
  final String message;

  @override
  String toString() => 'RallyProtocolException: $message';
}
