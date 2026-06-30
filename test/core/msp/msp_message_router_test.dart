import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/msp/msp_message.dart';
import 'package:helios_gcs/core/msp/msp_message_router.dart';
import 'package:helios_gcs/shared/models/vehicle_state.dart';

void main() {
  group('MspMessageRouter (State convergence)', () {
    late MspMessageRouter router;

    setUp(() => router = MspMessageRouter());

    test('starts firmware-unknown with default state', () {
      expect(router.firmware, AutopilotType.unknown);
      expect(router.state, const VehicleState());
    });

    test('FC_VARIANT detection maps Betaflight', () {
      router.route(const MspFcVariant('BTFL'));
      expect(router.firmware, AutopilotType.betaflight);
      expect(router.state.autopilotType, AutopilotType.betaflight);
    });

    test('FC_VARIANT detection maps iNav', () {
      router.route(const MspFcVariant('INAV'));
      expect(router.firmware, AutopilotType.inav);
    });

    test('FC_VARIANT detection leaves unknown variants unknown', () {
      router.route(const MspFcVariant('XXXX'));
      expect(router.firmware, AutopilotType.unknown);
    });

    test('FC_VERSION folds into version fields', () {
      final s = router.route(
        const MspFcVersion(major: 4, minor: 3, patch: 1),
      );
      expect(s.firmwareVersionMajor, 4);
      expect(s.firmwareVersionMinor, 3);
      expect(s.firmwareVersionPatch, 1);
      expect(s.firmwareVersion, '4.3.1');
    });

    test('STATUS interprets ARM flag and ANGLE mode (firmware-specific)', () {
      final s = router.route(
        const MspStatus(
          flightModeFlags: (1 << 0) | (1 << 1), // ARM | ANGLE
          sensorBitmask: 0,
        ),
      );
      expect(s.armed, isTrue);
      expect(s.flightMode.name, 'ANGLE');
      expect(s.flightMode.category, 'self-level');
    });

    test('STATUS maps HORIZON and AIRMODE bits', () {
      expect(
        router.route(const MspStatus(flightModeFlags: 1 << 2, sensorBitmask: 0))
            .flightMode
            .name,
        'HORIZON',
      );
      expect(
        router
            .route(const MspStatus(flightModeFlags: 1 << 21, sensorBitmask: 0))
            .flightMode
            .name,
        'AIR',
      );
    });

    test('STATUS with no mode bits falls back to ACRO and disarmed', () {
      final s = router.route(
        const MspStatus(flightModeFlags: 0, sensorBitmask: 0),
      );
      expect(s.armed, isFalse);
      expect(s.flightMode.name, 'ACRO');
    });

    test('ATTITUDE converts decidegrees to radians and heading', () {
      final s = router.route(
        const MspAttitude(rollDecideg: 150, pitchDecideg: -50, yawDeg: 270),
      );
      expect(s.roll, closeTo(15.0 * pi / 180.0, 1e-9));
      expect(s.pitch, closeTo(-5.0 * pi / 180.0, 1e-9));
      expect(s.heading, 270);
    });

    test('ATTITUDE wraps negative heading into 0-360', () {
      final s = router.route(
        const MspAttitude(rollDecideg: 0, pitchDecideg: 0, yawDeg: -90),
      );
      expect(s.heading, 270);
    });

    test('RAW_GPS folds fix/position/velocity with scaling', () {
      final s = router.route(
        const MspRawGps(
          fixType: 2,
          numSat: 12,
          latRaw: -353632610,
          lonRaw: 1491652300,
          altMeters: 123,
          speedCmS: 450,
          courseDecideg: 2700,
          hdopRaw: 150,
        ),
      );
      expect(s.gpsFix, GpsFix.fix3d);
      expect(s.satellites, 12);
      expect(s.latitude, closeTo(-35.363261, 1e-6));
      expect(s.longitude, closeTo(149.165230, 1e-6));
      expect(s.altitudeMsl, 123.0);
      expect(s.groundspeed, closeTo(4.5, 1e-9));
      expect(s.heading, 270);
      expect(s.hdop, closeTo(1.5, 1e-9));
    });

    test('RAW_GPS keeps prior HDOP when omitted', () {
      router.route(
        const MspRawGps(
          fixType: 2,
          numSat: 8,
          latRaw: 0,
          lonRaw: 0,
          altMeters: 0,
          speedCmS: 0,
          courseDecideg: 0,
          hdopRaw: 250, // 2.5
        ),
      );
      final s = router.route(
        const MspRawGps(
          fixType: 1,
          numSat: 7,
          latRaw: 0,
          lonRaw: 0,
          altMeters: 0,
          speedCmS: 0,
          courseDecideg: 0,
        ),
      );
      expect(s.gpsFix, GpsFix.fix2d);
      expect(s.hdop, closeTo(2.5, 1e-9));
    });

    test('ALTITUDE scales cm to metres', () {
      final s = router.route(const MspAltitude(altCm: 1234, varioCmS: -50));
      expect(s.altitudeRel, closeTo(12.34, 1e-9));
      expect(s.climbRate, closeTo(-0.5, 1e-9));
    });

    test('ANALOG scales voltage/current and rescales RSSI to 0-255', () {
      final s = router.route(
        const MspAnalog(
          vbatDecivolt: 118,
          mAhConsumed: 250,
          rssiRaw: 1023,
          amperageCentiamp: 150,
        ),
      );
      expect(s.batteryVoltage, closeTo(11.8, 1e-9));
      expect(s.batteryConsumed, 250.0);
      expect(s.batteryCurrent, closeTo(1.5, 1e-9));
      expect(s.rssi, 255);
    });

    test('BATTERY_STATE scales fields and clamps remaining', () {
      final s = router.route(
        const MspBatteryState(
          voltageDecivolt: 118,
          mAhDrawn: 300,
          currentCentiamp: 200,
          remainingPercent: 85,
        ),
      );
      expect(s.batteryVoltage, closeTo(11.8, 1e-9));
      expect(s.batteryConsumed, 300.0);
      expect(s.batteryCurrent, closeTo(2.0, 1e-9));
      expect(s.batteryRemaining, 85);
    });

    test('RC folds channels and count', () {
      final s = router.route(const MspRc([1500, 1000, 2000]));
      expect(s.rcChannels, [1500, 1000, 2000]);
      expect(s.rcChannelCount, 3);
    });

    test('accumulates state across messages', () {
      router.route(const MspFcVariant('BTFL'));
      router.route(
        const MspAttitude(rollDecideg: 100, pitchDecideg: 0, yawDeg: 0),
      );
      final s = router.route(const MspRc([1000, 1000]));
      // Firmware and attitude persist while RC is folded in.
      expect(s.autopilotType, AutopilotType.betaflight);
      expect(s.roll, closeTo(10.0 * pi / 180.0, 1e-9));
      expect(s.rcChannels, [1000, 1000]);
    });
  });
}
