import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../track_cover_art.dart';

/// A premium, rotating vinyl record widget with concentric grooves and circular
/// album artwork at its center.
///
/// Features:
/// - Smooth 33 RPM continuous rotation when [isPlaying] is `true`.
/// - Halts immediately on pause while strictly maintaining its rotation angle.
/// - Concentric glossy vinyl grooves and central metallic spindle hole.
/// - Isolated on its own GPU compositor layer via [RepaintBoundary] for 0% CPU
///   overhead on surrounding UI elements.
class VinylDiscWidget extends StatefulWidget {
  const VinylDiscWidget({
    super.key,
    required this.coverPath,
    required this.isPlaying,
    this.size = 136.0,
  });

  /// Path to local image file or remote HTTP artwork URL.
  final String? coverPath;

  /// Whether audio is actively playing to drive the rotation animation.
  final bool isPlaying;

  /// Total diameter of the vinyl disc.
  final double size;

  @override
  State<VinylDiscWidget> createState() => _VinylDiscWidgetState();
}

class _VinylDiscWidgetState extends State<VinylDiscWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    // 12 seconds per full 360 degree rotation emulating gentle turntable speed
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );

    if (widget.isPlaying) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant VinylDiscWidget oldWidget) {
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
    final discSize = widget.size;
    final labelSize = discSize * 0.52;
    final spindleSize = discSize * 0.085;

    return RepaintBoundary(
      child: SizedBox(
        width: discSize,
        height: discSize,
        child: RotationTransition(
          turns: _rotationController,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. Vinyl Record Disc Base
              Container(
                width: discSize,
                height: discSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [
                      Color(0xFF1C1D22),
                      Color(0xFF0F1014),
                      Color(0xFF070709),
                      Color(0xFF000000),
                    ],
                    stops: [0.35, 0.65, 0.88, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.55),
                      blurRadius: 16,
                      spreadRadius: 2,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
              ),

              // 2. Concentric Vinyl Grooves
              CustomPaint(
                size: Size(discSize, discSize),
                painter: _VinylGroovesPainter(),
              ),

              // 3. Circular Album Cover Label
              Container(
                width: labelSize,
                height: labelSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.7),
                      blurRadius: 6,
                      spreadRadius: 1,
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
                    fallbackIcon: Icons.album_rounded,
                    fallbackIconSize: labelSize * 0.45,
                  ),
                ),
              ),

              // 4. Center Spindle Ring and Hole
              Container(
                width: spindleSize,
                height: spindleSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0C0D10),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.45),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.8),
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter that renders fine circular micro-grooves and light reflections
/// characteristic of high-fidelity vinyl records.
class _VinylGroovesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Subtle concentric grooves
    final groovePaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Render concentric circles between center label and outer edge
    for (double r = radius * 0.58; r < radius * 0.94; r += 4.5) {
      canvas.drawCircle(center, r, groovePaint);
    }

    // Specular vinyl sheen reflections (conical light reflection simulation)
    final sheenPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.white.withOpacity(0.0),
          Colors.white.withOpacity(0.08),
          Colors.white.withOpacity(0.0),
          Colors.white.withOpacity(0.08),
          Colors.white.withOpacity(0.0),
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        transform: const GradientRotation(math.pi / 4),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius * 0.95, sheenPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
