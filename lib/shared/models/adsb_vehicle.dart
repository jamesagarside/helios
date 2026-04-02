import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

/// A live ADS-B traffic target decoded from ADSB_VEHICLE (msg_id=246).
class AdsbVehicle extends Equatable {
  const AdsbVehicle({
    required this.icaoAddress,
    required this.callsign,
    required this.position,
    required this.altMetres,
    required this.headingDeg,
    required this.speedMs,
    required this.emitterType,
    required this.lastSeen,
  });

  final int icaoAddress;
  final String callsign;
  final LatLng position;
  final double altMetres;
  final double headingDeg;
  final double speedMs;
  final int emitterType;
  final DateTime lastSeen;

  String get displayId =>
      callsign.isNotEmpty ? callsign : icaoAddress.toRadixString(16).toUpperCase().padLeft(6, '0');

  bool isStale(DateTime now) =>
      now.difference(lastSeen).inSeconds > 60;

  AdsbVehicle copyWith({DateTime? lastSeen}) => AdsbVehicle(
        icaoAddress: icaoAddress,
        callsign: callsign,
        position: position,
        altMetres: altMetres,
        headingDeg: headingDeg,
        speedMs: speedMs,
        emitterType: emitterType,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  @override
  List<Object?> get props => [icaoAddress, callsign, position, altMetres, headingDeg, speedMs, emitterType, lastSeen];
}
