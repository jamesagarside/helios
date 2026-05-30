import 'dart:typed_data';

/// MAVLink FTP (MAVFTP) opcodes — see
/// https://mavlink.io/en/services/ftp.html
abstract final class FtpOpcode {
  static const int none = 0;
  static const int terminateSession = 1;
  static const int resetSessions = 2;
  static const int listDirectory = 3;
  static const int openFileRO = 4;
  static const int readFile = 5;
  static const int createFile = 6;
  static const int writeFile = 7;
  static const int removeFile = 8;
  static const int createDirectory = 9;
  static const int removeDirectory = 10;
  static const int openFileWO = 11;
  static const int truncateFile = 12;
  static const int rename = 13;
  static const int calcFileCRC32 = 14;
  static const int burstReadFile = 15;

  // Response opcodes (server → GCS, carried in the `opcode` field).
  static const int ack = 128;
  static const int nak = 129;
}

/// MAVFTP NAK error codes (first data byte of a NAK response).
abstract final class FtpError {
  static const int none = 0;
  static const int fail = 1;
  static const int failErrno = 2;
  static const int invalidDataSize = 3;
  static const int invalidSession = 4;
  static const int noSessionsAvailable = 5;
  static const int eof = 6;
  static const int unknownCommand = 7;
  static const int fileExists = 8;
  static const int fileProtected = 9;
  static const int fileNotFound = 10;

  static String label(int code) => switch (code) {
        none => 'none',
        fail => 'fail',
        failErrno => 'fail (errno)',
        invalidDataSize => 'invalid data size',
        invalidSession => 'invalid session',
        noSessionsAvailable => 'no sessions available',
        eof => 'end of file',
        unknownCommand => 'unknown command',
        fileExists => 'file exists',
        fileProtected => 'file protected',
        fileNotFound => 'file not found',
        _ => 'error $code',
      };
}

/// A decoded/encodable MAVFTP payload — the bytes carried inside a
/// FILE_TRANSFER_PROTOCOL message after the 3-byte target prefix.
///
/// Wire layout (12-byte header + data):
///   u16 seqNumber, u8 session, u8 opcode, u8 size, u8 reqOpcode,
///   u8 burstComplete, u8 padding, u32 offset, u8 data[size]
///
/// [size] is the header `size` byte. For ACK/data responses it equals the
/// number of valid [data] bytes; for ReadFile/BurstReadFile *requests* it is
/// the number of bytes being requested (and [data] is empty).
class FtpPayload {
  const FtpPayload({
    required this.seqNumber,
    required this.session,
    required this.opcode,
    required this.size,
    required this.reqOpcode,
    required this.burstComplete,
    required this.offset,
    required this.data,
  });

  final int seqNumber;
  final int session;
  final int opcode;
  final int size;
  final int reqOpcode;
  final int burstComplete;
  final int offset;
  final Uint8List data;

  static const int headerSize = 12;

  /// Maximum data bytes per FTP payload (248-byte payload − 12-byte header).
  static const int maxData = 248 - headerSize;

  bool get isAck => opcode == FtpOpcode.ack;
  bool get isNak => opcode == FtpOpcode.nak;

  /// For a NAK, the error code carried in the first data byte.
  int get errorCode => (isNak && data.isNotEmpty) ? data[0] : FtpError.none;

  /// Encode this payload to its wire bytes (12-byte header + data).
  Uint8List encode() {
    final out = Uint8List(headerSize + data.length);
    final bd = ByteData.sublistView(out);
    bd.setUint16(0, seqNumber, Endian.little);
    out[2] = session;
    out[3] = opcode;
    out[4] = size;
    out[5] = reqOpcode;
    out[6] = burstComplete;
    out[7] = 0; // padding
    bd.setUint32(8, offset, Endian.little);
    out.setRange(headerSize, headerSize + data.length, data);
    return out;
  }

  /// Decode an FTP payload from wire bytes. Trailing padding beyond `size`
  /// is ignored (the FILE_TRANSFER_PROTOCOL field is zero-padded to 248).
  factory FtpPayload.decode(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw const FormatException('FTP payload shorter than header');
    }
    final bd = ByteData.sublistView(bytes);
    final size = bytes[4];
    final dataEnd = headerSize + size;
    final data = (dataEnd <= bytes.length)
        ? Uint8List.fromList(bytes.sublist(headerSize, dataEnd))
        : Uint8List.fromList(bytes.sublist(headerSize));
    return FtpPayload(
      seqNumber: bd.getUint16(0, Endian.little),
      session: bytes[2],
      opcode: bytes[3],
      size: size,
      reqOpcode: bytes[5],
      burstComplete: bytes[6],
      offset: bd.getUint32(8, Endian.little),
      data: data,
    );
  }

  /// Build an OpenFileRO request for [path].
  static FtpPayload openFileRO(int seq, String path) {
    final data = Uint8List.fromList(path.codeUnits);
    return FtpPayload(
      seqNumber: seq,
      session: 0,
      opcode: FtpOpcode.openFileRO,
      size: data.length,
      reqOpcode: 0,
      burstComplete: 0,
      offset: 0,
      data: data,
    );
  }

  /// Build a ReadFile request for [session] at [offset], requesting [length]
  /// bytes (1..[maxData]).
  static FtpPayload readFile(int seq, int session, int offset, int length) =>
      FtpPayload(
        seqNumber: seq,
        session: session,
        opcode: FtpOpcode.readFile,
        size: length,
        reqOpcode: 0,
        burstComplete: 0,
        offset: offset,
        data: Uint8List(0),
      );

  /// Build a BurstReadFile request for [session] at [offset].
  static FtpPayload burstReadFile(
          int seq, int session, int offset, int length) =>
      FtpPayload(
        seqNumber: seq,
        session: session,
        opcode: FtpOpcode.burstReadFile,
        size: length,
        reqOpcode: 0,
        burstComplete: 0,
        offset: offset,
        data: Uint8List(0),
      );

  /// Build a TerminateSession request for [session].
  static FtpPayload terminateSession(int seq, int session) => FtpPayload(
        seqNumber: seq,
        session: session,
        opcode: FtpOpcode.terminateSession,
        size: 0,
        reqOpcode: 0,
        burstComplete: 0,
        offset: 0,
        data: Uint8List(0),
      );
}
