import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Manages downloading, caching, and launching ArduPilot SITL binaries.
///
/// Platform: macOS, Linux (native binaries). Windows support planned.
///
/// Binaries are downloaded on-demand from the ArduPilot firmware server and
/// cached locally per vehicle type and version. Only the vehicles the user
/// actually flies are downloaded, keeping disk usage minimal.
class SitlLauncher {
  Process? _process;

  /// Whether the SITL process is currently running.
  bool get isRunning => _process != null;

  // ─── Vehicle / frame catalogue ─────────────────────────────────────────────

  /// Supported ArduPilot vehicle types.
  static const List<String> vehicles = [
    'ArduCopter',
    'ArduPlane',
    'ArduRover',
    'ArduSub',
    'ArduHeli',
  ];

  /// Binary name per vehicle type (as named on firmware.ardupilot.org).
  static const Map<String, String> _binaryNames = {
    'ArduCopter': 'arducopter',
    'ArduPlane': 'arduplane',
    'ArduRover': 'ardurover',
    'ArduSub': 'ardusub',
    'ArduHeli': 'arducopter',
  };

  /// Airframe variants per vehicle type.
  static Map<String, List<String>> get frames => {
        'ArduCopter': ['quad', 'X', '+', 'hex', 'octa', 'Y6', 'heli'],
        'ArduPlane': ['plane', 'quadplane'],
        'ArduRover': ['rover', 'boat'],
        'ArduSub': ['vectored'],
        'ArduHeli': ['heli'],
      };

  // ─── Predefined start locations ────────────────────────────────────────────

  /// Predefined SITL start locations.
  ///
  /// The last entry uses lat/lon of 0/0 as a sentinel for "Custom" - callers
  /// should present a custom coordinate entry form when it is selected.
  static const List<SitlLocation> locations = [
    SitlLocation('CMAC (Canberra, AU)', -35.3632, 149.1652, 353),
    SitlLocation('Duxford (UK)', 52.0908, 0.1319, 0),
    SitlLocation('San Francisco Bay', 37.4137, -122.0160, 270),
    SitlLocation('Sydney Airport', -33.9399, 151.1753, 70),
    SitlLocation('Custom...', 0, 0, 0),
  ];

  // ─── Binary management ────────────────────────────────────────────────────

  /// The current ArduPilot SITL version to download.
  static const String sitlVersion = 'stable';

  /// Base URL for SITL binary downloads.
  static const String _firmwareBaseUrl = 'https://firmware.ardupilot.org';

  /// Get the SITL binary cache directory.
  static Future<String> _cacheDir() async {
    final appDir = await getApplicationSupportDirectory();
    return p.join(appDir.path, 'sitl_binaries');
  }

  /// Get the platform identifier for firmware downloads.
  static String get _platformId {
    if (Platform.isMacOS) return 'SITL_arm_cxx-macosx';
    if (Platform.isLinux) return 'SITL_x86_64_linux_gnu';
    // Windows SITL requires Cygwin - not yet supported
    throw UnsupportedError('SITL binaries are not available for this platform');
  }

  /// Returns the local path where a vehicle binary is cached.
  static Future<String> _binaryPath(String vehicle) async {
    final cache = await _cacheDir();
    final binaryName = _binaryNames[vehicle] ?? vehicle.toLowerCase();
    return p.join(cache, vehicle, sitlVersion, binaryName);
  }

  /// Check if the SITL binary for a vehicle is already cached.
  static Future<bool> isCached(String vehicle) async {
    final path = await _binaryPath(vehicle);
    return File(path).existsSync();
  }

  /// List all cached vehicle types with their sizes.
  static Future<Map<String, int>> cachedVehicles() async {
    final cache = await _cacheDir();
    final dir = Directory(cache);
    if (!dir.existsSync()) return {};

    final result = <String, int>{};
    for (final vehicle in vehicles) {
      final path = await _binaryPath(vehicle);
      final file = File(path);
      if (file.existsSync()) {
        result[vehicle] = file.lengthSync();
      }
    }
    return result;
  }

  /// Delete the cached binary for a vehicle.
  static Future<void> deleteCached(String vehicle) async {
    final cache = await _cacheDir();
    final vehicleDir = Directory(p.join(cache, vehicle));
    if (vehicleDir.existsSync()) {
      await vehicleDir.delete(recursive: true);
    }
  }

