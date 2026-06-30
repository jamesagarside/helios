import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../core/airframe/airframe_config.dart';
import '../../core/airframe/airframe_painter.dart';
import '../../core/airframe/attitude_source.dart';
import '../../core/airframe/drone_mesh_builder.dart';
import '../../core/airframe/frame_conversion.dart';
import '../../core/airframe/mesh.dart';
import '../../shared/theme/helios_colors.dart';

/// Reusable Airframe Model: a real-time, frame-aware 3D representation of the
/// connected vehicle that rotates to match live attitude.
///
/// It is intentionally decoupled from Riverpod — it takes an [AttitudeSource]
/// and an [AirframeConfig] directly so it can be embedded anywhere
/// (Orientation home, calibration flow) and unit/widget-tested in isolation.
///
/// When [targetPose] is supplied, the model reports an **Orientation match**
/// (turns green, fires [onMatchChanged]) once the live attitude is within
/// [toleranceRadians] of the target.
class AirframeModelWidget extends StatefulWidget {
  const AirframeModelWidget({
    super.key,
    required this.source,
    required this.config,
    this.targetPose,
    this.toleranceRadians = 0.087, // ~5°
    this.onMatchChanged,
  });

  final AttitudeSource source;
  final AirframeConfig config;

  /// Optional target body→world attitude the vehicle should match.
  final Quaternion? targetPose;

  /// Angular tolerance for [targetPose] match, in radians.
  final double toleranceRadians;

  /// Called when the Orientation match state changes.
  final ValueChanged<bool>? onMatchChanged;

  @override
  State<AirframeModelWidget> createState() => _AirframeModelWidgetState();
}

class _AirframeModelWidgetState extends State<AirframeModelWidget>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  bool _tickerActive = false;

  late AirframeMesh _mesh;

  // Displayed (smoothed) body attitude. Slerped toward the source each tick.
  Quaternion _display = Quaternion.identity();
  bool _seeded = false;
  bool _matched = false;

  // Fast tracking — matches the PFD's ~50 ms time constant at 60 fps.
  static const double _k = 0.7;
  static const double _eps = 0.0005;

  @override
  void initState() {
    super.initState();
    _mesh = const DroneMeshBuilder().build(widget.config);
    _ticker = createTicker(_onTick);
    widget.source.addListener(_onSample);
    // Seed immediately if a sample already exists.
    _onSample();
  }

  @override
  void didUpdateWidget(covariant AirframeModelWidget old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      old.source.removeListener(_onSample);
      widget.source.addListener(_onSample);
    }
    if (old.config != widget.config) {
      _mesh = const DroneMeshBuilder().build(widget.config);
    }
    if (old.targetPose != widget.targetPose ||
        old.toleranceRadians != widget.toleranceRadians) {
      _evaluateMatch();
    }
  }

  @override
  void dispose() {
    widget.source.removeListener(_onSample);
    _ticker.dispose();
    super.dispose();
  }

  void _onSample() {
    final sample = widget.source.latest;
    if (sample == null) return;
    if (!_seeded) {
      _display = sample.quaternion.clone();
      _seeded = true;
      _evaluateMatch();
      if (mounted) setState(() {});
      return;
    }
    if (!_tickerActive) {
      _ticker.start();
      _tickerActive = true;
    }
  }

  void _onTick(Duration _) {
    final target = widget.source.latest?.quaternion;
    if (target == null) {
      _ticker.stop();
      _tickerActive = false;
      return;
    }
    // Slerp toward the latest sample. slerp handles the shortest-arc sign.
    _display = _slerp(_display, target, _k)..normalize();

    final remaining = FrameConversion.angleBetween(_display, target);
    if (remaining < _eps) {
      _display = target.clone();
      _ticker.stop();
      _tickerActive = false;
    }
    _evaluateMatch();
    if (mounted) setState(() {});
  }

  /// Shortest-arc quaternion slerp by fraction [t].
  Quaternion _slerp(Quaternion a, Quaternion b, double t) {
    var dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    var bb = b;
    if (dot < 0) {
      bb = Quaternion(-b.x, -b.y, -b.z, -b.w);
      dot = -dot;
    }
    // Near-linear region: nlerp to avoid division blow-up.
    if (dot > 0.9995) {
      final r = Quaternion(
        a.x + (bb.x - a.x) * t,
        a.y + (bb.y - a.y) * t,
        a.z + (bb.z - a.z) * t,
        a.w + (bb.w - a.w) * t,
      );
      return r..normalize();
    }
    return _trueSlerp(a, bb, dot, t);
  }

  Quaternion _trueSlerp(Quaternion a, Quaternion b, double dot, double t) {
    final theta0 = math.acos(dot);
    final theta = theta0 * t;
    final sinTheta0 = math.sin(theta0);
    final s0 = math.cos(theta) - dot * math.sin(theta) / sinTheta0;
    final s1 = math.sin(theta) / sinTheta0;
    return Quaternion(
      a.x * s0 + b.x * s1,
      a.y * s0 + b.y * s1,
      a.z * s0 + b.z * s1,
      a.w * s0 + b.w * s1,
    );
  }

  void _evaluateMatch() {
    final target = widget.targetPose;
    if (target == null) {
      if (_matched) {
        _matched = false;
        widget.onMatchChanged?.call(false);
      }
      return;
    }
    final angle = FrameConversion.angleBetween(_display, target);
    final now = angle <= widget.toleranceRadians;
    if (now != _matched) {
      _matched = now;
      widget.onMatchChanged?.call(now);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    if (!widget.source.hasAttitude) {
      return _EmptyState(hc: hc);
    }
    return CustomPaint(
      painter: AirframePainter(
        mesh: _mesh,
        bodyAttitude: _display,
        matched: _matched,
        colors: AirframePainterColors(
          edge: hc.background.withValues(alpha: 0.55),
          matched: hc.success,
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

/// Shown when no attitude has been received yet (disconnected / no telemetry).
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hc});
  final HeliosColors hc;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.threed_rotation_outlined,
              size: 40, color: hc.textTertiary),
          const SizedBox(height: 12),
          Text(
            'Waiting for attitude…',
            style: TextStyle(color: hc.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
