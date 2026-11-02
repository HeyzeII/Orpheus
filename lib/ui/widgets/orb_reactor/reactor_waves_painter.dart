import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Highly optimized [CustomPainter] simulating an expressive, fluid audio visualizer:
/// 1. Symmetrical lateral spectrum wings: vertical bars with dramatic transient peaks
///    positioned exclusively in the open left and right side spaces flanking the central orb disc.
/// 2. Concentric harmonic audio wave rings and inner core corona pulsing radially
///    around the central album disc within the unobstructed central circle.
/// 3. Horizontal fluid neon ribbon waves undulating smoothly across the panoramic canvas.
/// 4. Temporal exponential smoothing filter (*Inercia / Attack & Release*) for organic,
///    hypnotic motion without epileptic strobe or jumpiness.
///
/// ### Continuous-phase architecture (no visible loop seams)
/// Instead of deriving the animation phase from `animationValue * 2pi` — which resets
/// to 0.0 at the end of every [AnimationController] cycle and causes a hard jump in all
/// `sin/cos` expressions that use multipliers — we track an **unbounded elapsed-seconds
/// accumulator** ([_elapsedSeconds]) that grows monotonically forever.  Every `paint()`
/// call computes delta-t, handling the 1.0->0.0 wrap-around, and advances the accumulator
/// by `delta * periodSeconds`.  All trigonometric phases are expressed as
/// `_elapsedSeconds * omega` so they are C-infinity continuous across any number of loops.
///
/// Performance optimizations:
/// - Pre-allocated Paint and Path instances eliminating garbage collection (GC) churn.
/// - Isolated GPU layer execution within [RepaintBoundary].
/// - Vectorized geometry calculations for smooth 60/120 fps animations.
class ReactorWavesPainter extends CustomPainter {
  ReactorWavesPainter({
    required this.animationValue,
    required this.isPlaying,
    this.volume = 1.0,
    /// Duration in seconds of the underlying [AnimationController] period.
    /// Must match the value set in [OrbReactorView].
    this.periodSeconds = 3.2,
    Color? accentColor,
    Color? secondaryColor,
    Color? magentaColor,
  })  : accentColor = accentColor ?? AppTheme.accent,
        secondaryColor = secondaryColor ?? const Color(0xFF8B5CF6),
        magentaColor = magentaColor ?? const Color(0xFFD946EF);

  final double animationValue;
  final bool isPlaying;
  final double volume;
  final double periodSeconds;
  final Color accentColor;
  final Color secondaryColor;
  final Color magentaColor;

  static final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _strokePaint = Paint()..style = PaintingStyle.stroke;
  static final Paint _waveStrokePaint = Paint()..style = PaintingStyle.stroke;
  static final Paint _barPaint = Paint()..style = PaintingStyle.fill;
  static final Path _wavePath = Path();
  static final Path _horizontalPath = Path();

  // ── Continuous elapsed time accumulator (never resets) ────────────────────
  // Tracks unbounded seconds so that all sin/cos phases stay C-infinity continuous
  // across AnimationController resets (0.0->1.0 wrap-arounds).
  static double _elapsedSeconds = 0.0;
  static double _previousAnimValue = 0.0;

  // ── Temporal Exponential Smoothing State (Inertia Filter) ─────────────────
  static List<double> _smoothedHeights = [];
  static double _smoothedRhythmEnergy = 0.30;
  static double _smoothedWaveAmp = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // ── Advance the continuous elapsed-time accumulator ──────────────────────
    // Compute delta-t handling the wrap-around (1.0 -> 0.0) that AnimationController
    // performs at the end of every cycle.
    final double rawDelta = animationValue - _previousAnimValue;
    final double delta =
        rawDelta >= 0.0 ? rawDelta : (1.0 - _previousAnimValue + animationValue);
    _previousAnimValue = animationValue;
    _elapsedSeconds += delta * periodSeconds;

    // Convenience alias: e = unbounded elapsed seconds.
    final double e = _elapsedSeconds;

    final center = Offset(size.width / 2, size.height / 2);

    // ── Smooth Continuous Rhythmic Energy ─────────────────────────────────
    final volFactor = (volume.clamp(0.0, 1.0) * 0.75 + 0.25);

    // Continuous C-infinity periodic harmonic beats using unbounded phase
    final beatKick =
        math.pow(0.5 + 0.5 * math.sin(e * math.pi * 4.0), 3.0).toDouble();
    final beatSnare =
        math.pow(0.5 + 0.5 * math.sin(e * math.pi * 4.0 + math.pi), 3.0).toDouble();

