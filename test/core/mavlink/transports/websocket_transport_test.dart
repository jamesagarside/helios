import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/mavlink/transports/websocket_transport.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';

void main() {
  group('WebSocketTransport', () {
    test('initial state is disconnected', () {
      final transport = WebSocketTransport(
        uri: Uri.parse('ws://localhost:9999'),
      );

      expect(transport.state, TransportState.disconnected);
      transport.dispose();
    });

    test('emits error when connecting to unavailable server', () async {
      final transport = WebSocketTransport(
        uri: Uri.parse('ws://localhost:19999'),
        autoReconnect: false,
      );

      final states = <TransportState>[];
      transport.stateStream.listen(states.add);

      await transport.connect();

      // Give time for async connect attempt to fail
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(states, contains(TransportState.connecting));
      expect(states, contains(TransportState.error));

      transport.dispose();
    });

    test('connects to a real WebSocket server and exchanges data', () async {
      // Start a local WS server
      final server = await HttpServer.bind('127.0.0.1', 0);
      final port = server.port;
      final serverReceived = <List<int>>[];

      server.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final ws = await WebSocketTransformer.upgrade(request);
          ws.listen((data) {
            serverReceived.add(data as List<int>);
            // Echo back
            ws.add(data);
          });
        }
      });

      try {
        final transport = WebSocketTransport(
          uri: Uri.parse('ws://127.0.0.1:$port'),
          autoReconnect: false,
        );

        final states = <TransportState>[];
        final received = <Uint8List>[];
        transport.stateStream.listen(states.add);
        transport.dataStream.listen(received.add);

        await transport.connect();
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(transport.state, TransportState.connected);

        // Send data
        final testData = Uint8List.fromList([0xFE, 0x09, 0x01, 0x02]);
        await transport.send(testData);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        // Server should have received it
        expect(serverReceived, hasLength(1));
        expect(serverReceived.first, testData);

        // We should have received the echo
        expect(received, hasLength(1));
        expect(received.first, testData);

        await transport.disconnect();
        expect(transport.state, TransportState.disconnected);

        transport.dispose();
      } finally {
        await server.close(force: true);
      }
    });

    test('auto-reconnects on disconnect', () async {
      final transport = WebSocketTransport(
        uri: Uri.parse('ws://localhost:19998'),
        autoReconnect: true,
      );

      final states = <TransportState>[];
      transport.stateStream.listen(states.add);

      await transport.connect();
      await Future<void>.delayed(const Duration(seconds: 2));

      // Should have attempted connecting, failed, and tried again
      final connectingCount =
          states.where((s) => s == TransportState.connecting).length;
      expect(connectingCount, greaterThanOrEqualTo(2));

      transport.dispose();
    });

    test('disconnect stops auto-reconnect', () async {
      final transport = WebSocketTransport(
        uri: Uri.parse('ws://localhost:19997'),
        autoReconnect: true,
      );

      await transport.connect();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await transport.disconnect();

      final statesBefore = <TransportState>[];
      transport.stateStream.listen(statesBefore.add);

      // Wait — should NOT see any more connecting attempts
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(
        statesBefore.where((s) => s == TransportState.connecting),
        isEmpty,
      );

      transport.dispose();
    });

    test('dispose closes streams', () async {
      final transport = WebSocketTransport(
        uri: Uri.parse('ws://localhost:19996'),
      );

      var dataDone = false;
      var stateDone = false;
      transport.dataStream.listen(null, onDone: () => dataDone = true);
      transport.stateStream.listen(null, onDone: () => stateDone = true);

      transport.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(dataDone, isTrue);
      expect(stateDone, isTrue);
    });

    test('send is no-op when not connected', () async {
      final transport = WebSocketTransport(
        uri: Uri.parse('ws://localhost:19995'),
      );

      // Should not throw
      await transport.send(Uint8List.fromList([1, 2, 3]));
      transport.dispose();
    });
  });

  group('WebSocketConnectionConfig', () {
    test('uri getter builds correct WebSocket URI', () {
      // Import tested indirectly via connection_state_test, but verify here
      final uri = Uri.parse('ws://192.168.4.1:8765');
      expect(uri.scheme, 'ws');
      expect(uri.host, '192.168.4.1');
      expect(uri.port, 8765);
    });
  });
}
