import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../../shared/models/vehicle_state.dart';
import '../mavlink/transports/transport.dart';
import 'msp_codes.dart';
import 'msp_frame.dart';
import 'msp_parser.dart';

/// Polling service for MSP (MultiWii Serial Protocol) flight controllers.
///
/// Wraps a [MavlinkTransport] (which provides raw byte I/O) and converts
/// incoming MSP frames into a stream of [VehicleState] snapshots.
///
/// Polling rates (configurable via the private constants):
/// - Attitude  : 25 Hz  (every 40 ms)
/// - Status    : 10 Hz  (every 100 ms)
/// - GPS       : 5 Hz   (every 200 ms)
/// - Analog    : 2 Hz   (every 500 ms)
/// - RC        : 10 Hz  (every 100 ms)
///
/// On first connect the service also requests FC variant and version.
class MspService {
  MspService(this._transport);

  final MavlinkTransport _transport;
  final MspParser _parser = MspParser();

  // Current immutable state — mutated via copyWith on each decoded frame.
  VehicleState _state = const VehicleState();

  final StreamController<VehicleState> _stateController =
      StreamController<VehicleState>.broadcast();

  final StreamController<LinkState> _linkController =
      StreamController<LinkState>.broadcast();

  LinkState _linkState = LinkState.disconnected;
  DateTime? _lastResponseTime;

  StreamSubscription<Uint8List>? _dataSub;
  StreamSubscription<TransportState>? _transportStateSub;

  // Polling timers
  Timer? _attitudeTimer;
  Timer? _statusTimer;
  Timer? _gpsTimer;
  Timer? _altitudeTimer;
  Timer? _analogTimer;
  Timer? _rcTimer;
  Timer? _linkCheckTimer;

  // Telemetry poll intervals
  static const Duration _attitudeInterval = Duration(milliseconds: 40);
  static const Duration _statusInterval = Duration(milliseconds: 100);
  static const Duration _gpsInterval = Duration(milliseconds: 200);
  static const Duration _altitudeInterval = Duration(milliseconds: 200);
  static const Duration _analogInterval = Duration(milliseconds: 500);
  static const Duration _rcInterval = Duration(milliseconds: 100);
  static const Duration _linkCheckInterval = Duration(seconds: 1);

  // Link-health thresholds
  static const Duration _degradedThreshold = Duration(seconds: 2);
  static const Duration _lostThreshold = Duration(seconds: 5);

  // ---------------------------------------------------------------------------
  // Statistics
  // ---------------------------------------------------------------------------

  int _messagesReceived = 0;
  int _messagesSent = 0;

  /// Total MSP response frames successfully parsed and processed.
  int get messagesReceived => _messagesReceived;

  /// Total MSP request frames sent.
  int get messagesSent => _messagesSent;

  /// Total frames discarded by the parser due to checksum errors.
  int get parseErrors => _parser.parseErrors;

  // ---------------------------------------------------------------------------
  // Public streams / state
  // ---------------------------------------------------------------------------

  /// Stream of vehicle state snapshots; emits after each decoded frame.
  Stream<VehicleState> get vehicleStateStream => _stateController.stream;

  /// Stream of link-health state changes.
  Stream<LinkState> get linkStateStream => _linkController.stream;

  /// Current transport connection state.
  TransportState get transportState => _transport.state;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Connect the transport and start telemetry polling.
  ///
  /// Set [alreadyConnected] to true when the transport has already been
  /// connected externally (e.g. during protocol auto-detection).
  Future<void> connect({bool alreadyConnected = false}) async {
    if (!alreadyConnected) await _transport.connect();
    _startDataSubscription();
    _startPolling();
    _startLinkCheck();

    // Identify the FC.
    await _sendRequest(MspCodes.fcVariant);
    await _sendRequest(MspCodes.fcVersion);
  }

  /// Stop all polling and disconnect the transport.
  Future<void> disconnect() async {
    _stopPolling();
    _dataSub?.cancel();
    _dataSub = null;
    _transportStateSub?.cancel();
    _transportStateSub = null;
    await _transport.disconnect();
    _updateLinkState(LinkState.disconnected);
  }

