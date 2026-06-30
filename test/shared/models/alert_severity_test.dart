import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/models/alert_severity.dart';

void main() {
  group('AlertSeverity.fromStatusTextSeverity (alert history mapping)', () {
    test('EMERGENCY/ALERT/CRITICAL/ERROR (0-3) map to critical', () {
      for (final s in [0, 1, 2, 3]) {
        expect(AlertSeverity.fromStatusTextSeverity(s), AlertSeverity.critical,
            reason: 'severity $s');
      }
    });

    test('WARNING (4) and NOTICE (5) map to warning', () {
      expect(AlertSeverity.fromStatusTextSeverity(4), AlertSeverity.warning);
      expect(AlertSeverity.fromStatusTextSeverity(5), AlertSeverity.warning);
    });

    test('INFO (6), DEBUG (7) and out-of-range map to info', () {
      for (final s in [6, 7, 8, 255, -1]) {
        expect(AlertSeverity.fromStatusTextSeverity(s), AlertSeverity.info,
            reason: 'severity $s');
      }
    });
  });

  group('AlertSeverity.inspectorHintFromStatusTextSeverity', () {
    test('0-3 map to critical', () {
      for (final s in [0, 1, 2, 3]) {
        expect(AlertSeverity.inspectorHintFromStatusTextSeverity(s),
            AlertSeverity.critical,
            reason: 'severity $s');
      }
    });

    test('4 maps to warning', () {
      expect(AlertSeverity.inspectorHintFromStatusTextSeverity(4),
          AlertSeverity.warning);
    });

    test('5 (NOTICE) maps to info — differs from alert-history mapping', () {
      // The inspector treats NOTICE as info; the alert history treats it as
      // warning. This divergence is intentional and pinned by this test.
      expect(AlertSeverity.inspectorHintFromStatusTextSeverity(5),
          AlertSeverity.info);
      expect(AlertSeverity.fromStatusTextSeverity(5), AlertSeverity.warning);
    });

    test('6+ map to info', () {
      for (final s in [6, 7, 255]) {
        expect(AlertSeverity.inspectorHintFromStatusTextSeverity(s),
            AlertSeverity.info,
            reason: 'severity $s');
      }
    });
  });

  group('AlertEntry', () {
    test('stores fields', () {
      final ts = DateTime(2024, 1, 1);
      final entry = AlertEntry(
        message: 'PreArm: GPS',
        severity: AlertSeverity.critical,
        timestamp: ts,
      );
      expect(entry.message, 'PreArm: GPS');
      expect(entry.severity, AlertSeverity.critical);
      expect(entry.timestamp, ts);
    });
  });
}
