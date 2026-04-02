import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/telemetry/telemetry_store.dart';
import '../../../shared/theme/helios_colors.dart';
import '../../../shared/theme/helios_typography.dart';

/// Auto-generated flight scorecard based on DuckDB telemetry queries.
///
/// Runs four independent queries (GPS, battery, vibration, attitude) against
/// the currently-open flight in [store] and produces a 0–100 scorecard.
class FlightScorePanel extends StatefulWidget {
  const FlightScorePanel({
    super.key,
    required this.store,
    required this.filePath,
  });

  final TelemetryStore store;

  /// The file path of the flight to score. Used as a key so that the widget
  /// re-runs scoring whenever the selected flight changes.
  final String filePath;

  @override
  State<FlightScorePanel> createState() => _FlightScorePanelState();
}

class _FlightScorePanelState extends State<FlightScorePanel> {
  _ScoreResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runScoring();
  }

  @override
  void didUpdateWidget(FlightScorePanel old) {
    super.didUpdateWidget(old);
    if (old.filePath != widget.filePath) {
      setState(() {
        _result = null;
        _loading = true;
        _error = null;
      });
      _runScoring();
    }
  }

  Future<void> _runScoring() async {
    try {
      final store = widget.store;

      Future<Map<String, dynamic>> fetchFirst(String sql) async {
        final qr = await store.query(sql);
        if (qr.rows.isEmpty) return {};
        final row = <String, dynamic>{};
        for (var i = 0; i < qr.columnNames.length; i++) {
          row[qr.columnNames[i]] = qr.rows.first[i];
        }
        return row;
      }

      final gpsRow = await fetchFirst('''
        SELECT
          COALESCE(AVG(hdop), -1)              AS avg_hdop,
          COALESCE(AVG(satellites), -1)        AS avg_sat,
          COALESCE(MIN(satellites), -1)        AS min_sat,
          CASE WHEN COUNT(*) > 0
               THEN SUM(CASE WHEN fix_type >= 3 THEN 1.0 ELSE 0.0 END)
                    * 100.0 / COUNT(*)
               ELSE -1 END                    AS pct_fix3
        FROM gps
      ''');

      final battRow = await fetchFirst('''
        SELECT
          COALESCE(MIN(remaining_pct), -1)         AS min_pct,
          COALESCE(MAX(voltage) - MIN(voltage), -1) AS sag_v,
          COALESCE(MAX(consumed_mah), -1)           AS total_mah
        FROM battery
      ''');

      final vibeRow = await fetchFirst('''
        SELECT
          COALESCE(AVG((vibe_x + vibe_y + vibe_z) / 3.0), -1) AS avg_vibe,
          COALESCE(MAX(vibe_x), -1)    AS max_x,
          COALESCE(MAX(vibe_y), -1)    AS max_y,
          COALESCE(MAX(vibe_z), -1)    AS max_z,
          COALESCE(SUM(clip_0 + clip_1 + clip_2), -1) AS clips
        FROM vibration
      ''');

      final attRow = await fetchFirst('''
        SELECT
          COALESCE(STDDEV_SAMP(roll_spd)  * 180.0 / ${math.pi}, -1) AS roll_rate_sd,
          COALESCE(STDDEV_SAMP(pitch_spd) * 180.0 / ${math.pi}, -1) AS pitch_rate_sd,
          COALESCE(MAX(ABS(roll))  * 180.0 / ${math.pi}, -1)        AS max_roll_deg,
          COALESCE(MAX(ABS(pitch)) * 180.0 / ${math.pi}, -1)        AS max_pitch_deg
        FROM attitude
      ''');

      if (!mounted) return;
      setState(() {
        _result = _ScoreResult.compute(gpsRow, battRow, vibeRow, attRow);
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

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Scoring failed: $_error',
            style: TextStyle(color: hc.danger, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final r = _result!;
    final total = r.total;
    final gradeColor = _gradeColor(total, hc);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ScoreHeader(score: total, grade: _grade(total), gradeColor: gradeColor),
          const SizedBox(height: 12),
          _CategoryCard(
            icon: Icons.satellite_alt,
            label: 'GPS Quality',
            score: r.gpsScore,
            color: _categoryColor(r.gpsScore, 25, hc),
            metrics: r.gpsMetrics,
            note: r.gpsNote,
          ),
          const SizedBox(height: 8),
          _CategoryCard(
            icon: Icons.battery_charging_full,
            label: 'Battery Management',
            score: r.battScore,
            color: _categoryColor(r.battScore, 25, hc),
            metrics: r.battMetrics,
            note: r.battNote,
          ),
          const SizedBox(height: 8),
          _CategoryCard(
            icon: Icons.vibration,
            label: 'Vibration',
            score: r.vibeScore,
            color: _categoryColor(r.vibeScore, 25, hc),
            metrics: r.vibeMetrics,
            note: r.vibeNote,
          ),
          const SizedBox(height: 8),
          _CategoryCard(
            icon: Icons.track_changes,
            label: 'Attitude Stability',
            score: r.attScore,
            color: _categoryColor(r.attScore, 25, hc),
            metrics: r.attMetrics,
            note: r.attNote,
          ),
        ],
      ),
    );
  }

  static String _grade(int score) {
    if (score >= 90) return 'A';
    if (score >= 75) return 'B';
    if (score >= 60) return 'C';
    if (score >= 45) return 'D';
    return 'F';
  }

  static Color _gradeColor(int score, HeliosColors hc) {
    if (score >= 75) return hc.success;
    if (score >= 45) return hc.warning;
    return hc.danger;
  }

  static Color _categoryColor(int score, int max, HeliosColors hc) {
    final pct = score / max;
    if (pct >= 0.75) return hc.success;
    if (pct >= 0.45) return hc.warning;
    return hc.danger;
  }
}

