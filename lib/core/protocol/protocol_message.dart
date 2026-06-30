import 'package:dart_mavlink/dart_mavlink.dart';

import '../msp/msp_message.dart';

/// A single typed **Protocol message** flowing through the shared seam.
///
/// This sealed wrapper is the one type carried on `ProtocolService.messages`.
/// It has exactly two cases — [MavlinkMsg] and [MspMsg] — so the connection
/// layer dispatches inbound facts with a single *exhaustive* `switch`, the one
/// honest branch the ADR keeps ("one protocol seam" = one exhaustive switch,
/// not zero branching).
///
/// The wrapper deliberately leaves the vendored, generated [MavlinkMessage]
/// untouched: tagging it with a marker interface would mean editing generated
/// code in `packages/dart_mavlink`. Wrapping it here keeps that package pristine
/// while still yielding an exhaustive dispatch. See ADR 0002.
sealed class ProtocolMessage {
  const ProtocolMessage();
}

/// A typed MAVLink fact decoded off the wire.
class MavlinkMsg extends ProtocolMessage {
  const MavlinkMsg(this.message);

  final MavlinkMessage message;
}

/// A typed MSP fact decoded off the wire.
class MspMsg extends ProtocolMessage {
  const MspMsg(this.message);

  final MspMessage message;
}
