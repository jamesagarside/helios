import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/connection_state.dart';

/// Persists the last-used connection settings for quick reconnect.
class ConnectionSettingsNotifier extends StateNotifier<ConnectionConfig?> {
  ConnectionSettingsNotifier() : super(null) {
    _load();
  }

  static const _keyType = 'conn_type';
  static const _keyHost = 'conn_host';
  static const _keyPort = 'conn_port';
  static const _keyBaud = 'conn_baud';
  static const _keySerialPort = 'conn_serial_port';
  static const _keyProtocol = 'conn_protocol';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final type = prefs.getString(_keyType);
    if (type == null) return;

    final protocol = _parseProtocol(prefs.getString(_keyProtocol));

    switch (type) {
      case 'udp':
        state = UdpConnectionConfig(
          bindAddress: prefs.getString(_keyHost) ?? '0.0.0.0',
          port: prefs.getInt(_keyPort) ?? 14550,
          protocol: protocol,
        );
      case 'tcp':
        state = TcpConnectionConfig(
          host: prefs.getString(_keyHost) ?? '127.0.0.1',
          port: prefs.getInt(_keyPort) ?? 5760,
          protocol: protocol,
        );
      case 'serial':
        final portName = prefs.getString(_keySerialPort);
        if (portName != null) {
          state = SerialConnectionConfig(
            portName: portName,
            baudRate: prefs.getInt(_keyBaud) ?? 115200,
            protocol: protocol,
          );
        }
      case 'websocket':
        state = WebSocketConnectionConfig(
          host: prefs.getString(_keyHost) ?? 'localhost',
          port: prefs.getInt(_keyPort) ?? 8765,
          protocol: protocol,
        );
    }
  }

  Future<void> save(ConnectionConfig config) async {
    state = config;
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_keyProtocol, config.protocol.name);

    switch (config) {
      case UdpConnectionConfig(:final bindAddress, :final port):
        await prefs.setString(_keyType, 'udp');
        await prefs.setString(_keyHost, bindAddress);
        await prefs.setInt(_keyPort, port);
      case TcpConnectionConfig(:final host, :final port):
        await prefs.setString(_keyType, 'tcp');
        await prefs.setString(_keyHost, host);
        await prefs.setInt(_keyPort, port);
      case SerialConnectionConfig(:final portName, :final baudRate):
        await prefs.setString(_keyType, 'serial');
        await prefs.setString(_keySerialPort, portName);
        await prefs.setInt(_keyBaud, baudRate);
      case WebSocketConnectionConfig(:final host, :final port):
        await prefs.setString(_keyType, 'websocket');
        await prefs.setString(_keyHost, host);
        await prefs.setInt(_keyPort, port);
    }
  }

  /// Parse a stored protocol string, defaulting to [ProtocolType.auto].
  static ProtocolType _parseProtocol(String? value) =>
      ProtocolType.values.firstWhere(
        (p) => p.name == value,
        orElse: () => ProtocolType.auto,
      );

  String get label {
    final config = state;
    if (config == null) return '';
    return switch (config) {
      UdpConnectionConfig(:final bindAddress, :final port) =>
        'UDP $bindAddress:$port',
      TcpConnectionConfig(:final host, :final port) =>
        'TCP $host:$port',
      SerialConnectionConfig(:final portName, :final baudRate) =>
        'Serial $portName @ $baudRate',
      WebSocketConnectionConfig(:final host, :final port) =>
        'WS $host:$port',
    };
  }
}

final connectionSettingsProvider =
    StateNotifierProvider<ConnectionSettingsNotifier, ConnectionConfig?>(
  (ref) => ConnectionSettingsNotifier(),
);
