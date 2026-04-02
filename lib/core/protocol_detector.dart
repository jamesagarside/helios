import 'dart:async';
import 'package:dart_mavlink/dart_mavlink.dart';
import '../shared/models/connection_state.dart';
import 'mavlink/transports/transport.dart';
import 'msp/msp_codes.dart';
import 'msp/msp_frame.dart';
import 'msp/msp_parser.dart';

/// Probes a connected transport to determine whether the remote end speaks
/// MAVLink or MSP.
///
/// Strategy:
///   1. Subscribe to the transport's byte stream.
///   2. Send both a MAVLink GCS heartbeat and an MSP_FC_VARIANT request every
///      500 ms.
///   3. Feed every incoming byte chunk to both parsers simultaneously.
///   4. Complete as soon as either parser produces a valid frame.
///   5. If no valid frame arrives within [timeout], fall back to MAVLink.
///
/// The transport must already be connected before calling [detect].
/// The caller retains ownership of the transport — this class does not
/// disconnect or dispose it.
abstract final class ProtocolDetector {
  static const Duration timeout = Duration(seconds: 5);
  static const Duration _probeInterval = Duration(milliseconds: 500);

  /// Detect the protocol in use on [transport].
  ///
  /// Returns [ProtocolType.mavlink] or [ProtocolType.msp].
  /// Never returns [ProtocolType.auto].
  static Future<ProtocolType> detect(MavlinkTransport transport) async {
    final mavParser = MavlinkParser();
    final mspParser = MspParser();
    final frameBuilder = MavlinkFrameBuilder();

    final completer = Completer<ProtocolType>();

    void complete(ProtocolType p) {
      if (!completer.isCompleted) completer.complete(p);
    }

    final sub = transport.dataStream.listen((bytes) {
      if (completer.isCompleted) return;

      // Try MAVLink
      mavParser.parse(bytes);
      if (mavParser.takeMessages().isNotEmpty) {
        complete(ProtocolType.mavlink);
        return;
      }

      // Try MSP
      mspParser.feed(bytes);
      if (mspParser.takeFrames().isNotEmpty) {
        complete(ProtocolType.msp);
      }
    });

    void probe() {
      if (completer.isCompleted) return;
      try {
        transport.send(frameBuilder.buildHeartbeat());
        transport.send(MspFrame.buildRequest(MspCodes.fcVariant));
      } catch (_) {}
    }

    // Probe immediately then on interval.
    probe();
    final probeTimer = Timer.periodic(_probeInterval, (_) => probe());
    final timeoutTimer = Timer(timeout, () => complete(ProtocolType.mavlink));

    try {
      return await completer.future;
    } finally {
      probeTimer.cancel();
      timeoutTimer.cancel();
      await sub.cancel();
    }
  }
}
