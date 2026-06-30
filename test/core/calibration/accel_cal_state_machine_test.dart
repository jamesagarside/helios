import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/calibration/accel_cal_state_machine.dart';
import 'package:vector_math/vector_math_64.dart';

/// Simulated ArduPilot 6-point accel-cal STATUSTEXT prompts, in firmware order.
const _prompts = [
  'Place vehicle level and press any key.',
  'Place vehicle on its LEFT side and press any key.',
  'Place vehicle on its RIGHT side and press any key.',
  'Place vehicle nose DOWN and press any key.',
  'Place vehicle nose UP and press any key.',
  'Place vehicle on its BACK and press any key.',
];

const _orderedPositions = [
  AccelCalPosition.level,
  AccelCalPosition.leftSide,
  AccelCalPosition.rightSide,
  AccelCalPosition.noseDown,
  AccelCalPosition.noseUp,
  AccelCalPosition.back,
];

void main() {
  group('AccelCalStateMachine — full happy path', () {
    test('drives all six positions and completes on success', () {
      final m = AccelCalStateMachine();

      expect(m.snapshot.phase, AccelCalPhase.idle);
      expect(m.start().phase, AccelCalPhase.starting);

      for (var i = 0; i < _prompts.length; i++) {
        final afterPrompt = m.onStatusText(_prompts[i]);
        expect(afterPrompt.phase, AccelCalPhase.awaitingPosition);
        expect(afterPrompt.position, _orderedPositions[i],
            reason: 'prompt $i should map to ${_orderedPositions[i]}');

        final confirm = m.confirmPosition();
        expect(confirm.action, AccelCalAction.sendPositionConfirm);
        expect(confirm.snapshot.phase, AccelCalPhase.confirming);
        expect(confirm.snapshot.completedPositions.contains(_orderedPositions[i]),
            isTrue);
      }

      expect(m.snapshot.completedPositions.length, 6);

      final done = m.onStatusText('Calibration successful');
      expect(done.phase, AccelCalPhase.success);
      expect(done.isTerminal, isTrue);
    });

    test('position index matches MAV_CMD_ACCELCAL_VEHICLE_POS ordering', () {
      expect(AccelCalPosition.level.posIndex, 1);
      expect(AccelCalPosition.leftSide.posIndex, 2);
      expect(AccelCalPosition.rightSide.posIndex, 3);
      expect(AccelCalPosition.noseDown.posIndex, 4);
      expect(AccelCalPosition.noseUp.posIndex, 5);
      expect(AccelCalPosition.back.posIndex, 6);
    });
  });

  group('AccelCalStateMachine — prompt parsing tolerance', () {
    test('matches varied wording and is case-insensitive', () {
      final cases = <String, AccelCalPosition>{
        'place vehicle level': AccelCalPosition.level,
        'Place Vehicle On Its Left Side': AccelCalPosition.leftSide,
        'PLACE VEHICLE ON ITS RIGHT SIDE': AccelCalPosition.rightSide,
        'Place vehicle nose Down': AccelCalPosition.noseDown,
        'Place vehicle nose up and hold': AccelCalPosition.noseUp,
        'Place vehicle on its back': AccelCalPosition.back,
      };
      cases.forEach((text, expected) {
        final m = AccelCalStateMachine()..start();
        expect(m.onStatusText(text).position, expected, reason: text);
      });
    });

    test('nose-down is not mistaken for the back position', () {
      final m = AccelCalStateMachine()..start();
      // "back" substring could appear; ensure nose checks win when present.
      expect(m.onStatusText('Place vehicle nose DOWN').position,
          AccelCalPosition.noseDown);
    });

    test('ignores unrelated chatter without changing phase', () {
      final m = AccelCalStateMachine()..start();
      m.onStatusText(_prompts[0]);
      final before = m.snapshot;
      final after = m.onStatusText('EKF3 IMU0 is using GPS');
      expect(after.phase, before.phase);
      expect(after.position, before.position);
    });
  });

  group('AccelCalStateMachine — failure and cancel paths', () {
    test('failure STATUSTEXT transitions to failed and is terminal', () {
      final m = AccelCalStateMachine()..start();
      m.onStatusText(_prompts[0]);
      final failed = m.onStatusText('Calibration FAILED');
      expect(failed.phase, AccelCalPhase.failed);
      expect(failed.isTerminal, isTrue);
      // No further transitions after terminal.
      expect(m.onStatusText('Place vehicle level').phase, AccelCalPhase.failed);
    });

    test('cancel transitions to cancelled and clears the position', () {
      final m = AccelCalStateMachine()..start();
      m.onStatusText(_prompts[1]);
      final cancelled = m.cancel();
      expect(cancelled.phase, AccelCalPhase.cancelled);
      expect(cancelled.position, isNull);
      expect(cancelled.isTerminal, isTrue);
    });

    test('reset returns to idle for a fresh run', () {
      final m = AccelCalStateMachine()..start();
      m.onStatusText(_prompts[0]);
      m.cancel();
      expect(m.reset().phase, AccelCalPhase.idle);
      expect(m.start().phase, AccelCalPhase.starting);
    });
  });

  group('AccelCalStateMachine — confirm guards', () {
    test('confirm is a no-op when no position is awaiting', () {
      final m = AccelCalStateMachine()..start();
      final r = m.confirmPosition();
      expect(r.action, AccelCalAction.none);
      expect(r.snapshot.phase, AccelCalPhase.starting);
    });

    test('confirm is a no-op once terminal', () {
      final m = AccelCalStateMachine()..start();
      m.onStatusText('Calibration successful');
      final r = m.confirmPosition();
      expect(r.action, AccelCalAction.none);
      expect(r.snapshot.phase, AccelCalPhase.success);
    });
  });

  group('AccelCalPosition — target poses', () {
    test('level is identity', () {
      final q = AccelCalPosition.level.targetPose..normalize();
      expect(q.w.abs(), closeTo(1.0, 1e-9));
    });

    test('opposite roll positions differ by ~180 degrees', () {
      final left = AccelCalPosition.leftSide.targetPose;
      final right = AccelCalPosition.rightSide.targetPose;
      final angle = _angleBetween(left, right);
      expect(angle, closeTo(math.pi, 1e-6));
    });

    test('nose up/down are 90 degrees from level', () {
      final level = AccelCalPosition.level.targetPose;
      expect(_angleBetween(level, AccelCalPosition.noseUp.targetPose),
          closeTo((math.pi / 2), 1e-6));
      expect(_angleBetween(level, AccelCalPosition.noseDown.targetPose),
          closeTo((math.pi / 2), 1e-6));
    });

    test('back is ~180 degrees from level', () {
      final level = AccelCalPosition.level.targetPose;
      expect(_angleBetween(level, AccelCalPosition.back.targetPose),
          closeTo(math.pi, 1e-6));
    });
  });
}

double _angleBetween(Quaternion a, Quaternion b) {
  final an = a.normalized();
  final bn = b.normalized();
  var dot = (an.x * bn.x + an.y * bn.y + an.z * bn.z + an.w * bn.w).abs();
  if (dot > 1.0) dot = 1.0;
  return 2.0 * math.acos(dot);
}
