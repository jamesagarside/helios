import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:duckdb_dart/duckdb_dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/telemetry/schema.dart';
import 'package:helios_gcs/core/telemetry/telemetry_store.dart';

/// Regression tests for issue #14: the flight recorder previously wrote
/// fabricated GPS-quality constants (fix_type=3, satellites=14, hdop=0.85,
/// vdop=1.2, vel=0, cog=0) into every gps row because GLOBAL_POSITION_INT
/// does not carry those fields. They must now come from GPS_RAW_INT, or be
/// NULL when no GPS_RAW_INT has been received.

bool get _duckdbAvailable {
  try {
    Connection.inMemory().close();
    return true;
  } catch (_) {
    return false;
  }
}

GlobalPositionIntMessage _pos() => GlobalPositionIntMessage(
      systemId: 1,
      componentId: 1,
      sequence: 0,
      timeBootMs: 0,
      lat: 515000000, // 51.5 degE7
      lon: -1000000, // -0.1 degE7
      alt: 100000, // 100 m MSL (mm)
      relativeAlt: 50000, // 50 m rel (mm)
      vx: 0,
      vy: 0,
      vz: 0,
      hdg: 9000,
    );

GpsRawIntMessage _raw({
  int fixType = 6,
  int sats = 19,
  int eph = 70, // HDOP 0.70
  int epv = 110, // VDOP 1.10
  int vel = 1234, // 12.34 m/s
  int cog = 4500, // 45.0 deg
}) =>
    GpsRawIntMessage(
      systemId: 1,
      componentId: 1,
      sequence: 0,
      timeUsec: 0,
      fixType: fixType,
      lat: 515000000,
      lon: -1000000,
      alt: 100000,
      eph: eph,
      epv: epv,
      vel: vel,
      cog: cog,
      satellitesVisible: sats,
    );

void main() {
  group(
    'GPS quality recording (#14)',
    skip: !_duckdbAvailable ? 'libduckdb not available' : null,
    () {
      late Connection conn;

      setUp(() {
        conn = Connection.inMemory();
        conn.execute(HeliosSchema.createGps);
      });

      tearDown(() => conn.close());

      void insert(GlobalPositionIntMessage pos, GpsRawIntMessage? raw) {
        final row = TelemetryStore.buildGpsRowValues(
          '2026-06-30 12:00:00',
          pos,
          raw,
        );
        conn.execute('INSERT INTO gps VALUES $row');
      }

      test('records real GPS quality from GPS_RAW_INT, not constants', () {
        insert(_pos(), _raw());

        final r = conn.fetch(
          'SELECT fix_type, satellites, hdop, vdop, vel, cog FROM gps',
        );
        expect(r['fix_type']![0], 6);
        expect(r['satellites']![0], 19);
        expect((r['hdop']![0] as num).toDouble(), closeTo(0.70, 1e-6));
        expect((r['vdop']![0] as num).toDouble(), closeTo(1.10, 1e-6));
        expect((r['vel']![0] as num).toDouble(), closeTo(12.34, 1e-6));
        expect((r['cog']![0] as num).toDouble(), closeTo(45.0, 1e-6));
      });

      test('does not contain the old fabricated constant placeholders', () {
        // A spread of realistic GPS_RAW_INT values that deliberately differ
        // from the old hardcoded constants.
        insert(_pos(), _raw(fixType: 4, sats: 11, eph: 130, epv: 200, vel: 0));
        insert(_pos(), _raw(fixType: 6, sats: 21, eph: 60, epv: 90, vel: 500));

        // The exact old placeholder row would have had
        // fix_type=3, satellites=14, hdop=0.85, vdop=1.2.
        final placeholder = conn.fetch('''
          SELECT COUNT(*) AS c FROM gps
          WHERE fix_type = 3 AND satellites = 14
            AND hdop = 0.85 AND vdop = 1.2
        ''');
        expect(placeholder['c']![0], 0,
            reason: 'No row should match the old fabricated constants');

        // And specifically the fabricated satellite count of 14 must never
        // appear when the real telemetry reported a different count.
        final sats = conn.fetch('SELECT satellites FROM gps');
        expect(sats['satellites'], isNot(contains(14)));
      });

      test('writes NULL quality when no GPS_RAW_INT has been received', () {
        insert(_pos(), null);

        final r = conn.fetch(
          'SELECT fix_type, satellites, hdop, vdop, vel, cog FROM gps',
        );
        expect(r['fix_type']![0], isNull);
        expect(r['satellites']![0], isNull);
        expect(r['hdop']![0], isNull);
        expect(r['vdop']![0], isNull);
        expect(r['vel']![0], isNull);
        expect(r['cog']![0], isNull);

        // Position columns are still populated from GLOBAL_POSITION_INT.
        final pos = conn.fetch('SELECT lat, lon, alt_rel FROM gps');
        expect((pos['lat']![0] as num).toDouble(), closeTo(51.5, 1e-6));
        expect((pos['alt_rel']![0] as num).toDouble(), closeTo(50.0, 1e-6));
      });

      test('UINT16_MAX sentinels map to NULL (unknown), not zero', () {
        insert(_pos(), _raw(eph: 0xFFFF, epv: 0xFFFF, vel: 0xFFFF, cog: 0xFFFF));

        final r = conn.fetch('SELECT hdop, vdop, vel, cog FROM gps');
        expect(r['hdop']![0], isNull);
        expect(r['vdop']![0], isNull);
        expect(r['vel']![0], isNull);
        expect(r['cog']![0], isNull);
      });
    },
  );
}
