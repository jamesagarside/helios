import 'dart:typed_data';

import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/models/mission_item.dart';

void main() {
  group('MissionItem', () {
    test('default values are sensible', () {
      const item = MissionItem(seq: 0);

      expect(item.seq, 0);
      expect(item.frame, MavFrame.globalRelativeAlt);
      expect(item.command, MavCmd.navWaypoint);
      expect(item.autocontinue, 1);
      expect(item.altitude, 50.0);
      expect(item.latitude, 0.0);
      expect(item.longitude, 0.0);
    });

    test('latE7 and lonE7 convert correctly', () {
      const item = MissionItem(
        seq: 1,
        latitude: -35.3632,
        longitude: 149.1652,
      );

      expect(item.latE7, -353632000);
      expect(item.lonE7, 1491652000);
    });

    test('commandLabel returns correct labels', () {
      expect(
        const MissionItem(seq: 0, command: MavCmd.navWaypoint).commandLabel,
        'Waypoint',
      );
      expect(
        const MissionItem(seq: 0, command: MavCmd.navTakeoff).commandLabel,
        'Takeoff',
      );
      expect(
        const MissionItem(seq: 0, command: MavCmd.navLand).commandLabel,
        'Land',
      );
      expect(
        const MissionItem(seq: 0, command: MavCmd.navReturnToLaunch).commandLabel,
        'RTL',
      );
      expect(
        const MissionItem(seq: 0, command: 999).commandLabel,
        'CMD 999',
      );
    });

    test('isNavCommand identifies navigation commands', () {
      expect(const MissionItem(seq: 0, command: MavCmd.navWaypoint).isNavCommand, true);
      expect(const MissionItem(seq: 0, command: MavCmd.navTakeoff).isNavCommand, true);
      expect(const MissionItem(seq: 0, command: MavCmd.doChangeSpeed).isNavCommand, false);
      expect(const MissionItem(seq: 0, command: MavCmd.doSetHome).isNavCommand, false);
    });

    test('copyWith preserves unchanged fields', () {
      const item = MissionItem(
        seq: 3,
        latitude: -35.0,
        longitude: 149.0,
        altitude: 100.0,
      );

      final updated = item.copyWith(altitude: 200.0);

      expect(updated.seq, 3);
      expect(updated.latitude, -35.0);
      expect(updated.longitude, 149.0);
      expect(updated.altitude, 200.0);
    });

    test('equality works correctly', () {
      const a = MissionItem(seq: 0, latitude: -35.0, longitude: 149.0);
      const b = MissionItem(seq: 0, latitude: -35.0, longitude: 149.0);
      const c = MissionItem(seq: 1, latitude: -35.0, longitude: 149.0);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('MissionState', () {
    test('default state is empty and idle', () {
      const state = MissionState();

      expect(state.items, isEmpty);
      expect(state.transferState, MissionTransferState.idle);
      expect(state.currentWaypoint, 0);
      expect(state.transferProgress, 0.0);
      expect(state.errorMessage, isNull);
      expect(state.isEmpty, true);
      expect(state.isTransferring, false);
      expect(state.waypointCount, 0);
    });

    test('isTransferring is true during download and upload', () {
      const downloading = MissionState(
        transferState: MissionTransferState.downloading,
      );
      expect(downloading.isTransferring, true);

      const uploading = MissionState(
        transferState: MissionTransferState.uploading,
      );
      expect(uploading.isTransferring, true);

      const idle = MissionState(
        transferState: MissionTransferState.idle,
      );
      expect(idle.isTransferring, false);

      const complete = MissionState(
        transferState: MissionTransferState.complete,
      );
      expect(complete.isTransferring, false);
    });

    test('totalDistanceMetres calculates distance between nav items', () {
      const state = MissionState(items: [
        MissionItem(seq: 0, latitude: 0.0, longitude: 0.0),
        MissionItem(seq: 1, latitude: 0.0, longitude: 1.0),
      ]);

      // ~111km for 1 degree at equator
      expect(state.totalDistanceMetres, greaterThan(110000));
      expect(state.totalDistanceMetres, lessThan(112000));
    });

    test('totalDistanceMetres skips non-nav commands', () {
      const state = MissionState(items: [
        MissionItem(seq: 0, latitude: 0.0, longitude: 0.0),
        MissionItem(seq: 1, command: MavCmd.doChangeSpeed),
        MissionItem(seq: 2, latitude: 0.0, longitude: 1.0),
      ]);

      // Should still be ~111km (skip the speed change)
      expect(state.totalDistanceMetres, greaterThan(110000));
    });

    test('copyWith clears errorMessage when not provided', () {
      const state = MissionState(errorMessage: 'timeout');
      final updated = state.copyWith(transferState: MissionTransferState.idle);

      expect(updated.errorMessage, isNull);
    });
  });

  group('MissionItem JSON serialisation', () {
    test('toJson produces map with all expected keys', () {
      const item = MissionItem(
        seq: 3,
        command: MavCmd.navWaypoint,
        latitude: -35.3632,
        longitude: 149.1652,
        altitude: 100.0,
        param1: 5.0,
        param2: 10.0,
        param3: 0.0,
        param4: 90.0,
        frame: MavFrame.globalRelativeAlt,
        autocontinue: 1,
      );
      final json = item.toJson();

      expect(json.containsKey('seq'), true);
      expect(json.containsKey('command'), true);
      expect(json.containsKey('lat'), true);
      expect(json.containsKey('lon'), true);
      expect(json.containsKey('alt'), true);
      expect(json.containsKey('p1'), true);
      expect(json.containsKey('p2'), true);
      expect(json.containsKey('p3'), true);
      expect(json.containsKey('p4'), true);
      expect(json.containsKey('frame'), true);
      expect(json.containsKey('autoContinue'), true);
    });

    test('toJson encodes values correctly', () {
      const item = MissionItem(
        seq: 3,
        command: MavCmd.navWaypoint,
        latitude: -35.3632,
        longitude: 149.1652,
        altitude: 100.0,
        param1: 5.0,
        param2: 10.0,
        param3: 0.0,
        param4: 90.0,
        frame: MavFrame.globalRelativeAlt,
        autocontinue: 1,
      );
      final json = item.toJson();

      expect(json['seq'], 3);
      expect(json['command'], MavCmd.navWaypoint);
      expect(json['lat'], closeTo(-35.3632, 0.000001));
      expect(json['lon'], closeTo(149.1652, 0.000001));
      expect(json['alt'], closeTo(100.0, 0.001));
      expect(json['p1'], closeTo(5.0, 0.001));
      expect(json['p2'], closeTo(10.0, 0.001));
      expect(json['p3'], closeTo(0.0, 0.001));
      expect(json['p4'], closeTo(90.0, 0.001));
      expect(json['frame'], MavFrame.globalRelativeAlt);
      expect(json['autoContinue'], true);
    });

    test('toJson encodes autoContinue as false when autocontinue is 0', () {
      const item = MissionItem(seq: 0, autocontinue: 0);
      final json = item.toJson();
      expect(json['autoContinue'], false);
    });

    test('fromJson round-trips correctly', () {
      const original = MissionItem(
        seq: 5,
        command: MavCmd.navTakeoff,
        latitude: -35.3632,
        longitude: 149.1652,
        altitude: 50.0,
        param1: 0.0,
        param2: 0.0,
        param3: 0.0,
        param4: 0.0,
        frame: MavFrame.globalRelativeAlt,
        autocontinue: 1,
      );

      final json = original.toJson();
      final restored = MissionItem.fromJson(json);

      expect(restored, equals(original));
    });

    test('fromJson handles num types — int values stored in JSON', () {
      // JSON parsers may produce int or double for numeric fields.
      // fromJson must handle both via (as num).toDouble() / (as num).toInt().
      final json = <String, dynamic>{
        'seq': 2,           // int
        'command': 16,      // int
        'lat': -35,         // int, should become -35.0
        'lon': 149,         // int, should become 149.0
        'alt': 100,         // int, should become 100.0
        'p1': 0,
        'p2': 0,
        'p3': 0,
        'p4': 0,
        'frame': 3,         // int
        'autoContinue': true,
      };

      final item = MissionItem.fromJson(json);

      expect(item.seq, 2);
      expect(item.command, 16);
      expect(item.latitude, -35.0);
      expect(item.longitude, 149.0);
      expect(item.altitude, 100.0);
      expect(item.frame, 3);
      expect(item.autocontinue, 1);
    });

    test('fromJson uses defaults for missing optional fields', () {
      // Only the required keys are present; p1-p4, frame, autoContinue absent.
      final json = <String, dynamic>{
        'seq': 1,
        'command': MavCmd.navWaypoint,
        'lat': -35.3632,
        'lon': 149.1652,
        'alt': 80.0,
      };

      final item = MissionItem.fromJson(json);

      expect(item.param1, 0.0);
      expect(item.param2, 0.0);
      expect(item.param3, 0.0);
      expect(item.param4, 0.0);
      expect(item.frame, MavFrame.globalRelativeAlt);
      expect(item.autocontinue, 1); // autoContinue defaults to true → 1
    });

    test('fromJson autoContinue false maps to autocontinue 0', () {
      final json = <String, dynamic>{
        'seq': 0,
        'command': MavCmd.navWaypoint,
        'lat': 0.0,
        'lon': 0.0,
        'alt': 50.0,
        'autoContinue': false,
      };

      final item = MissionItem.fromJson(json);
      expect(item.autocontinue, 0);
    });

    test('fromJson and toJson are stable across multiple round-trips', () {
      const original = MissionItem(
        seq: 7,
        command: MavCmd.navLoiterTime,
        latitude: 51.5074,
        longitude: -0.1278,
        altitude: 120.0,
        param1: 30.0,
        param2: 5.0,
        param3: 0.0,
        param4: -1.0,
        frame: MavFrame.globalRelativeAlt,
        autocontinue: 1,
      );

      final once = MissionItem.fromJson(original.toJson());
      final twice = MissionItem.fromJson(once.toJson());

      expect(once, equals(original));
      expect(twice, equals(original));
    });
  });

  group('Mission message parsing', () {
    test('MissionCountMessage parses correctly', () {
      final payload = _buildCountPayload(count: 5, targetSys: 1, targetComp: 1);
      final msg = MissionCountMessage.fromPayload(payload, 1, 1, 0);

      expect(msg.count, 5);
      expect(msg.targetSystem, 1);
      expect(msg.targetComponent, 1);
    });

    test('MissionItemIntMessage parses with correct lat/lon conversion', () {
      final payload = _buildItemIntPayload(
        seq: 2,
        command: MavCmd.navWaypoint,
        frame: MavFrame.globalRelativeAlt,
        latE7: -353632000,
        lonE7: 1491652000,
        alt: 100.0,
        param1: 5.0,
      );
      final msg = MissionItemIntMessage.fromPayload(payload, 1, 1, 0);

      expect(msg.seq, 2);
      expect(msg.command, MavCmd.navWaypoint);
      expect(msg.frame, MavFrame.globalRelativeAlt);
      expect(msg.latDeg, closeTo(-35.3632, 0.0001));
      expect(msg.lonDeg, closeTo(149.1652, 0.0001));
      expect(msg.z, closeTo(100.0, 0.01));
      expect(msg.param1, closeTo(5.0, 0.01));
    });

    test('MissionAckMessage parses accepted', () {
      final payload = _buildAckPayload(
        targetSys: 255,
        targetComp: 190,
        type: MavMissionResult.accepted,
      );
      final msg = MissionAckMessage.fromPayload(payload, 1, 1, 0);

      expect(msg.accepted, true);
      expect(msg.type, MavMissionResult.accepted);
    });

    test('MissionAckMessage parses error', () {
      final payload = _buildAckPayload(
        targetSys: 255,
        targetComp: 190,
        type: MavMissionResult.error,
      );
      final msg = MissionAckMessage.fromPayload(payload, 1, 1, 0);

      expect(msg.accepted, false);
      expect(msg.type, MavMissionResult.error);
    });

    test('MissionCurrentMessage parses waypoint sequence', () {
      final payload = _buildCurrentPayload(seq: 3);
      final msg = MissionCurrentMessage.fromPayload(payload, 1, 1, 0);

      expect(msg.seq, 3);
    });

    test('MissionRequestIntMessage parses sequence', () {
      final payload = _buildRequestIntPayload(
        seq: 2,
        targetSys: 1,
        targetComp: 1,
      );
      final msg = MissionRequestIntMessage.fromPayload(payload, 255, 190, 0);

      expect(msg.seq, 2);
      expect(msg.targetSystem, 1);
      expect(msg.targetComponent, 1);
    });

    test('MissionItem.fromMessage converts from protocol message', () {
      final payload = _buildItemIntPayload(
        seq: 1,
        command: MavCmd.navTakeoff,
        frame: MavFrame.globalRelativeAlt,
        latE7: -353632000,
        lonE7: 1491652000,
        alt: 50.0,
      );
      final msg = MissionItemIntMessage.fromPayload(payload, 1, 1, 0);
      final item = MissionItem.fromMessage(msg);

      expect(item.seq, 1);
      expect(item.command, MavCmd.navTakeoff);
      expect(item.latitude, closeTo(-35.3632, 0.0001));
      expect(item.longitude, closeTo(149.1652, 0.0001));
      expect(item.altitude, closeTo(50.0, 0.01));
    });
  });
}

// --- Test payload builders ---

Uint8List _buildCountPayload({
  required int count,
  required int targetSys,
  required int targetComp,
}) {
  final payload = Uint8List(5);
  final data = ByteData.sublistView(payload);
  data.setUint16(0, count, Endian.little);
  payload[2] = targetSys;
  payload[3] = targetComp;
  payload[4] = 0;
  return payload;
}

Uint8List _buildItemIntPayload({
  required int seq,
  required int command,
  required int frame,
  int latE7 = 0,
  int lonE7 = 0,
  double alt = 0.0,
  double param1 = 0.0,
  double param2 = 0.0,
  double param3 = 0.0,
  double param4 = 0.0,
  int targetSys = 1,
  int targetComp = 1,
}) {
  final payload = Uint8List(38);
  final data = ByteData.sublistView(payload);
  data.setFloat32(0, param1, Endian.little);
  data.setFloat32(4, param2, Endian.little);
  data.setFloat32(8, param3, Endian.little);
  data.setFloat32(12, param4, Endian.little);
  data.setInt32(16, latE7, Endian.little);
  data.setInt32(20, lonE7, Endian.little);
  data.setFloat32(24, alt, Endian.little);
  data.setUint16(28, seq, Endian.little);
  data.setUint16(30, command, Endian.little);
  payload[32] = targetSys;
  payload[33] = targetComp;
  payload[34] = frame;
  payload[35] = 0;
  payload[36] = 1;
  payload[37] = 0;
  return payload;
}

Uint8List _buildAckPayload({
  required int targetSys,
  required int targetComp,
  required int type,
}) {
  final payload = Uint8List(4);
  payload[0] = targetSys;
  payload[1] = targetComp;
  payload[2] = type;
  payload[3] = 0;
  return payload;
}

Uint8List _buildCurrentPayload({required int seq}) {
  final payload = Uint8List(2);
  final data = ByteData.sublistView(payload);
  data.setUint16(0, seq, Endian.little);
  return payload;
}

Uint8List _buildRequestIntPayload({
  required int seq,
  required int targetSys,
  required int targetComp,
}) {
  final payload = Uint8List(5);
  final data = ByteData.sublistView(payload);
  data.setUint16(0, seq, Endian.little);
  payload[2] = targetSys;
  payload[3] = targetComp;
  payload[4] = 0;
  return payload;
}
