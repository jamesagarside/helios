import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/calibration/rc_calibration.dart';

void main() {
  group('RcEndpointCapture', () {
    test('seeds min/max/trim from the starting snapshot', () {
      final capture = RcEndpointCapture();
      capture.start([1500, 1500, 1000, 1500]);

      final result = capture.finish();
      expect(result, hasLength(4));

      final ch1 = result.firstWhere((c) => c.channel == 1);
      expect(ch1.min, 1500);
      expect(ch1.max, 1500);
      expect(ch1.trim, 1500);
    });

    test('expands min/max as samples sweep the range', () {
      final capture = RcEndpointCapture();
      capture.start([1500, 1500]);
      capture.addSample([1100, 1500]); // CH1 low
      capture.addSample([1900, 1500]); // CH1 high
      capture.addSample([1500, 1050]); // CH2 low
      capture.addSample([1500, 1980]); // CH2 high

      final result = capture.finish();
      final ch1 = result.firstWhere((c) => c.channel == 1);
      final ch2 = result.firstWhere((c) => c.channel == 2);

      expect(ch1.min, 1100);
      expect(ch1.max, 1900);
      expect(ch2.min, 1050);
      expect(ch2.max, 1980);
    });

    test('keeps trim from the resting snapshot, clamped into captured range',
        () {
      final capture = RcEndpointCapture();
      // Start with trim at 1500.
      capture.start([1500]);
      // Sweep up only — min never drops below 1500, so trim==min is valid.
      capture.addSample([2000]);
      final result = capture.finish();
      expect(result.single.trim, 1500);
      expect(result.single.min, 1500);
      expect(result.single.max, 2000);
    });

    test('ignores out-of-range and zero (failsafe) samples', () {
      final capture = RcEndpointCapture();
      capture.start([1500]);
      capture.addSample([0]); // failsafe / unconnected
      capture.addSample([3000]); // impossible
      capture.addSample([1200]); // valid
      final result = capture.finish();
      expect(result.single.min, 1200);
      expect(result.single.max, 1500);
    });

    test('does not seed channels whose starting value is invalid', () {
      final capture = RcEndpointCapture();
      capture.start([1500, 0]); // CH2 unconnected
      // No valid sample for CH2 ever arrives.
      final result = capture.finish();
      expect(result.map((c) => c.channel), [1]);
    });

    test('captureTrim updates centre without disturbing extremes', () {
      final capture = RcEndpointCapture();
      capture.start([1500]);
      capture.addSample([1100]);
      capture.addSample([1900]);
      // Re-centre stick and capture trim.
      capture.captureTrim([1480]);
      final result = capture.finish();
      expect(result.single.min, 1100);
      expect(result.single.max, 1900);
      expect(result.single.trim, 1480);
    });

    test('addSample is a no-op before start', () {
      final capture = RcEndpointCapture();
      capture.addSample([1100, 1900]);
      expect(capture.observedChannels, isEmpty);
    });

    test('seeds reversal and deadzone forward into the result', () {
      final capture = RcEndpointCapture();
      capture.start([1500]);
      capture.addSample([1100]);
      capture.addSample([1900]);
      final result = capture.finish(
        seedReversed: {1: true},
        seedDeadzone: {1: 30},
      );
      expect(result.single.reversed, isTrue);
      expect(result.single.deadzone, 30);
    });

    test('cancel discards in-progress capture', () {
      final capture = RcEndpointCapture();
      capture.start([1500]);
      capture.addSample([1100]);
      capture.cancel();
      expect(capture.isCapturing, isFalse);
      expect(capture.observedChannels, isEmpty);
    });

    test('respects custom bounds when filtering samples', () {
      final capture = RcEndpointCapture(
        bounds: const RcCalibrationBounds(absoluteMin: 1000, absoluteMax: 2000),
      );
      capture.start([1500]);
      capture.addSample([900]); // below custom floor → ignored
      capture.addSample([1100]);
      final result = capture.finish();
      expect(result.single.min, 1100);
    });
  });

  group('validateCalibration', () {
    RcChannelCalibration cal({
      int channel = 1,
      int min = 1100,
      int max = 1900,
      int trim = 1500,
      bool reversed = false,
      int deadzone = 0,
    }) =>
        RcChannelCalibration(
          channel: channel,
          min: min,
          max: max,
          trim: trim,
          reversed: reversed,
          deadzone: deadzone,
        );

    test('accepts a normal calibration', () {
      expect(validateCalibration([cal()]), isEmpty);
    });

    test('rejects out-of-range PWM', () {
      final issues = validateCalibration([cal(min: 500)]);
      expect(issues, hasLength(1));
      expect(issues.single.channel, 1);
      expect(issues.single.message, contains('out of range'));
    });

    test('rejects max <= min', () {
      final issues = validateCalibration([cal(min: 1900, max: 1100)]);
      expect(issues.single.message, contains('greater than min'));
    });

    test('rejects travel that is too small', () {
      final issues = validateCalibration([cal(min: 1490, max: 1510)]);
      expect(issues.single.message, contains('travel too small'));
    });

    test('rejects trim outside the captured range', () {
      final issues = validateCalibration([cal(trim: 2000)]);
      expect(issues.single.message, contains('trim'));
    });

    test('rejects negative deadzone', () {
      final issues = validateCalibration([cal(deadzone: -5)]);
      expect(issues.single.message, contains('deadzone'));
    });

    test('reports issues across multiple channels', () {
      final issues = validateCalibration([
        cal(channel: 1),
        cal(channel: 2, min: 1490, max: 1510),
        cal(channel: 3, min: 500),
      ]);
      expect(issues.map((i) => i.channel), unorderedEquals([2, 3]));
    });
  });

  group('parameter mapping', () {
    test('channelParams emits the five RCx_* params', () {
      final params = channelParams(const RcChannelCalibration(
        channel: 2,
        min: 1100,
        max: 1900,
        trim: 1500,
        reversed: true,
        deadzone: 20,
      ));
      expect(params, {
        'RC2_MIN': 1100.0,
        'RC2_MAX': 1900.0,
        'RC2_TRIM': 1500.0,
        'RC2_REVERSED': 1.0,
        'RC2_DZ': 20.0,
      });
    });

    test('buildParameterWrites includes RCMAP assignments', () {
      final writes = buildParameterWrites(
        [
          const RcChannelCalibration(
              channel: 1, min: 1100, max: 1900, trim: 1500),
        ],
        {
          RcFunction.roll: 1,
          RcFunction.pitch: 2,
          RcFunction.throttle: 3,
          RcFunction.yaw: null, // unassigned → omitted
        },
      );
      expect(writes['RCMAP_ROLL'], 1.0);
      expect(writes['RCMAP_PITCH'], 2.0);
      expect(writes['RCMAP_THROTTLE'], 3.0);
      expect(writes.containsKey('RCMAP_YAW'), isFalse);
      expect(writes['RC1_MIN'], 1100.0);
    });

    test('readAssignments round-trips RCMAP params', () {
      final assignments = readAssignments({
        'RCMAP_ROLL': 1,
        'RCMAP_PITCH': 2,
        'RCMAP_THROTTLE': 3,
        // RCMAP_YAW missing → null
      });
      expect(assignments[RcFunction.roll], 1);
      expect(assignments[RcFunction.pitch], 2);
      expect(assignments[RcFunction.throttle], 3);
      expect(assignments[RcFunction.yaw], isNull);
    });

    test('readChannelCalibration reconstructs a stored channel', () {
      final cal = readChannelCalibration(4, {
        'RC4_MIN': 1090,
        'RC4_MAX': 1920,
        'RC4_TRIM': 1505,
        'RC4_REVERSED': 1,
        'RC4_DZ': 15,
      });
      expect(cal, isNotNull);
      expect(cal!.min, 1090);
      expect(cal.max, 1920);
      expect(cal.trim, 1505);
      expect(cal.reversed, isTrue);
      expect(cal.deadzone, 15);
    });

    test('readChannelCalibration returns null when min/max absent', () {
      expect(readChannelCalibration(7, const {}), isNull);
    });

    test('readChannelCalibration defaults trim to midpoint when missing', () {
      final cal = readChannelCalibration(1, {
        'RC1_MIN': 1100,
        'RC1_MAX': 1900,
      });
      expect(cal!.trim, 1500);
    });
  });
}