// ─── Score computation ────────────────────────────────────────────────────────

class _ScoreResult {
  _ScoreResult({
    required this.gpsScore,
    required this.battScore,
    required this.vibeScore,
    required this.attScore,
    required this.gpsMetrics,
    required this.battMetrics,
    required this.vibeMetrics,
    required this.attMetrics,
    this.gpsNote,
    this.battNote,
    this.vibeNote,
    this.attNote,
  });

  final int gpsScore;
  final int battScore;
  final int vibeScore;
  final int attScore;

  final List<_Metric> gpsMetrics;
  final List<_Metric> battMetrics;
  final List<_Metric> vibeMetrics;
  final List<_Metric> attMetrics;

  final String? gpsNote;
  final String? battNote;
  final String? vibeNote;
  final String? attNote;

  int get total => gpsScore + battScore + vibeScore + attScore;

  factory _ScoreResult.compute(
    Map<String, dynamic> gps,
    Map<String, dynamic> batt,
    Map<String, dynamic> vibe,
    Map<String, dynamic> att,
  ) {
    // ── GPS (0–25 pts) ───────────────────────────────────────────────────────
    final avgHdop = _d(gps['avg_hdop']);
    final avgSat  = _d(gps['avg_sat']);
    final minSat  = _d(gps['min_sat']);
    final pctFix3 = _d(gps['pct_fix3']);

    int gpsScore;
    String? gpsNote;

    if (avgHdop < 0) {
      gpsScore = 12;
      gpsNote = 'No GPS data recorded.';
    } else {
      // HDOP: 0–15 pts
      final hdopPts = avgHdop <= 0.8 ? 15
          : avgHdop <= 1.2 ? 13
          : avgHdop <= 1.5 ? 10
          : avgHdop <= 2.0 ? 7
          : avgHdop <= 3.0 ? 4
          : 1;
      if (avgHdop > 3.0) {
        gpsNote = 'High HDOP (${avgHdop.toStringAsFixed(1)}) — poor satellite geometry.';
      }

      // Satellites: 0–7 pts
      final satPts = avgSat >= 14 ? 7
          : avgSat >= 10 ? 6
          : avgSat >= 8  ? 5
          : avgSat >= 6  ? 3
          : 1;
      if (avgSat < 6) {
        gpsNote ??= 'Low satellite count (avg ${avgSat.toStringAsFixed(0)}).';
      }

      // Fix: 0–3 pts
      final fixPts = pctFix3 >= 99 ? 3
          : pctFix3 >= 95 ? 2
          : pctFix3 >= 80 ? 1
          : 0;
      if (pctFix3 >= 0 && pctFix3 < 95) {
        gpsNote ??= '${(100 - pctFix3).toStringAsFixed(0)}% of time without a 3D fix.';
      }

      gpsScore = (hdopPts + satPts + fixPts).clamp(0, 25);
    }

    // ── Battery (0–25 pts) ───────────────────────────────────────────────────
    final minPct   = _d(batt['min_pct']);
    final sagV     = _d(batt['sag_v']);
    final totalMah = _d(batt['total_mah']);

    int battScore;
    String? battNote;

    if (minPct < 0) {
      battScore = 12;
      battNote = 'No battery data recorded.';
    } else {
      // Landing %: 0–18 pts
      final pctPts = minPct >= 40 ? 18
          : minPct >= 30 ? 15
          : minPct >= 20 ? 11
          : minPct >= 15 ? 7
          : minPct >= 10 ? 3
          : 0;
      if (minPct < 15) {
        battNote = minPct < 10
            ? 'Critical landing battery: ${minPct.toStringAsFixed(0)}%.'
            : 'Low landing battery: ${minPct.toStringAsFixed(0)}%.';
      }

      // Voltage sag: 0–7 pts (lower = healthier cells)
      final sagPts = sagV < 0 ? 4
          : sagV <= 0.3 ? 7
          : sagV <= 0.6 ? 5
          : sagV <= 1.0 ? 3
          : 1;
      if (sagV > 1.0) {
        battNote ??= 'High voltage sag: ${sagV.toStringAsFixed(2)} V.';
      }

      battScore = (pctPts + sagPts).clamp(0, 25);
    }

    // ── Vibration (0–25 pts) ─────────────────────────────────────────────────
    final avgVibe = _d(vibe['avg_vibe']);
    final maxX    = _d(vibe['max_x']);
    final maxY    = _d(vibe['max_y']);
    final maxZ    = _d(vibe['max_z']);
    final clips   = vibe['clips'] == null ? -1 : switch (vibe['clips']) {
      BigInt v => v.toInt(),
      num v    => v.toInt(),
      _        => -1,
    };

    int vibeScore;
    String? vibeNote;

    if (avgVibe < 0) {
      vibeScore = 12;
      vibeNote = 'No vibration data recorded.';
    } else {
      // avg vibe (ArduPilot threshold ~30 m/s²): 0–20 pts
      final vibePts = avgVibe <= 5  ? 20
          : avgVibe <= 10 ? 17
          : avgVibe <= 20 ? 13
          : avgVibe <= 30 ? 8
          : 3;
      if (avgVibe > 20) {
        vibeNote = avgVibe > 30
            ? 'High vibration (avg ${avgVibe.toStringAsFixed(1)} m/s²) — check prop balance.'
            : 'Elevated vibration (avg ${avgVibe.toStringAsFixed(1)} m/s²).';
      }

      // Clipping: 0–5 pts
      final clipPts = clips <= 0 ? 5
          : clips <= 2  ? 3
          : clips <= 10 ? 1
          : 0;
      if (clips > 0) {
        vibeNote ??= clips > 10
            ? 'Severe clipping: $clips events — IMU saturation likely.'
            : '$clips accelerometer clipping event${clips == 1 ? '' : 's'}.';
      }

      vibeScore = (vibePts + clipPts).clamp(0, 25);
    }

    // ── Attitude (0–25 pts) ──────────────────────────────────────────────────
    final rollSd  = _d(att['roll_rate_sd']);
    final pitchSd = _d(att['pitch_rate_sd']);
    final maxRoll  = _d(att['max_roll_deg']);
    final maxPitch = _d(att['max_pitch_deg']);

    int attScore;
    String? attNote;

    if (rollSd < 0) {
      attScore = 12;
      attNote = 'No attitude data recorded.';
    } else {
      // Rate smoothness: 0–20 pts
      final avgSd = (rollSd + pitchSd) / 2;
      final ratePts = avgSd <= 5  ? 20
          : avgSd <= 10 ? 17
          : avgSd <= 20 ? 13
          : avgSd <= 35 ? 8
          : 3;
      if (avgSd > 35) {
        attNote = 'High attitude rate variance — very dynamic flight.';
      }

      // Max bank angle: 0–5 pts
      final maxBank = math.max(maxRoll.abs(), maxPitch.abs());
      final bankPts = maxBank <= 30 ? 5
          : maxBank <= 60 ? 4
          : maxBank <= 80 ? 2
          : 1;
      if (maxBank > 80) {
        attNote ??= 'Max bank angle ${maxBank.toStringAsFixed(0)}°.';
      }

      attScore = (ratePts + bankPts).clamp(0, 25);
    }

    // ── Metrics lists ─────────────────────────────────────────────────────────
    final gpsMetrics = <_Metric>[
      if (avgHdop >= 0) ...[
        _Metric('Avg HDOP', avgHdop.toStringAsFixed(2),
            avgHdop <= 1.5 ? _ML.good : _ML.warn),
        _Metric('Avg Sats', avgSat.toStringAsFixed(0),
            avgSat >= 8 ? _ML.good : _ML.warn),
        if (minSat >= 0)
          _Metric('Min Sats', minSat.toStringAsFixed(0),
              minSat >= 6 ? _ML.good : _ML.bad),
        if (pctFix3 >= 0)
          _Metric('3D Fix', '${pctFix3.toStringAsFixed(0)}%',
              pctFix3 >= 95 ? _ML.good : _ML.warn),
      ],
    ];

    final battMetrics = <_Metric>[
      if (minPct >= 0) ...[
        _Metric('Min Battery', '${minPct.toStringAsFixed(0)}%',
            minPct >= 20 ? _ML.good : _ML.bad),
        if (sagV >= 0)
          _Metric('Voltage Sag', '${sagV.toStringAsFixed(2)} V',
              sagV <= 0.6 ? _ML.good : _ML.warn),
        if (totalMah >= 0)
          _Metric('Consumed', '${totalMah.toStringAsFixed(0)} mAh', _ML.neutral),
      ],
    ];

    final vibeMetrics = <_Metric>[
      if (avgVibe >= 0) ...[
        _Metric('Avg Vibe', '${avgVibe.toStringAsFixed(1)} m/s²',
            avgVibe <= 20 ? _ML.good : _ML.bad),
        if (maxX >= 0 && maxY >= 0 && maxZ >= 0)
          _Metric('Max X/Y/Z',
              '${maxX.toStringAsFixed(0)} / ${maxY.toStringAsFixed(0)} / ${maxZ.toStringAsFixed(0)}',
              math.max(math.max(maxX, maxY), maxZ) <= 30 ? _ML.good : _ML.warn),
        if (clips >= 0)
          _Metric('Clipping', clips.toString(),
              clips == 0 ? _ML.good : _ML.bad),
      ],
    ];

    final attMetrics = <_Metric>[
      if (rollSd >= 0) ...[
        _Metric('Roll Rate σ', '${rollSd.toStringAsFixed(1)} °/s',
            rollSd <= 15 ? _ML.good : _ML.warn),
        _Metric('Pitch Rate σ', '${pitchSd.toStringAsFixed(1)} °/s',
            pitchSd <= 15 ? _ML.good : _ML.warn),
        if (maxRoll >= 0)
          _Metric('Max Roll', '${maxRoll.toStringAsFixed(0)}°',
              maxRoll <= 60 ? _ML.good : _ML.warn),
        if (maxPitch >= 0)
          _Metric('Max Pitch', '${maxPitch.toStringAsFixed(0)}°',
              maxPitch <= 60 ? _ML.good : _ML.warn),
      ],
    ];

    return _ScoreResult(
      gpsScore: gpsScore,
      battScore: battScore,
      vibeScore: vibeScore,
      attScore: attScore,
      gpsMetrics: gpsMetrics,
      battMetrics: battMetrics,
      vibeMetrics: vibeMetrics,
      attMetrics: attMetrics,
      gpsNote: gpsNote,
      battNote: battNote,
      vibeNote: vibeNote,
      attNote: attNote,
    );
  }

