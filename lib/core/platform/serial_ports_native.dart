import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'serial_ports_interface.dart';

/// Native serial port service backed by libserialport.
final SerialPortService serialPortService = _NativeSerialPortService();

class _NativeSerialPortService implements SerialPortService {
  @override
  List<SerialPortInfo> availablePorts() {
    return SerialPort.availablePorts.map((portName) {
      try {
        final port = SerialPort(portName);
        final info = SerialPortInfo(
          name: portName,
          displayName: _buildDisplayName(port),
          manufacturer: port.manufacturer,
          vendorId: port.vendorId,
          productId: port.productId,
        );
        port.dispose();
        return info;
      } catch (_) {
        return SerialPortInfo(name: portName, displayName: portName);
      }
    }).toList();
  }

  @override
  bool get isSupported => true;

  String _buildDisplayName(SerialPort port) {
    final desc = port.description ?? port.name ?? '';
    final manufacturer = port.manufacturer;
    if (manufacturer != null && manufacturer.isNotEmpty) {
      return '$desc ($manufacturer)';
    }
    return desc;
  }
}
