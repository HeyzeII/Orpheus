import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../track_cover_art.dart';

/// Central glowing spherical orb displaying the current track's circular artwork
/// with rotation animation and dynamic glow aura.
class CentralOrbDisc extends StatefulWidget {
  const CentralOrbDisc({
    super.key,
    required this.coverPath,
    required this.isPlaying,
    this.size = 126.0,
    this.accentColor,
  });

  final String? coverPath;
  final bool isPlaying;
  final double size;
  final Color? accentColor;

  @override
  State<CentralOrbDisc> createState() => _CentralOrbDiscState();
}

class _CentralOrbDiscState extends State<CentralOrbDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );

    if (widget.isPlaying) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant CentralOrbDisc oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _rotationController.repeat();
      } else {
        _rotationController.stop();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orbSize = widget.size;
    final labelSize = orbSize * 0.76;
    final spindleSize = orbSize * 0.12;
    final accent = widget.accentColor ?? AppTheme.accent;

    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        width: orbSize,
        height: orbSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(widget.isPlaying ? 0.35 : 0.10),
              blurRadius: widget.isPlaying ? 24 : 12,
              spreadRadius: widget.isPlaying ? 3 : 0,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.70),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: RotationTransition(
          turns: _rotationController,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. Outer Dark Halo Rim
              Container(
                width: orbSize,
                height: orbSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [
                      Color(0xFF1E2028),
                      Color(0xFF101218),
                      Color(0xFF07080B),
                    ],
                    stops: [0.65, 0.88, 1.0],
                  ),
                  border: Border.all(
                    color: accent.withOpacity(widget.isPlaying ? 0.45 : 0.20),
                    width: 1.5,
                  ),
                ),
              ),

              // 2. Micro Concentric Sound Grooves
              CustomPaint(
                size: Size(orbSize, orbSize),
                painter: _OrbGroovesPainter(accentColor: accent),
              ),

              // 3. Central Circular Album Artwork
              Container(
                width: labelSize,
                height: labelSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.85),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: TrackCoverArt(
                    coverPath: widget.coverPath,
                    width: labelSize,
                    height: labelSize,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.zero,
                    fallbackIcon: Icons.music_note_rounded,
                    fallbackIconSize: labelSize * 0.40,
                  ),
                ),
              ),

              // 4. Center Reactor Core Pin / Metallic Spindle
              Container(
                width: spindleSize,
                height: spindleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF090A0D),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.60),
                    width: 1.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.50),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: spindleSize * 0.35,
                    height: spindleSize * 0.35,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrbGroovesPainter extends CustomPainter {
  const _OrbGroovesPainter({required this.accentColor});

  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final groovePaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (double r = radius * 0.80; r < radius * 0.96; r += 3.5) {
      canvas.drawCircle(center, r, groovePaint);
    }

    // Specular sheen light sweep
    final sheenPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.white.withOpacity(0.0),
          accentColor.withOpacity(0.08),
          Colors.white.withOpacity(0.0),
          Colors.white.withOpacity(0.06),
          Colors.white.withOpacity(0.0),
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        transform: const GradientRotation(math.pi / 4),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius * 0.98, sheenPaint);
  }

  @override
  bool shouldRepaint(covariant _OrbGroovesPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}
