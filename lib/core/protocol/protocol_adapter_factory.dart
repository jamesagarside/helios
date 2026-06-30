import '../../shared/models/connection_state.dart';
import '../mavlink/mavlink_service.dart';
import '../mavlink/transports/transport.dart';
import '../msp/msp_service.dart';
import 'protocol_service.dart';

/// Constructs the one **Protocol adapter** for a (detected protocol, transport)
/// pair, behind the shared [ProtocolService] seam.
///
/// This is the single construction point the connection layer uses once the
/// protocol is known: `connect()` builds the transport, runs detection if the
/// requested protocol is [ProtocolType.auto], then asks this factory for the
/// matching adapter. After that the wiring (reconnect, stats timer, auto-record)
/// is identical regardless of protocol. See ADR 0002, decision 6.
abstract final class ProtocolAdapterFactory {
  /// Build the adapter for [protocol] over [transport].
  ///
  /// [protocol] must already be resolved to a concrete protocol — pass the
  /// result of detection, never [ProtocolType.auto].
  static ProtocolService create(
    ProtocolType protocol,
    MavlinkTransport transport,
  ) {
    return switch (protocol) {
      ProtocolType.msp => MspService(transport),
      ProtocolType.mavlink => MavlinkService(transport),
      ProtocolType.auto => throw ArgumentError(
          'ProtocolAdapterFactory.create requires a resolved protocol; '
          'detect before calling (got ProtocolType.auto).',
        ),
    };
  }
}
