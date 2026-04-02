import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../shared/models/vehicle_state.dart';
import 'param_meta.dart';

/// Fetches and caches ArduPilot parameter metadata from autotest.ardupilot.org.
///
/// Platform: All (requires internet for initial fetch; gracefully offline
/// after caching).
///
/// Usage:
/// ```dart
/// final meta = await ParamMetaService().loadForVehicle(VehicleType.quadrotor);
/// final acroMeta = meta['ACRO_BAL_PITCH'];
/// ```
class ParamMetaService {
  // ── URL helpers ─────────────────────────────────────────────────────────────

  /// ArduPilot autotest URL for a given vehicle key.
  static String xmlUrl(String vehicleKey) =>
      'https://autotest.ardupilot.org/Parameters/$vehicleKey/apm.pdef.xml';

  /// Maps a Helios [VehicleType] to the ArduPilot vehicle key used in the URL
  /// and cache file name.
  static String vehicleKey(VehicleType vt) => switch (vt) {
        VehicleType.quadrotor || VehicleType.helicopter => 'ArduCopter',
        VehicleType.fixedWing || VehicleType.vtol => 'ArduPlane',
        VehicleType.rover || VehicleType.boat => 'APMrover2',
        VehicleType.unknown => 'ArduCopter',
      };

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Load parameter metadata for [vt].
  ///
  /// Resolution order:
  /// 1. Cache file (`{appSupportDir}/param_meta/{vehicleKey}.json`) if it
  ///    exists and is less than 7 days old.
  /// 2. Live XML fetch from autotest.ardupilot.org → parse → write cache.
  /// 3. Stale cache (any age) if the network fetch fails.
  /// 4. Empty map as a final graceful fallback.
  Future<Map<String, ParamMeta>> loadForVehicle(VehicleType vt) async {
    final key = vehicleKey(vt);

    // 1. Try fresh cache.
    final cached = await _loadCache(key);
    if (cached != null) return cached;

    // 2. Try network fetch.
    try {
      final xml = await _fetchXml(xmlUrl(key));
      final meta = parseXml(xml);
      if (meta.isNotEmpty) {
        await _saveCache(key, meta);
      }
      return meta;
    } catch (_) {
      // Network failed — fall through to stale cache or empty.
    }

    // 3. Stale cache as last resort.
    final stale = await _loadCache(key, ignoreAge: true);
    if (stale != null) return stale;

    // 4. Graceful empty fallback.
    return const {};
  }

  // ── XML parsing ─────────────────────────────────────────────────────────────

