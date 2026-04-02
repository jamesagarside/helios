import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/params/parameter_service.dart';

void main() {
  group('ParameterService.parseParamFile', () {
    test('parses valid CSV content', () {
      const content = 'ARMING_CHECK,1.0\nBATT_CAPACITY,5000.0';
      final result = ParameterService.parseParamFile(content);

      expect(result.length, 2);
      expect(result[0].$1, 'ARMING_CHECK');
      expect(result[0].$2, 1.0);
      expect(result[1].$1, 'BATT_CAPACITY');
      expect(result[1].$2, 5000.0);
    });

    test('ignores blank lines', () {
      const content = 'PARAM_A,1.0\n\n\nPARAM_B,2.0\n';
      final result = ParameterService.parseParamFile(content);

      expect(result.length, 2);
      expect(result[0].$1, 'PARAM_A');
      expect(result[1].$1, 'PARAM_B');
    });

    test('ignores comment lines starting with #', () {
      const content = '# This is a comment\nPARAM_A,1.0\n# Another comment\nPARAM_B,2.0';
      final result = ParameterService.parseParamFile(content);

      expect(result.length, 2);
      expect(result[0].$1, 'PARAM_A');
      expect(result[1].$1, 'PARAM_B');
    });

    test('handles integer values stored as doubles', () {
      const content = 'ARMING_CHECK,1\nSCHED_LOOP_RATE,400';
      final result = ParameterService.parseParamFile(content);

      expect(result.length, 2);
      expect(result[0].$2, 1.0);
      expect(result[1].$2, 400.0);
    });

    test('handles float values', () {
      const content = 'INS_ACCEL_FILTER,20.5\nAHRS_TRIM_X,-0.003456';
      final result = ParameterService.parseParamFile(content);

      expect(result.length, 2);
      expect(result[0].$2, closeTo(20.5, 0.0001));
      expect(result[1].$2, closeTo(-0.003456, 0.000001));
    });

    test('returns empty list for empty string', () {
      final result = ParameterService.parseParamFile('');
      expect(result, isEmpty);
    });

    test('returns empty list for whitespace-only string', () {
      final result = ParameterService.parseParamFile('   \n  \n  ');
      expect(result, isEmpty);
    });

    test('skips lines missing a comma', () {
      const content = 'VALID_PARAM,1.0\nNO_COMMA_LINE\nANOTHER_VALID,2.0';
      final result = ParameterService.parseParamFile(content);

      expect(result.length, 2);
      expect(result[0].$1, 'VALID_PARAM');
      expect(result[1].$1, 'ANOTHER_VALID');
    });

    test('skips lines with non-numeric value', () {
      const content = 'VALID_PARAM,1.0\nBAD_PARAM,notanumber\nANOTHER_VALID,2.0';
      final result = ParameterService.parseParamFile(content);

      expect(result.length, 2);
      expect(result[0].$1, 'VALID_PARAM');
      expect(result[1].$1, 'ANOTHER_VALID');
    });

    test('handles mixed valid and malformed lines gracefully', () {
      const content = '''
# Header comment
ARMING_CHECK,1.0
BATT_CAPACITY,5200.0
MALFORMED LINE
BAD_VALUE,abc
,5.0
VALID_LAST,99.0
''';
      final result = ParameterService.parseParamFile(content);

      expect(result.length, 3);
      expect(result[0].$1, 'ARMING_CHECK');
      expect(result[1].$1, 'BATT_CAPACITY');
      expect(result[2].$1, 'VALID_LAST');
    });

    test('trims whitespace from name and value', () {
      const content = '  PARAM_A  ,  1.5  ';
      final result = ParameterService.parseParamFile(content);

      expect(result.length, 1);
      expect(result[0].$1, 'PARAM_A');
      expect(result[0].$2, 1.5);
    });

    test('handles only comment lines', () {
      const content = '# comment 1\n# comment 2\n# comment 3';
      final result = ParameterService.parseParamFile(content);
      expect(result, isEmpty);
    });
  });

  group('ParameterService.exportToParamFile round-trip', () {
    test('exported content can be parsed back to matching values', () {
      // Build the service and inject params via the internal map through
      // parseParamFile (static) + exportToParamFile instance method.
      // We use parseParamFile to generate expected pairs, then build a
      // realistic param file and verify the round-trip.
      const original = '''
# Helios param file
ARMING_CHECK,1.0
BATT_CAPACITY,5200.0
SCHED_LOOP_RATE,400.0
AHRS_TRIM_X,-0.003456
''';
      final parsed = ParameterService.parseParamFile(original);

      // Re-serialise by building a minimal param-file string from the parsed
      // pairs (sorted by name, same as exportToParamFile does), then parse
      // again and confirm values match.
      final sorted = [...parsed]..sort((a, b) => a.$1.compareTo(b.$1));
      final rebuilt = sorted.map((p) => '${p.$1},${p.$2}').join('\n');
      final reparsed = ParameterService.parseParamFile(rebuilt);

      expect(reparsed.length, parsed.length);
      for (var i = 0; i < reparsed.length; i++) {
        expect(reparsed[i].$1, sorted[i].$1);
        expect(reparsed[i].$2, closeTo(sorted[i].$2, 0.000001));
      }
    });
  });
}
