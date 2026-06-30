/// Severity levels for alert entries shown in the alert history / status bar.
enum AlertSeverity {
  info,
  warning,
  critical;

  /// Single source of truth mapping a MAVLink `STATUSTEXT.severity` byte to an
  /// [AlertSeverity] for the alert history.
  ///
  /// MAVLink severities follow the syslog scale (MAV_SEVERITY):
  ///   0 EMERGENCY, 1 ALERT, 2 CRITICAL, 3 ERROR → critical
  ///   4 WARNING, 5 NOTICE                       → warning
  ///   6 INFO, 7 DEBUG, anything else            → info
  static AlertSeverity fromStatusTextSeverity(int severity) {
    return switch (severity) {
      0 || 1 || 2 => AlertSeverity.critical,
      3 => AlertSeverity.critical,
      4 => AlertSeverity.warning,
      5 => AlertSeverity.warning,
      _ => AlertSeverity.info,
    };
  }

  /// Severity used for the MAVLink Inspector's per-packet display hint.
  ///
  /// This differs from [fromStatusTextSeverity] at severity 5 (NOTICE): the
  /// inspector treats NOTICE as [info] whereas the alert history treats it as
  /// [warning]. The inspector value is a colour hint for the raw packet list,
  /// not an alert-history classification, so the two are intentionally distinct.
  static AlertSeverity inspectorHintFromStatusTextSeverity(int severity) {
    return switch (severity) {
      0 || 1 || 2 || 3 => AlertSeverity.critical,
      4 => AlertSeverity.warning,
      _ => AlertSeverity.info,
    };
  }
}

/// A single alert entry from STATUSTEXT or internal state changes.
class AlertEntry {
  const AlertEntry({
    required this.message,
    required this.severity,
    required this.timestamp,
  });

  final String message;
  final AlertSeverity severity;
  final DateTime timestamp;
}
