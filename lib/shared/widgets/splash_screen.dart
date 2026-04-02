import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// Helios splash screen.
///
/// Dots representing the Helios logo nodes spiral in from outside the screen
/// like rotor blades slowing to a stop, then settle into the constellation
/// pattern. Connection lines draw in, the core lights up, and the app name
/// fades in before the whole screen dissolves into the main UI.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _assembleController;
  late final AnimationController _fadeController;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();

    _assembleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _assembleController.forward().then((_) {
      if (!mounted) return;
      _delayTimer = Timer(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        _delayTimer = null;
        _fadeController.forward().then((_) {
          if (mounted) widget.onComplete();
        });
      });
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _delayTimer = null;
    _assembleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_assembleController, _fadeController]),
      builder: (context, _) {
        // Raw controller value → eased progress for the logo assembly
        final assembleRaw = _assembleController.value;
        final assembleProgress = Curves.easeOutCubic.transform(assembleRaw);

        final textOpacity = const Interval(0.75, 1.0, curve: Curves.easeIn)
            .transform(assembleRaw);

        return Opacity(
          opacity: 1.0 - _fadeController.value,
          child: Container(
            color: const Color(0xFF0D1117),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(
                    size: const Size(240, 240),
                    painter: _HeliosLogoPainter(progress: assembleProgress),
                  ),
                  const SizedBox(height: 32),
                  Opacity(
                    opacity: textOpacity,
                    child: const _SplashText(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SplashText extends StatelessWidget {
  const _SplashText();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'HELIOS',
          style: TextStyle(
            color: Color(0xFF58A6FF),
            fontSize: 28,
            fontWeight: FontWeight.w300,
            letterSpacing: 14,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'GROUND CONTROL STATION',
          style: TextStyle(
            color: const Color(0xFF58A6FF).withValues(alpha: 0.45),
            fontSize: 10,
            fontWeight: FontWeight.w400,
            letterSpacing: 4,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

/// Draws the Helios logo assembling from spiralling dots.
///
/// Coordinate system: logo-space is 100×100 with (0,0) at the centre.
/// Canvas is scaled so 1 logo unit = size.width / 100 pixels.
class _HeliosLogoPainter extends CustomPainter {
  const _HeliosLogoPainter({required this.progress});

  final double progress;

  // ── Node definitions ── logo coords offset from centre (50,50)
  // Format: [dx, dy, circleRadius, baseOpacity]

  static const _coronaNodes = <List<double>>[
    [0, -22, 3.2, 0.9],
    [0, 22, 3.2, 0.9],
    [-22, 0, 3.2, 0.9],
    [22, 0, 3.2, 0.9],
    [-15, -12, 3.0, 0.9],
    [15, -12, 3.0, 0.9],
    [-15, 12, 3.0, 0.9],
    [15, 12, 3.0, 0.9],
  ];

  static const _rayNodes = <List<double>>[
    [0, -40, 2.4, 0.8],
    [0, 40, 2.4, 0.8],
    [-40, 0, 2.4, 0.8],
    [40, 0, 2.4, 0.8],
    [-29, -29, 2.0, 0.7],
    [29, 29, 2.0, 0.7],
    [29, -29, 2.0, 0.7],
    [-29, 29, 2.0, 0.7],
  ];

  // Lines between fixed final positions (in logo coords offset from centre).
  // Format: [x1, y1, x2, y2, strokeWidth, baseOpacity]
  static const _lines = <List<double>>[
    // Outer sight-line rays
    [0, -25, 0, -40, 0.8, 0.4],
    [0, 25, 0, 40, 0.8, 0.4],
    [-25, 0, -40, 0, 0.8, 0.4],
    [25, 0, 40, 0, 0.8, 0.4],
    [-18, -18, -29, -29, 0.8, 0.4],
    [18, 18, 29, 29, 0.8, 0.4],
    [18, -18, 29, -29, 0.8, 0.4],
    [-18, 18, -29, 29, 0.8, 0.4],
    // Inner network connections
    [0, -22, -15, -12, 0.5, 0.5],
    [0, -22, 15, -12, 0.5, 0.5],
    [-15, -12, -22, 0, 0.5, 0.5],
    [15, -12, 22, 0, 0.5, 0.5],
    [-22, 0, -15, 12, 0.5, 0.5],
    [22, 0, 15, 12, 0.5, 0.5],
    [-15, 12, 0, 22, 0.5, 0.5],
    [15, 12, 0, 22, 0.5, 0.5],
    // Cross connections
    [-15, -12, 15, -12, 0.5, 0.35],
    [-15, 12, 15, 12, 0.5, 0.35],
    [-22, 0, 22, 0, 0.5, 0.35],
    // Diagonal cross
    [-15, -12, 15, 12, 0.5, 0.25],
    [15, -12, -15, 12, 0.5, 0.25],
  ];

  static const _accent = Color(0xFF58A6FF);

  // ── Spiral-in calculation ─────────────────────────────────────────────────

  /// Returns the current canvas position for a node defined by its final
  /// offset [dx], [dy] from centre. Uses [progress] (0→1, already eased) to
  /// interpolate from start (large radius, rotated back) to final position.
  Offset _nodePos(double dx, double dy) {
    final finalR = sqrt(dx * dx + dy * dy);
    if (finalR < 0.001) return Offset.zero;

    final finalAngle = atan2(dy, dx);

    // Outer nodes rotate through a larger arc so the whole assembly sweeps
    // together like rotor blades converging from different distances.
    const startR = 170.0;
    final rotations = finalR > 30.0 ? 2.0 : 1.5;
    final startAngle = finalAngle - rotations * pi;

    final t = progress;
    final r = startR + (finalR - startR) * t;
    final angle = startAngle + (finalAngle - startAngle) * t;

    return Offset(cos(angle) * r, sin(angle) * r);
  }

  // ── Paint ─────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100.0;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);

    // Subtle background glow that grows as the logo assembles
    final glowOpacity = (progress * 0.06).clamp(0.0, 0.06);
    if (glowOpacity > 0) {
      final gradient = RadialGradient(
        colors: [
          _accent.withValues(alpha: glowOpacity),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      );
      canvas.drawCircle(
        Offset.zero,
        55,
        Paint()
          ..shader = gradient.createShader(
            Rect.fromCircle(center: Offset.zero, radius: 55),
          ),
      );
    }

    // ── Connection lines (fade in t=0.45→0.80) ──
    final lineOpacity = ((progress - 0.45) / 0.35).clamp(0.0, 1.0);
    if (lineOpacity > 0) {
      for (final l in _lines) {
        canvas.drawLine(
          Offset(l[0], l[1]),
          Offset(l[2], l[3]),
          Paint()
            ..color = _accent.withValues(alpha: l[5] * lineOpacity)
            ..strokeWidth = l[4]
            ..style = PaintingStyle.stroke,
        );
      }
    }

    // ── Corona nodes (dots spiral in 0→1) ──
    for (final n in _coronaNodes) {
      canvas.drawCircle(
        _nodePos(n[0], n[1]),
        n[2],
        Paint()
          ..color = _accent.withValues(alpha: n[3] * progress)
          ..style = PaintingStyle.fill,
      );
    }

    // ── Ray tip nodes ──
    for (final n in _rayNodes) {
      canvas.drawCircle(
        _nodePos(n[0], n[1]),
        n[2],
        Paint()
          ..color = _accent.withValues(alpha: n[3] * progress)
          ..style = PaintingStyle.fill,
      );
    }

    // ── Centre core (builds up t=0.65→1.0) ──
    final coreT = ((progress - 0.65) / 0.35).clamp(0.0, 1.0);
    if (coreT > 0) {
      // Outer glow ring
      canvas.drawCircle(
        Offset.zero,
        8.0,
        Paint()
          ..color = _accent.withValues(alpha: 0.15 * coreT)
          ..style = PaintingStyle.fill,
      );
      // Solid core — scales in
      canvas.drawCircle(
        Offset.zero,
        5.6 * coreT,
        Paint()
          ..color = _accent.withValues(alpha: coreT)
          ..style = PaintingStyle.fill,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeliosLogoPainter old) => old.progress != progress;
}
