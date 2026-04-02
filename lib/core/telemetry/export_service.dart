import 'dart:io';

import '../../shared/models/mission_item.dart';
import '../../shared/models/vehicle_state.dart';
import 'telemetry_store.dart';

/// Service for exporting flight telemetry to KML and CSV formats.
///
/// Supports both [VehicleState] snapshots and [QueryResult] from DuckDB.
class TelemetryExportService {
  // ─── KML Export ──────────────────────────────────────────────────────────

  /// Export flight path as KML file.
  ///
  /// Color-codes the flight path by flight mode:
  /// - AUTO = blue, GUIDED = purple, RTL = red, LAND = orange
  /// - LOITER = cyan, STABILIZE/MANUAL = green, other = white
  ///
  /// Includes: home position marker, waypoint markers, timestamp annotations,
  /// and altitude profile.
  static Future<void> exportKml({
    required String filePath,
    required List<VehicleState> snapshots,
    String flightName = 'Helios Flight',
    List<MissionItem> missionItems = const [],
  }) async {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    buf.writeln('<Document>');
    buf.writeln('  <name>${_xmlEscape(flightName)}</name>');
    buf.writeln('  <description>Exported by Helios GCS</description>');

    // Style definitions for flight mode line segments
    for (final entry in _modeStyles.entries) {
      buf.writeln('  <Style id="style_${entry.key}">');
      buf.writeln('    <LineStyle>');
      buf.writeln('      <color>${entry.value}</color>');
      buf.writeln('      <width>3</width>');
      buf.writeln('    </LineStyle>');
      buf.writeln('  </Style>');
    }

    // Waypoint marker style
    buf.writeln('  <Style id="style_waypoint">');
    buf.writeln('    <IconStyle>');
    buf.writeln('      <color>ff00ffff</color>');
    buf.writeln('      <scale>0.8</scale>');
    buf.writeln('      <Icon><href>'
        'http://maps.google.com/mapfiles/kml/paddle/wht-blank.png'
        '</href></Icon>');
    buf.writeln('    </IconStyle>');
    buf.writeln('    <LabelStyle><scale>0.7</scale></LabelStyle>');
    buf.writeln('  </Style>');

    // Home marker style
    buf.writeln('  <Style id="style_home">');
    buf.writeln('    <IconStyle>');
    buf.writeln('      <color>ff00ff00</color>');
    buf.writeln('      <scale>1.0</scale>');
    buf.writeln('      <Icon><href>'
        'http://maps.google.com/mapfiles/kml/paddle/H.png'
        '</href></Icon>');
    buf.writeln('    </IconStyle>');
    buf.writeln('  </Style>');

    // Home marker
    final firstWithHome = snapshots.where((s) => s.hasHome).firstOrNull;
    if (firstWithHome != null) {
      buf.writeln('  <Placemark>');
      buf.writeln('    <name>Home</name>');
      buf.writeln('    <styleUrl>#style_home</styleUrl>');
      buf.writeln('    <Point>');
      buf.writeln('      <altitudeMode>absolute</altitudeMode>');
      buf.writeln('      <coordinates>'
          '${firstWithHome.homeLongitude},${firstWithHome.homeLatitude},'
          '${firstWithHome.homeAltitude}</coordinates>');
      buf.writeln('    </Point>');
      buf.writeln('  </Placemark>');
    }

    // Waypoint markers from mission items
    if (missionItems.isNotEmpty) {
      buf.writeln('  <Folder>');
      buf.writeln('    <name>Mission Waypoints</name>');
      for (final item in missionItems.where((i) => i.isNavCommand)) {
        buf.writeln('    <Placemark>');
        buf.writeln('      <name>WP ${item.seq} (${item.commandLabel})</name>');
        buf.writeln('      <styleUrl>#style_waypoint</styleUrl>');
        buf.writeln('      <Point>');
        buf.writeln('        <altitudeMode>relativeToGround</altitudeMode>');
        buf.writeln('        <coordinates>'
            '${item.longitude},${item.latitude},${item.altitude}'
            '</coordinates>');
        buf.writeln('      </Point>');
        buf.writeln('    </Placemark>');
      }
      buf.writeln('  </Folder>');
    }

    // Flight path segments grouped by mode
    if (snapshots.isNotEmpty) {
      buf.writeln('  <Folder>');
      buf.writeln('    <name>Flight Path</name>');

      var segStart = 0;
      for (var i = 1; i <= snapshots.length; i++) {
        final modeChanged = i == snapshots.length ||
            snapshots[i].flightMode.name != snapshots[i - 1].flightMode.name;

        if (modeChanged) {
          final segment = snapshots.sublist(segStart, i);
          final modeName = segment.first.flightMode.name;
          final styleKey = _styleKeyFor(modeName);

          // Timestamp annotation for segment start
          final startTs = segment.first.lastHeartbeat;
          final tsLabel =
              startTs != null ? ' (${_formatTime(startTs)})' : '';

          buf.writeln('    <Placemark>');
          buf.writeln('      <name>$modeName$tsLabel</name>');
          buf.writeln('      <description>'
              '${segment.length} samples, mode: $modeName'
              '</description>');
          buf.writeln('      <styleUrl>#style_$styleKey</styleUrl>');
          buf.writeln('      <LineString>');
          buf.writeln('        <altitudeMode>absolute</altitudeMode>');
          buf.writeln('        <coordinates>');

          for (final s in segment) {
            if (s.hasPosition) {
              buf.writeln(
                  '          ${s.longitude},${s.latitude},${s.altitudeMsl}');
            }
          }

          buf.writeln('        </coordinates>');
          buf.writeln('      </LineString>');
          buf.writeln('    </Placemark>');

          segStart = i;
        }
      }

      buf.writeln('  </Folder>');

      // Altitude profile as a clamped-to-ground path
      buf.writeln('  <Folder>');
      buf.writeln('    <name>Altitude Profile</name>');
      buf.writeln('    <visibility>0</visibility>');
      buf.writeln('    <Placemark>');
      buf.writeln('      <name>Altitude AGL</name>');
      buf.writeln('      <Style><LineStyle>');
      buf.writeln('        <color>8800ff00</color>');
      buf.writeln('        <width>2</width>');
      buf.writeln('      </LineStyle></Style>');
      buf.writeln('      <LineString>');
      buf.writeln('        <altitudeMode>relativeToGround</altitudeMode>');
      buf.writeln('        <coordinates>');
      for (final s in snapshots) {
        if (s.hasPosition) {
          buf.writeln(
              '          ${s.longitude},${s.latitude},${s.altitudeRel}');
        }
      }
      buf.writeln('        </coordinates>');
      buf.writeln('      </LineString>');
      buf.writeln('    </Placemark>');
      buf.writeln('  </Folder>');
    }

    buf.writeln('</Document>');
    buf.writeln('</kml>');

    await File(filePath).writeAsString(buf.toString());
  }

