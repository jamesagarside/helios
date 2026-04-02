import 'package:flutter/material.dart';
import '../../../core/telemetry/telemetry_store.dart';
import '../../../shared/theme/helios_colors.dart';

/// Aggregated fleet statistics across all recorded flights.
///
/// Opens each .duckdb file in turn, queries key stats, closes it, and
/// displays a summary header + per-flight table sorted by date.
class FleetDashboardPanel extends StatefulWidget {
  const FleetDashboardPanel({
    super.key,
    required this.store,
    required this.flights,
  });

  final TelemetryStore store;
  final List<FlightSummary> flights;

  @override
  State<FleetDashboardPanel> createState() => _FleetDashboardPanelState();
}

class _FleetDashboardPanelState extends State<FleetDashboardPanel> {
  List<_FlightStats>? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void didUpdateWidget(FleetDashboardPanel old) {
    super.didUpdateWidget(old);
    // Re-query if the flight list has changed (e.g. a new flight was added).
    if (old.flights.length != widget.flights.length) {
      setState(() {
        _stats = null;
        _loading = true;
        _error = null;
      });
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    try {
      final results = <_FlightStats>[];
      for (final flight in widget.flights) {
        try {
          results.add(await _queryFlight(flight));
        } catch (_) {
          // Skip corrupt/empty files — add a placeholder row.
          results.add(_FlightStats.empty(flight));
        }
      }
      if (!mounted) return;
      setState(() {
        _stats = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<_FlightStats> _queryFlight(FlightSummary flight) async {
    // Use the already-open connection when this is the live recording.
    final isOpen = widget.store.isRecording &&
        widget.store.currentFilePath == flight.filePath;

    Future<QueryResult> q(String sql) => isOpen
        ? widget.store.query(sql)
        : widget.store.queryFile(flight.filePath, sql);

    final timeRow = await q('''
      SELECT
        epoch_ms(MAX(ts)) - epoch_ms(MIN(ts)) AS duration_ms,
        MIN(ts) AS start_ts
      FROM attitude
    ''');

    final gpsRow = await q('''
      SELECT
        MAX(alt_rel)  AS max_alt_m,
        MAX(vel)      AS max_speed_ms,
        SUM(step_m)   AS total_dist_m
      FROM (
        SELECT
          alt_rel,
          vel,
          SQRT(
            POWER((lat - LAG(lat) OVER (ORDER BY ts)) * 111319, 2) +
            POWER((lon - LAG(lon) OVER (ORDER BY ts)) * 111319
                  * COS(RADIANS(lat)), 2)
          ) AS step_m
        FROM gps
      )
    ''');

    final battRow = await q('''
      SELECT
        MIN(remaining_pct) AS min_pct,
        MAX(consumed_mah)  AS mah
      FROM battery
    ''');

    double? durationSec;
    if (timeRow.rows.isNotEmpty) {
      final ms = timeRow.rows.first[0];
      if (ms != null) durationSec = (ms as num).toDouble() / 1000;
    }

    double? maxAlt;
    double? maxSpeedMs;
    double? distM;
    if (gpsRow.rows.isNotEmpty) {
      final r = gpsRow.rows.first;
      maxAlt = r[0] == null ? null : (r[0] as num).toDouble();
      maxSpeedMs = r[1] == null ? null : (r[1] as num).toDouble();
      distM = r[2] == null ? null : (r[2] as num).toDouble();
    }

    double? mah;
    int? minPct;
    if (battRow.rows.isNotEmpty) {
      final r = battRow.rows.first;
      minPct = r[0] == null ? null : (r[0] as num).toInt();
      mah = r[1] == null ? null : (r[1] as num).toDouble();
    }

    return _FlightStats(
      flight: flight,
      durationSec: durationSec,
      maxAltM: maxAlt,
      maxSpeedMs: maxSpeedMs,
      totalDistM: distM,
      mahConsumed: mah,
      minBattPct: minPct,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'Scanning ${widget.flights.length} flight${widget.flights.length == 1 ? '' : 's'}…',
              style: TextStyle(color: hc.textTertiary, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Text('Error: $_error',
            style: TextStyle(color: hc.danger, fontSize: 13)),
      );
    }

    final stats = _stats ?? [];
    if (stats.isEmpty) {
      return Center(
        child: Text(
          'No flights recorded yet.',
          style: TextStyle(color: hc.textTertiary, fontSize: 13),
        ),
      );
    }

    // Aggregates
    final totalFlights = stats.length;
    final totalSec = stats
        .map((s) => s.durationSec ?? 0)
        .fold<double>(0, (a, b) => a + b);
    final totalDistKm = stats
        .map((s) => (s.totalDistM ?? 0) / 1000)
        .fold<double>(0, (a, b) => a + b);
    final totalMah = stats
        .map((s) => s.mahConsumed ?? 0)
        .fold<double>(0, (a, b) => a + b);
    final maxAltEver = stats
        .map((s) => s.maxAltM ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final maxSpeedEver = stats
        .map((s) => s.maxSpeedMs ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Aggregate header ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          color: hc.surface,
          child: Row(
            children: [
              _StatTile(
                label: 'Total Flights',
                value: '$totalFlights',
                icon: Icons.flight_takeoff,
              ),
              _Divider(),
              _StatTile(
                label: 'Total Flight Time',
                value: _formatDuration(totalSec),
                icon: Icons.schedule,
              ),
              _Divider(),
              _StatTile(
                label: 'Total Distance',
                value: totalDistKm >= 1
                    ? '${totalDistKm.toStringAsFixed(1)} km'
                    : '${(totalDistKm * 1000).toStringAsFixed(0)} m',
                icon: Icons.route,
              ),
              _Divider(),
              _StatTile(
                label: 'Battery Consumed',
                value: totalMah >= 1000
                    ? '${(totalMah / 1000).toStringAsFixed(1)} Ah'
                    : '${totalMah.toStringAsFixed(0)} mAh',
                icon: Icons.battery_charging_full,
              ),
              _Divider(),
              _StatTile(
                label: 'Max Altitude',
                value: '${maxAltEver.toStringAsFixed(0)} m',
                icon: Icons.trending_up,
              ),
              _Divider(),
              _StatTile(
                label: 'Max Speed',
                value: '${maxSpeedEver.toStringAsFixed(1)} m/s',
                icon: Icons.speed,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: hc.border),

        // ── Column headers ────────────────────────────────────────────────
        Container(
          height: 28,
          color: hc.surfaceDim,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: _headerCells(hc)),
        ),
        Divider(height: 1, color: hc.border),

        // ── Per-flight rows ───────────────────────────────────────────────
        Expanded(
          child: ListView.separated(
            itemCount: stats.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: hc.border),
            itemBuilder: (context, i) {
              final s = stats[i];
              return _FlightRow(stats: s);
            },
          ),
        ),
      ],
    );
  }

  static List<Widget> _headerCells(HeliosColors hc) {
    final labels = [
      ('Date', 2.0),
      ('Duration', 1.0),
      ('Max Alt', 1.0),
      ('Max Speed', 1.0),
      ('Distance', 1.0),
      ('Battery', 1.0),
      ('Min %', 0.8),
    ];
    return labels
        .map((l) => Expanded(
              flex: (l.$2 * 10).toInt(),
              child: Text(
                l.$1,
                style: TextStyle(
                    color: hc.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
            ))
        .toList();
  }

  static String _formatDuration(double secs) {
    final h = (secs / 3600).floor();
    final m = ((secs % 3600) / 60).floor();
    final s = (secs % 60).floor();
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

class _FlightRow extends StatelessWidget {
  const _FlightRow({required this.stats});
  final _FlightStats stats;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final s = stats;
    final dateStr = s.flight.startTime != null
        ? '${s.flight.startTime!.year}-'
          '${s.flight.startTime!.month.toString().padLeft(2, '0')}-'
          '${s.flight.startTime!.day.toString().padLeft(2, '0')} '
          '${s.flight.startTime!.hour.toString().padLeft(2, '0')}:'
          '${s.flight.startTime!.minute.toString().padLeft(2, '0')}'
        : s.flight.fileName;

    final durStr = s.durationSec != null
        ? _formatDuration(s.durationSec!)
        : '—';
    final altStr = s.maxAltM != null
        ? '${s.maxAltM!.toStringAsFixed(0)} m'
        : '—';
    final speedStr = s.maxSpeedMs != null
        ? '${s.maxSpeedMs!.toStringAsFixed(1)} m/s'
        : '—';
    final distStr = s.totalDistM != null
        ? s.totalDistM! >= 1000
            ? '${(s.totalDistM! / 1000).toStringAsFixed(1)} km'
            : '${s.totalDistM!.toStringAsFixed(0)} m'
        : '—';
    final mahStr = s.mahConsumed != null
        ? '${s.mahConsumed!.toStringAsFixed(0)} mAh'
        : '—';
    final pctStr = s.minBattPct != null ? '${s.minBattPct}%' : '—';
    final pctColor = s.minBattPct == null
        ? hc.textTertiary
        : s.minBattPct! >= 20
            ? hc.success
            : s.minBattPct! >= 10
                ? hc.warning
                : hc.danger;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 20,
            child: Text(dateStr,
                style: TextStyle(color: hc.textPrimary, fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 10,
            child: Text(durStr,
                style: TextStyle(color: hc.textSecondary, fontSize: 12)),
          ),
          Expanded(
            flex: 10,
            child: Text(altStr,
                style: TextStyle(color: hc.textSecondary, fontSize: 12)),
          ),
          Expanded(
            flex: 10,
            child: Text(speedStr,
                style: TextStyle(color: hc.textSecondary, fontSize: 12)),
          ),
          Expanded(
            flex: 10,
            child: Text(distStr,
                style: TextStyle(color: hc.textSecondary, fontSize: 12)),
          ),
          Expanded(
            flex: 10,
            child: Text(mahStr,
                style: TextStyle(color: hc.textSecondary, fontSize: 12)),
          ),
          Expanded(
            flex: 8,
            child: Text(pctStr,
                style: TextStyle(
                    color: pctColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(double secs) {
    final h = (secs / 3600).floor();
    final m = ((secs % 3600) / 60).floor();
    final s = (secs % 60).floor();
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _FlightStats {
  _FlightStats({
    required this.flight,
    this.durationSec,
    this.maxAltM,
    this.maxSpeedMs,
    this.totalDistM,
    this.mahConsumed,
    this.minBattPct,
  });

  factory _FlightStats.empty(FlightSummary flight) =>
      _FlightStats(flight: flight);

  final FlightSummary flight;
  final double? durationSec;
  final double? maxAltM;
  final double? maxSpeedMs;
  final double? totalDistM;
  final double? mahConsumed;
  final int? minBattPct;
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: hc.accent),
              const SizedBox(width: 4),
              Text(label,
                  style:
                      TextStyle(color: hc.textTertiary, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: hc.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: hc.border,
    );
  }
}