  /// Release all resources.  Call instead of [disconnect] only when the
  /// service will not be used again.
  void dispose() {
    _stopPolling();
    _dataSub?.cancel();
    _transportStateSub?.cancel();
    _stateController.close();
    _linkController.close();
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
        _updateLinkState(LinkState.disconnected);
      }
    });
  }

  void _onData(Uint8List data) {
    _parser.feed(data);
    final frames = _parser.takeFrames();
    if (frames.isNotEmpty) {
      _lastResponseTime = DateTime.now();
      if (_linkState == LinkState.disconnected ||
          _linkState == LinkState.lost ||
          _linkState == LinkState.degraded) {
        _updateLinkState(LinkState.connected);
      }
      for (final frame in frames) {
        _messagesReceived++;
        _processFrame(frame);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Polling
  // ---------------------------------------------------------------------------

  void _startPolling() {
    _attitudeTimer =
        Timer.periodic(_attitudeInterval, (_) => _sendRequest(MspCodes.attitude));
    _statusTimer =
        Timer.periodic(_statusInterval, (_) => _sendRequest(MspCodes.status));
    _gpsTimer =
        Timer.periodic(_gpsInterval, (_) => _sendRequest(MspCodes.rawGps));
    _altitudeTimer =
        Timer.periodic(_altitudeInterval, (_) => _sendRequest(MspCodes.altitude));
    _analogTimer =
        Timer.periodic(_analogInterval, (_) {
          _sendRequest(MspCodes.analog);
          _sendRequest(MspCodes.batteryState);
        });
    _rcTimer =
        Timer.periodic(_rcInterval, (_) => _sendRequest(MspCodes.rc));
  }

  void _stopPolling() {
    _attitudeTimer?.cancel();
    _statusTimer?.cancel();
    _gpsTimer?.cancel();
    _altitudeTimer?.cancel();
    _analogTimer?.cancel();
    _rcTimer?.cancel();
    _linkCheckTimer?.cancel();
    _attitudeTimer = null;
    _statusTimer = null;
    _gpsTimer = null;
    _altitudeTimer = null;
    _analogTimer = null;
    _rcTimer = null;
    _linkCheckTimer = null;
  }

  void _startLinkCheck() {
    _linkCheckTimer = Timer.periodic(_linkCheckInterval, (_) {
      if (_linkState == LinkState.disconnected) return;
      final last = _lastResponseTime;
      if (last == null) return;

      final elapsed = DateTime.now().difference(last);
      if (elapsed >= _lostThreshold) {
        _updateLinkState(LinkState.lost);
      } else if (elapsed >= _degradedThreshold) {
        _updateLinkState(LinkState.degraded);
      } else {
        _updateLinkState(LinkState.connected);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Frame dispatch
  // ---------------------------------------------------------------------------

  void _processFrame(MspFrame frame) {
    // Only decode responses; ignore echo-backs of our own requests.
    if (frame.direction != MspDirection.response) return;

    switch (frame.code) {
      case MspCodes.fcVariant:
        _decodeFcVariant(frame.payload);
      case MspCodes.fcVersion:
        _decodeFcVersion(frame.payload);
      case MspCodes.status:
      case MspCodes.statusEx:
        _decodeStatus(frame.payload);
      case MspCodes.attitude:
        _decodeAttitude(frame.payload);
      case MspCodes.rawGps:
        _decodeRawGps(frame.payload);
      case MspCodes.altitude:
        _decodeAltitude(frame.payload);
      case MspCodes.analog:
        _decodeAnalog(frame.payload);
      case MspCodes.batteryState:
        _decodeBatteryState(frame.payload);
      case MspCodes.rc:
        _decodeRc(frame.payload);
      default:
        // Unhandled code — silently ignore.
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // MSP decoders
  // ---------------------------------------------------------------------------

  void _decodeFcVariant(List<int> payload) {
    if (payload.length < 4) return;

    final variant = String.fromCharCodes(payload.take(4));
    AutopilotType type;
    switch (variant) {
      case 'BTFL':
        type = AutopilotType.betaflight;
      case 'INAV':
        type = AutopilotType.inav;
      default:
        type = AutopilotType.unknown;
    }
    _emit(_state.copyWith(autopilotType: type));
  }

  void _decodeFcVersion(List<int> payload) {
    if (payload.length < 3) return;

    final major = payload[0];
    final minor = payload[1];
    final patch = payload[2];
    _emit(
      _state.copyWith(
        firmwareVersionMajor: major,
        firmwareVersionMinor: minor,
        firmwareVersionPatch: patch,
        firmwareVersion: '$major.$minor.$patch',
      ),
    );
  }

  void _decodeStatus(List<int> payload) {
    if (payload.length < 11) return;

    final bd = ByteData.sublistView(Uint8List.fromList(payload));

    // Bytes 0-1: cycleTime (unused for state, kept for completeness)
    // Bytes 2-3: i2cErrors
    // Bytes 4-5: sensors bitmask
    // Bytes 6-9: flight-mode flags (uint32 LE)
    // Byte  10:  active profile

    final flightModeFlags = bd.getUint32(6, Endian.little);

    final isArmed = (flightModeFlags & (1 << 0)) != 0;
    final flightMode = _decodeBfFlightMode(flightModeFlags);

    final VehicleState next = _state.copyWith(
      armed: isArmed,
      flightMode: flightMode,
      lastHeartbeat: DateTime.now(),
    );

    // Extended field: average system load (bytes 11-12 in statusEx / BF 3+).
    if (payload.length >= 13) {
      // averageSystemLoad uint16 LE at offset 11 — available but not mapped
      // to any VehicleState field; retained here for future use.
    }

    _emit(next);
  }

  FlightMode _decodeBfFlightMode(int flags) {
    // Betaflight flight-mode flag bits (from bf source, modes.h):
    //   bit 0  = ARM
    //   bit 1  = ANGLE
    //   bit 2  = HORIZON
    //   bit 21 = AIRMODE (BF)
    // iNav shares the first few bits with slightly different semantics but
    // ANGLE/HORIZON/ACRO are consistent enough for display purposes.

    final isAngle = (flags & (1 << 1)) != 0;
    final isHorizon = (flags & (1 << 2)) != 0;
    final isAirMode = (flags & (1 << 21)) != 0;

    if (isAngle) {
      return const FlightMode('ANGLE', 1, category: 'self-level');
    }
    if (isHorizon) {
      return const FlightMode('HORIZON', 2, category: 'self-level');
    }
    if (isAirMode) {
      return const FlightMode('AIR', 21, category: 'acro');
    }
    return const FlightMode('ACRO', 0, category: 'acro');
  }

  void _decodeAttitude(List<int> payload) {
    // roll  int16 LE  degrees * 10
    // pitch int16 LE  degrees * 10
    // yaw   int16 LE  degrees (heading)
    if (payload.length < 6) return;

    final bd = ByteData.sublistView(Uint8List.fromList(payload));
    final rollTenths = bd.getInt16(0, Endian.little);
    final pitchTenths = bd.getInt16(2, Endian.little);
    final yawDeg = bd.getInt16(4, Endian.little);

    const degToRad = pi / 180.0;
    final roll = (rollTenths / 10.0) * degToRad;
    final pitch = (pitchTenths / 10.0) * degToRad;
    final yaw = yawDeg.toDouble() * degToRad;

    _emit(
      _state.copyWith(
        roll: roll,
        pitch: pitch,
        yaw: yaw,
        heading: yawDeg < 0 ? (yawDeg + 360) : yawDeg,
      ),
    );
  }

  void _decodeRawGps(List<int> payload) {
    // fixType  uint8    0=none/no-fix  1=2D  2=3D
    // numSat   uint8
    // lat      int32 LE  degrees * 1e7
    // lon      int32 LE  degrees * 1e7
    // altitude uint16 LE metres
    // speed    uint16 LE cm/s
    // groundCourse uint16 LE  degrees * 10
    // [hdop    uint16 LE  BF 3.3+]
    if (payload.length < 14) return;

    final bd = ByteData.sublistView(Uint8List.fromList(payload));
    final fixType = payload[0];
    final numSat = payload[1];
    final latRaw = bd.getInt32(2, Endian.little);
    final lonRaw = bd.getInt32(6, Endian.little);
    final altMeters = bd.getUint16(10, Endian.little);
    final speedCmS = bd.getUint16(12, Endian.little);
    final courseTenths = bd.getUint16(14, Endian.little);

    final GpsFix gpsFix;
    switch (fixType) {
      case 0:
        gpsFix = GpsFix.noFix;
      case 1:
        gpsFix = GpsFix.fix2d;
      case 2:
        gpsFix = GpsFix.fix3d;
      default:
        gpsFix = GpsFix.none;
    }

    double hdop = _state.hdop;
    if (payload.length >= 17) {
      // Some BF versions encode HDOP as hdop * 100; others as hdop * 10.
      // The most common encoding is × 100 (matching MAVLink GPS_RAW_INT).
      final hdopRaw = bd.getUint16(16, Endian.little);
      hdop = hdopRaw / 100.0;
    }

    _emit(
      _state.copyWith(
        gpsFix: gpsFix,
        satellites: numSat,
        latitude: latRaw / 1e7,
        longitude: lonRaw / 1e7,
        altitudeMsl: altMeters.toDouble(),
        groundspeed: speedCmS / 100.0,
        heading: (courseTenths ~/ 10).clamp(0, 359),
        hdop: hdop,
      ),
    );
  }

  void _decodeAltitude(List<int> payload) {
    // estimatedAltitude int32 LE  cm
    // vario             int16 LE  cm/s
    if (payload.length < 6) return;

    final bd = ByteData.sublistView(Uint8List.fromList(payload));
    final altCm = bd.getInt32(0, Endian.little);
    final varioCmS = bd.getInt16(4, Endian.little);

    _emit(
      _state.copyWith(
        altitudeRel: altCm / 100.0,
        climbRate: varioCmS / 100.0,
      ),
    );
  }

  void _decodeAnalog(List<int> payload) {
    // vbat               uint8     0.1 V units
    // intPowerMeterSum   uint16 LE mAh consumed
    // rssi               uint16 LE 0-1023
    // amperage           int16 LE  0.01 A units
    if (payload.length < 7) return;

    final bd = ByteData.sublistView(Uint8List.fromList(payload));
    final vbatRaw = payload[0];
    final mAhConsumed = bd.getUint16(1, Endian.little);
    final rssiRaw = bd.getUint16(3, Endian.little);
    final amperageRaw = bd.getInt16(5, Endian.little);

    // Scale RSSI from 0-1023 to 0-255 to match MAVLink convention.
    final rssi = (rssiRaw * 255 ~/ 1023).clamp(0, 255);

    _emit(
      _state.copyWith(
        batteryVoltage: vbatRaw / 10.0,
        batteryConsumed: mAhConsumed.toDouble(),
        rssi: rssi,
        batteryCurrent: amperageRaw / 100.0,
      ),
    );
  }

  void _decodeBatteryState(List<int> payload) {
    // Betaflight 3.1+ MSP_BATTERY_STATE
    // cellCount  uint8
    // capacity   uint16 LE  mAh
    // voltage    uint8      0.1 V  (older BF; newer uses uint16 LE 0.01 V)
    // mAhDrawn   uint16 LE
    // current    uint16 LE  0.01 A
    // remaining  uint8      percent
    if (payload.length < 9) return;

    final bd = ByteData.sublistView(Uint8List.fromList(payload));

    // Remaining percent is at offset 8 in the classic layout.
    final remaining = payload[8];

    // Current at bytes 6-7 (uint16 LE, 0.01 A).
    final currentRaw = bd.getUint16(6, Endian.little);

    // mAh drawn at bytes 4-5.
    final mAhDrawn = bd.getUint16(4, Endian.little);

    // Voltage at byte 3.
    final voltageRaw = payload[3];

    _emit(
      _state.copyWith(
        batteryVoltage: voltageRaw / 10.0,
        batteryConsumed: mAhDrawn.toDouble(),
        batteryCurrent: currentRaw / 100.0,
        batteryRemaining: remaining.clamp(0, 100),
      ),
    );
  }

  void _decodeRc(List<int> payload) {
    // Pairs of uint16 LE — up to 16 channels.
    if (payload.length < 2) return;

    final bd = ByteData.sublistView(Uint8List.fromList(payload));
    final channelCount = (payload.length ~/ 2).clamp(0, 16);
    final channels = <int>[];
    for (var i = 0; i < channelCount; i++) {
      channels.add(bd.getUint16(i * 2, Endian.little)); // index varies
    }

    _emit(
      _state.copyWith(
        rcChannels: channels,
        rcChannelCount: channelCount,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Update internal state and broadcast to subscribers.
  void _emit(VehicleState next) {
    if (next == _state) return;
    _state = next;
    _stateController.add(_state);
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

  void _updateLinkState(LinkState next) {
    if (next == _linkState) return;
    _linkState = next;
    _linkController.add(_linkState);
  }
}
