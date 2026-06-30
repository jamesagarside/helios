import '../../shared/models/vehicle_state.dart';
import 'protocol_message.dart';

/// The unified protocol seam: one **Protocol adapter** behind a single inbound
/// interface (see ADR 0002 and the *Protocol adapter* entry in `CONTEXT.md`).
///
/// MAVLink and MSP each implement this. The seam guarantees **inbound +
/// lifecycle + link health + stats** only:
///
/// - one [messages] stream of typed [ProtocolMessage]s,
/// - one [linkHealth] stream (computed identically for every protocol),
/// - transport-state passthrough,
/// - [connect] / [disconnect] / [dispose] lifecycle,
/// - read-only [messagesReceived] / [messagesSent] / [parseErrors] stats.
///
/// **Outbound stays protocol-specific** and is deliberately *not* part of this
/// interface — MAVLink command/mission/param/calibration and MSP polling have
/// genuinely different shapes (YAGNI). Callers reach outbound behaviour through
/// the concrete adapter (e.g. the MAVLink adapter's `sendCommand`).
abstract interface class ProtocolService {
  /// Stream of typed inbound Protocol messages.
  Stream<ProtocolMessage> get messages;

  /// Stream of Link-health changes (connected / degraded / lost).
  Stream<LinkState> get linkHealth;

  /// Current Link health.
  LinkState get linkState;

  /// Current transport connection state.
  TransportState get transportState;

  /// Stream of transport connection-state changes.
  Stream<TransportState> get transportStateStream;

  /// Total inbound Protocol messages processed.
  int get messagesReceived;

  /// Total frames/messages sent to the vehicle.
  int get messagesSent;

  /// Total inbound frames discarded due to parse/checksum errors.
  int get parseErrors;

  /// Connect the transport and start message processing.
  ///
  /// Set [alreadyConnected] when the transport was connected externally (e.g.
  /// during protocol auto-detection) so it is not re-connected.
  Future<void> connect({bool alreadyConnected});

  /// Disconnect and stop all processing.
  Future<void> disconnect();

  /// Release all resources.
  void dispose();
}