  /// Export KML from DuckDB query results.
  ///
  /// Expects columns: ts, lat, lon, alt_msl, alt_rel, flight_mode.
  static Future<void> exportKmlFromQuery({
    required String filePath,
    required QueryResult result,
    String flightName = 'Helios Flight',
  }) async {
    final snapshots = _queryResultToSnapshots(result);
    await exportKml(
      filePath: filePath,
      snapshots: snapshots,
      flightName: flightName,
    );
  }

  // ─── CSV Export ──────────────────────────────────────────────────────────

  /// Export telemetry as CSV file.
  static Future<void> exportCsv({
    required String filePath,
    required List<VehicleState> snapshots,
  }) async {
    final buf = StringBuffer();

    // Header
    buf.writeln('timestamp,latitude,longitude,alt_msl,alt_rel,'
        'roll,pitch,yaw,heading,groundspeed,airspeed,climb_rate,'
        'battery_v,battery_a,battery_pct,gps_fix,satellites,'
        'flight_mode,armed,throttle,vibration_x,vibration_y,vibration_z');

    for (final s in snapshots) {
      final ts = s.lastHeartbeat?.toIso8601String() ?? '';
      buf.writeln('$ts,${s.latitude},${s.longitude},'
          '${s.altitudeMsl.toStringAsFixed(2)},'
          '${s.altitudeRel.toStringAsFixed(2)},'
          '${(s.roll * 57.2958).toStringAsFixed(2)},'
          '${(s.pitch * 57.2958).toStringAsFixed(2)},'
          '${(s.yaw * 57.2958).toStringAsFixed(2)},'
          '${s.heading},'
          '${s.groundspeed.toStringAsFixed(2)},'
          '${s.airspeed.toStringAsFixed(2)},'
          '${s.climbRate.toStringAsFixed(2)},'
          '${s.batteryVoltage.toStringAsFixed(2)},'
          '${s.batteryCurrent.toStringAsFixed(2)},'
          '${s.batteryRemaining},'
          '${s.gpsFix.name},'
          '${s.satellites},'
          '${s.flightMode.name},'
          '${s.armed ? 1 : 0},'
          '${s.throttle},'
          '${s.vibrationX.toStringAsFixed(4)},'
          '${s.vibrationY.toStringAsFixed(4)},'
          '${s.vibrationZ.toStringAsFixed(4)}');
    }

    await File(filePath).writeAsString(buf.toString());
  }