  /// Extract a double from a DuckDB result cell; returns -1 if null/missing.
  static double _d(dynamic v) => switch (v) {
    null    => -1.0,
    BigInt b => b.toDouble(),
    num n    => n.toDouble(),
    _        => -1.0,
  };
}

class _Metric {
  const _Metric(this.label, this.value, this.level);
  final String label;
  final String value;
  final _ML level;
}

typedef _ML = _MetricLevel;

enum _MetricLevel { good, warn, bad, neutral }

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _ScoreHeader extends StatelessWidget {
  const _ScoreHeader({
    required this.score,
    required this.grade,
    required this.gradeColor,
  });

  final int score;
  final String grade;
  final Color gradeColor;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: Row(
        children: [
          // Large score number
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$score',
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w700,
                  color: gradeColor,
                  height: 1,
                ),
              ),
              Text(
                'out of 100',
                style: TextStyle(color: hc.textTertiary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(width: 20),
          // Grade badge
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: gradeColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: gradeColor, width: 2),
            ),
            child: Center(
              child: Text(
                grade,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: gradeColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          // Progress bar + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Flight Score', style: HeliosTypography.caption),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: score / 100,
                    minHeight: 10,
                    backgroundColor: hc.border,
                    valueColor: AlwaysStoppedAnimation(gradeColor),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _description(score),
                  style: TextStyle(color: hc.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _description(int score) {
    if (score >= 90) return 'Excellent — all systems nominal.';
    if (score >= 75) return 'Good — minor areas to improve.';
    if (score >= 60) return 'Fair — review observations below.';
    if (score >= 45) return 'Marginal — address issues before next flight.';
    return 'Poor — significant problems detected.';
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.icon,
    required this.label,
    required this.score,
    required this.color,
    required this.metrics,
    this.note,
  });

  final IconData icon;
  final String label;
  final int score;
  final Color color;
  final List<_Metric> metrics;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hc.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label, style: HeliosTypography.caption),
              const Spacer(),
              Text(
                '$score / 25',
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: score / 25,
                    minHeight: 5,
                    backgroundColor: hc.border,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
            ],
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: metrics.map((m) => _MetricChip(metric: m)).toList(),
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 12, color: hc.textTertiary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    note!,
                    style: TextStyle(
                      color: hc.textSecondary,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.metric});
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final dotColor = switch (metric.level) {
      _ML.good    => hc.success,
      _ML.warn    => hc.warning,
      _ML.bad     => hc.danger,
      _ML.neutral => hc.textTertiary,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          '${metric.label}: ',
          style: TextStyle(color: hc.textTertiary, fontSize: 11),
        ),
        Text(
          metric.value,
          style: TextStyle(
            color: hc.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
