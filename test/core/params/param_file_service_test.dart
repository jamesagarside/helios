import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/params/param_file_service.dart';
import 'package:helios_gcs/core/params/parameter_service.dart';

void main() {
  late ParamFileService service;

  setUp(() {
    service = ParamFileService();
  });

  Parameter _param(String id, double value,
      {int type = 6, double? defaultValue}) {
    return Parameter(
      id: id,
      value: value,
      type: type,
      index: 0,
      defaultValue: defaultValue,
    );
  }

  group('ArduPilot format', () {
    test('save produces comma-separated format', () {
      final params = {
        'ARMING_CHECK': _param('ARMING_CHECK', 1),
        'BATT_CAPACITY': _param('BATT_CAPACITY', 3300),
      };
      final output = service.saveArduPilot(params);
      expect(output, contains('ARMING_CHECK,1'));
      expect(output, contains('BATT_CAPACITY,3300'));
    });

    test('save sorts parameters alphabetically', () {
      final params = {
        'Z_PARAM': _param('Z_PARAM', 1),
        'A_PARAM': _param('A_PARAM', 2),
      };
      final output = service.saveArduPilot(params);
      final lines = output.split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines[0], startsWith('A_PARAM'));
      expect(lines[1], startsWith('Z_PARAM'));
    });

    test('load parses comma-separated format', () {
      const content = 'ARMING_CHECK,1\nBATT_CAPACITY,3300\nWPNAV_SPEED,500.5\n';
      final result = service.load(content);
      expect(result.length, equals(3));
      expect(result['ARMING_CHECK'], equals(1));
      expect(result['BATT_CAPACITY'], equals(3300));
      expect(result['WPNAV_SPEED'], closeTo(500.5, 0.01));
    });

    test('load skips comments and blank lines', () {
      const content = '# Comment\nARMING_CHECK,1\n\n# Another\nBATT_CAPACITY,3300\n';
      final result = service.load(content);
      expect(result.length, equals(2));
    });

    test('save and load round-trips', () {
      final params = {
        'ARMING_CHECK': _param('ARMING_CHECK', 1),
        'BATT_CAPACITY': _param('BATT_CAPACITY', 3300),
        'WPNAV_SPEED': _param('WPNAV_SPEED', 500.5, type: 9),
      };
      final output = service.saveArduPilot(params);
      final result = service.load(output);
      expect(result['ARMING_CHECK'], equals(1));
      expect(result['BATT_CAPACITY'], equals(3300));
      expect(result['WPNAV_SPEED'], closeTo(500.5, 0.01));
    });
  });

  group('QGC format', () {
    test('save produces QGC format with header', () {
      final params = {
        'ARMING_CHECK': _param('ARMING_CHECK', 1),
      };
      final output = service.saveQgc(params);
      expect(output, contains('ARMING_CHECK'));
      expect(output, contains('# Helios GCS'));
    });

    test('load detects and parses QGC format', () {
      const content =
          '# Helios GCS\n# Vehicle: 1\n\n1\t1\tARMING_CHECK\t1\t6\n1\t1\tBATT_CAPACITY\t3300\t6\n';
      final result = service.load(content);
      expect(result.length, equals(2));
      expect(result['ARMING_CHECK'], equals(1));
      expect(result['BATT_CAPACITY'], equals(3300));
    });
  });

  group('saveModifiedOnly', () {
    test('excludes params at default values', () {
      final params = {
        'ARMING_CHECK': _param('ARMING_CHECK', 1, defaultValue: 1),
        'BATT_CAPACITY': _param('BATT_CAPACITY', 3300, defaultValue: 4000),
      };
      final output = service.saveModifiedOnly(params);
      expect(output, isNot(contains('ARMING_CHECK')));
      expect(output, contains('BATT_CAPACITY'));
    });

    test('includes params with no known default', () {
      final params = {
        'CUSTOM_PARAM': _param('CUSTOM_PARAM', 42),
      };
      final output = service.saveModifiedOnly(params);
      expect(output, contains('CUSTOM_PARAM'));
    });
  });

  group('compare', () {
    test('detects changed parameters', () {
      final old = {'ARMING_CHECK': 1.0, 'BATT_CAPACITY': 3300.0};
      final now = {'ARMING_CHECK': 0.0, 'BATT_CAPACITY': 3300.0};
      final diff = service.compare(old, now);
      expect(diff.changed.length, equals(1));
      expect(diff.changed['ARMING_CHECK'], equals((1.0, 0.0)));
      expect(diff.added, isEmpty);
      expect(diff.removed, isEmpty);
    });

    test('detects added parameters', () {
      final old = {'ARMING_CHECK': 1.0};
      final now = {'ARMING_CHECK': 1.0, 'NEW_PARAM': 42.0};
      final diff = service.compare(old, now);
      expect(diff.changed, isEmpty);
      expect(diff.added.length, equals(1));
      expect(diff.added['NEW_PARAM'], equals(42.0));
    });

    test('detects removed parameters', () {
      final old = {'ARMING_CHECK': 1.0, 'OLD_PARAM': 99.0};
      final now = {'ARMING_CHECK': 1.0};
      final diff = service.compare(old, now);
      expect(diff.removed.length, equals(1));
      expect(diff.removed['OLD_PARAM'], equals(99.0));
    });

    test('isEmpty returns true when no changes', () {
      final old = {'A': 1.0, 'B': 2.0};
      final now = {'A': 1.0, 'B': 2.0};
      final diff = service.compare(old, now);
      expect(diff.isEmpty, isTrue);
      expect(diff.totalChanges, equals(0));
    });

    test('compareWithCache works with Parameter objects', () {
      final cache = {
        'ARMING_CHECK': _param('ARMING_CHECK', 1),
        'BATT_CAPACITY': _param('BATT_CAPACITY', 3300),
      };
      final fileParams = {'ARMING_CHECK': 0.0, 'BATT_CAPACITY': 3300.0};
      final diff = service.compareWithCache(cache, fileParams);
      expect(diff.changed.length, equals(1));
      expect(diff.changed.containsKey('ARMING_CHECK'), isTrue);
    });
  });
}
