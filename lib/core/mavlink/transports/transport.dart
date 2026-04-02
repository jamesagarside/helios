import 'dart:async';
import 'dart:typed_data';
import '../../../shared/models/vehicle_state.dart';

/// Abstract transport interface for MAVLink communication.
///
/// All transports (UDP, TCP, Serial) implement this interface.
/// The transport handles raw byte I/O; parsing happens in MavlinkService.
abstract class MavlinkTransport {
  /// Connect or bind the transport. Completes when ready.
  Future<void> connect();

  /// Disconnect and release all resources.
  Future<void> disconnect();

  /// Stream of raw bytes from the vehicle.
  Stream<Uint8List> get dataStream;

  /// Send raw bytes to the vehicle.
  Future<void> send(Uint8List data);

  /// Current transport state.
  TransportState get state;

  /// Stream of state changes.
  Stream<TransportState> get stateStream;

  /// Dispose of all resources. Called when transport is no longer needed.
  void dispose();
}
