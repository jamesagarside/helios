import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/params/param_pck_decoder.dart';

/// Builds a param.pck byte buffer entry-by-entry for tests, mirroring
/// ArduPilot's encoder.
class _PckBuilder {
  _PckBuilder({required this.withDefaults, this.totalParams = 0});
  final bool withDefaults;
  final int totalParams;
  final BytesBuilder _b = BytesBuilder();
  String _prev = '';
  int _count = 0;

  void add(String name, int type, double value, {double? defaultValue}) {
    // Common-prefix length with previous name (max 15).
    var common = 0;
    final maxCommon = name.length < _prev.length ? name.length : _prev.length;
    while (common < maxCommon && common < 15 && name[common] == _prev[common]) {
      common++;
    }
    final suffix = name.substring(common);
    final nameLen = suffix.length; // 1..16
    final flags = defaultValue != null ? 0x01 : 0x00;

    _b.addByte((type & 0x0F) | ((flags & 0x0F) << 4));
    _b.addByte((common & 0x0F) | (((nameLen - 1) & 0x0F) << 4));
    _b.add(suffix.codeUnits);
    _b.add(_encodeValue(type, value));
    if (defaultValue != null) _b.add(_encodeValue(type, defaultValue));

    _prev = name;
    _count++;
  }

  Uint8List _encodeValue(int type, double v) {
    final bd = ByteData(4);
    switch (type) {
      case 1:
        return Uint8List.fromList([v.toInt() & 0xFF]);
      case 2:
        bd.setInt16(0, v.toInt(), Endian.little);
        return bd.buffer.asUint8List(0, 2);
      case 3:
        bd.setInt32(0, v.toInt(), Endian.little);
        return bd.buffer.asUint8List(0, 4);
      case 4:
        bd.setFloat32(0, v, Endian.little);
        return bd.buffer.asUint8List(0, 4);
      default:
        return Uint8List(0);
    }
  }

  Uint8List build() {
    final header = ByteData(6);
    header.setUint16(
        0, withDefaults ? 0x671c : 0x671b, Endian.little);
    header.setUint16(2, _count, Endian.little);
    header.setUint16(
        4, totalParams == 0 ? _count : totalParams, Endian.little);
    final out = BytesBuilder();
    out.add(header.buffer.asUint8List());
    out.add(_b.toBytes());
    return out.toBytes();
  }
}

void main() {
  group('ParamPckDecoder', () {
    test('rejects a bad magic', () {
      final bytes = Uint8List(6)
        ..[0] = 0xFF
        ..[1] = 0xFF;
      expect(() => ParamPckDecoder.decode(bytes), throwsFormatException);
    });

    test('decodes mixed types without defaults', () {
      final b = _PckBuilder(withDefaults: false)
        ..add('ARMING_CHECK', 3, 1) // INT32
        ..add('BATT_CAPACITY', 4, 5000) // FLOAT
        ..add('COMPASS_USE', 1, 1); // INT8
      final result = ParamPckDecoder.decode(b.build());

      expect(result.hasDefaults, isFalse);
      expect(result.params, hasLength(3));
      expect(result.params[0].name, 'ARMING_CHECK');
      expect(result.params[0].value, 1);
      expect(result.params[1].name, 'BATT_CAPACITY');
      expect(result.params[1].value, closeTo(5000, 0.001));
      expect(result.params[2].name, 'COMPASS_USE');
      expect(result.params[2].value, 1);
      // No defaults present.
      expect(result.params.every((p) => p.defaultValue == null), isTrue);
    });

    test('decodes common-prefix compressed names', () {
      final b = _PckBuilder(withDefaults: false)
        ..add('BATT_CAPACITY', 4, 5000)
        ..add('BATT_MONITOR', 1, 4); // shares "BATT_" prefix
      final result = ParamPckDecoder.decode(b.build());
      expect(result.params[1].name, 'BATT_MONITOR');
    });

    test('decodes defaults when present and exposes non-default detection', () {
      final b = _PckBuilder(withDefaults: true)
        ..add('ARMING_CHECK', 3, 0, defaultValue: 1) // changed from default
        ..add('FENCE_ENABLE', 1, 0); // equals default (no default byte)
      final result = ParamPckDecoder.decode(b.build());

      expect(result.hasDefaults, isTrue);
      expect(result.params[0].defaultValue, 1);
      expect(result.params[0].value, 0);
      expect(result.params[1].defaultValue, isNull);

      // defaultsMap falls back to the current value when no explicit default.
      final map = ParamPckDecoder.defaultsMap(result);
      expect(map['ARMING_CHECK'], 1);
      expect(map['FENCE_ENABLE'], 0);
    });

    test('totalParams from the header is preserved', () {
      final b = _PckBuilder(withDefaults: false, totalParams: 1200)
        ..add('A_PARAM', 3, 7);
      final result = ParamPckDecoder.decode(b.build());
      expect(result.totalParams, 1200);
    });
  });
}
