/// Describes a serial port available on the system.
class SerialPortInfo {
  const SerialPortInfo({
    required this.name,
    required this.displayName,
    this.manufacturer,
    this.vendorId,
    this.productId,
  });

  /// System-level port identifier (e.g. '/dev/tty.usbmodem1', 'COM3').
  final String name;

  /// Human-readable display name.
  final String displayName;

  /// USB manufacturer string, if available.
  final String? manufacturer;

  /// USB vendor ID, if available.
  final int? vendorId;

  /// USB product ID, if available.
  final int? productId;
}

/// Abstract interface for serial port discovery.
///
/// Platform implementations provide concrete listings. The [serialPortService]
/// top-level getter is defined in the platform-specific files.
abstract class SerialPortService {
  /// List all serial ports currently visible on the system.
  List<SerialPortInfo> availablePorts();

  /// Whether serial port access is supported on this platform.
  bool get isSupported;
}
