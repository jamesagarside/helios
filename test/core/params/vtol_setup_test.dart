import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/params/vtol_setup.dart';

/// Correctness gate for the VTOL / quadplane core logic. The gating decision,
/// the `Q_OPTIONS` bitmask, the conditional-tilt rule, the QAUTOTUNE guard, and
/// the STATUSTEXT classifier are all safety-relevant (a wrong gate hides the
/// panel on the very vehicles it exists for; a wrong bit silently changes VTOL
/// behaviour), so each rule is pinned with explicit values.
void main() {
  group('vtolGateFor — Q_ENABLE gating (ADR 0003)', () {
    test('params not loaded -> paramsUnloaded (no empty flash)', () {
      expect(
        vtolGateFor(paramsLoaded: false, qEnable: null),
        VtolGate.paramsUnloaded,
      );
      // Even a present value is suppressed until the cache is considered loaded.
      expect(
        vtolGateFor(paramsLoaded: false, qEnable: 1),
        VtolGate.paramsUnloaded,
      );
    });

    test('Q_ENABLE absent -> hidden (non-quadplane firmware)', () {
      expect(
        vtolGateFor(paramsLoaded: true, qEnable: null),
        VtolGate.hidden,
      );
    });

    test('Q_ENABLE == 0 -> enablePrompt (Plane, quadplane off)', () {
      expect(
        vtolGateFor(paramsLoaded: true, qEnable: 0),
        VtolGate.enablePrompt,
      );
      // Tolerate the FC storing the int as a double.
      expect(
        vtolGateFor(paramsLoaded: true, qEnable: 0.0),
        VtolGate.enablePrompt,
      );
    });

    test('Q_ENABLE == 1 -> fullPanel', () {
      expect(
        vtolGateFor(paramsLoaded: true, qEnable: 1),
        VtolGate.fullPanel,
      );
      expect(
        vtolGateFor(paramsLoaded: true, qEnable: 0.9999),
        VtolGate.fullPanel,
      );
    });

    test('vtolTabVisible is true only for enablePrompt / fullPanel', () {
      expect(vtolTabVisible(paramsLoaded: false, qEnable: null), isFalse);
      expect(vtolTabVisible(paramsLoaded: true, qEnable: null), isFalse);
      expect(vtolTabVisible(paramsLoaded: true, qEnable: 0), isTrue);
      expect(vtolTabVisible(paramsLoaded: true, qEnable: 1), isTrue);
    });
  });

  group('tiltAutoVisible — conditional tilt', () {
    test('absent Q_TILT_MASK is not auto-visible', () {
      expect(tiltAutoVisible(null), isFalse);
    });

    test('Q_TILT_MASK == 0 is not auto-visible', () {
      expect(tiltAutoVisible(0), isFalse);
      expect(tiltAutoVisible(0.0), isFalse);
    });

    test('non-zero Q_TILT_MASK is auto-visible (real tiltrotor)', () {
      expect(tiltAutoVisible(1), isTrue);
      expect(tiltAutoVisible(5), isTrue);
    });
  });

  group('QOptionsMask — Q_OPTIONS bitmask', () {
    test('fromParam rounds the double parameter value to an int', () {
      expect(QOptionsMask.fromParam(0.0).value, 0);
      expect(QOptionsMask.fromParam(5.0).value, 5);
      expect(QOptionsMask.fromParam(4.9999).value, 5);
    });

    test('isEnabled decodes individual bits', () {
      const mask = QOptionsMask(0x05); // bits 0 and 2
      expect(mask.isEnabled(1 << 0), isTrue);
      expect(mask.isEnabled(1 << 1), isFalse);
      expect(mask.isEnabled(1 << 2), isTrue);
    });

    test('enabledBits returns only known set bits', () {
      const mask = QOptionsMask((1 << 0) | (1 << 4));
      expect(mask.enabledBits, {1 << 0, 1 << 4});
    });

    test('toggling a bit on sets it without disturbing others', () {
      const start = QOptionsMask(1 << 0);
      final next = start.toggle(1 << 4, true);
      expect(next.value, (1 << 0) | (1 << 4));
      expect(next.isEnabled(1 << 0), isTrue);
      expect(next.isEnabled(1 << 4), isTrue);
    });

    test('toggling a bit off clears only that bit', () {
      const start = QOptionsMask((1 << 0) | (1 << 1) | (1 << 2));
      final next = start.toggle(1 << 1, false);
      expect(next.value, (1 << 0) | (1 << 2));
      expect(next.isEnabled(1 << 1), isFalse);
    });

    test('toggling to the current state is a value no-op', () {
      const mask = QOptionsMask((1 << 0) | (1 << 3));
      expect(mask.toggle(1 << 0, true).value, mask.value);
      expect(mask.toggle(1 << 5, false).value, mask.value);
    });

    test('round-trips through paramValue', () {
      for (final v in [0, 1, 0x05, 0x1FE, 0xFFFFF]) {
        final mask = QOptionsMask(v);
        final round = QOptionsMask.fromParam(mask.paramValue);
        expect(round.value, v);
        expect(round, mask);
      }
    });

    test('option bits are unique and labelled', () {
      final bits = qOptionBits.map((o) => o.bit).toList();
      expect(bits.toSet().length, bits.length, reason: 'bits must be unique');
      for (final o in qOptionBits) {
        expect(o.label, isNotEmpty);
        expect(o.description, isNotEmpty);
      }
    });
  });

  group('QAUTOTUNE guard (pragmatic override)', () {
    test('only effective when armed AND in a VTOL mode', () {
      // Armed + QHOVER (18) -> effective.
      expect(
        qAutotuneLikelyEffective(armed: true, currentMode: 18),
        isTrue,
      );
      // Disarmed in a VTOL mode -> not effective.
      expect(
        qAutotuneLikelyEffective(armed: false, currentMode: 18),
        isFalse,
      );
      // Armed but in a fixed-wing mode (MANUAL=0) -> not effective.
      expect(
        qAutotuneLikelyEffective(armed: true, currentMode: 0),
        isFalse,
      );
    });

    test('isVtolMode covers the Q-mode range', () {
      for (final m in const [17, 18, 19, 20, 21, 22, 23]) {
        expect(isVtolMode(m), isTrue, reason: 'mode $m');
      }
      for (final m in const [0, 10, 11, 16, 24]) {
        expect(isVtolMode(m), isFalse, reason: 'mode $m');
      }
    });

    test('QAUTOTUNE mode number is the Plane value (22)', () {
      expect(kQAutotuneMode, 22);
      expect(isVtolMode(kQAutotuneMode), isTrue);
    });
  });

  group('classifyQAutotuneStatus — STATUSTEXT readout', () {
    test('unrelated text returns null (caller keeps prior state)', () {
      expect(classifyQAutotuneStatus('EKF3 IMU0 is using GPS'), isNull);
      expect(classifyQAutotuneStatus(''), isNull);
    });

    test('start / begin -> tuning', () {
      expect(classifyQAutotuneStatus('AutoTune: Started'),
          QAutotuneProgress.tuning);
      expect(classifyQAutotuneStatus('QAutoTune: begin'),
          QAutotuneProgress.tuning);
    });

    test('saved -> saved (takes priority over other keywords)', () {
      expect(classifyQAutotuneStatus('AutoTune: Saved gains for roll'),
          QAutotuneProgress.saved);
    });

    test('fail / abort -> failed', () {
      expect(classifyQAutotuneStatus('AutoTune: FAILED'),
          QAutotuneProgress.failed);
      expect(classifyQAutotuneStatus('AutoTune aborted by pilot'),
          QAutotuneProgress.failed);
    });

    test('matching is case-insensitive', () {
      expect(classifyQAutotuneStatus('autotune: tuning roll'),
          QAutotuneProgress.tuning);
    });
  });
}
