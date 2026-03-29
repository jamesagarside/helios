import 'package:equatable/equatable.dart';
import 'vehicle_state.dart';

/// Wire protocol spoken over the transport.
enum ProtocolType {
  /// Auto-detect by probing both MAVLink and MSP simultaneously.
  /// Whichever produces a valid frame first wins (5s timeout → MAVLink).
  auto,

  /// MAVLink v2 — ArduPilot, PX4, iNav (with MAVLink enabled).
  mavlink,

  /// MSP (MultiWii Serial Protocol) — Betaflight, iNav.
  msp,
}

/// Connection configuration — sealed class for transport types.
sealed class ConnectionConfig extends Equatable {
  const ConnectionConfig({this.protocol = ProtocolType.mavlink});

  /// Wire protocol to use on this connection.
  final ProtocolType protocol;
}

class UdpConnectionConfig extends ConnectionConfig {
  const UdpConnectionConfig({
    this.bindAddress = '0.0.0.0',
    this.port = 14550,
    super.protocol,
  });

  final String bindAddress;
  final int port;

  @override
  List<Object?> get props => [bindAddress, port, protocol];
}

class TcpConnectionConfig extends ConnectionConfig {
  const TcpConnectionConfig({
    required this.host,
    this.port = 5760,
    super.protocol,
  });

  final String host;
  final int port;

  @override
  List<Object?> get props => [host, port, protocol];
}

class SerialConnectionConfig extends ConnectionConfig {
  const SerialConnectionConfig({
    required this.portName,
    this.baudRate = 57600,
    super.protocol,
  });

  final String portName;
  final int baudRate;

  @override
  List<Object?> get props => [portName, baudRate, protocol];
}

/// Live connection status.
class ConnectionStatus extends Equatable {
  const ConnectionStatus({
    this.transportState = TransportState.disconnected,
    this.linkState = LinkState.disconnected,
    this.activeConfig,
    this.connectedSince,
    this.messagesReceived = 0,
    this.messagesSent = 0,
    this.messageRate = 0.0,
  });

  final TransportState transportState;
  final LinkState linkState;
  final ConnectionConfig? activeConfig;
  final DateTime? connectedSince;
  final int messagesReceived;
  final int messagesSent;
  final double messageRate;

  ConnectionStatus copyWith({
    TransportState? transportState,
    LinkState? linkState,
    ConnectionConfig? activeConfig,
    DateTime? connectedSince,
    int? messagesReceived,
    int? messagesSent,
    double? messageRate,
  }) {
    return ConnectionStatus(
      transportState: transportState ?? this.transportState,
      linkState: linkState ?? this.linkState,
      activeConfig: activeConfig ?? this.activeConfig,
      connectedSince: connectedSince ?? this.connectedSince,
      messagesReceived: messagesReceived ?? this.messagesReceived,
      messagesSent: messagesSent ?? this.messagesSent,
      messageRate: messageRate ?? this.messageRate,
    );
  }

  @override
  List<Object?> get props => [
        transportState, linkState, activeConfig,
        connectedSince, messagesReceived, messagesSent, messageRate,
      ];
}
