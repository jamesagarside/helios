import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/mavlink/message_router.dart';
import 'package:helios_gcs/shared/models/alert_severity.dart';

/// Recording stub for [MavlinkRouterSinks]. Captures every sink invocation so
/// tests can assert "message in → which sinks fired with what".
class _RecordingSinks {
  int activeId = 0;
  bool recording = false;
  bool inspectorOn = false;
  final Set<int> known = {};

  final List<MavlinkMessage> handled = [];
  final List<MavlinkMessage> buffered = [];
  final List<AlertEntry> alerts = [];
  final List<AdsbVehicleMessage> adsb = [];
  final List<MavlinkPacketEntry> inspector = [];
  final List<int> registered = [];
  final List<int> synced = [];
  final List<List<int>> firstHeartbeats = []; // [systemId, componentId]

  MavlinkRouterSinks build() => MavlinkRouterSinks(
        activeVehicleId: () => activeId,
        handleVehicleMessage: handled.add,
        isRecording: () => recording,
        bufferTelemetry: buffered.add,
        addAlert: alerts.add,
        updateAdsb: adsb.add,
        inspectorActive: () => inspectorOn,
        addInspectorPacket: inspector.add,
        knownVehicleIds: () => known,
        registerVehicle: (id) {
          known.add(id);
          registered.add(id);
        },
        syncVehicleToRegistry: synced.add,
        onFirstHeartbeat: (sys, comp) => firstHeartbeats.add([sys, comp]),
      );
}

HeartbeatMessage _heartbeat({int systemId = 1, int componentId = 1}) =>
    HeartbeatMessage(
      systemId: systemId,
      componentId: componentId,
      sequence: 0,
      type: 2,
      autopilot: 3,
      baseMode: 0,
      customMode: 0,
      systemStatus: 4,
      mavlinkVersion: 3,
    );

AttitudeMessage _attitude({int systemId = 1}) => AttitudeMessage(
      systemId: systemId,
      componentId: 1,
      sequence: 0,
      timeBootMs: 0,
      roll: 0,
      pitch: 0,
      yaw: 0,
      rollSpeed: 0,
      pitchSpeed: 0,
      yawSpeed: 0,
    );

StatusTextMessage _statusText({int severity = 2, String text = 'PreArm'}) =>
    StatusTextMessage(
      systemId: 1,
      componentId: 1,
      sequence: 0,
      severity: severity,
      text: text,
    );

AdsbVehicleMessage _adsb({int icao = 0xABCDEF}) => AdsbVehicleMessage(
      systemId: 1,
      componentId: 1,
      sequence: 0,
      icaoAddress: icao,
      lat: 515000000,
      lon: -1000000,
      altitudeType: 1,
      altitude: 100000,
      heading: 9000,
      horVelocity: 5000,
      verVelocity: 0,
      flags: 0,
      squawk: 1200,
      emitterType: 1,
      tslc: 0,
      callsign: 'TEST',
    );

