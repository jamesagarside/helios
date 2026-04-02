import 'dart:typed_data';
import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';
import 'package:helios_gcs/shared/providers/vehicle_state_notifier.dart';
import 'package:helios_gcs/core/telemetry/telemetry_field_registry.dart';

void main() {
  group('GPS data consistency', () {
    late VehicleStateNotifier notifier;

    setUp(() {
      notifier = VehicleStateNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    GpsRawIntMessage makeGpsRaw({
      int fixType = 0,
      int satellites = 0,
      int eph = 85,
      int epv = 100,
    }) {
      // Build a GPS_RAW_INT payload manually.
      final payload = Uint8List(30);
      final data = ByteData.sublistView(payload);
      data.setUint64(0, 0, Endian.little); // timeUsec
      data.setInt32(8, 0, Endian.little);   // lat
      data.setInt32(12, 0, Endian.little);  // lon
      data.setInt32(16, 0, Endian.little);  // alt
      data.setUint16(20, eph, Endian.little); // eph
      data.setUint16(22, epv, Endian.little); // epv
      data.setUint16(24, 0, Endian.little); // vel
      data.setUint16(26, 0, Endian.little); // cog
      data.setUint8(28, fixType);           // fix_type
      data.setUint8(29, satellites);        // satellites_visible

      return GpsRawIntMessage.fromPayload(payload, 1, 1, 0);
    }

    test('eph=85 produces hdop=0.85', () {
      final msg = makeGpsRaw(eph: 85);
      notifier.handleMessage(msg);
      notifier.flush();

      expect(notifier.state.hdop, closeTo(0.85, 0.01));
    });

    test('eph=65535 (UINT16_MAX) does not update hdop', () {
      // First set a known hdop value
      final msg1 = makeGpsRaw(eph: 100); // hdop = 1.0
      notifier.handleMessage(msg1);
      notifier.flush();
      expect(notifier.state.hdop, closeTo(1.0, 0.01));

      // Now send UINT16_MAX — hdop should stay at previous value
      final msg2 = makeGpsRaw(eph: 65535);
      notifier.handleMessage(msg2);
      notifier.flush();
      expect(notifier.state.hdop, closeTo(1.0, 0.01));
    });

    test('default hdop is 99.99', () {
      expect(notifier.state.hdop, 99.99);
    });

    test('satellites are always updated', () {
      final msg = makeGpsRaw(satellites: 7, eph: 65535);
      notifier.handleMessage(msg);
      notifier.flush();
      expect(notifier.state.satellites, 7);
    });

    test('GPS fix type is mapped correctly', () {
      final cases = <int, GpsFix>{
        0: GpsFix.none,
        1: GpsFix.noFix,
        2: GpsFix.fix2d,
        3: GpsFix.fix3d,
        4: GpsFix.dgps,
        5: GpsFix.rtkFloat,
        6: GpsFix.rtkFixed,
        99: GpsFix.none,
      };

      for (final entry in cases.entries) {
        final msg = makeGpsRaw(fixType: entry.key, eph: 100);
        notifier.handleMessage(msg);
        notifier.flush();
        expect(notifier.state.gpsFix, entry.value,
            reason: 'fixType ${entry.key} should map to ${entry.value}');
      }
    });
  });

  group('TelemetryFieldRegistry GPS fields', () {
    test('hdop getter returns actual value for valid hdop', () {
      final def = TelemetryFieldRegistry.byId('gps_hdop');
      expect(def, isNotNull);

      const state = VehicleState(hdop: 1.5);
      expect(def!.getter(state), 1.5);
    });

    test('hdop format shows "--" for unknown hdop (>= 50)', () {
      final def = TelemetryFieldRegistry.byId('gps_hdop')!;
      expect(def.format(99.99), '--');
      expect(def.format(655.35), '--');
    });

    test('hdop format shows value for known hdop (< 50)', () {
      final def = TelemetryFieldRegistry.byId('gps_hdop')!;
      expect(def.format(0.85), '0.8');
      expect(def.format(1.0), '1.0');
      expect(def.format(2.5), '2.5');
    });

    test('satellites getter returns satellite count', () {
      final def = TelemetryFieldRegistry.byId('gps_sats');
      expect(def, isNotNull);

      const state = VehicleState(satellites: 12);
      expect(def!.getter(state), 12.0);
    });
  });
}
