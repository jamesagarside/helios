import 'dart:typed_data';

/// A single parameter decoded from an ArduPilot `param.pck` file.
class PckParam {
  const PckParam({
    required this.name,
    required this.value,
    required this.type,
    this.defaultValue,
  });

  /// Full parameter name (decompressed from common-prefix encoding).
  final String name;

  /// Current value, normalised to a double regardless of stored type.
  final double value;

  /// AP_Param type: 1=INT8, 2=INT16, 3=INT32, 4=FLOAT.
  final int type;

  /// Default value, present only when the file was fetched `withdefaults=1`
  /// AND the default differs from the current value (ArduPilot only includes
  /// a default when it differs).
  final double? defaultValue;
}

/// Result of decoding a `param.pck` file.
class PckResult {
  const PckResult({
    required this.params,
    required this.totalParams,
    required this.hasDefaults,
  });

  final List<PckParam> params;

  /// Total parameter count advertised in the header (may exceed
  /// `params.length` if the file is fetched in chunks).
  final int totalParams;

  /// Whether this file carries default values (magic 0x671c).
  final bool hasDefaults;
}

/// Decoder for ArduPilot's packed parameter file (`@PARAM/param.pck`,
/// optionally `?withdefaults=1`).
///
/// Binary format (little-endian):
///   Header (6 bytes): u16 magic, u16 num_params, u16 total_params
///     magic 0x671b = no defaults, 0x671c = defaults included
///   Per entry:
///     byte 0: type:4 (low nibble) | flags:4 (high nibble); flag bit0 = default follows
///     byte 1: common_len:4 (low) | name_len_minus_1:4 (high)
///     name[name_len] : non-common suffix (name_len = high nibble + 1)
///     value[N]       : N by type (INT8=1, INT16=2, INT32=4, FLOAT=4)
///     default[N]     : present iff flag bit0 set, same N
abstract final class ParamPckDecoder {
  static const int magicNoDefaults = 0x671b;
  static const int magicWithDefaults = 0x671c;

  static int _typeSize(int type) => switch (type) {
        1 => 1, // INT8
        2 => 2, // INT16
        3 => 4, // INT32
        4 => 4, // FLOAT
        _ => 0,
      };

  static double _readValue(ByteData bd, int offset, int type) =>
      switch (type) {
        1 => bd.getInt8(offset).toDouble(),
        2 => bd.getInt16(offset, Endian.little).toDouble(),
        3 => bd.getInt32(offset, Endian.little).toDouble(),
        4 => bd.getFloat32(offset, Endian.little),
        _ => 0.0,
      };

  /// Decode [bytes]. Throws [FormatException] on a bad magic or truncation.
  static PckResult decode(Uint8List bytes) {
    if (bytes.length < 6) {
      throw const FormatException('param.pck shorter than header');
    }
    final bd = ByteData.sublistView(bytes);
    final magic = bd.getUint16(0, Endian.little);
    if (magic != magicNoDefaults && magic != magicWithDefaults) {
      throw FormatException(
          'Bad param.pck magic: 0x${magic.toRadixString(16)}');
    }
    final hasDefaults = magic == magicWithDefaults;
    final totalParams = bd.getUint16(4, Endian.little);

    final params = <PckParam>[];
    var offset = 6;
    var prevName = '';

    while (offset + 2 <= bytes.length) {
      // Stop on trailing zero padding: a valid entry always has a non-zero
      // AP_Param type in the low nibble of the first byte.
      if ((bytes[offset] & 0x0F) == 0) break;

      final typeFlags = bytes[offset];
      final nameLens = bytes[offset + 1];
      offset += 2;

      final type = typeFlags & 0x0F;
      final flags = (typeFlags >> 4) & 0x0F;
      final hasDefault = (flags & 0x01) != 0;

      final commonLen = nameLens & 0x0F;
      final nameLen = ((nameLens >> 4) & 0x0F) + 1;

      if (offset + nameLen > bytes.length) break;
      final suffix = String.fromCharCodes(
          bytes.sublist(offset, offset + nameLen));
      offset += nameLen;

      final common =
          commonLen <= prevName.length ? prevName.substring(0, commonLen) : prevName;
      final name = common + suffix;
      prevName = name;

      final n = _typeSize(type);
      if (n == 0 || offset + n > bytes.length) break;
      final value = _readValue(bd, offset, type);
      offset += n;

      double? defaultValue;
      if (hasDefault) {
        if (offset + n > bytes.length) break;
        defaultValue = _readValue(bd, offset, type);
        offset += n;
      }

      params.add(PckParam(
        name: name,
        value: value,
        type: type,
        defaultValue: defaultValue,
      ));
    }

    return PckResult(
      params: params,
      totalParams: totalParams,
      hasDefaults: hasDefaults,
    );
  }

  /// Convenience: extract a `name → defaultValue` map for every parameter
  /// whose default is known. For params present in the file but unchanged
  /// from default (no explicit default included), the current value *is* the
  /// default, so it is included too.
  static Map<String, double> defaultsMap(PckResult result) {
    final out = <String, double>{};
    for (final p in result.params) {
      out[p.name] = p.defaultValue ?? p.value;
    }
    return out;
  }
}
