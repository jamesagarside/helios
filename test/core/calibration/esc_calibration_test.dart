import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/calibration/esc_calibration.dart';

void main() {
  group('EscProtocol.fromValue', () {
    test('maps known MOT_PWM_TYPE values', () {
      expect(EscProtocol.fromValue(0), EscProtocol.normalPwm);
      expect(EscProtocol.fromValue(1), EscProtocol.oneShot);
      expect(EscProtocol.fromValue(2), EscProtocol.oneShot125);
      expect(EscProtocol.fromValue(3), EscProtocol.brushed);
      expect(EscProtocol.fromValue(4), EscProtocol.dShot150);
      expect(EscProtocol.fromValue(5), EscProtocol.dShot300);
      expect(EscProtocol.fromValue(6), EscProtocol.dShot600);
      expect(EscProtocol.fromValue(7), EscProtocol.dShot1200);
      expect(EscProtocol.fromValue(8), EscProtocol.pwmRange);
    });

    test('rounds fractional values from PARAM_VALUE floats', () {
      expect(EscProtocol.fromValue(4.0), EscProtocol.dShot150);
      expect(EscProtocol.fromValue(0.0), EscProtocol.normalPwm);
    });

    test('null and out-of-range fall back to unknown', () {
      expect(EscProtocol.fromValue(null), EscProtocol.unknown);
      expect(EscProtocol.fromValue(99), EscProtocol.unknown);
      expect(EscProtocol.fromValue(-5), EscProtocol.unknown);
    });
  });

  group('EscProtocol.calibratable — detection / skip rules', () {
    test('analog protocols are calibratable', () {
      expect(EscProtocol.normalPwm.calibratable, isTrue);
      expect(EscProtocol.oneShot.calibratable, isTrue);
      expect(EscProtocol.oneShot125.calibratable, isTrue);
      expect(EscProtocol.pwmRange.calibratable, isTrue);
    });

    test('DShot and brushed are NOT calibratable', () {
      expect(EscProtocol.dShot150.calibratable, isFalse);
      expect(EscProtocol.dShot300.calibratable, isFalse);
      expect(EscProtocol.dShot600.calibratable, isFalse);
      expect(EscProtocol.dShot1200.calibratable, isFalse);
      expect(EscProtocol.brushed.calibratable, isFalse);
    });

    test('isDigital flags only DShot variants', () {
      expect(EscProtocol.dShot150.isDigital, isTrue);
      expect(EscProtocol.dShot1200.isDigital, isTrue);
      expect(EscProtocol.brushed.isDigital, isFalse);
      expect(EscProtocol.normalPwm.isDigital, isFalse);
    });

    test('unknown is treated as calibratable-with-caution', () {
      expect(EscProtocol.unknown.calibratable, isTrue);
    });
  });

  group('EscCalStateMachine — props-off safety gating', () {
    test('starts on the mandatory props-off gate', () {
      final m = EscCalStateMachine();
      expect(m.snapshot.phase, EscCalPhase.idle);

      final s = m.start();
      expect(s.phase, EscCalPhase.awaitingPropsOff);
      expect(s.propsOff, isFalse);
      expect(s.throttleAllowed, isFalse);
    });

    test('throttle is forbidden until props-off is confirmed', () {
      final m = EscCalStateMachine();
      m.start();
      expect(m.snapshot.throttleAllowed, isFalse);

      final confirmed = m.setPropsOff(true);
      expect(confirmed.throttleAllowed, isTrue);
      expect(confirmed.phase, EscCalPhase.ready);
    });

    test('cannot arm calibration before confirming props off', () {
      final m = EscCalStateMachine();
      m.start();

      final r = m.armCalibration();
      expect(r.action, EscCalAction.none);
      expect(r.snapshot.phase, EscCalPhase.awaitingPropsOff);
    });

    test('un-confirming props off returns to the gate', () {
      final m = EscCalStateMachine();
      m.start();
      m.setPropsOff(true);
      expect(m.snapshot.phase, EscCalPhase.ready);

      final back = m.setPropsOff(false);
      expect(back.phase, EscCalPhase.awaitingPropsOff);
      expect(back.throttleAllowed, isFalse);
    });
  });

  group('EscCalStateMachine — semi-automatic happy path', () {
    test('arms the param then guides through power-cycle to done', () {
      final m = EscCalStateMachine();
      m.start();
      m.setPropsOff(true);

      final armed = m.armCalibration();
      expect(armed.action, EscCalAction.armCalibrationParam);
      expect(armed.snapshot.phase, EscCalPhase.awaitingPowerCycle);
      expect(armed.snapshot.message, contains('battery'));

      final done = m.completePowerCycle();
      expect(done.phase, EscCalPhase.done);
      expect(done.message, contains('motor direction'));
    });

    test('completePowerCycle is a no-op outside the power-cycle phase', () {
      final m = EscCalStateMachine();
      m.start();
      expect(m.completePowerCycle().phase, EscCalPhase.awaitingPropsOff);
    });
  });

  group('EscCalStateMachine — cancellation', () {
    test('cancelling an armed flow restores the calibration param', () {
      final m = EscCalStateMachine();
      m.start();
      m.setPropsOff(true);
      m.armCalibration();

      final c = m.cancel();
      expect(c.action, EscCalAction.restoreCalibrationParam);
      expect(c.snapshot.phase, EscCalPhase.idle);
      expect(c.snapshot.propsOff, isFalse);
    });

    test('cancelling before arming requires no param restore', () {
      final m = EscCalStateMachine();
      m.start();
      m.setPropsOff(true);

      final c = m.cancel();
      expect(c.action, EscCalAction.none);
      expect(c.snapshot.phase, EscCalPhase.idle);
    });

    test('props-off cannot be silently dropped once armed', () {
      final m = EscCalStateMachine();
      m.start();
      m.setPropsOff(true);
      m.armCalibration();

      // Attempting to flip props-off mid-flow is ignored.
      final s = m.setPropsOff(false);
      expect(s.phase, EscCalPhase.awaitingPowerCycle);
      expect(s.propsOff, isTrue);
    });
  });

  group('EscParams', () {
    test('exposes the manual endpoint parameter ids', () {
      expect(EscParams.editableEndpoints, [
        'MOT_PWM_MIN',
        'MOT_PWM_MAX',
        'MOT_SPIN_ARM',
        'MOT_SPIN_MIN',
        'MOT_SPIN_MAX',
      ]);
    });

    test('semi-auto value triggers calibrate-on-next-boot', () {
      expect(EscParams.semiAutoCalibrateValue, 3.0);
      expect(EscParams.normalValue, 0.0);
    });
  });
}