  /// Parse an apm.pdef.xml string and return a map from param name to
  /// [ParamMeta].
  ///
  /// Parsing is done with RegExp / String methods — no external XML package.
  Map<String, ParamMeta> parseXml(String xml) {
    if (xml.trim().isEmpty) return {};

    final result = <String, ParamMeta>{};

    // Extract individual <param ...> blocks (including the closing </param>).
    // We use dotAll so that multi-line param blocks are captured correctly.
    final paramBlockRe = RegExp(
      r'<param\s([\s\S]*?)</param>',
      dotAll: true,
    );

    for (final blockMatch in paramBlockRe.allMatches(xml)) {
      final block = blockMatch.group(0) ?? '';

      // ── Attributes on the opening <param> tag ──────────────────────────────
      final name = _attr(block, 'name');
      if (name.isEmpty) continue;

      final humanName = _attr(block, 'humanName');
      final documentation = _attr(block, 'documentation');
      final userAttr = _attr(block, 'user');
      final userLevel =
          (userAttr.isEmpty || userAttr == 'Standard') ? userAttr : 'Advanced';

      // ── Group derivation ──────────────────────────────────────────────────
      // Prefer humanName prefix before ':' (e.g. "Arming: Require GPS Config"
      // → "Arming"). Fall back to param name prefix before first '_'.
      final String group;
      if (humanName.contains(':')) {
        group = humanName.substring(0, humanName.indexOf(':')).trim();
      } else {
        final sep = name.indexOf('_');
        group = sep > 0 ? name.substring(0, sep) : name;
      }

      // ── Field values ───────────────────────────────────────────────────────
      String units = '';
      double? rangeMin;
      double? rangeMax;
      double? increment;
      Map<int, String> bitmaskBits = const {};

      // Match every <field name="...">...</field> in this block.
      final fieldRe = RegExp(
        r'<field\s+name="([^"]+)"[^>]*>([\s\S]*?)</field>',
        dotAll: true,
      );
      for (final fm in fieldRe.allMatches(block)) {
        final fieldName = fm.group(1) ?? '';
        final fieldValue = (fm.group(2) ?? '').trim();

        switch (fieldName) {
          case 'Units':
            units = fieldValue;

          case 'Range':
            final parts = fieldValue.split(RegExp(r'\s+'));
            if (parts.length >= 2) {
              rangeMin = double.tryParse(parts[0]);
              rangeMax = double.tryParse(parts[1]);
            }

          case 'Increment':
            increment = double.tryParse(fieldValue);

          case 'Bitmask':
            bitmaskBits = _parseBitmask(fieldValue);
        }
      }

      // ── Enum <values> block ────────────────────────────────────────────────
      final Map<int, String> enumValues;
      final valuesBlockRe =
          RegExp(r'<values>([\s\S]*?)</values>', dotAll: true);
      final valuesMatch = valuesBlockRe.firstMatch(block);
      if (valuesMatch != null) {
        enumValues = _parseEnumValues(valuesMatch.group(1) ?? '');
      } else {
        enumValues = const {};
      }

      result[name] = ParamMeta(
        name: name,
        displayName: humanName,
        description: documentation,
        group: group,
        units: units,
        rangeMin: rangeMin,
        rangeMax: rangeMax,
        increment: increment,
        values: enumValues,
        bitmaskBits: bitmaskBits,
        userLevel: userLevel.isEmpty ? 'Advanced' : userLevel,
      );
    }

    return result;
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  /// Extract an XML attribute value by name from [tag].
  String _attr(String tag, String attrName) {
    final re = RegExp('$attrName="([^"]*)"');
    return re.firstMatch(tag)?.group(1) ?? '';
  }

  /// Parse `"0:All,1:Barometer,2:Compass"` into `{0: 'All', 1: 'Barometer', 2: 'Compass'}`.
  Map<int, String> _parseBitmask(String raw) {
    final map = <int, String>{};
    for (final part in raw.split(',')) {
      final colon = part.indexOf(':');
      if (colon <= 0) continue;
      final bit = int.tryParse(part.substring(0, colon).trim());
      final label = part.substring(colon + 1).trim();
      if (bit != null && label.isNotEmpty) {
        map[bit] = label;
      }
    }
    return map;
  }

  /// Parse the inner content of a `<values>` block into an int→String map.
  Map<int, String> _parseEnumValues(String inner) {
    final map = <int, String>{};
    final re = RegExp(r'<value\s+code="(\d+)"[^>]*>([\s\S]*?)</value>',
        dotAll: true);
    for (final m in re.allMatches(inner)) {
      final code = int.tryParse(m.group(1) ?? '');
      final label = (m.group(2) ?? '').trim();
      if (code != null) {
        map[code] = label;
      }
    }
    return map;
  }

  // ── Network ─────────────────────────────────────────────────────────────────

  Future<String> _fetchXml(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      HttpClientRequest request = await client.getUrl(Uri.parse(url));
      HttpClientResponse response = await request.close()
          .timeout(const Duration(seconds: 15));

      // Follow one redirect manually if needed (dart:io HttpClient follows
      // redirects automatically by default, so this is belt-and-braces).
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers.value('location');
        if (location != null) {
          request = await client.getUrl(Uri.parse(location));
          response = await request.close()
              .timeout(const Duration(seconds: 15));
        }
      }

      if (response.statusCode != 200) {
        throw HttpException(
            'HTTP ${response.statusCode} fetching param metadata from $url');
      }

      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  // ── Cache ────────────────────────────────────────────────────────────────────

  Future<Directory> _cacheDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'param_meta'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Load cached metadata. Returns null if the cache is missing, corrupt, or
  /// (when [ignoreAge] is false) older than 7 days.
  Future<Map<String, ParamMeta>?> _loadCache(
    String key, {
    bool ignoreAge = false,
  }) async {
    try {
      final dir = await _cacheDir();
      final file = File(p.join(dir.path, '$key.json'));
      if (!await file.exists()) return null;

      if (!ignoreAge) {
        final stat = await file.stat();
        final age = DateTime.now().difference(stat.modified);
        if (age.inDays >= 7) return null;
      }

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return {
        for (final e in json.entries)
          e.key: ParamMeta.fromJson(e.value as Map<String, dynamic>),
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(String key, Map<String, ParamMeta> meta) async {
    try {
      final dir = await _cacheDir();
      final file = File(p.join(dir.path, '$key.json'));
      final json = {for (final e in meta.entries) e.key: e.value.toJson()};
      await file.writeAsString(jsonEncode(json));
    } catch (_) {
      // Cache write failure is non-fatal.
    }
  }
}
