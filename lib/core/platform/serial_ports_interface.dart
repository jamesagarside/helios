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
  ///
  /// On native this enumerates OS devices. On web (Web Serial API) it returns
  /// only ports the user has previously granted this origin access to via
  /// [requestPort].
  List<SerialPortInfo> availablePorts();

  /// Whether serial port access is supported on this platform.
  bool get isSupported;

  /// Whether ports must be explicitly granted by a user gesture before they
  /// appear in [availablePorts]. True on web (Web Serial), false on native.
  bool get requiresUserGesture => false;

  /// Prompt the user to grant access to a serial port. Only meaningful where
  /// [requiresUserGesture] is true (web); returns the granted port info, or
  /// null if the user cancelled. Native implementations return null.
  Future<SerialPortInfo?> requestPort() async => null;
}
