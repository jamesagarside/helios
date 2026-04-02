import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:latlong2/latlong.dart';

/// A loaded SRTM elevation tile covering one 1°×1° cell.
class _SrtmTile {
  _SrtmTile({
    required this.latSouth,
    required this.lonWest,
    required this.samples,
    required this.size,
  });

  final int latSouth; // integer degree of tile's southern edge
  final int lonWest;  // integer degree of tile's western edge
  final Int16List samples; // row-major, north-first
  final int size; // 1201 for SRTM3, 3601 for SRTM1

  double elevationAt(double lat, double lon) {
    // Fractional position within tile
    final row = (latSouth + 1 - lat) * (size - 1);
    final col = (lon - lonWest) * (size - 1);

    final r0 = row.floor().clamp(0, size - 2);
    final c0 = col.floor().clamp(0, size - 2);
    final fr = row - r0;
    final fc = col - c0;

    final e00 = samples[r0 * size + c0].toDouble();
    final e01 = samples[r0 * size + c0 + 1].toDouble();
    final e10 = samples[(r0 + 1) * size + c0].toDouble();
    final e11 = samples[(r0 + 1) * size + c0 + 1].toDouble();

    // Bilinear interpolation (skip void -32768 cells)
    if (e00 == -32768 || e01 == -32768 || e10 == -32768 || e11 == -32768) {
      // Return average of valid cells
      final valid = [e00, e01, e10, e11].where((v) => v != -32768).toList();
      if (valid.isEmpty) return 0;
      return valid.reduce((a, b) => a + b) / valid.length;
    }

    return e00 * (1 - fr) * (1 - fc) +
        e01 * (1 - fr) * fc +
        e10 * fr * (1 - fc) +
        e11 * fr * fc;
  }
}

/// Service for loading SRTM HGT elevation tiles and querying terrain height.
///
/// Usage:
///   1. Call [loadHgt] with one or more .hgt file paths.
///   2. Call [elevationAt] to query MSL altitude at any lat/lon.
///   3. Call [terrainProfile] to get a list of elevations along a path.
class DemService {
  final _tiles = <String, _SrtmTile>{};

  bool get hasData => _tiles.isNotEmpty;

  /// Parse an SRTM .hgt filename to get the tile's SW corner.
  /// Format: N35E149.hgt or S35W149.hgt
  static ({int lat, int lon})? parseTileName(String filename) {
    final base = filename.split(Platform.pathSeparator).last.toUpperCase();
    final re = RegExp(r'^([NS])(\d{2})([EW])(\d{3})\.HGT$');
    final m = re.firstMatch(base);
    if (m == null) return null;
    final lat = int.parse(m.group(2)!) * (m.group(1) == 'N' ? 1 : -1);
    final lon = int.parse(m.group(4)!) * (m.group(3) == 'E' ? 1 : -1);
    return (lat: lat, lon: lon);
  }

  /// Load an SRTM .hgt file into memory.
  Future<void> loadHgt(String path) async {
    final coords = parseTileName(path);
    if (coords == null) return;

    final bytes = await File(path).readAsBytes();
    final totalSamples = bytes.length ~/ 2;

    // SRTM3 = 1201×1201 = 1442401, SRTM1 = 3601×3601 = 12967201
    final size = switch (totalSamples) {
      1442401 => 1201,
      12967201 => 3601,
      _ => null,
    };
    if (size == null) return; // unrecognised format

    // Parse big-endian int16 samples
    final samples = Int16List(totalSamples);
    for (var i = 0; i < totalSamples; i++) {
      final high = bytes[i * 2];
      final low = bytes[i * 2 + 1];
      var val = (high << 8) | low;
      if (val > 32767) val -= 65536;
      samples[i] = val;
    }

    final key = '${coords.lat}_${coords.lon}';
    _tiles[key] = _SrtmTile(
      latSouth: coords.lat,
      lonWest: coords.lon,
      samples: samples,
      size: size,
    );
  }

  void clear() => _tiles.clear();

  /// Returns MSL elevation in metres at [lat]/[lon], or null if no tile loaded.
  double? elevationAt(double lat, double lon) {
    final tileLatKey = lat >= 0 ? lat.floor() : -((-lat).ceil());
    final tileLonKey = lon >= 0 ? lon.floor() : -((-lon).ceil());
    final key = '${tileLatKey}_$tileLonKey';
    final tile = _tiles[key];
    if (tile == null) return null;
    return tile.elevationAt(lat, lon);
  }

  /// Returns terrain elevation samples along a path defined by [waypoints].
  ///
  /// Samples are evenly spaced at approximately [stepMetres] intervals.
  /// Returns a list of (cumulativeDistKm, elevationM) pairs.
  List<({double distKm, double elevM})> terrainProfile(
    List<LatLng> waypoints, {
    double stepMetres = 100,
  }) {
    if (waypoints.length < 2 || !hasData) return [];

    final profile = <({double distKm, double elevM})>[];
    var cumDistM = 0.0;

    for (var i = 0; i < waypoints.length - 1; i++) {
      final from = waypoints[i];
      final to = waypoints[i + 1];
      final segDistM = _haversine(from, to);
      final steps = (segDistM / stepMetres).ceil().clamp(1, 500);

      for (var s = 0; s < steps; s++) {
        final t = s / steps;
        final lat = from.latitude + (to.latitude - from.latitude) * t;
        final lon = from.longitude + (to.longitude - from.longitude) * t;
        final elev = elevationAt(lat, lon);
        if (elev != null) {
          profile.add((distKm: (cumDistM + segDistM * t) / 1000, elevM: elev));
        }
      }
      cumDistM += segDistM;
    }

    // Add the last point
    final last = waypoints.last;
    final lastElev = elevationAt(last.latitude, last.longitude);
    if (lastElev != null) {
      profile.add((distKm: cumDistM / 1000, elevM: lastElev));
    }

    return profile;
  }

  static double _haversine(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final sq = math.pow(math.sin(dLat / 2), 2) +
        math.pow(math.sin(dLon / 2), 2) * math.cos(lat1) * math.cos(lat2);
    return r * 2.0 * math.asin(math.sqrt(sq.clamp(0.0, 1.0)));
  }
}