  /// Download the SITL binary for the given vehicle type.
  ///
  /// Reports progress via [onProgress] as a 0.0-1.0 fraction.
  /// Returns the local path to the downloaded binary.
  static Future<String> downloadBinary({
    required String vehicle,
    void Function(double progress)? onProgress,
  }) async {
    final binaryName = _binaryNames[vehicle] ?? vehicle.toLowerCase();
    final url = '$_firmwareBaseUrl/$vehicle/$sitlVersion/$_platformId/$binaryName';

    final localPath = await _binaryPath(vehicle);
    final localFile = File(localPath);

    // Ensure directory exists
    final dir = Directory(p.dirname(localPath));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Download
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw SitlLaunchException(
          'Failed to download $vehicle SITL binary.\n'
          'HTTP ${response.statusCode} from $url',
        );
      }

      final contentLength = response.contentLength;
      int received = 0;

      final sink = localFile.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          onProgress?.call(received / contentLength);
        }
      }
      await sink.close();

      // Make executable on macOS/Linux
      if (Platform.isMacOS || Platform.isLinux) {
        await Process.run('chmod', ['+x', localPath]);
      }

      return localPath;
    } finally {
      client.close();
    }
  }

  // ─── Launch / stop ─────────────────────────────────────────────────────────

  /// Launches the SITL binary directly (no Docker required).
  ///
  /// Downloads the binary first if not cached. Streams stdout/stderr to
  /// [onLog]. Calls [onExit] when the process terminates.
  ///
  /// Throws [SitlLaunchException] if the binary cannot be started.
  Future<void> launch({
    required String vehicle,
    required String frame,
    required double lat,
    required double lon,
    required double altM,
    required double headingDeg,
    required void Function(String line) onLog,
    required void Function() onExit,
    void Function(double progress)? onDownloadProgress,
  }) async {
    if (_process != null) {
      throw SitlLaunchException('SITL is already running. Call stop() first.');
    }

    // Ensure binary is available
    final cached = await isCached(vehicle);
    String binaryPath;

    if (!cached) {
      onLog('Downloading $vehicle SITL binary...');
      try {
        binaryPath = await downloadBinary(
          vehicle: vehicle,
          onProgress: (p) {
            onDownloadProgress?.call(p);
            onLog('Download: ${(p * 100).toStringAsFixed(0)}%');
          },
        );
        onLog('Download complete.');
      } catch (e) {
        throw SitlLaunchException('Failed to download SITL binary: $e');
      }
    } else {
      binaryPath = await _binaryPath(vehicle);
    }

    // Build arguments
    final args = [
      '--model',
      frame,
      '--home',
      '$lat,$lon,$altM,$headingDeg',
      '--speedup',
      '1',
    ];

    try {
      _process = await Process.start(binaryPath, args);
    } on ProcessException catch (e) {
      throw SitlLaunchException(
        'Failed to start SITL binary.\nError: ${e.message}',
      );
    }

    // Stream stdout
    _process!.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) => onLog(line));

    // Stream stderr
    _process!.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) => onLog(line));

    // Handle process exit
    _process!.exitCode.then((_) {
      _process = null;
      onExit();
    });
  }

  /// Terminates the SITL process.
  Future<void> stop() async {
    final proc = _process;
    _process = null;
    if (proc != null) {
      proc.kill(ProcessSignal.sigterm);
      // Give a moment for graceful shutdown, then force-kill.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      proc.kill(ProcessSignal.sigkill);
    }
  }
}

// ─── Value types ──────────────────────────────────────────────────────────────

/// A named SITL start location.
class SitlLocation {
  const SitlLocation(this.name, this.lat, this.lon, this.heading);

  final String name;
  final double lat;
  final double lon;
  final double heading;

  /// True when this entry represents the custom coordinate option.
  bool get isCustom => lat == 0 && lon == 0 && name.startsWith('Custom');
}

// ─── Exceptions ───────────────────────────────────────────────────────────────

/// Thrown when the SITL process cannot be started.
class SitlLaunchException implements Exception {
  const SitlLaunchException(this.message);

  final String message;

  @override
  String toString() => 'SitlLaunchException: $message';
}
