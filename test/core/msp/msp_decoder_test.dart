import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/msp/msp_codes.dart';
import 'package:helios_gcs/core/msp/msp_decoder.dart';
import 'package:helios_gcs/core/msp/msp_frame.dart';
import 'package:helios_gcs/core/msp/msp_message.dart';

/// Builds a response [MspFrame] for [code] with the given [payload].
MspFrame _response(int code, List<int> payload) =>
    MspFrame(code: code, payload: payload, direction: MspDirection.response);

/// Little-endian helpers for assembling raw payloads.
List<int> _u16(int v) {
  final b = ByteData(2)..setUint16(0, v, Endian.little);
  return b.buffer.asUint8List();
}

List<int> _i16(int v) {
  final b = ByteData(2)..setInt16(0, v, Endian.little);
  return b.buffer.asUint8List();
}

List<int> _i32(int v) {
  final b = ByteData(4)..setInt32(0, v, Endian.little);
  return b.buffer.asUint8List();
}

List<int> _u32(int v) {
  final b = ByteData(4)..setUint32(0, v, Endian.little);
  return b.buffer.asUint8List();
}

void main() {
  group('MspDecoder', () {
    test('ignores request frames (echo-backs)', () {
      final frame = MspFrame(
        code: MspCodes.attitude,
        payload: const [],
        direction: MspDirection.request,
      );
      expect(MspDecoder.decode(frame), isNull);
    });

    test('returns null for unmodelled codes', () {
      expect(MspDecoder.decode(_response(MspCodes.boxNames, const [1, 2])),
          isNull);
    });

    test('decodes FC_VARIANT to raw identifier', () {
      final frame = _response(MspCodes.fcVariant, 'BTFL'.codeUnits);
      final msg = MspDecoder.decode(frame);
      expect(msg, isA<MspFcVariant>());
      expect((msg! as MspFcVariant).identifier, 'BTFL');
    });

    test('decodes FC_VARIANT for iNav without interpreting it', () {
      // The decoder stays firmware-agnostic: it returns the raw string only.
      final msg = MspDecoder.decode(_response(MspCodes.fcVariant, 'INAV'.codeUnits));
      expect((msg! as MspFcVariant).identifier, 'INAV');
    });

    test('rejects short FC_VARIANT payloads', () {
      expect(MspDecoder.decode(_response(MspCodes.fcVariant, [66, 84, 70])),
          isNull);
    });

    test('decodes FC_VERSION triple', () {
      final msg = MspDecoder.decode(_response(MspCodes.fcVersion, [4, 3, 1]));
      expect(msg, isA<MspFcVersion>());
      final v = msg! as MspFcVersion;
      expect(v.major, 4);
      expect(v.minor, 3);
      expect(v.patch, 1);
    });

    test('decodes STATUS raw flags and sensor bitmask without interpretation',
        () {
      final payload = <int>[
        ..._u16(100), // cycleTime
        ..._u16(0), // i2cErrors
        ..._u16(0x23), // sensors bitmask
        ..._u32((1 << 0) | (1 << 1)), // ARM | ANGLE
        7, // active profile
      ];
      final msg = MspDecoder.decode(_response(MspCodes.status, payload));
      expect(msg, isA<MspStatus>());
      final s = msg! as MspStatus;
      // Raw fields preserved; ARM/ANGLE meaning is not resolved here.
      expect(s.flightModeFlags, (1 << 0) | (1 << 1));
      expect(s.sensorBitmask, 0x23);
    });

    test('decodes STATUS_EX through the same path', () {
      final payload = <int>[
        ..._u16(100),
        ..._u16(0),
        ..._u16(0),
        ..._u32(0),
        0,
      ];
      expect(MspDecoder.decode(_response(MspCodes.statusEx, payload)),
          isA<MspStatus>());
    });

    test('rejects short STATUS payloads', () {
      expect(MspDecoder.decode(_response(MspCodes.status, [0, 0, 0])), isNull);
    });

    test('decodes ATTITUDE raw integers', () {
      final payload = <int>[
        ..._i16(150), // roll 15.0 deg
        ..._i16(-50), // pitch -5.0 deg
        ..._i16(270), // heading
      ];
      final msg = MspDecoder.decode(_response(MspCodes.attitude, payload));
      final a = msg! as MspAttitude;
      expect(a.rollDecideg, 150);
      expect(a.pitchDecideg, -50);
      expect(a.yawDeg, 270);
    });

    test('decodes RAW_GPS without HDOP', () {
      final payload = <int>[
        2, // fixType 3D
        12, // numSat
        ..._i32(-353632610), // lat
        ..._i32(1491652300), // lon
        ..._u16(123), // altitude m
        ..._u16(450), // speed cm/s
        ..._u16(2700), // course decideg
      ];
      final msg = MspDecoder.decode(_response(MspCodes.rawGps, payload));
      final g = msg! as MspRawGps;
      expect(g.fixType, 2);
      expect(g.numSat, 12);
      expect(g.latRaw, -353632610);
      expect(g.lonRaw, 1491652300);
      expect(g.altMeters, 123);
      expect(g.speedCmS, 450);
      expect(g.courseDecideg, 2700);
      expect(g.hdopRaw, isNull);
    });

    test('decodes RAW_GPS with HDOP when present', () {
      final payload = <int>[
        2, 12,
        ..._i32(0), ..._i32(0),
        ..._u16(0), ..._u16(0), ..._u16(0),
        ..._u16(150), // hdop raw
      ];
      final g = MspDecoder.decode(_response(MspCodes.rawGps, payload))!
          as MspRawGps;
      expect(g.hdopRaw, 150);
    });

    test('rejects short RAW_GPS payloads', () {
      expect(MspDecoder.decode(_response(MspCodes.rawGps, [2, 12, 0, 0])),
          isNull);
    });

    test('decodes ALTITUDE raw integers', () {
      final payload = <int>[..._i32(1234), ..._i16(-50)];
      final a =
          MspDecoder.decode(_response(MspCodes.altitude, payload))! as MspAltitude;
      expect(a.altCm, 1234);
      expect(a.varioCmS, -50);
    });

    test('decodes ANALOG raw integers', () {
      final payload = <int>[
        118, // vbat 11.8V
        ..._u16(250), // mAh consumed
        ..._u16(512), // rssi 0-1023
        ..._i16(150), // amperage 1.5A
      ];
      final a =
          MspDecoder.decode(_response(MspCodes.analog, payload))! as MspAnalog;
      expect(a.vbatDecivolt, 118);
      expect(a.mAhConsumed, 250);
      expect(a.rssiRaw, 512);
      expect(a.amperageCentiamp, 150);
    });

    test('decodes BATTERY_STATE raw integers', () {
      final payload = <int>[
        4, // cellCount
        ..._u16(1500), // capacity
        118, // voltage 11.8V
        ..._u16(300), // mAh drawn
        ..._u16(200), // current 2.0A
        85, // remaining %
      ];
      final b = MspDecoder.decode(_response(MspCodes.batteryState, payload))!
          as MspBatteryState;
      expect(b.voltageDecivolt, 118);
      expect(b.mAhDrawn, 300);
      expect(b.currentCentiamp, 200);
      expect(b.remainingPercent, 85);
    });

    test('decodes RC channels', () {
      final payload = <int>[
        ..._u16(1500),
        ..._u16(1000),
        ..._u16(2000),
        ..._u16(1234),
      ];
      final rc = MspDecoder.decode(_response(MspCodes.rc, payload))! as MspRc;
      expect(rc.channels, [1500, 1000, 2000, 1234]);
    });

    test('clamps RC to 16 channels', () {
      final payload = <int>[for (var i = 0; i < 20; i++) ..._u16(1000 + i)];
      final rc = MspDecoder.decode(_response(MspCodes.rc, payload))! as MspRc;
      expect(rc.channels.length, 16);
    });
  });
}
