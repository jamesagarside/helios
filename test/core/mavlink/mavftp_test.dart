import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helios_gcs/core/mavlink/mavftp.dart';

void main() {
  group('FtpPayload encode/decode', () {
    test('round-trips an OpenFileRO request', () {
      final p = FtpPayload.openFileRO(7, '@PARAM/param.pck');
      final decoded = FtpPayload.decode(p.encode());
      expect(decoded.seqNumber, 7);
      expect(decoded.opcode, FtpOpcode.openFileRO);
      expect(decoded.size, '@PARAM/param.pck'.length);
      expect(String.fromCharCodes(decoded.data), '@PARAM/param.pck');
    });

    test('ReadFile request carries requested length in the size byte', () {
      final p = FtpPayload.readFile(3, 1, 1024, 200);
      final bytes = p.encode();
      // Header byte 4 = size.
      expect(bytes[4], 200);
      final decoded = FtpPayload.decode(bytes);
      expect(decoded.opcode, FtpOpcode.readFile);
      expect(decoded.session, 1);
      expect(decoded.offset, 1024);
      expect(decoded.size, 200);
    });

    test('decodes an ACK data response and ignores trailing padding', () {
      final ack = FtpPayload(
        seqNumber: 9,
        session: 2,
        opcode: FtpOpcode.ack,
        size: 4,
        reqOpcode: FtpOpcode.readFile,
        burstComplete: 0,
        offset: 0,
        data: Uint8List.fromList([1, 2, 3, 4]),
      );
      // Simulate a 248-byte zero-padded field.
      final padded = Uint8List(248)..setRange(0, ack.encode().length, ack.encode());
      final decoded = FtpPayload.decode(padded);
      expect(decoded.isAck, isTrue);
      expect(decoded.reqOpcode, FtpOpcode.readFile);
      expect(decoded.data, [1, 2, 3, 4]);
    });

    test('decodes a NAK with an EOF error code', () {
      final nak = FtpPayload(
        seqNumber: 1,
        session: 0,
        opcode: FtpOpcode.nak,
        size: 1,
        reqOpcode: FtpOpcode.readFile,
        burstComplete: 0,
        offset: 0,
        data: Uint8List.fromList([FtpError.eof]),
      );
      final decoded = FtpPayload.decode(nak.encode());
      expect(decoded.isNak, isTrue);
      expect(decoded.errorCode, FtpError.eof);
    });

    test('throws on a payload shorter than the header', () {
      expect(() => FtpPayload.decode(Uint8List(4)), throwsFormatException);
    });
  });
}
