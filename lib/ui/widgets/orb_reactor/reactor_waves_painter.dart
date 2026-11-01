import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Highly optimized [CustomPainter] simulating fluid, concentric audio waves
/// pulsing radially around the central orb disc.
///
/// Performance optimizations:
/// - Evaluates smooth harmonic curves using 12 nodal control points connected by quadratic Béziers.
/// - Pre-allocated reusable paths avoiding garbage collection (GC) churn.
/// - Dynamic amplitude scaling: energetic multi-octave oscillation during playback,
///   smooth resting breath cycle when paused.
class ReactorWavesPainter extends CustomPainter {
  ReactorWavesPainter({
    required this.animationValue,
    required this.isPlaying,
    Color? accentColor,
    Color? secondaryColor,
  })  : accentColor = accentColor ?? AppTheme.accent,
        secondaryColor = secondaryColor ?? const Color(0xFF8B5CF6);

  final double animationValue;
  final bool isPlaying;
  final Color accentColor;
  final Color secondaryColor;

  // Reusable objects to minimize heap allocation during 60 FPS animation loop
  static final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _strokePaint = Paint()..style = PaintingStyle.stroke;
  static final Path _wavePath = Path();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.shortestSide * 0.28; // ~70px on a 250px container
    final twoPi = math.pi * 2;
    final t = animationValue * twoPi;

    // Amplitude factors: active high-energy wave vs calm breathing wave
    final amp1 = isPlaying ? 7.5 : 2.0;
    final amp2 = isPlaying ? 5.5 : 1.2;
    final amp3 = isPlaying ? 4.0 : 0.8;

    // ── Layer 1: Outer Ambient Diffusion Aura ─────────────────────────────
    _drawFluidRing(
      canvas: canvas,
      center: center,
      baseRadius: baseRadius + 24.0,
      amplitude: amp1,
      harmonicFreq: 3,
      phase: t * 0.8,
      paint: _fillPaint
        ..shader = RadialGradient(
          colors: [
            secondaryColor.withOpacity(isPlaying ? 0.20 : 0.08),
            accentColor.withOpacity(isPlaying ? 0.10 : 0.03),
            Colors.transparent,
          ],
          stops: const [0.65, 0.88, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: baseRadius + 36.0)),
      isFill: true,
    );

    // ── Layer 2: Intermediate Harmonic Resonant Wave ──────────────────────
    _drawFluidRing(
      canvas: canvas,
      center: center,
      baseRadius: baseRadius + 14.0,
      amplitude: amp2,
      harmonicFreq: 4,
      phase: -t * 1.2,
      paint: _strokePaint
        ..shader = SweepGradient(
          center: Alignment.center,
          colors: [
            accentColor.withOpacity(isPlaying ? 0.45 : 0.18),
            secondaryColor.withOpacity(isPlaying ? 0.35 : 0.12),
            accentColor.withOpacity(isPlaying ? 0.45 : 0.18),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: baseRadius + 20.0))
        ..strokeWidth = 1.6,
      isFill: false,
    );

    // ── Layer 3: Inner High-Energy Core Corona ────────────────────────────
    _drawFluidRing(
      canvas: canvas,
      center: center,
      baseRadius: baseRadius + 4.0,
      amplitude: amp3,
      harmonicFreq: 5,
      phase: t * 1.6,
      paint: _strokePaint
        ..shader = null
        ..color = accentColor.withOpacity(isPlaying ? 0.75 : 0.35)
        ..strokeWidth = 2.0,
      isFill: false,
    );
  }

  void _drawFluidRing({
    required Canvas canvas,
    required Offset center,
    required double baseRadius,
    required double amplitude,
    required int harmonicFreq,
    required double phase,
    required Paint paint,
    required bool isFill,
  }) {
    const int nodes = 12;
    final List<Offset> points = [];

    for (int i = 0; i < nodes; i++) {
      final theta = (i / nodes) * (math.pi * 2);
      final harmonicMod = math.sin(harmonicFreq * theta + phase) * 0.65 +
          math.cos((harmonicFreq - 1) * theta - phase * 0.8) * 0.35;
      final r = baseRadius + (amplitude * harmonicMod);
      final x = center.dx + r * math.cos(theta);
      final y = center.dy + r * math.sin(theta);
      points.add(Offset(x, y));
    }

    _wavePath.reset();
    // Smooth quadratic Bézier interpolation connecting midpoints of adjacent nodes
    final firstMid = Offset(
      (points[0].dx + points[nodes - 1].dx) / 2,
      (points[0].dy + points[nodes - 1].dy) / 2,
    );
    _wavePath.moveTo(firstMid.dx, firstMid.dy);

    for (int i = 0; i < nodes; i++) {
      final nextIdx = (i + 1) % nodes;
      final mid = Offset(
        (points[i].dx + points[nextIdx].dx) / 2,
        (points[i].dy + points[nextIdx].dy) / 2,
      );
      _wavePath.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    _wavePath.close();

    canvas.drawPath(_wavePath, paint);
  }

  @override
  bool shouldRepaint(covariant ReactorWavesPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}
