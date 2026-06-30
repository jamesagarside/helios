import 'dart:async';
import 'dart:typed_data';

import '../../shared/models/vehicle_state.dart';
import '../link/link_health_monitor.dart';
import '../mavlink/transports/transport.dart';
import '../protocol/protocol_message.dart';
import '../protocol/protocol_service.dart';
import 'msp_codes.dart';
import 'msp_decoder.dart';
import 'msp_frame.dart';
import 'msp_parser.dart';

/// MSP **Protocol adapter** behind the shared seam ([ProtocolService]).
///
/// Wraps a [MavlinkTransport] (raw byte I/O), polls a Betaflight / iNav flight
/// controller, parses inbound frames, and runs each response through the pure
/// [MspDecoder] to produce typed [MspMessage]s. Those are presented inbound as
/// [MspMsg] Protocol messages — State convergence (folding them into
/// `VehicleState`, with the firmware-specific interpretation) happens above the
/// seam in `MspMessageRouter`, not here.
///
/// Polling rates (configurable via the private constants):
/// - Attitude  : 25 Hz  (every 40 ms)
/// - Status    : 10 Hz  (every 100 ms)
/// - GPS       : 5 Hz   (every 200 ms)
/// - Altitude  : 5 Hz   (every 200 ms)
/// - Analog    : 2 Hz   (every 500 ms)
/// - RC        : 10 Hz  (every 100 ms)
///
/// On first connect the adapter requests FC variant and version so convergence
/// learns which firmware is speaking (`MSP_FC_VARIANT`). Polling is the MSP
/// adapter's protocol-specific outbound and is not part of the seam interface.
class MspService implements ProtocolService {
  MspService(this._transport);

  final MavlinkTransport _transport;
  final MspParser _parser = MspParser();

  /// Shared Link-health module, fed by [recordActivity] on every response frame.
  final LinkHealthMonitor _linkMonitor = LinkHealthMonitor();

  final StreamController<ProtocolMessage> _messageController =
      StreamController<ProtocolMessage>.broadcast();

  StreamSubscription<Uint8List>? _dataSub;
  StreamSubscription<TransportState>? _transportStateSub;

  // Polling timers
  Timer? _attitudeTimer;
  Timer? _statusTimer;
  Timer? _gpsTimer;
  Timer? _altitudeTimer;
  Timer? _analogTimer;
  Timer? _rcTimer;

  // Telemetry poll intervals
  static const Duration _attitudeInterval = Duration(milliseconds: 40);
  static const Duration _statusInterval = Duration(milliseconds: 100);
  static const Duration _gpsInterval = Duration(milliseconds: 200);
  static const Duration _altitudeInterval = Duration(milliseconds: 200);
  static const Duration _analogInterval = Duration(milliseconds: 500);
  static const Duration _rcInterval = Duration(milliseconds: 100);

  // ---------------------------------------------------------------------------
  // Statistics
  // ---------------------------------------------------------------------------

  int _messagesReceived = 0;
  int _messagesSent = 0;

  /// Total MSP response frames successfully parsed and processed.
  @override
  int get messagesReceived => _messagesReceived;

  /// Total MSP request frames sent.
  @override
  int get messagesSent => _messagesSent;

  /// Total frames discarded by the parser due to checksum errors.
  @override
  int get parseErrors => _parser.parseErrors;

  // ---------------------------------------------------------------------------
  // ProtocolService seam
  // ---------------------------------------------------------------------------

  /// Stream of typed inbound MSP Protocol messages (wrapped as [MspMsg]).
  @override
  Stream<ProtocolMessage> get messages => _messageController.stream;

  /// Stream of Link-health changes.
  @override
  Stream<LinkState> get linkHealth => _linkMonitor.stateStream;

  /// Current Link health.
  @override
  LinkState get linkState => _linkMonitor.state;

  /// Current transport connection state.
  @override
  TransportState get transportState => _transport.state;