void main() {
  group('vehicle-state routing', () {
    test('routes to handler when active id is 0 (accept all)', () {
      final sinks = _RecordingSinks()..activeId = 0;
      MavlinkMessageRouter(sinks.build()).route(_attitude(systemId: 7));
      expect(sinks.handled, hasLength(1));
    });

    test('routes when message system matches active id', () {
      final sinks = _RecordingSinks()..activeId = 3;
      MavlinkMessageRouter(sinks.build()).route(_attitude(systemId: 3));
      expect(sinks.handled, hasLength(1));
    });

    test('does NOT route when message system differs from active id', () {
      final sinks = _RecordingSinks()..activeId = 3;
      MavlinkMessageRouter(sinks.build()).route(_attitude(systemId: 9));
      expect(sinks.handled, isEmpty);
    });
  });

  group('telemetry buffering', () {
    test('buffers only when recording', () {
      final sinks = _RecordingSinks()..recording = false;
      final router = MavlinkMessageRouter(sinks.build());
      router.route(_attitude());
      expect(sinks.buffered, isEmpty);

      sinks.recording = true;
      router.route(_attitude());
      expect(sinks.buffered, hasLength(1));
    });
  });

  group('alert routing', () {
    test('STATUSTEXT produces an alert with mapped severity and text', () {
      final sinks = _RecordingSinks();
      MavlinkMessageRouter(sinks.build())
          .route(_statusText(severity: 4, text: 'Battery low'));
      expect(sinks.alerts, hasLength(1));
      expect(sinks.alerts.single.message, 'Battery low');
      expect(sinks.alerts.single.severity, AlertSeverity.warning);
    });

    test('non-STATUSTEXT messages produce no alert', () {
      final sinks = _RecordingSinks();
      MavlinkMessageRouter(sinks.build()).route(_attitude());
      expect(sinks.alerts, isEmpty);
    });

    test('critical severity is mapped from severity 0', () {
      final sinks = _RecordingSinks();
      MavlinkMessageRouter(sinks.build()).route(_statusText(severity: 0));
      expect(sinks.alerts.single.severity, AlertSeverity.critical);
    });
  });

  group('ADS-B routing', () {
    test('ADSB_VEHICLE forwards to adsb sink', () {
      final sinks = _RecordingSinks();
      MavlinkMessageRouter(sinks.build()).route(_adsb(icao: 0x42));
      expect(sinks.adsb, hasLength(1));
      expect(sinks.adsb.single.icaoAddress, 0x42);
    });
  });

  group('inspector routing', () {
    test('no packet entry added when inspector inactive', () {
      final sinks = _RecordingSinks()..inspectorOn = false;
      MavlinkMessageRouter(sinks.build()).route(_attitude());
      expect(sinks.inspector, isEmpty);
    });

    test('packet entry built with name, payload length and no severity', () {
      final sinks = _RecordingSinks()..inspectorOn = true;
      MavlinkMessageRouter(sinks.build()).route(_attitude(systemId: 5));
      expect(sinks.inspector, hasLength(1));
      final entry = sinks.inspector.single;
      expect(entry.msgName, 'ATTITUDE');
      expect(entry.msgId, 30);
      expect(entry.systemId, 5);
      expect(entry.payloadLength, 28);
      expect(entry.severity, isNull);
    });

    test('STATUSTEXT packet entry carries inspector-hint severity', () {
      // Severity 5 (NOTICE) is the divergent case: inspector hint = info.
      final sinks = _RecordingSinks()..inspectorOn = true;
      MavlinkMessageRouter(sinks.build()).route(_statusText(severity: 5));
      expect(sinks.inspector.single.severity, AlertSeverity.info);
    });
  });

  group('heartbeat / first-heartbeat setup', () {
    test('first heartbeat registers vehicle and runs setup once', () {
      final sinks = _RecordingSinks();
      final router = MavlinkMessageRouter(sinks.build());

      router.route(_heartbeat(systemId: 2, componentId: 1));
      expect(sinks.registered, [2]);
      expect(sinks.synced, [2]);
      expect(sinks.firstHeartbeats, [
        [2, 1],
      ]);
      expect(router.streamsRequested, isTrue);

      // Second heartbeat: already known → no re-register, setup not repeated,
      // but registry sync still happens every heartbeat.
      router.route(_heartbeat(systemId: 2, componentId: 1));
      expect(sinks.registered, [2]); // unchanged
      expect(sinks.firstHeartbeats, hasLength(1)); // setup ran only once
      expect(sinks.synced, [2, 2]); // synced again
    });

    test('heartbeat with systemId 0 is ignored for registry/setup', () {
      final sinks = _RecordingSinks();
      final router = MavlinkMessageRouter(sinks.build());
      router.route(_heartbeat(systemId: 0));
      expect(sinks.registered, isEmpty);
      expect(sinks.firstHeartbeats, isEmpty);
      expect(router.streamsRequested, isFalse);
    });

    test('a second distinct vehicle registers but does not re-run setup', () {
      final sinks = _RecordingSinks();
      final router = MavlinkMessageRouter(sinks.build());
      router.route(_heartbeat(systemId: 1));
      router.route(_heartbeat(systemId: 2));
      expect(sinks.registered, [1, 2]);
      // onFirstHeartbeat is a once-per-connection latch, not per-vehicle.
      expect(sinks.firstHeartbeats, hasLength(1));
    });
  });
}