  /// Export CSV from DuckDB query results.
  ///
  /// Writes column headers and all rows directly from the query result.
  static Future<void> exportCsvFromQuery({
    required String filePath,
    required QueryResult result,
  }) async {
    final buf = StringBuffer();

    // Header from column names
    buf.writeln(result.columnNames.join(','));

    // Rows
    for (final row in result.rows) {
      buf.writeln(row.map((v) => _csvEscapeValue(v)).join(','));
    }

    await File(filePath).writeAsString(buf.toString());
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// KML color for each flight mode (AABBGGRR format).
  static const _modeStyles = <String, String>{
    'auto': 'ffff0000', // blue
    'guided': 'ffff00ff', // purple
    'rtl': 'ff0000ff', // red
    'land': 'ff0099ff', // orange
    'loiter': 'ffffff00', // cyan
    'stabilize': 'ff00ff00', // green
    'manual': 'ff00ff00', // green
    'other': 'ffffffff', // white
  };

  static String _styleKeyFor(String modeName) {
    final lower = modeName.toLowerCase();
    if (lower.contains('auto')) return 'auto';
    if (lower.contains('guided')) return 'guided';
    if (lower.contains('rtl') || lower.contains('smart')) return 'rtl';
    if (lower.contains('land')) return 'land';
    if (lower.contains('loiter') || lower.contains('hold')) return 'loiter';
    if (lower.contains('stab') || lower.contains('acro')) return 'stabilize';
    if (lower.contains('manual')) return 'manual';
    return 'other';
  }

  static String _xmlEscape(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  static String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  /// Escape a value for CSV output.
  static String _csvEscapeValue(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  /// Convert DuckDB query results to VehicleState snapshots for KML export.
  ///
  /// Maps common column names to VehicleState fields.
  static List<VehicleState> _queryResultToSnapshots(QueryResult result) {
    final cols = result.columnNames;
    final latIdx = _findCol(cols, ['lat', 'latitude']);
    final lonIdx = _findCol(cols, ['lon', 'longitude']);
    final altMslIdx = _findCol(cols, ['alt_msl', 'altitude_msl', 'alt']);
    final altRelIdx = _findCol(cols, ['alt_rel', 'altitude_rel']);
    final modeIdx = _findCol(cols, ['flight_mode', 'mode']);
    final tsIdx = _findCol(cols, ['ts', 'timestamp']);

    if (latIdx < 0 || lonIdx < 0) return [];

    final snapshots = <VehicleState>[];
    for (final row in result.rows) {
      final lat = _toDouble(row, latIdx);
      final lon = _toDouble(row, lonIdx);
      if (lat == 0 && lon == 0) continue;

      DateTime? ts;
      if (tsIdx >= 0 && row[tsIdx] != null) {
        ts = row[tsIdx] is DateTime
            ? row[tsIdx] as DateTime
            : DateTime.tryParse(row[tsIdx].toString());
      }

      final modeName =
          modeIdx >= 0 && row[modeIdx] != null ? row[modeIdx].toString() : '';

      snapshots.add(VehicleState(
        latitude: lat,
        longitude: lon,
        altitudeMsl: altMslIdx >= 0 ? _toDouble(row, altMslIdx) : 0,
        altitudeRel: altRelIdx >= 0 ? _toDouble(row, altRelIdx) : 0,
        flightMode: FlightMode(modeName, 0),
        lastHeartbeat: ts,
      ));
    }
    return snapshots;
  }

  static int _findCol(List<String> cols, List<String> candidates) {
    for (final c in candidates) {
      final idx = cols.indexWhere(
          (col) => col.toLowerCase() == c.toLowerCase());
      if (idx >= 0) return idx;
    }
    return -1;
  }

  static double _toDouble(List<dynamic> row, int idx) {
    if (idx < 0 || idx >= row.length || row[idx] == null) return 0.0;
    if (row[idx] is num) return (row[idx] as num).toDouble();
    return double.tryParse(row[idx].toString()) ?? 0.0;
  }
}
