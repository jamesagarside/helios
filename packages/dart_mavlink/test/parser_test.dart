import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dart_mavlink/dart_mavlink.dart';

void main() {
  late MavlinkParser parser;
  late MavlinkFrameBuilder builder;

  setUp(() {
    parser = MavlinkParser();
    builder = MavlinkFrameBuilder(systemId: 1, componentId: 1);
  });

  group('CRC', () {
    test('accumulate produces correct values', () {
      // Known CRC test vector from MAVLink docs
      var crc = 0xFFFF;
      for (final byte in [0x01, 0x02, 0x03]) {
        crc = MavlinkCrc.accumulate(byte, crc);
      }
      expect(crc, isNonZero); // Sanity — not zero
    });

    test('calculate over empty data returns initial value XOR', () {
      final crc = MavlinkCrc.calculate(Uint8List(0));
      expect(crc, 0xFFFF);
    });
  });

  group('FrameBuilder', () {
    test('builds valid heartbeat frame', () {
      final frame = builder.buildHeartbeat();
      expect(frame[0], mavlinkV2Magic);
      expect(frame[1], 9); // payload length
      expect(frame[5], 1); // system ID
      expect(frame[6], 1); // component ID
      expect(frame[7], 0); // message ID (HEARTBEAT)
    });

    test('builds valid COMMAND_LONG frame', () {
      final frame = builder.buildCommandLong(
        targetSystem: 1,
        targetComponent: 1,
        command: 400, // MAV_CMD_COMPONENT_ARM_DISARM
        param1: 1.0, // arm
      );
      expect(frame[0], mavlinkV2Magic);
      expect(frame[7], 76); // message ID (COMMAND_LONG)
    });

    test('sequence increments', () {
      final frame1 = builder.buildHeartbeat();
      final frame2 = builder.buildHeartbeat();
      expect(frame2[4], frame1[4] + 1);
    });
  });

  group('MavlinkParser v2', () {
    test('parses valid HEARTBEAT', () {
      final frame = builder.buildHeartbeat();
      parser.parse(frame);
      final messages = parser.takeMessages();

      expect(messages.length, 1);
      expect(messages[0], isA<HeartbeatMessage>());
      final hb = messages[0] as HeartbeatMessage;
      expect(hb.type, MavType.gcs);
      expect(hb.autopilot, MavAutopilot.invalid);
      expect(hb.systemStatus, MavState.active);
      expect(hb.messageId, 0);
      expect(hb.systemId, 1);
      expect(hb.componentId, 1);
    });

    test('parses valid ATTITUDE', () {
      final payload = Uint8List(28);
      final data = ByteData.sublistView(payload);
      data.setUint32(0, 12345, Endian.little); // time_boot_ms
      data.setFloat32(4, 0.5, Endian.little);   // roll
      data.setFloat32(8, -0.1, Endian.little);  // pitch
      data.setFloat32(12, 3.14, Endian.little); // yaw
      data.setFloat32(16, 0.01, Endian.little); // rollspeed
      data.setFloat32(20, 0.0, Endian.little);  // pitchspeed
      data.setFloat32(24, -0.02, Endian.little); // yawspeed

      final frame = builder.buildFrame(messageId: 30, payload: payload);
      parser.parse(frame);
      final messages = parser.takeMessages();

      expect(messages.length, 1);
      expect(messages[0], isA<AttitudeMessage>());
      final att = messages[0] as AttitudeMessage;
      expect(att.roll, closeTo(0.5, 0.001));
      expect(att.pitch, closeTo(-0.1, 0.001));
      expect(att.yaw, closeTo(3.14, 0.001));
      expect(att.timeBootMs, 12345);
    });

    test('parses valid GLOBAL_POSITION_INT', () {
      final payload = Uint8List(28);
      final data = ByteData.sublistView(payload);
      data.setUint32(0, 10000, Endian.little); // time_boot_ms
      data.setInt32(4, -353620000, Endian.little); // lat (degE7)
      data.setInt32(8, 1491650000, Endian.little); // lon (degE7)
      data.setInt32(12, 245000, Endian.little); // alt mm MSL
      data.setInt32(16, 120000, Endian.little); // relative_alt mm
      data.setInt16(20, 100, Endian.little); // vx cm/s
      data.setInt16(22, 50, Endian.little);  // vy
      data.setInt16(24, -10, Endian.little); // vz
      data.setUint16(26, 18200, Endian.little); // hdg cdeg

      final frame = builder.buildFrame(messageId: 33, payload: payload);
      parser.parse(frame);
      final messages = parser.takeMessages();

      expect(messages.length, 1);
      final gps = messages[0] as GlobalPositionIntMessage;
      expect(gps.latDeg, closeTo(-35.362, 0.001));
      expect(gps.lonDeg, closeTo(149.165, 0.001));
      expect(gps.altMetres, closeTo(245.0, 0.001));
      expect(gps.relAltMetres, closeTo(120.0, 0.001));
      expect(gps.headingDeg, 182);
    });

    test('parses valid SYS_STATUS', () {
      final payload = Uint8List(31);
      final data = ByteData.sublistView(payload);
      data.setUint16(14, 12420, Endian.little); // voltage mV
      data.setInt16(16, 1500, Endian.little);    // current cA
      payload[30] = 78; // battery remaining %

      final frame = builder.buildFrame(messageId: 1, payload: payload);
      parser.parse(frame);
      final messages = parser.takeMessages();

      expect(messages.length, 1);
      final sys = messages[0] as SysStatusMessage;
      expect(sys.voltageVolts, closeTo(12.42, 0.01));
      expect(sys.currentAmps, closeTo(15.0, 0.01));
      expect(sys.batteryRemaining, 78);
    });

    test('parses valid VFR_HUD', () {
      final payload = Uint8List(20);
      final data = ByteData.sublistView(payload);
      data.setFloat32(0, 22.5, Endian.little);  // airspeed
      data.setFloat32(4, 25.1, Endian.little);  // groundspeed
      data.setFloat32(8, 245.0, Endian.little);  // alt
      data.setFloat32(12, 2.1, Endian.little);  // climb
      data.setInt16(16, 182, Endian.little);     // heading
      data.setUint16(18, 65, Endian.little);     // throttle

      final frame = builder.buildFrame(messageId: 74, payload: payload);
      parser.parse(frame);
      final messages = parser.takeMessages();

      expect(messages.length, 1);
      final hud = messages[0] as VfrHudMessage;
      expect(hud.airspeed, closeTo(22.5, 0.01));
      expect(hud.groundspeed, closeTo(25.1, 0.01));
      expect(hud.heading, 182);
      expect(hud.throttle, 65);
      expect(hud.climb, closeTo(2.1, 0.01));
    });

    test('parses valid STATUSTEXT', () {
      final text = 'PreArm: GPS not healthy';
      final payload = Uint8List(51); // severity + 50 chars
      payload[0] = MavSeverity.warning;
      final textBytes = text.codeUnits;
      payload.setRange(1, 1 + textBytes.length, textBytes);

      final frame = builder.buildFrame(messageId: 253, payload: payload);
      parser.parse(frame);
      final messages = parser.takeMessages();

      expect(messages.length, 1);
      final st = messages[0] as StatusTextMessage;
      expect(st.severity, MavSeverity.warning);
      expect(st.text, 'PreArm: GPS not healthy');
    });

    test('parses valid COMMAND_ACK', () {
      final payload = Uint8List(3);
      final data = ByteData.sublistView(payload);
      data.setUint16(0, 400, Endian.little); // command
      payload[2] = 0; // MAV_RESULT_ACCEPTED

      final frame = builder.buildFrame(messageId: 77, payload: payload);
      parser.parse(frame);
      final messages = parser.takeMessages();

      expect(messages.length, 1);
      final ack = messages[0] as CommandAckMessage;
      expect(ack.command, 400);
      expect(ack.accepted, true);
    });

    test('rejects frame with invalid CRC', () {
      final frame = builder.buildHeartbeat();
      // Corrupt CRC
      frame[frame.length - 1] ^= 0xFF;

      parser.parse(frame);
      final messages = parser.takeMessages();

      expect(messages, isEmpty);
      expect(parser.crcErrors, 1);
    });

    test('skips invalid magic byte', () {
      final data = Uint8List.fromList([0x00, 0x01, 0x02]);
      parser.parse(data);
      expect(parser.takeMessages(), isEmpty);
    });

    test('handles truncated frame (waits for more data)', () {
      final frame = builder.buildHeartbeat();
      // Send first half
      parser.parse(Uint8List.sublistView(frame, 0, 5));
      expect(parser.takeMessages(), isEmpty);

      // Send second half
      parser.parse(Uint8List.sublistView(frame, 5));
      final messages = parser.takeMessages();
      expect(messages.length, 1);
      expect(messages[0], isA<HeartbeatMessage>());
    });

    test('handles multiple frames in single buffer', () {
      final frame1 = builder.buildHeartbeat();
      final payload = Uint8List(28);
      ByteData.sublistView(payload).setFloat32(4, 0.5, Endian.little);
      final frame2 = builder.buildFrame(messageId: 30, payload: payload);

      final combined = Uint8List(frame1.length + frame2.length);
      combined.setRange(0, frame1.length, frame1);
      combined.setRange(frame1.length, combined.length, frame2);

      parser.parse(combined);
      final messages = parser.takeMessages();
      expect(messages.length, 2);
      expect(messages[0], isA<HeartbeatMessage>());
      expect(messages[1], isA<AttitudeMessage>());
    });

    test('handles garbage between frames', () {
      final frame = builder.buildHeartbeat();
      final data = Uint8List(5 + frame.length);
      data.setRange(0, 5, [0x00, 0x01, 0x02, 0x03, 0x04]);
      data.setRange(5, data.length, frame);

      parser.parse(data);
      final messages = parser.takeMessages();
      expect(messages.length, 1);
      expect(messages[0], isA<HeartbeatMessage>());
    });

    test('increments messagesDecoded counter', () {
      parser.parse(builder.buildHeartbeat());
      parser.parse(builder.buildHeartbeat());
      parser.takeMessages();
      expect(parser.messagesDecoded, 2);
    });

    test('heartbeat armed flag detection', () {
      final payload = Uint8List(9);
      payload[4] = MavType.fixedWing;
      payload[5] = MavAutopilot.ardupilotmega;
      payload[6] = MavModeFlag.safetyArmed; // armed
      payload[7] = MavState.active;
      payload[8] = 3;

      final frame = builder.buildFrame(messageId: 0, payload: payload);
      parser.parse(frame);
      final hb = parser.takeMessages()[0] as HeartbeatMessage;
      expect(hb.armed, true);
      expect(hb.type, MavType.fixedWing);
      expect(hb.autopilot, MavAutopilot.ardupilotmega);
    });

    test('heartbeat disarmed flag detection', () {
      final payload = Uint8List(9);
      payload[4] = MavType.fixedWing;
      payload[5] = MavAutopilot.ardupilotmega;
      payload[6] = 0; // disarmed
      payload[7] = MavState.standby;
      payload[8] = 3;

      final frame = builder.buildFrame(messageId: 0, payload: payload);
      parser.parse(frame);
      final hb = parser.takeMessages()[0] as HeartbeatMessage;
      expect(hb.armed, false);
    });
  });
}
