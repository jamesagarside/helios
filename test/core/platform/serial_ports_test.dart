import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/platform/serial_ports.dart';

void main() {
  group('SerialPortService', () {
    test('serialPortService is available', () {
      expect(serialPortService, isNotNull);
    });

    test('isSupported returns true on native', () {
      expect(serialPortService.isSupported, isTrue);
    });

    // Note: availablePorts() requires the native libserialport.dylib which
    // is only bundled inside the app binary, not in the test runner.
    // These tests verify the interface contract; integration testing with
    // real ports happens via the macOS/Linux app build.
  });

  group('SerialPortInfo', () {
    test('constructor sets fields correctly', () {
      const info = SerialPortInfo(
        name: '/dev/ttyUSB0',
        displayName: 'USB Serial (FTDI)',
        manufacturer: 'FTDI',
        vendorId: 0x0403,
        productId: 0x6001,
      );

      expect(info.name, '/dev/ttyUSB0');
      expect(info.displayName, 'USB Serial (FTDI)');
      expect(info.manufacturer, 'FTDI');
      expect(info.vendorId, 0x0403);
      expect(info.productId, 0x6001);
    });

    test('optional fields default to null', () {
      const info = SerialPortInfo(
        name: 'COM3',
        displayName: 'COM3',
      );

      expect(info.manufacturer, isNull);
      expect(info.vendorId, isNull);
      expect(info.productId, isNull);
    });
  });
}
