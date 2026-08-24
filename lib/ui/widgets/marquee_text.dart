import 'package:flutter/material.dart';

/// Smooth, auto-scrolling marquee widget for single-line text that overflows its bounds.
///
/// If [text] fits within the parent width, it renders as a standard static [Text].
/// If [text] exceeds available width, it scrolls smoothly to the right, pauses,
/// returns to the beginning, and repeats.
///
/// The leading (left) edge is kept completely crisp without cutoffs, while only the
/// trailing (right) edge features a gentle fade.
class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.velocity = 28.0,
    this.pauseDuration = const Duration(seconds: 2),
    this.fadeLength = 16.0,
    /// Extra blank space appended after the text so the final characters
    /// are fully visible before the cycle restarts (in pixels).
    this.trailingSpace = 48.0,
  });

  final String text;
  final TextStyle style;
  final double velocity;
  final Duration pauseDuration;
  final double fadeLength;
  final double trailingSpace;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with TickerProviderStateMixin {
  late final ScrollController _scrollController;
  AnimationController? _animController;
  Animation<double>? _animation;
  double _lastMaxScroll = -1;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _stopAnimation();
      _lastMaxScroll = -1;
    }
  }

  @override
  void dispose() {
    _stopAnimation();
    _scrollController.dispose();
    super.dispose();
  }

  void _stopAnimation() {
    _animController?.stop();
    _animController?.dispose();
    _animController = null;
    _animation = null;
  }

  void _setupAnimation(double maxScroll) {
    if (_animController != null && (_lastMaxScroll - maxScroll).abs() < 1.0) {
      return;
    }
    _stopAnimation();
    if (!mounted || maxScroll <= 0) return;
    _lastMaxScroll = maxScroll;

    final scrollMs = ((maxScroll / widget.velocity) * 1000).toInt().clamp(1000, 40000);
    final pauseMs = widget.pauseDuration.inMilliseconds;
    final totalMs = scrollMs * 2 + pauseMs * 2;

    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );

    final pPause1 = pauseMs / totalMs;
    final pForward = scrollMs / totalMs;
    final pPause2 = pauseMs / totalMs;
    final pReturn = scrollMs / totalMs;

    _animation = TweenSequence<double>([
      // Initial pause at start
      TweenSequenceItem(
        tween: ConstantTween<double>(0.0),
        weight: pPause1,
      ),
      // Smooth scroll forward
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: maxScroll)
            .chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: pForward,
      ),
      // Pause at end
      TweenSequenceItem(
        tween: ConstantTween<double>(maxScroll),
        weight: pPause2 * 0.75,
      ),
      // Smooth scroll back to start
      TweenSequenceItem(
        tween: Tween<double>(begin: maxScroll, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInOutSine)),
        weight: pReturn,
      ),
      // Small settle pause before repeating
      TweenSequenceItem(
        tween: ConstantTween<double>(0.0),
        weight: pPause2 * 0.25,
      ),
    ]).animate(_animController!);

    _animController!.addListener(() {
      if (_scrollController.hasClients && _animation != null) {
        _scrollController.jumpTo(_animation!.value);
      }
    });

    _animController!.repeat();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerWidth = constraints.maxWidth;
        if (containerWidth <= 0) return const SizedBox.shrink();

        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        final textWidth = textPainter.width;
        // Add trailing space so the last character clears the fade before restart.
        final maxScroll = (textWidth + widget.trailingSpace) - containerWidth;

        if (maxScroll > 2.0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _setupAnimation(maxScroll);
          });

          // Only apply a fade gradient to the RIGHT (trailing) edge so the left stays 100% crisp.
          return ShaderMask(
            shaderCallback: (Rect bounds) {
              final fadeFrac = (widget.fadeLength / bounds.width).clamp(0.0, 0.12);
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Colors.black,
                  Colors.black,
                  Colors.transparent,
                ],
                stops: [
                  0.0,
                  (1.0 - fadeFrac).clamp(0.85, 1.0),
                  1.0,
                ],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Padding(
                // Extra right padding = trailingSpace so text never gets
                // visually clipped by the ShaderMask fade zone.
                padding: EdgeInsets.only(right: widget.trailingSpace),
                child: Text(
                  widget.text,
                  style: widget.style,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
            ),
          );
        } else {
          _stopAnimation();
          return Text(
            widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          );
        }
      },
    );
  }
}
