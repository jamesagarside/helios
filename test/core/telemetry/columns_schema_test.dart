import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/telemetry/columns.dart';
import 'package:helios_gcs/core/telemetry/schema.dart';

/// Guards the single-source-of-truth invariant from issue #15: every column
/// constant must actually appear in its table's `CREATE TABLE` definition, so a
/// rename in `columns.dart` that the schema didn't pick up is caught here
/// rather than silently breaking a reader at runtime.
void main() {
  group('column constants appear in CREATE TABLE definitions', () {
    void check(String createSql, String table, List<String> columns) {
      expect(createSql, contains(table),
          reason: 'CREATE for $table should name the table');
      for (final col in columns) {
        // Word-boundary match so `ts` does not match inside `start_ts`.
        expect(
          RegExp('\\b${RegExp.escape(col)}\\b').hasMatch(createSql),
          isTrue,
          reason: 'column "$col" missing from CREATE TABLE for $table',
        );
      }
    }

    test('attitude', () {
      check(HeliosSchema.createAttitude, AttitudeColumns.table,
          AttitudeColumns.columns);
    });

    test('gps', () {
      check(HeliosSchema.createGps, GpsColumns.table, GpsColumns.columns);
    });

    test('battery', () {
      check(HeliosSchema.createBattery, BatteryColumns.table,
          BatteryColumns.columns);
    });

    test('vfr_hud', () {
      check(HeliosSchema.createVfrHud, VfrHudColumns.table,
          VfrHudColumns.columns);
    });

    test('vibration', () {
      check(HeliosSchema.createVibration, VibrationColumns.table,
          VibrationColumns.columns);
    });

    test('events', () {
      check(HeliosSchema.createEvents, EventsColumns.table,
          EventsColumns.columns);
    });

    test('missions', () {
      check(HeliosSchema.createMissions, MissionsColumns.table,
          MissionsColumns.columns);
    });

    test('flight_meta', () {
      check(HeliosSchema.createFlightMeta, FlightMetaColumns.table,
          [FlightMetaColumns.key, FlightMetaColumns.value]);
    });
  });

  test('column lists have no duplicates', () {
    for (final cols in [
      AttitudeColumns.columns,
      GpsColumns.columns,
      BatteryColumns.columns,
      VfrHudColumns.columns,
      VibrationColumns.columns,
      EventsColumns.columns,
      MissionsColumns.columns,
    ]) {
      expect(cols.toSet().length, cols.length,
          reason: 'duplicate column name in $cols');
    }
  });
}
