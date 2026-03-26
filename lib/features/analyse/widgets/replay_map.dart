import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/map/cached_tile_provider.dart';
import '../../../core/telemetry/telemetry_store.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// A flight replay map that shows the full GPS track with a moving vehicle
/// marker synchronised to the shared [crosshairX] timeline position.
class ReplayMap extends StatefulWidget {
  const ReplayMap({
    super.key,
    required this.store,
    required this.crosshairX,
  });

  final TelemetryStore store;
  final ValueNotifier<double?> crosshairX;

  @override
  State<ReplayMap> createState() => _ReplayMapState();
}

class _ReplayMapState extends State<ReplayMap> {
  final MapController _mapController = MapController();
  bool _mapReady = false;
  bool _loading = true;

  /// GPS track: each entry is (timeSeconds, lat, lon).
  List<_GpsPoint> _track = [];

  @override
  void initState() {
    super.initState();
    _loadTrack();
  }

  Future<void> _loadTrack() async {
    try {
      final result = await widget.store.query(
        'SELECT ts, lat, lon FROM gps ORDER BY ts',
      );
      if (result.rowCount == 0) {
        setState(() => _loading = false);
        return;
      }

      final startTime = _parseTimestamp(result.rows.first[0]);
      final points = <_GpsPoint>[];
      for (final row in result.rows) {
        final ts = _parseTimestamp(row[0]);
        final timeSec = ts.difference(startTime).inMilliseconds / 1000.0;
        final lat = (row[1] as num?)?.toDouble() ?? 0;
        final lon = (row[2] as num?)?.toDouble() ?? 0;
        if (lat != 0 || lon != 0) {
          points.add(_GpsPoint(timeSec, lat, lon));
        }
      }

      setState(() {
        _track = points;
        _loading = false;
      });

      // Fit bounds to track
      if (_mapReady && points.length >= 2) {
        _fitBounds();
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _fitBounds() {
    if (_track.length < 2) return;
    final bounds = LatLngBounds.fromPoints(
      _track.map((p) => LatLng(p.lat, p.lon)).toList(),
    );
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(32),
        ),
      );
    } catch (_) {}
  }

  DateTime _parseTimestamp(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString()) ?? DateTime.now();
  }

  /// Find the GPS point closest to [timeSeconds] using binary search.
  _GpsPoint? _pointAtTime(double timeSeconds) {
    if (_track.isEmpty) return null;
    var lo = 0;
    var hi = _track.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_track[mid].timeSec < timeSeconds) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo > 0 &&
        (timeSeconds - _track[lo - 1].timeSec).abs() <
            (_track[lo].timeSec - timeSeconds).abs()) {
      return _track[lo - 1];
    }
    return _track[lo];
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    if (_loading) {
      return Container(
        height: 200,
        color: hc.surfaceDim,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_track.length < 2) {
      return Container(
        height: 48,
        color: hc.surfaceDim,
        alignment: Alignment.center,
        child: Text('No GPS data for map replay',
            style: HeliosTypography.caption
                .copyWith(color: hc.textTertiary)),
      );
    }

    final trackPoints = _track.map((p) => LatLng(p.lat, p.lon)).toList();
    final homePos = trackPoints.first;
    final landPos = trackPoints.last;

    return SizedBox(
      height: 250,
      child: ValueListenableBuilder<double?>(
        valueListenable: widget.crosshairX,
        builder: (context, cx, _) {
          final vehiclePoint = cx != null ? _pointAtTime(cx) : null;

          return FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: homePos,
              initialZoom: 16,
              onMapReady: () {
                _mapReady = true;
                _fitBounds();
              },
            ),
            children: [
              // Dark OSM tiles
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.argus.helios_gcs',
                maxZoom: 19,
                tileProvider: CachedTileProvider(),
                tileBuilder: _darkTileBuilder,
              ),

              // Full flight path
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: trackPoints,
                    color: hc.accent.withValues(alpha: 0.6),
                    strokeWidth: 2.5,
                  ),
                ],
              ),

              // Traversed portion (if crosshair active)
              if (vehiclePoint != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _track
                          .where((p) => p.timeSec <= cx!)
                          .map((p) => LatLng(p.lat, p.lon))
                          .toList(),
                      color: hc.accent,
                      strokeWidth: 3,
                    ),
                  ],
                ),

              // Home marker
              MarkerLayer(
                markers: [
                  Marker(
                    point: homePos,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hc.success.withValues(alpha: 0.2),
                        border: Border.all(color: hc.success, width: 2),
                      ),
                      child: Center(
                        child: Icon(Icons.home,
                            size: 12, color: hc.success),
                      ),
                    ),
                  ),
                ],
              ),

              // Landing marker
              MarkerLayer(
                markers: [
                  Marker(
                    point: landPos,
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hc.warning.withValues(alpha: 0.2),
                        border: Border.all(color: hc.warning, width: 2),
                      ),
                      child: Center(
                        child: Icon(Icons.flight_land,
                            size: 12, color: hc.warning),
                      ),
                    ),
                  ),
                ],
              ),

              // Vehicle position at crosshair time
              if (vehiclePoint != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point:
                          LatLng(vehiclePoint.lat, vehiclePoint.lon),
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hc.accent,
                          border: Border.all(
                              color: hc.textPrimary, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: hc.accent.withValues(alpha: 0.5),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _darkTileBuilder(
      BuildContext context, Widget tileWidget, TileImage tile) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        -0.5, 0, 0, 0, 128,
        0, -0.5, 0, 0, 128,
        0, 0, -0.5, 0, 128,
        0, 0, 0, 1, 0,
      ]),
      child: tileWidget,
    );
  }
}

class _GpsPoint {
  const _GpsPoint(this.timeSec, this.lat, this.lon);
  final double timeSec;
  final double lat;
  final double lon;
}
