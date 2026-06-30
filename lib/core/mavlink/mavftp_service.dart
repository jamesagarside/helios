import 'dart:async';
import 'dart:typed_data';

import 'package:dart_mavlink/dart_mavlink.dart';

import 'mavftp.dart';
import 'mavlink_service.dart';

/// Minimal MAVLink FTP client: open a file read-only, read it sequentially,
/// then terminate the session.
///
/// This is intentionally a small, sequential (non-burst) implementation —
/// robust over lossy links and sufficient for small files like
/// `@PARAM/param.pck`. Burst reads can be layered on later for large files
/// (e.g. dataflash logs) without changing the public API.
class MavFtpService {
  MavFtpService(this._mavlink);

  final MavlinkService _mavlink;

  int _seq = 0;
  int _nextSeq() => _seq = (_seq + 1) & 0xFFFF;

  /// Read an entire file at [path] into memory.
  ///
  /// [onProgress] receives bytes-read so far (total size is unknown until
  /// EOF). Throws [MavFtpException] on NAK or timeout.
  Future<Uint8List> readFile(
    String path, {
    required int targetSystem,
    required int targetComponent,
    Duration timeout = const Duration(seconds: 3),
    int maxRetries = 3,
    void Function(int bytesRead)? onProgress,
  }) async {
    final session = await _open(
      path,
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      timeout: timeout,
      maxRetries: maxRetries,
    );

    final builder = BytesBuilder(copy: false);
    var offset = 0;
    try {
      while (true) {
        final reply = await _request(
          FtpPayload.readFile(
              _nextSeq(), session, offset, FtpPayload.maxData),
          targetSystem: targetSystem,
          targetComponent: targetComponent,
          timeout: timeout,
          maxRetries: maxRetries,
        );

        if (reply.isNak) {
          if (reply.errorCode == FtpError.eof) break; // normal end
          throw MavFtpException(
              'Read failed: ${FtpError.label(reply.errorCode)}');
        }
        if (reply.data.isEmpty) break; // defensive: zero-length ACK = EOF
        builder.add(reply.data);
        offset += reply.data.length;
        onProgress?.call(offset);

        // A short read (fewer than requested) also signals EOF on many stacks,
        // but ArduPilot sends an explicit EOF NAK, so we keep looping until it.
      }
    } finally {
      // Best-effort session cleanup; ignore failures.
      try {
        await _request(
          FtpPayload.terminateSession(_nextSeq(), session),
          targetSystem: targetSystem,
          targetComponent: targetComponent,
          timeout: const Duration(seconds: 1),
          maxRetries: 1,
        );
      } catch (_) {}
    }

    return builder.toBytes();
  }

  Future<int> _open(
    String path, {
    required int targetSystem,
    required int targetComponent,
    required Duration timeout,
    required int maxRetries,
  }) async {
    final reply = await _request(
      FtpPayload.openFileRO(_nextSeq(), path),
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      timeout: timeout,
      maxRetries: maxRetries,
    );
    if (reply.isNak) {
      throw MavFtpException(
          'Open "$path" failed: ${FtpError.label(reply.errorCode)}');
    }
    return reply.session;
  }

  /// Send one FTP request payload and await the matching reply (by seqNumber,
  /// which the server echoes incremented... ArduPilot replies with the same
  /// or seq+1; we accept the first FILE_TRANSFER_PROTOCOL whose reqOpcode
  /// matches our opcode or whose seqNumber is our seq/seq+1).
  Future<FtpPayload> _request(
    FtpPayload payload, {
    required int targetSystem,
    required int targetComponent,
    required Duration timeout,
    required int maxRetries,
  }) async {
    final frame = _mavlink.frameBuilder.buildFileTransferProtocol(
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      ftpPayload: payload.encode(),
    );

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      final replyFuture = _mavlink
          .messagesOf<FileTransferProtocolMessage>()
          .map((m) => FtpPayload.decode(m.payloadBytes))
          .where((p) => _matches(p, payload))
          .first
          .timeout(timeout);

      await _mavlink.sendRaw(frame);

      try {
        return await replyFuture;
      } on TimeoutException {
        if (attempt >= maxRetries) {
          throw MavFtpException(
              'Timeout on FTP opcode ${payload.opcode} after $maxRetries retries');
        }
      }
    }
    throw MavFtpException('FTP request failed (opcode ${payload.opcode})');
  }

  /// Match a reply payload to our request: the server echoes our request
  /// opcode in [FtpPayload.reqOpcode] and uses seqNumber = request seq + 1.
  bool _matches(FtpPayload reply, FtpPayload request) {
    if (reply.reqOpcode == request.opcode) return true;
    final expected = (request.seqNumber + 1) & 0xFFFF;
    return reply.seqNumber == expected || reply.seqNumber == request.seqNumber;
  }
}

class MavFtpException implements Exception {
  MavFtpException(this.message);
  final String message;
  @override
  String toString() => 'MavFtpException: $message';
}
