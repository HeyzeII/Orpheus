import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Staggered animated equalizer bars (3 or 4 vertical bouncing bars).
///
/// When [isPlaying] is true, the bars animate smoothly with fluid sine/cosine curves.
/// When [isPlaying] is false, the bars settle into a fixed resting height.
class AnimatedEqualizer extends StatefulWidget {
  const AnimatedEqualizer({
    super.key,
    required this.isPlaying,
    this.color = AppTheme.accent,
    this.barCount = 3,
    this.barWidth = 2.5,
    this.maxHeight = 14.0,
    this.minHeight = 3.0,
    this.spacing = 2.0,
  });

  final bool isPlaying;
  final Color color;
  final int barCount;
  final double barWidth;
  final double maxHeight;
  final double minHeight;
  final double spacing;

  @override
  State<AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<AnimatedEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(AnimatedEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(widget.barCount, (i) {
            double heightFraction;
            if (widget.isPlaying) {
              // Stagger phase offsets per bar for realistic audio pulsing.
              // Both fundamental and 2nd harmonic are exactly 2π-periodic,
              // producing a 100% seamless, mathematically continuous loop without any jumps.
              final phase = i * (math.pi / (widget.barCount > 1 ? widget.barCount : 1));
              final wave1 = math.sin(t + phase);
              final wave2 = 0.5 * math.sin(2 * t + phase * 2);
              final raw = ((wave1 + wave2) / 1.5 + 1.0) / 2.0;
              heightFraction = raw.clamp(0.08, 1.0);
            } else {
              // Resting height when paused
              heightFraction = (i % 2 == 0) ? 0.25 : 0.4;
            }

            final h = widget.minHeight +
                heightFraction * (widget.maxHeight - widget.minHeight);

            return Container(
              margin: EdgeInsets.symmetric(horizontal: widget.spacing / 2),
              width: widget.barWidth,
              height: h,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(widget.barWidth / 2),
              ),
            );
          }),
        );
      },
    );
  }
}