  /// Stream of transport connection-state changes.
  @override
  Stream<TransportState> get transportStateStream => _transport.stateStream;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Connect the transport and start telemetry polling.
  ///
  /// Set [alreadyConnected] to true when the transport has already been
  /// connected externally (e.g. during protocol auto-detection).
  @override
  Future<void> connect({bool alreadyConnected = false}) async {
    if (!alreadyConnected) await _transport.connect();
    _startDataSubscription();
    _startPolling();

    // Identify the FC so convergence knows the firmware (MSP_FC_VARIANT).
    await _sendRequest(MspCodes.fcVariant);
    await _sendRequest(MspCodes.fcVersion);
  }

  /// Stop all polling and disconnect the transport.
  @override
  Future<void> disconnect() async {
    _stopPolling();
    _dataSub?.cancel();
    _dataSub = null;
    _transportStateSub?.cancel();
    _transportStateSub = null;
    await _transport.disconnect();
    _linkMonitor.reset();
  }

  /// Release all resources.  Call instead of [disconnect] only when the
  /// service will not be used again.
  @override
  void dispose() {
    _stopPolling();
    _dataSub?.cancel();
    _transportStateSub?.cancel();
    _messageController.close();
    _linkMonitor.dispose();
    _transport.dispose();
  }

  // ---------------------------------------------------------------------------
  // Transport subscription
  // ---------------------------------------------------------------------------

  void _startDataSubscription() {
    _dataSub = _transport.dataStream.listen(
      _onData,
      onError: (Object error) {
        // Transport errors are surfaced via link-state degradation; no need
        // to re-throw here.
      },
      cancelOnError: false,
    );

    _transportStateSub = _transport.stateStream.listen((state) {
      if (state == TransportState.disconnected ||
          state == TransportState.error) {
        _linkMonitor.reset();
      }
    });
  }

  void _onData(Uint8List data) {
    _parser.feed(data);
    final frames = _parser.takeFrames();
    for (final frame in frames) {
      final message = MspDecoder.decode(frame);
      if (message == null) continue;
      // A decoded response is genuine Link activity — feed the shared monitor.
      _linkMonitor.recordActivity();
      _messagesReceived++;
      _messageController.add(MspMsg(message));
    }
  }

  // ---------------------------------------------------------------------------
  // Polling (MSP-specific outbound — not part of the seam interface)
  // ---------------------------------------------------------------------------

  void _startPolling() {
    _attitudeTimer = Timer.periodic(
        _attitudeInterval, (_) => _sendRequest(MspCodes.attitude));
    _statusTimer =
        Timer.periodic(_statusInterval, (_) => _sendRequest(MspCodes.status));
    _gpsTimer =
        Timer.periodic(_gpsInterval, (_) => _sendRequest(MspCodes.rawGps));
    _altitudeTimer = Timer.periodic(
        _altitudeInterval, (_) => _sendRequest(MspCodes.altitude));
    _analogTimer = Timer.periodic(_analogInterval, (_) {
      _sendRequest(MspCodes.analog);
      _sendRequest(MspCodes.batteryState);
    });
    _rcTimer = Timer.periodic(_rcInterval, (_) => _sendRequest(MspCodes.rc));
  }

  void _stopPolling() {
    _attitudeTimer?.cancel();
    _statusTimer?.cancel();
    _gpsTimer?.cancel();
    _altitudeTimer?.cancel();
    _analogTimer?.cancel();
    _rcTimer?.cancel();
    _attitudeTimer = null;
    _statusTimer = null;
    _gpsTimer = null;
    _altitudeTimer = null;
    _analogTimer = null;
    _rcTimer = null;
  }

  /// Send a zero-payload MSP request frame.
  Future<void> _sendRequest(int code) async {
    try {
      await _transport.send(MspFrame.buildRequest(code));
      _messagesSent++;
    } catch (_) {
      // Transport errors are monitored via link-state; silently swallow here.
    }
  }
}
