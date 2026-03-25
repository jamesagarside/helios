import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/models/connection_state.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';

void main() {
  group('ConnectionConfig', () {
    test('UDP config has correct defaults', () {
      const config = UdpConnectionConfig();
      expect(config.bindAddress, '0.0.0.0');
      expect(config.port, 14550);
    });

    test('TCP config requires host', () {
      const config = TcpConnectionConfig(host: '192.168.1.10');
      expect(config.host, '192.168.1.10');
      expect(config.port, 5760);
    });

    test('Serial config requires port name', () {
      const config = SerialConnectionConfig(portName: '/dev/ttyUSB0');
      expect(config.portName, '/dev/ttyUSB0');
      expect(config.baudRate, 57600);
    });

    test('sealed class works with switch expression', () {
      const ConnectionConfig config = UdpConnectionConfig();
      final label = switch (config) {
        UdpConnectionConfig() => 'UDP',
        TcpConnectionConfig() => 'TCP',
        SerialConnectionConfig() => 'Serial',
      };
      expect(label, 'UDP');
    });
  });

  group('ConnectionStatus', () {
    test('default status is disconnected', () {
      const status = ConnectionStatus();
      expect(status.transportState, TransportState.disconnected);
      expect(status.linkState, LinkState.disconnected);
      expect(status.messagesReceived, 0);
      expect(status.messageRate, 0.0);
    });

    test('copyWith updates correctly', () {
      const status = ConnectionStatus();
      final updated = status.copyWith(
        transportState: TransportState.connected,
        linkState: LinkState.connected,
        messagesReceived: 42,
        messageRate: 125.0,
      );

      expect(updated.transportState, TransportState.connected);
      expect(updated.linkState, LinkState.connected);
      expect(updated.messagesReceived, 42);
      expect(updated.messageRate, 125.0);
    });
  });
}
