/// Generates MAVLink CRC extras from XML definitions.
///
/// Usage: dart run scripts/generate_crc_extras.dart
///
/// Parses common.xml and ardupilotmega.xml, computes CRC_EXTRA for each
/// message, and writes the result to packages/dart_mavlink/lib/src/generated_crc_extras.dart
library;

import 'dart:io';
import 'package:xml/xml.dart';

void main() {
  final messages = <int, _MsgDef>{};

  // Parse common.xml first, then ardupilotmega.xml (which includes common)
  for (final file in ['minimal.xml', 'common.xml', 'ardupilotmega.xml']) {
    final path = 'scripts/mavlink_xml/$file';
    final xml = XmlDocument.parse(File(path).readAsStringSync());
    final msgElements = xml.findAllElements('message');

    for (final msg in msgElements) {
      final id = int.parse(msg.getAttribute('id')!);
      final name = msg.getAttribute('name')!;

      final fields = <_FieldDef>[];
      var inExtension = false;

      for (final child in msg.children) {
        if (child is XmlElement) {
          if (child.name.local == 'extensions') {
            inExtension = true;
            continue;
          }
          if (child.name.local == 'field' && !inExtension) {
            final type = child.getAttribute('type')!;
            final fieldName = child.getAttribute('name')!;
            fields.add(_FieldDef(type, fieldName));
          }
        }
      }

      messages[id] = _MsgDef(id, name, fields);
    }
  }

  // Messages from standard.xml (not in our XML files) — hardcoded extras.
  // These must be added manually because standard.xml is not in our repo.
  // CRC values verified against pymavlink and MAVLink specification.
  const standardXmlExtras = {
    148: (178, 'AUTOPILOT_VERSION'), // standard.xml — requested via MAV_CMD_REQUEST_MESSAGE
  };

  // Inject standard.xml extras that are missing from parsed XML.
  for (final entry in standardXmlExtras.entries) {
    if (!messages.containsKey(entry.key)) {
      messages[entry.key] = _MsgDef(entry.key, entry.value.$2, []);
    }
  }
  final allSorted = messages.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  // Generate Dart file
  final buffer = StringBuffer();
  buffer.writeln('/// AUTO-GENERATED from MAVLink XML definitions.');
  buffer.writeln('/// Run: dart run scripts/generate_crc_extras.dart');
  buffer.writeln('///');
  buffer.writeln('/// Contains CRC extras for ${allSorted.length} messages');
  buffer.writeln('/// from common.xml and ardupilotmega.xml.');
  buffer.writeln('const Map<int, int> mavlinkCrcExtras = {');

  for (final entry in allSorted) {
    final msg = entry.value;
    final override = standardXmlExtras[msg.id];
    final crc = override != null ? override.$1 : _computeCrcExtra(msg);
    final comment = override != null
        ? '${msg.name} (from standard.xml — not in common.xml, manually added)'
        : msg.name;
    buffer.writeln('  ${msg.id}: $crc, // $comment');
  }

  buffer.writeln('};');

  final outPath = 'packages/dart_mavlink/lib/src/generated_crc_extras.dart';
  File(outPath).writeAsStringSync(buffer.toString());
  print('Generated $outPath with ${allSorted.length} CRC extras');
}

int _computeCrcExtra(_MsgDef msg) {
  // CRC_EXTRA is computed over:
  //   message_name + ' ' + field_type + ' ' + field_name + ' ' (for each field)
  // using CRC-16/MCRF4XX, then taking the low byte XOR high byte

  var crc = 0xFFFF;

  // Hash message name
  for (final c in msg.name.codeUnits) {
    crc = _crcAccumulate(c, crc);
  }
  crc = _crcAccumulate(0x20, crc); // space

  // Hash each field (sorted by wire order — largest type first, then alphabetical)
  final wireFields = _sortByWireOrder(msg.fields);

  for (final field in wireFields) {
    final baseType = _baseType(field.type);

    // Hash type name
    for (final c in baseType.codeUnits) {
      crc = _crcAccumulate(c, crc);
    }
    crc = _crcAccumulate(0x20, crc); // space

    // Hash field name
    for (final c in field.name.codeUnits) {
      crc = _crcAccumulate(c, crc);
    }
    crc = _crcAccumulate(0x20, crc); // space

    // If array, hash the array length
    final arrayLen = _arrayLength(field.type);
    if (arrayLen > 0) {
      crc = _crcAccumulate(arrayLen, crc);
    }
  }

  return ((crc & 0xFF) ^ (crc >> 8)) & 0xFF;
}

int _crcAccumulate(int byte, int crc) {
  var tmp = byte ^ (crc & 0xFF);
  tmp ^= (tmp << 4) & 0xFF;
  return ((crc >> 8) ^ (tmp << 8) ^ (tmp << 3) ^ (tmp >> 4)) & 0xFFFF;
}

/// MAVLink wire order: sort by type size (descending), then by field order in XML
List<_FieldDef> _sortByWireOrder(List<_FieldDef> fields) {
  final indexed = fields.asMap().entries.toList();
  indexed.sort((a, b) {
    final sizeA = _typeSize(_baseType(a.value.type));
    final sizeB = _typeSize(_baseType(b.value.type));
    if (sizeA != sizeB) return sizeB.compareTo(sizeA); // largest first
    return a.key.compareTo(b.key); // preserve XML order for same size
  });
  return indexed.map((e) => e.value).toList();
}

String _baseType(String type) {
  // Strip array notation: "char[16]" -> "char", "uint8_t[4]" -> "uint8_t"
  var t = type;
  final bracket = t.indexOf('[');
  if (bracket >= 0) t = t.substring(0, bracket);
  // uint8_t_mavlink_version is treated as uint8_t for CRC purposes
  if (t == 'uint8_t_mavlink_version') t = 'uint8_t';
  return t;
}

int _arrayLength(String type) {
  final match = RegExp(r'\[(\d+)\]').firstMatch(type);
  return match != null ? int.parse(match.group(1)!) : 0;
}

int _typeSize(String baseType) {
  return switch (baseType) {
    'uint8_t' || 'int8_t' || 'char' || 'uint8_t_mavlink_version' => 1,
    'uint16_t' || 'int16_t' => 2,
    'uint32_t' || 'int32_t' || 'float' => 4,
    'uint64_t' || 'int64_t' || 'double' => 8,
    _ => 1,
  };
}

class _MsgDef {
  final int id;
  final String name;
  final List<_FieldDef> fields;
  _MsgDef(this.id, this.name, this.fields);
}

class _FieldDef {
  final String type;
  final String name;
  _FieldDef(this.type, this.name);
}
