import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/calibration/airspeed_calibration.dart';

void main() {
  group('AirspeedCalibration param catalogue', () {
    test('exposes the documented airspeed parameter ids', () {
      expect(
        AirspeedCalibration.paramIds,
        containsAll(<String>[
          'ARSPD_ENABLE',
          'ARSPD_TYPE',
          'ARSPD_BUS',
          'ARSPD_PIN',
          'ARSPD_OFFSET',
          'ARSPD_RATIO',
          'ARSPD_AUTOCAL',
        ]),
      );
    });

    test('paramIds matches the descriptor list order with no duplicates', () {
      final ids = AirspeedCalibration.paramIds;
      expect(ids.toSet().length, ids.length, reason: 'no duplicate ids');
      expect(ids, AirspeedCalibration.params.map((p) => p.id).toList());
    });

    test('descriptorFor resolves known ids and rejects unknown', () {
      expect(AirspeedCalibration.descriptorFor('ARSPD_RATIO')?.id,
          'ARSPD_RATIO');
      expect(AirspeedCalibration.descriptorFor('GPS_TYPE'), isNull);
    });
  });

  group('write-mapping: MAV_PARAM_TYPE selection', () {
    test('offset and ratio map to REAL32', () {
      expect(AirspeedCalibration.paramTypeFor('ARSPD_OFFSET'),
          AirspeedCalibration.typeReal32);
      expect(AirspeedCalibration.paramTypeFor('ARSPD_RATIO'),
          AirspeedCalibration.typeReal32);
    });

    test('type/bus/pin/autocal/enable map to UINT8', () {
      for (final id in ['ARSPD_TYPE', 'ARSPD_BUS', 'ARSPD_PIN',
        'ARSPD_AUTOCAL', 'ARSPD_ENABLE']) {
        expect(AirspeedCalibration.paramTypeFor(id),
            AirspeedCalibration.typeUint8,
            reason: '$id should be written as a small integer');
      }
    });
  });

  group('read-mapping: value formatting', () {
    test('enum values render their label', () {
      final type = AirspeedCalibration.descriptorFor('ARSPD_TYPE')!;
      expect(type.format(1), 'I2C-MS4525');
      expect(type.format(2), 'Analog');

      final autocal = AirspeedCalibration.descriptorFor('ARSPD_AUTOCAL')!;
      expect(autocal.format(0), 'Disabled');
      expect(autocal.format(1), 'Enabled');
    });

    test('enum values outside the documented range fall back to the number', () {
      final type = AirspeedCalibration.descriptorFor('ARSPD_TYPE')!;
      expect(type.format(99), '99');
    });

    test('numeric offset is shown to 2dp, ratio to 3dp', () {
      final offset = AirspeedCalibration.descriptorFor('ARSPD_OFFSET')!;
      final ratio = AirspeedCalibration.descriptorFor('ARSPD_RATIO')!;
      expect(offset.format(123.456), '123.46');
      expect(ratio.format(1.9936), '1.994');
    });

    test('enum-vs-number kinds are assigned correctly', () {
      expect(AirspeedCalibration.descriptorFor('ARSPD_OFFSET')!.kind,
          AirspeedFieldKind.number);
      expect(AirspeedCalibration.descriptorFor('ARSPD_RATIO')!.kind,
          AirspeedFieldKind.number);
      expect(AirspeedCalibration.descriptorFor('ARSPD_TYPE')!.kind,
          AirspeedFieldKind.enumeration);
      expect(AirspeedCalibration.descriptorFor('ARSPD_AUTOCAL')!.kind,
          AirspeedFieldKind.enumeration);
    });
  });

  group('change detection', () {
    test('treats float-noise echoes as unchanged', () {
      expect(AirspeedCalibration.isChanged(2.0, 2.0 + 1e-9), isFalse);
    });

    test('treats real edits as changed', () {
      expect(AirspeedCalibration.isChanged(2.0, 2.1), isTrue);
      expect(AirspeedCalibration.isChanged(0.0, 1.0), isTrue);
    });
  });

  group('preflight command constant', () {
    test('uses MAV_CMD_PREFLIGHT_CALIBRATION (241)', () {
      expect(AirspeedCalibration.cmdPreflightCalibration, 241);
    });
  });
}
