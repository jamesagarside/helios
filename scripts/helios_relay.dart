#!/usr/bin/env dart
/// Helios Relay — WebSocket ↔ TCP bridge for browser-based GCS connections.
///
/// Allows Helios running in a web browser to connect to a flight controller
/// over WiFi/network via TCP, by bridging browser-compatible WebSocket
/// connections to raw TCP.
///
/// Usage:
///   dart run scripts/helios_relay.dart                         # defaults
///   dart run scripts/helios_relay.dart --fc-host 192.168.4.1   # WiFi FC
///   dart run scripts/helios_relay.dart --fc-port 5762          # custom port
///
/// Compile to standalone binary:
///   dart compile exe scripts/helios_relay.dart -o helios-relay
///   ./helios-relay --fc-host 192.168.4.1
///
/// No admin/root access required — runs entirely in user space.
///
/// Architecture:
///   Browser (WS) ←→ [helios-relay :8765] ←→ Flight Controller (TCP :5760)
///
/// Each WebSocket client gets its own TCP connection to the FC.
/// Multiple browser tabs can connect simultaneously.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) async {
  final config = _parseArgs(args);

  print('');
  print('  ╔══════════════════════════════════════════════╗');
  print('  ║           Helios Relay v1.0                  ║');
  print('  ║   WebSocket ↔ TCP bridge for MAVLink         ║');
  print('  ╚══════════════════════════════════════════════╝');
  print('');
  print('  WebSocket : ws://${config.wsHost}:${config.wsPort}');
  print('  TCP target: ${config.fcHost}:${config.fcPort}');
  print('');

  final server = await HttpServer.bind(config.wsHost, config.wsPort);
  print('  [relay] Listening for WebSocket connections...');
  print('  [relay] Open Helios in your browser and select WebSocket connection');
  print('  [relay] Ctrl+C to stop');
  print('');

  var clientId = 0;

  await for (final request in server) {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      clientId++;
      final id = clientId;
      _handleClient(request, id, config);
    } else {
      // Serve a simple status page for non-WS requests
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(_statusPage(config))
        ..close();
    }
  }
}

Future<void> _handleClient(
  HttpRequest request,
  int id,
  _Config config,
) async {
  WebSocket? ws;
  Socket? tcp;

  try {
    ws = await WebSocketTransformer.upgrade(request);
    print('  [client $id] WebSocket connected from ${request.connectionInfo?.remoteAddress.address}');

    // Connect to the flight controller
    tcp = await Socket.connect(config.fcHost, config.fcPort,
        timeout: const Duration(seconds: 5));
    print('  [client $id] TCP connected to ${config.fcHost}:${config.fcPort}');

    var wsBytes = 0;
    var tcpBytes = 0;

    // TCP → WebSocket (FC → Browser)
    final tcpSub = tcp.listen(
      (Uint8List data) {
        tcpBytes += data.length;
        try {
          ws?.add(data);
        } catch (_) {}
      },
      onError: (Object e) {
        print('  [client $id] TCP error: $e');
        ws?.close();
      },
      onDone: () {
        print('  [client $id] TCP disconnected ($tcpBytes bytes received)');
        ws?.close();
      },
    );

    // WebSocket → TCP (Browser → FC)
    ws.listen(
      (dynamic data) {
        if (data is List<int>) {
          wsBytes += data.length;
          tcp?.add(Uint8List.fromList(data));
        }
      },
      onError: (Object e) {
        print('  [client $id] WebSocket error: $e');
        tcp?.destroy();
      },
      onDone: () {
        print('  [client $id] WebSocket disconnected ($wsBytes bytes sent)');
        tcpSub.cancel();
        tcp?.destroy();
      },
    );
  } catch (e) {
    print('  [client $id] Connection failed: $e');
    ws?.close();
    tcp?.destroy();
  }
}

// ─── CLI argument parsing ────────────────────────────────────────────────────

class _Config {
  const _Config({
    required this.wsHost,
    required this.wsPort,
    required this.fcHost,
    required this.fcPort,
  });

  final String wsHost;
  final int wsPort;
  final String fcHost;
  final int fcPort;
}

_Config _parseArgs(List<String> args) {
  var wsHost = '0.0.0.0';
  var wsPort = 8765;
  var fcHost = '127.0.0.1';
  var fcPort = 5760;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--ws-host':
        if (i + 1 < args.length) wsHost = args[++i];
      case '--ws-port':
        if (i + 1 < args.length) wsPort = int.parse(args[++i]);
      case '--fc-host':
        if (i + 1 < args.length) fcHost = args[++i];
      case '--fc-port':
        if (i + 1 < args.length) fcPort = int.parse(args[++i]);
      case '-h' || '--help':
        _printUsage();
    }
  }

  return _Config(wsHost: wsHost, wsPort: wsPort, fcHost: fcHost, fcPort: fcPort);
}

Never _printUsage() {
  print('''
Helios Relay — WebSocket to TCP bridge for MAVLink

Usage: helios-relay [options]

Options:
  --ws-host HOST   WebSocket listen address  (default: 0.0.0.0)
  --ws-port PORT   WebSocket listen port     (default: 8765)
  --fc-host HOST   Flight controller address (default: 127.0.0.1)
  --fc-port PORT   Flight controller port    (default: 5760)
  -h, --help       Show this help

Examples:
  helios-relay                                   # SITL on localhost
  helios-relay --fc-host 192.168.4.1             # WiFi flight controller
  helios-relay --fc-host 10.0.0.5 --fc-port 5762 # Custom address/port

No admin access required. Runs as a regular user process.
''');
  exit(0);
}

// ─── Status page ─────────────────────────────────────────────────────────────

String _statusPage(_Config config) => '''
<!DOCTYPE html>
<html>
<head><title>Helios Relay</title>
<style>
  body { font-family: system-ui; background: #1a1a2e; color: #e0e0e0;
         display: flex; justify-content: center; align-items: center;
         height: 100vh; margin: 0; }
  .card { background: #16213e; padding: 2rem; border-radius: 12px;
          box-shadow: 0 4px 20px rgba(0,0,0,0.3); max-width: 400px; }
  h1 { color: #4fc3f7; margin-top: 0; font-size: 1.4rem; }
  .status { color: #66bb6a; font-weight: bold; }
  code { background: #0a1128; padding: 2px 8px; border-radius: 4px;
         font-size: 0.9rem; }
  p { line-height: 1.6; }
</style></head>
<body>
<div class="card">
  <h1>Helios Relay</h1>
  <p>Status: <span class="status">Running</span></p>
  <p>WebSocket: <code>ws://${config.wsHost}:${config.wsPort}</code></p>
  <p>FC target: <code>${config.fcHost}:${config.fcPort}</code></p>
  <p>Open Helios GCS in your browser and select<br>
     <strong>WebSocket</strong> connection type.</p>
</div>
</body></html>
''';
