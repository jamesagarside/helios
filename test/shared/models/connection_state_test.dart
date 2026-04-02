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

    test('WebSocket config has correct defaults', () {
      const config = WebSocketConnectionConfig(host: 'localhost');
      expect(config.host, 'localhost');
      expect(config.port, 8765);
      expect(config.uri, Uri.parse('ws://localhost:8765'));
    });

    test('WebSocket config builds custom URI', () {
      const config = WebSocketConnectionConfig(
        host: '192.168.4.1',
        port: 9000,
      );
      expect(config.uri.scheme, 'ws');
      expect(config.uri.host, '192.168.4.1');
      expect(config.uri.port, 9000);
    });

    test('WebSocket config supports protocol selection', () {
      const config = WebSocketConnectionConfig(
        host: 'localhost',
        protocol: ProtocolType.msp,
      );
      expect(config.protocol, ProtocolType.msp);
    });

    test('sealed class works with switch expression', () {
      const ConnectionConfig config = UdpConnectionConfig();
      final label = switch (config) {
        UdpConnectionConfig() => 'UDP',
        TcpConnectionConfig() => 'TCP',
        SerialConnectionConfig() => 'Serial',
        WebSocketConnectionConfig() => 'WebSocket',
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
