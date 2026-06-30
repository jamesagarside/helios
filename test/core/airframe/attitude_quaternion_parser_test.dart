import 'dart:typed_data';

import 'package:dart_mavlink/dart_mavlink.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the dart_mavlink parser decodes ATTITUDE_QUATERNION (msg 31),
/// which this feature added. Builds a real v2 frame (with correct CRC extra)
/// and parses it back.
void main() {
  test('ATTITUDE_QUATERNION (msg 31) round-trips through the parser', () {
    final builder = MavlinkFrameBuilder();
    final parser = MavlinkParser();

    // Payload: time_boot_ms(u32), q1..q4(f32), roll/pitch/yaw speed(f32).
    final payload = Uint8List(32);
    final bd = ByteData.sublistView(payload);
    bd.setUint32(0, 12345, Endian.little);
    bd.setFloat32(4, 0.7071, Endian.little); // q1 = w
    bd.setFloat32(8, 0.0, Endian.little); // q2 = x
    bd.setFloat32(12, 0.0, Endian.little); // q3 = y
    bd.setFloat32(16, 0.7071, Endian.little); // q4 = z
    bd.setFloat32(20, 0.1, Endian.little);
    bd.setFloat32(24, 0.2, Endian.little);
    bd.setFloat32(28, 0.3, Endian.little);

    final frame = builder.buildFrame(messageId: 31, payload: payload);

    parser.parse(frame);
    final messages = parser.takeMessages();

    expect(messages, hasLength(1));
    final msg = messages.single;
    expect(msg, isA<AttitudeQuaternionMessage>());
    final q = msg as AttitudeQuaternionMessage;
    expect(q.messageId, 31);
    expect(q.timeBootMs, 12345);
    expect(q.q1, closeTo(0.7071, 1e-4));
    expect(q.q4, closeTo(0.7071, 1e-4));
    expect(q.rollSpeed, closeTo(0.1, 1e-4));
    expect(q.yawSpeed, closeTo(0.3, 1e-4));
  });
}