    // Exponential smoothing for master rhythm energy
    final targetEnergy = isPlaying
        ? (1.0 + 0.50 * beatKick + 0.30 * beatSnare) * volFactor
        : 0.25;
    _smoothedRhythmEnergy += (targetEnergy - _smoothedRhythmEnergy) * 0.12;

    // Exponential smoothing for panoramic wave amplitude
    final targetWaveAmp = isPlaying ? (18.0 * _smoothedRhythmEnergy) : 4.0;
    _smoothedWaveAmp += (targetWaveAmp - _smoothedWaveAmp) * 0.10;

    // ── Layer 1: Panoramic Horizontal Harmonic Flow Waves ────────────────
    _drawHorizontalWaves(
      canvas: canvas,
      size: size,
      center: center,
      e: e,
      waveAmp: _smoothedWaveAmp,
    );

    // ── Layer 2: Lateral Spectrum Wings ───────────────────────────────────
    _drawLateralSpectrumWings(
      canvas: canvas,
      size: size,
      center: center,
      e: e,
      beatKick: beatKick,
      beatSnare: beatSnare,
    );

    // Dynamic wave amplitudes
    final amp1 = isPlaying ? (9.5 * _smoothedRhythmEnergy) : 2.0;
    final amp2 = isPlaying ? (7.0 * _smoothedRhythmEnergy) : 1.5;
    final amp3 = isPlaying ? (4.8 * _smoothedRhythmEnergy) : 1.0;

    // Base radius sized outside the CentralOrbDisc (diameter 122 -> radius 61)
    const double baseRadius = 62.0;

    // ── Layer 3: Outer Ambient Chromatic Diffusion Aura ──────────────────
    _drawFluidRing(
      canvas: canvas,
      center: center,
      baseRadius: baseRadius + 36.0,
      amplitude: amp1,
      harmonicFreq: 3,
      phase: e * 0.8 * math.pi * 2,
      paint: _fillPaint
        ..shader = RadialGradient(
          colors: [
            magentaColor.withOpacity(
                isPlaying ? (0.24 + 0.08 * beatKick) * volFactor : 0.08),
            accentColor.withOpacity(isPlaying ? 0.18 * volFactor : 0.05),
            Colors.transparent,
          ],
          stops: const [0.48, 0.80, 1.0],
        ).createShader(
            Rect.fromCircle(center: center, radius: baseRadius + 58.0)),
      isFill: true,
    );

    // ── Layer 4: Outer Harmonic Neon Resonant Wave ────────────────────────
    _drawFluidRing(
      canvas: canvas,
      center: center,
      baseRadius: baseRadius + 22.0,
      amplitude: amp1,
      harmonicFreq: 4,
      phase: -e * 1.1 * math.pi * 2,
      paint: _strokePaint
        ..shader = SweepGradient(
          center: Alignment.center,
          transform: GradientRotation(e * 0.8 * math.pi * 2),
          colors: [
            accentColor.withOpacity(isPlaying ? 0.90 : 0.35),
            magentaColor.withOpacity(isPlaying ? 0.85 : 0.30),
            secondaryColor.withOpacity(isPlaying ? 0.75 : 0.25),
            accentColor.withOpacity(isPlaying ? 0.90 : 0.35),
          ],
          stops: const [0.0, 0.40, 0.75, 1.0],
        ).createShader(
            Rect.fromCircle(center: center, radius: baseRadius + 36.0))
        ..strokeWidth = isPlaying ? (2.4 + 0.5 * beatKick) : 2.2,
      isFill: false,
    );

    // ── Layer 5: Counter-Rotating Intermediate Harmonic Wave ──────────────
    _drawFluidRing(
      canvas: canvas,
      center: center,
      baseRadius: baseRadius + 14.0,
      amplitude: amp2,
      harmonicFreq: 5,
      phase: e * 1.4 * math.pi * 2,
      paint: _strokePaint
        ..shader = SweepGradient(
          center: Alignment.center,
          transform: GradientRotation(-e * 1.2 * math.pi * 2),
          colors: [
            magentaColor.withOpacity(isPlaying ? 0.85 : 0.30),
            secondaryColor.withOpacity(isPlaying ? 0.75 : 0.25),
            accentColor.withOpacity(isPlaying ? 0.90 : 0.35),
            magentaColor.withOpacity(isPlaying ? 0.85 : 0.30),
          ],
          stops: const [0.0, 0.35, 0.70, 1.0],
        ).createShader(
            Rect.fromCircle(center: center, radius: baseRadius + 24.0))
        ..strokeWidth = 2.2,
      isFill: false,
    );

