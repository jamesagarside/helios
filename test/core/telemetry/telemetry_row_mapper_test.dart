import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/telemetry/columns.dart';
import 'package:helios_gcs/core/telemetry/telemetry_row_mapper.dart';

void main() {
  group('TelemetryRowMapper.insertStatement', () {
    test('qualifies the statement with an explicit column list', () {
      final sql = TelemetryRowMapper.insertStatement(
        AttitudeColumns.table,
        AttitudeColumns.columns,
        ["('ts', 1, 2, 3, 4, 5, 6)"],
      );
      expect(
        sql,
        'INSERT INTO attitude '
        '(ts, roll, pitch, yaw, roll_spd, pitch_spd, yaw_spd) '
        "VALUES ('ts', 1, 2, 3, 4, 5, 6)",
      );
    });

    test('joins multiple tuples with commas', () {
      final sql = TelemetryRowMapper.insertStatement(
        VfrHudColumns.table,
        VfrHudColumns.columns,
        ['(1)', '(2)', '(3)'],
      );
      expect(sql, endsWith('VALUES (1), (2), (3)'));
    });
  });

  group('VALUES tuple builders', () {
    test('attitude maps message fields in column order', () {
      final m = AttitudeMessage(
        systemId: 1,
        componentId: 1,
        sequence: 0,
        timeBootMs: 0,
        roll: 0.1,
        pitch: 0.2,
        yaw: 0.3,
        rollSpeed: 0.4,
        pitchSpeed: 0.5,
        yawSpeed: 0.6,
      );
      expect(
        TelemetryRowMapper.attitude('2026-06-30 12:00:00', m),
        "('2026-06-30 12:00:00', 0.1, 0.2, 0.3, 0.4, 0.5, 0.6)",
      );
    });

    test('event escapes single quotes in type and detail', () {
      final tuple = TelemetryRowMapper.event(
        '2026-06-30 12:00:00',
        "it's",
        "a 'quoted' detail",
        4,
      );
      expect(tuple, contains("'it''s'"));
      expect(tuple, contains("'a ''quoted'' detail'"));
      expect(tuple, endsWith(', 4)'));
    });

    test('gps writes NULL quality columns when no GPS_RAW_INT seen', () {
      final pos = GlobalPositionIntMessage(
        systemId: 1,
        componentId: 1,
        sequence: 0,
        timeBootMs: 0,
        lat: 515000000,
        lon: -1000000,
        alt: 100000,
        relativeAlt: 50000,
        vx: 0,
        vy: 0,
        vz: 0,
        hdg: 9000,
      );
      final tuple = TelemetryRowMapper.gps('2026-06-30 12:00:00', pos, null);
      // lat/lon/alt present, all six quality columns NULL.
      expect('NULL'.allMatches(tuple).length, 6);
    });
  });
}
