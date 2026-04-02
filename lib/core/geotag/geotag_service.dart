import 'dart:io';
import 'package:image/image.dart' as img;
import '../../core/telemetry/telemetry_store.dart';

/// Result for a single image in a geotagging batch.
class GeotagResult {
  const GeotagResult({
    required this.imagePath,
    required this.success,
    this.lat,
    this.lon,
    this.altM,
    this.errorMessage,
  });

  final String imagePath;
  final bool success;
  final double? lat;
  final double? lon;
  final double? altM;
  final String? errorMessage;

  String get filename => imagePath.split(Platform.pathSeparator).last;
}

/// Matches images to GPS positions from a DuckDB flight file by EXIF timestamp,
/// then writes GPS EXIF tags back into the JPEG files.
///
/// Strategy:
/// 1. Read EXIF DateTimeOriginal from each image.
/// 2. Query the DuckDB GPS table for the nearest timestamp within [maxDeltaSecs].
/// 3. Write GPSLatitude/GPSLongitude/GPSAltitude into the image and overwrite.
class GeotagService {
  /// Maximum allowed difference between photo timestamp and GPS fix.
  static const int maxDeltaSecs = 5;

  /// Geotag [imagePaths] using GPS data from the flight at [dbPath].
  ///
  /// [timeOffsetSecs] can compensate for camera clock drift.
  Future<List<GeotagResult>> geotag({
    required List<String> imagePaths,
    required String dbPath,
    int timeOffsetSecs = 0,
  }) async {
    // Load full GPS track from the flight file
    final track = await _loadGpsTrack(dbPath);
    if (track.isEmpty) {
      return imagePaths
          .map((p) => GeotagResult(
                imagePath: p,
                success: false,
                errorMessage: 'No GPS track in flight file',
              ))
          .toList();
    }

    final results = <GeotagResult>[];
    for (final path in imagePaths) {
      results.add(await _geotagOne(path, track, timeOffsetSecs));
    }
    return results;
  }

  Future<GeotagResult> _geotagOne(
    String path,
    List<_GpsPoint> track,
    int timeOffsetSecs,
  ) async {
    try {
      final bytes = await File(path).readAsBytes();
      final image = img.decodeJpg(bytes);
      if (image == null) {
        return GeotagResult(
          imagePath: path,
          success: false,
          errorMessage: 'Could not decode JPEG',
        );
      }

      // Read EXIF timestamp
      final exif = image.exif;
      final dtStr = _readExifDateTime(exif);
      if (dtStr == null) {
        return GeotagResult(
          imagePath: path,
          success: false,
          errorMessage: 'No DateTimeOriginal EXIF tag',
        );
      }

      final photoTime = _parseExifDateTime(dtStr);
      if (photoTime == null) {
        return GeotagResult(
          imagePath: path,
          success: false,
          errorMessage: 'Could not parse EXIF datetime: $dtStr',
        );
      }

      final adjusted = photoTime.add(Duration(seconds: timeOffsetSecs));

      // Find nearest GPS fix
      final match = _findNearest(track, adjusted);
      if (match == null) {
        return GeotagResult(
          imagePath: path,
          success: false,
          errorMessage: 'No GPS fix within ${maxDeltaSecs}s of $dtStr',
        );
      }

      // Write GPS EXIF
      _writeGpsExif(exif, match.lat, match.lon, match.altM);

      // Re-encode and overwrite
      final encoded = img.encodeJpg(image, quality: 95);
      await File(path).writeAsBytes(encoded);

      return GeotagResult(
        imagePath: path,
        success: true,
        lat: match.lat,
        lon: match.lon,
        altM: match.altM,
      );
    } catch (e) {
      return GeotagResult(
        imagePath: path,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Read DateTimeOriginal (0x9003) or DateTime (0x0132) from EXIF.
  String? _readExifDateTime(img.ExifData exif) {
    final ifd = exif['ifd0'];
    // DateTimeOriginal is in exif sub-IFD (tag 0x9003)
    final exifIfd = ifd.sub['exif'];
    final dto = exifIfd[0x9003];
    if (dto != null) return dto.toData().toString();
    // Fallback to DateTime tag (0x0132)
    final dt = ifd[0x0132];
    if (dt != null) return dt.toData().toString();
    return null;
  }

  /// Parse EXIF datetime string "YYYY:MM:DD HH:MM:SS" into [DateTime].
  DateTime? _parseExifDateTime(String s) {
    try {
      // Format: "2024:06:15 14:32:01"
      final parts = s.trim().split(' ');
      if (parts.length != 2) return null;
      final dateParts = parts[0].split(':');
      final timeParts = parts[1].split(':');
      if (dateParts.length != 3 || timeParts.length != 3) return null;
      return DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
        int.parse(timeParts[2]),
      );
    } catch (_) {
      return null;
    }
  }

  _GpsPoint? _findNearest(List<_GpsPoint> track, DateTime t) {
    _GpsPoint? best;
    var bestDelta = maxDeltaSecs + 1;
    for (final p in track) {
      final delta = (p.ts.difference(t).inSeconds).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        best = p;
      }
    }
    return bestDelta <= maxDeltaSecs ? best : null;
  }

  void _writeGpsExif(img.ExifData exif, double lat, double lon, double altM) {
    final gps = exif.gpsIfd;

    // Latitude ref and value
    gps[0x0001] = lat >= 0 ? 'N' : 'S';
    gps[0x0002] = _dmsRational(lat.abs());

    // Longitude ref and value
    gps[0x0003] = lon >= 0 ? 'E' : 'W';
    gps[0x0004] = _dmsRational(lon.abs());

    // Altitude ref (0 = above sea level) and value
    gps[0x0005] = 0;
    final altVal = img.IfdValueRational((altM * 100).round(), 100);
    gps[0x0006] = altVal;
  }

  /// Convert decimal degrees to a 3-element IfdValueRational [D, M, S].
  img.IfdValueRational _dmsRational(double deg) {
    final d = deg.floor();
    final mFrac = (deg - d) * 60;
    final m = mFrac.floor();
    final s = (mFrac - m) * 60;
    final val = img.IfdValueRational(d, 1);
    val.setRational(m, 1, 1);
    val.setRational((s * 10000).round(), 10000, 2);
    return val;
  }

  /// Load GPS track from DuckDB flight file as a time-sorted list.
  Future<List<_GpsPoint>> _loadGpsTrack(String dbPath) async {
    try {
      final store = TelemetryStore();
      final result = await store.queryFile(
        dbPath,
        'SELECT ts, lat, lon, alt_msl FROM gps ORDER BY ts',
      );
      return result.rows.map((row) {
        final ts = row[0] is DateTime
            ? row[0] as DateTime
            : DateTime.parse(row[0].toString());
        return _GpsPoint(
          ts: ts,
          lat: (row[1] as num).toDouble(),
          lon: (row[2] as num).toDouble(),
          altM: (row[3] as num).toDouble(),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}

class _GpsPoint {
  const _GpsPoint({
    required this.ts,
    required this.lat,
    required this.lon,
    required this.altM,
  });

  final DateTime ts;
  final double lat;
  final double lon;
  final double altM;
}