    // ── Layer 6: Inner High-Energy Core Corona (Disc Rim) ─────────────────
    _drawFluidRing(
      canvas: canvas,
      center: center,
      baseRadius: baseRadius + 6.0,
      amplitude: amp3,
      harmonicFreq: 6,
      phase: e * 1.8 * math.pi * 2,
      paint: _strokePaint
        ..shader = SweepGradient(
          center: Alignment.center,
          transform: GradientRotation(e * 1.5 * math.pi * 2),
          colors: [
            accentColor.withOpacity(isPlaying ? 0.95 : 0.45),
            const Color(0xFFFDF4FF)
                .withOpacity(isPlaying ? (0.85 + 0.15 * beatKick) : 0.40),
            magentaColor.withOpacity(isPlaying ? 0.90 : 0.40),
            accentColor.withOpacity(isPlaying ? 0.95 : 0.45),
          ],
          stops: const [0.0, 0.45, 0.75, 1.0],
        ).createShader(
            Rect.fromCircle(center: center, radius: baseRadius + 14.0))
        ..strokeWidth = isPlaying ? (2.6 + 0.8 * beatKick) : 2.4,
      isFill: false,
    );
  }

  /// Draws fluid horizontal harmonic waves running smoothly across the panoramic canvas.
  void _drawHorizontalWaves({
    required Canvas canvas,
    required Size size,
    required Offset center,
    required double e,
    required double waveAmp,
  }) {
    final width = size.width;
    const pointsCount = 42;
    final dx = width / pointsCount;

    // Harmonic Wave 1: Primary Cyan -> Magenta flow
    _horizontalPath.reset();
    for (int i = 0; i <= pointsCount; i++) {
      final x = i * dx;
      final normX = (x - center.dx) / (width / 2);
      final envelope = math.exp(-normX * normX * 1.5);
      final y = center.dy +
          math.sin(x * 0.022 + e * 1.4) * waveAmp * envelope +
          math.cos(x * 0.045 - e * 0.8) * (waveAmp * 0.5) * envelope;
      if (i == 0) {
        _horizontalPath.moveTo(x, y);
      } else {
        _horizontalPath.lineTo(x, y);
      }
    }

    _waveStrokePaint
      ..shader = LinearGradient(
        colors: [
          accentColor.withOpacity(isPlaying ? 0.80 : 0.22),
          magentaColor.withOpacity(isPlaying ? 0.85 : 0.26),
          secondaryColor.withOpacity(isPlaying ? 0.75 : 0.18),
          accentColor.withOpacity(isPlaying ? 0.80 : 0.22),
        ],
        stops: const [0.0, 0.35, 0.70, 1.0],
      ).createShader(Rect.fromLTWH(0, center.dy - 35, width, 70))
      ..strokeWidth = isPlaying ? 2.5 : 2.0;
    canvas.drawPath(_horizontalPath, _waveStrokePaint);

    // Harmonic Wave 2: Counter-undulating Magenta -> Violet ribbon
    _horizontalPath.reset();
    for (int i = 0; i <= pointsCount; i++) {
      final x = i * dx;
      final normX = (x - center.dx) / (width / 2);
      final envelope = math.exp(-normX * normX * 1.5);
      final y = center.dy +
          math.sin(x * 0.028 - e * 1.7) * (waveAmp * 0.75) * envelope +
          math.cos(x * 0.015 + e * 1.1) * (waveAmp * 0.40) * envelope;
      if (i == 0) {
        _horizontalPath.moveTo(x, y);
      } else {
        _horizontalPath.lineTo(x, y);
      }
    }

    _waveStrokePaint
      ..shader = LinearGradient(
        colors: [
          magentaColor.withOpacity(isPlaying ? 0.75 : 0.18),
          secondaryColor.withOpacity(isPlaying ? 0.70 : 0.15),
          accentColor.withOpacity(isPlaying ? 0.75 : 0.18),
          magentaColor.withOpacity(isPlaying ? 0.75 : 0.18),
        ],
        stops: const [0.0, 0.30, 0.65, 1.0],
      ).createShader(Rect.fromLTWH(0, center.dy - 35, width, 70))
      ..strokeWidth = isPlaying ? 2.0 : 1.6;
    canvas.drawPath(_horizontalPath, _waveStrokePaint);
  }

  /// Draws lateral spectrum wings flanking the left and right sides of the central disc.
  void _drawLateralSpectrumWings({
    required Canvas canvas,
    required Size size,
    required Offset center,
    required double e,
    required double beatKick,
    required double beatSnare,
  }) {
    const int barsPerWing = 14;
    const int totalBars = barsPerWing * 2;

    if (_smoothedHeights.length != totalBars) {
      _smoothedHeights = List<double>.filled(totalBars, 16.0);
    }

    const double barWidth = 3.2;
    const double barGap = 4.4;
    const double wingSpan =
        barsPerWing * barWidth + (barsPerWing - 1) * barGap;

    const double innerClearance = 70.0;
    final double leftWingStart = center.dx - innerClearance - wingSpan;
    final double rightWingStart = center.dx + innerClearance;

    final fullSpectrumBounds = Rect.fromCenter(
      center: center,
      width: (innerClearance + wingSpan) * 2,
      height: 220.0,
    );

    for (int barIdx = 0; barIdx < totalBars; barIdx++) {
      final bool isLeftWing = barIdx < barsPerWing;
      final int wingBarIdx = isLeftWing ? barIdx : (barIdx - barsPerWing);

      final double barX = isLeftWing
          ? (leftWingStart + wingBarIdx * (barWidth + barGap))
          : (rightWingStart + wingBarIdx * (barWidth + barGap));

      final double v = isLeftWing
          ? (barsPerWing - 1 - wingBarIdx) / (barsPerWing - 1)
          : wingBarIdx / (barsPerWing - 1);

      final double wingEnvelope = 0.40 + 0.60 * math.sin(v * math.pi);

      // All phases use unbounded 'e' — C-infinity continuous forever.
      final double stereoPhase = isLeftWing ? 0.0 : 1.45;
      final bandFreq1 = 1.6 + (wingBarIdx % 5) * 0.75;
      final bandFreq2 = 2.5 + ((wingBarIdx * 3) % 7) * 0.85;

      final rawWave =
          math.sin(e * bandFreq1 + wingBarIdx * 1.1 + stereoPhase) * 0.55 +
              math.cos(e * bandFreq2 - wingBarIdx * 0.8 + stereoPhase) * 0.45;
      final normalizedEnergy = ((rawWave + 1.0) / 2.0).clamp(0.0, 1.0);
      final dynamicSpike = math.pow(normalizedEnergy, 2.2).toDouble();

      double bandAccent = 0.0;
      if (v < 0.35) {
        bandAccent = beatKick * 0.50;
      } else if (v > 0.70) {
        bandAccent =
            (0.5 + 0.5 * math.sin(e * 6.5 + wingBarIdx * 1.8 + stereoPhase)) *
                0.40;
      } else {
        bandAccent = beatSnare * 0.45;
      }

      const minBarHeight = 16.0;
      const maxBarHeight = 155.0;

      final targetSignal =
          (dynamicSpike * 0.60 + bandAccent * 0.40) * _smoothedRhythmEnergy;
      final targetHeight = isPlaying
          ? (minBarHeight +
              (maxBarHeight - minBarHeight) *
                  targetSignal.clamp(0.0, 1.0) *
                  wingEnvelope)
          : (minBarHeight + 8.0 * normalizedEnergy * wingEnvelope);

      // Exponential Smoothing: fast attack, slow release
      final currentHeight = _smoothedHeights[barIdx];
      final alpha = targetHeight > currentHeight ? 0.20 : 0.07;
      final smoothedHeight =
          currentHeight + (targetHeight - currentHeight) * alpha;
      _smoothedHeights[barIdx] = smoothedHeight;

      final barRect = Rect.fromCenter(
        center: Offset(barX, center.dy),
        width: barWidth,
        height: smoothedHeight,
      );
      final barRRect =
          RRect.fromRectAndRadius(barRect, const Radius.circular(2.0));

      final isHighPeak = smoothedHeight > (maxBarHeight * 0.50);
      final barOpacity = isPlaying
          ? (0.38 + 0.52 * (smoothedHeight / maxBarHeight)).clamp(0.20, 0.96)
          : 0.16;

      _barPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          (isHighPeak ? const Color(0xFFE0F2FE) : accentColor)
              .withOpacity(barOpacity * 0.92),
          magentaColor.withOpacity(barOpacity),
          secondaryColor.withOpacity(barOpacity * 0.85),
          magentaColor.withOpacity(barOpacity),
          accentColor.withOpacity(barOpacity * 0.92),
        ],
        stops: const [0.0, 0.28, 0.50, 0.72, 1.0],
      ).createShader(fullSpectrumBounds);

      canvas.drawRRect(barRRect, _barPaint);
    }
  }

  /// Renders a fluid closed-ring harmonic wave around [center].
  /// [phase] is an unbounded radian value — never wraps, always smooth.
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
      _wavePath.quadraticBezierTo(
          points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    _wavePath.close();

    canvas.drawPath(_wavePath, paint);
  }

  @override
  bool shouldRepaint(covariant ReactorWavesPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.volume != volume ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.magentaColor != magentaColor;
  }
}
