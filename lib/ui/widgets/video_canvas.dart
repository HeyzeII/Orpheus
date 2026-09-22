import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models/models.dart';
import '../../core/services/audio_handler.dart';
import '../../core/services/audio_player_service.dart';
import '../theme/app_theme.dart';
import 'marquee_text.dart';

/// Premium video canvas that replaces the static album-art container when the
/// currently playing track is a video (MP4 / m4v).
///
/// Features:
/// - In **Portrait mode**: renders a clean, passive edge-to-edge video stream
///   without overlapping controls.
/// - In **Fullscreen mode**: rotates the device to landscape with immersive UI,
///   providing Tidal-style on-screen controls (-10s, previous, play/pause, next,
///   +10s, shuffle, repeat, and scrubber) that auto-hide after 3.5 seconds.
/// - **Resilient Lifecycle (UI Unmounting)**: Dynamically unmounts the native [Video]
///   widget whenever the app lifecycle state is NOT [AppLifecycleState.resumed]
///   (e.g., when notification panel is pulled down or app is minimized). This
///   completely liberates the native SurfaceTexture, eliminating any micro-cuts
///   or unwanted playback pauses while preserving 100% continuous audio stream.
class VideoCanvas extends StatefulWidget {
  const VideoCanvas({
    super.key,
    required this.controller,
    this.borderRadius = 0.0,
    this.aspectRatio = 16 / 9,
    this.track,
  });

  final VideoController controller;

  /// Corner radius applied when NOT in fullscreen mode.
  final double borderRadius;

  /// Fallback aspect ratio for the non-fullscreen container.
  final double aspectRatio;

  /// Optional track for rendering static fallback artwork when unmounted.
  final Track? track;

  /// Global helper to enter fullscreen landscape mode with immersive sticky UI.
  static Future<void> enterFullscreen(
    BuildContext context,
    VideoController controller,
  ) async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (!context.mounted) return;

    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (ctx, _, __) => _FullscreenVideoPage(
          controller: controller,
        ),
        transitionsBuilder: (ctx, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );

    // Restore orientation when returning from fullscreen
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
  }

  @override
  State<VideoCanvas> createState() => _VideoCanvasState();
}

class _VideoCanvasState extends State<VideoCanvas> with WidgetsBindingObserver {
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  /// P0: Pending timer that delays remounting of the [Video] widget after
  /// resume, giving the native [VideoController] time to reinitialize its
  /// SurfaceTexture before the Flutter rasterizer tries to composite frames.
  Timer? _resumeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// P0: Delays Video widget remounting by 250 ms on [AppLifecycleState.resumed]
  /// so the native VideoController has time to reinitialize its SurfaceTexture
  /// before Flutter's rasterizer attempts to composite frames from it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeTimer?.cancel();
      _resumeTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted) setState(() => _lifecycleState = state);
      });
    } else {
      _resumeTimer?.cancel();
      if (_lifecycleState != state) {
        setState(() => _lifecycleState = state);
      }
    }
  }

  /// P1: Static fallback shown while the [VideoController]'s SurfaceTexture
  /// is not yet ready (rect == null or Rect.zero after a resume).
  Widget _buildFallback(String? coverPath) {
    return Container(
      color: const Color(0xFF000000),
      child: (coverPath != null &&
              coverPath.isNotEmpty &&
              File(coverPath).existsSync())
          ? Image.file(File(coverPath), fit: BoxFit.contain)
          : const Center(
              child: Icon(
                Icons.music_video_rounded,
                color: Colors.white24,
                size: 48,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isResumed = _lifecycleState == AppLifecycleState.resumed;
    final currentTrack =
        widget.track ?? AudioPlayerService.instance.currentTrack;
    final coverPath = currentTrack?.customMetadata.customCoverPath;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        // P1: Only mount the native Video widget when the VideoController's
        // rect is confirmed valid, preventing double-binding race conditions
        // and rasterizer stalls on a not-yet-ready SurfaceTexture.
        child: isResumed
            ? ValueListenableBuilder<Rect?>(
                valueListenable: widget.controller.rect,
                builder: (context, rect, _) {
                  final isRectValid = rect != null && rect != Rect.zero;
                  return isRectValid
                      ? Video(
                          controller: widget.controller,
                          fit: BoxFit.contain,
                          controls: NoVideoControls,
                        )
                      : _buildFallback(coverPath);
                },
              )
            : _buildFallback(coverPath),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fullscreen route (landscape, immersive, with auto-hide controls)
// ─────────────────────────────────────────────────────────────────────────────

const _kOverlayTimeout = Duration(milliseconds: 3500);

class _FullscreenVideoPage extends StatefulWidget {
  const _FullscreenVideoPage({required this.controller});
  final VideoController controller;

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _controlsVisible = true;
  Timer? _hideTimer;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  /// P0: Pending timer that delays remounting of the [Video] widget after
  /// resume in fullscreen mode.
  Timer? _resumeTimer;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0,
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
    _scheduleHide();
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  /// P0: Same 250 ms delay as [_VideoCanvasState] applied to the fullscreen
  /// page to prevent double-binding the VideoController to two surfaces.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeTimer?.cancel();
      _resumeTimer = Timer(const Duration(milliseconds: 250), () {
        if (mounted) setState(() => _lifecycleState = state);
      });
    } else {
      _resumeTimer?.cancel();
      if (_lifecycleState != state) {
        setState(() => _lifecycleState = state);
      }
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_kOverlayTimeout, () {
      if (mounted) {
        _fadeCtrl.reverse().then((_) {
          if (mounted) setState(() => _controlsVisible = false);
        });
      }
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      _fadeCtrl.reverse().then((_) {
        if (mounted) setState(() => _controlsVisible = false);
      });
    } else {
      setState(() => _controlsVisible = true);
      _fadeCtrl.forward();
      _scheduleHide();
    }
  }

  void _seekRelative(int seconds) {
    if (!OrpheusAudioHandler.hasInstance) return;
    final handler = OrpheusAudioHandler.instance;
    final current = handler.position;
    final target = current + Duration(seconds: seconds);
    final dur = handler.duration;
    final clampedMs = target.inMilliseconds.clamp(0, dur.inMilliseconds);
    handler.seek(Duration(milliseconds: clampedMs));
  }

  Future<void> _exitFullscreen() async {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final handler = AudioPlayerService.instance;
    final audioHandler = OrpheusAudioHandler.hasInstance
        ? OrpheusAudioHandler.instance
        : null;
    final isResumed = _lifecycleState == AppLifecycleState.resumed;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) {
        // Safe exit
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: GestureDetector(
          onTap: _toggleControls,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Full-bleed video ─────────────────────────────────────────
              // P1: Only mount Video when the VideoController's rect is valid,
              // preventing double-binding with _VideoCanvasState on the same
              // VideoController instance during concurrent resume.
              if (isResumed)
                ValueListenableBuilder<Rect?>(
                  valueListenable: widget.controller.rect,
                  builder: (context, rect, _) {
                    final isRectValid = rect != null && rect != Rect.zero;
                    if (!isRectValid) {
                      return const ColoredBox(color: Color(0xFF000000));
                    }
                    return Video(
                      controller: widget.controller,
                      fit: BoxFit.contain,
                      controls: NoVideoControls,
                    );
                  },
                )
              else
                Container(
                  color: const Color(0xFF000000),
                  child: Center(
                    child: StreamBuilder<Track?>(
                      stream: handler.currentTrackStream,
                      initialData: handler.currentTrack,
                      builder: (_, snap) {
                        final track = snap.data;
                        final coverPath = track?.customMetadata.customCoverPath;
                        if (coverPath != null &&
                            coverPath.isNotEmpty &&
                            File(coverPath).existsSync()) {
                          return Image.file(
                            File(coverPath),
                            fit: BoxFit.contain,
                          );
                        }
                        return const Icon(
                          Icons.music_video_rounded,
                          color: Colors.white24,
                          size: 64,
                        );
                      },
                    ),
                  ),
                ),

              // ── Tidal-style fullscreen overlay ───────────────────────────
              FadeTransition(
                opacity: _fadeAnim,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.75),
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.85),
                        ],
                        stops: const [0.0, 0.25, 0.65, 1.0],
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // ── Top Bar ──────────────────────────────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.fullscreen_exit_rounded,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                  tooltip: 'Salir de pantalla completa',
                                  onPressed: _exitFullscreen,
                                ),
                                const SizedBox(width: 12),
                                // Track Title & Artist Stream
                                Expanded(
                                  child: StreamBuilder<Track?>(
                                    stream: handler.currentTrackStream,
                                    builder: (_, snap) {
                                      final track =
                                          snap.data ?? handler.currentTrack;
                                      if (track == null) {
                                        return const SizedBox.shrink();
                                      }
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          MarqueeText(
                                            text: track.displayTitle,
                                            style: const TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          MarqueeText(
                                            text: track.displayArtist,
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 12,
                                              color: Colors.white
                                                  .withValues(alpha: 0.70),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Video format badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color:
                                        AppTheme.accent.withValues(alpha: 0.90),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'VIDEO',
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                            ),
                          ),

                          // ── Center Controls Row (-10s, Prev, Play/Pause, Next, +10s) ──
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // -10s
                                IconButton(
                                  icon: const Icon(Icons.replay_10_rounded,
                                      color: Colors.white, size: 36),
                                  tooltip: 'Retroceder 10 s',
                                  onPressed: () {
                                    _seekRelative(-10);
                                    _scheduleHide();
                                  },
                                ),
                                const SizedBox(width: 24),
                                // Previous
                                StreamBuilder<Track?>(
                                  stream: handler.currentTrackStream,
                                  builder: (_, __) {
                                    final canPrev = handler.canSkipPrevious;
                                    return IconButton(
                                      icon: Icon(
                                        Icons.skip_previous_rounded,
                                        color: canPrev
                                            ? Colors.white
                                            : Colors.white24,
                                        size: 44,
                                      ),
                                      tooltip: 'Pista anterior',
                                      onPressed: canPrev
                                          ? () {
                                              if (audioHandler != null) {
                                                audioHandler.skipToPrevious();
                                              } else {
                                                handler.previous();
                                              }
                                              _scheduleHide();
                                            }
                                          : null,
                                    );
                                  },
                                ),
                                const SizedBox(width: 24),
                                // Prominent Play / Pause
                                _PlayPauseButton(
                                  handler: handler,
                                  size: 76,
                                  onPressed: _scheduleHide,
                                ),
                                const SizedBox(width: 24),
                                // Next
                                StreamBuilder<Track?>(
                                  stream: handler.currentTrackStream,
                                  builder: (_, __) {
                                    final canNext = handler.canSkipNext;
                                    return IconButton(
                                      icon: Icon(
                                        Icons.skip_next_rounded,
                                        color: canNext
                                            ? Colors.white
                                            : Colors.white24,
                                        size: 44,
                                      ),
                                      tooltip: 'Pista siguiente',
                                      onPressed: canNext
                                          ? () {
                                              if (audioHandler != null) {
                                                audioHandler.skipToNext();
                                              } else {
                                                handler.next();
                                              }
                                              _scheduleHide();
                                            }
                                          : null,
                                    );
                                  },
                                ),
                                const SizedBox(width: 24),
                                // +10s
                                IconButton(
                                  icon: const Icon(Icons.forward_10_rounded,
                                      color: Colors.white, size: 36),
                                  tooltip: 'Avanzar 10 s',
                                  onPressed: () {
                                    _seekRelative(10);
                                    _scheduleHide();
                                  },
                                ),
                              ],
                            ),
                          ),

                          // ── Bottom Bar: Secondary Controls + Scrubber ────
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Secondary: Shuffle & Repeat
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    StreamBuilder<bool>(
                                      stream: handler.shuffleStream,
                                      builder: (_, snap) {
                                        final on =
                                            snap.data ?? handler.shuffleEnabled;
                                        return IconButton(
                                          icon: Icon(
                                            Icons.shuffle_rounded,
                                            color: on
                                                ? AppTheme.accent
                                                : Colors.white54,
                                            size: 24,
                                          ),
                                          tooltip: 'Modo aleatorio',
                                          onPressed: () {
                                            if (audioHandler != null) {
                                              audioHandler.toggleShuffle();
                                            } else {
                                              handler.toggleShuffle();
                                            }
                                            _scheduleHide();
                                          },
                                        );
                                      },
                                    ),
                                    StreamBuilder<PlayerRepeatMode>(
                                      stream: handler.repeatStream,
                                      builder: (_, snap) {
                                        final mode =
                                            snap.data ?? handler.repeatMode;
                                        final (icon, color) = switch (mode) {
                                          PlayerRepeatMode.single => (
                                              Icons.repeat_one_rounded,
                                              AppTheme.accent
                                            ),
                                          PlayerRepeatMode.playlist => (
                                              Icons.repeat_rounded,
                                              AppTheme.accent
                                            ),
                                          PlayerRepeatMode.off => (
                                              Icons.repeat_rounded,
                                              Colors.white54
                                            ),
                                        };
                                        return IconButton(
                                          icon: Icon(icon,
                                              color: color, size: 24),
                                          tooltip: 'Modo de repetición',
                                          onPressed: () {
                                            if (audioHandler != null) {
                                              audioHandler.toggleRepeat();
                                            } else {
                                              handler.toggleRepeat();
                                            }
                                            _scheduleHide();
                                          },
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // Progress scrubber
                                _VideoSeekBar(
                                  handler: handler,
                                  onScrub: _scheduleHide,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.handler,
    this.size = 56,
    this.onPressed,
  });

  final AudioPlayerService handler;
  final double size;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: handler.isPlayingStream,
      builder: (_, snap) {
        final playing = snap.data ?? handler.isPlaying;
        return GestureDetector(
          onTap: () {
            if (playing) {
              handler.pause();
            } else {
              handler.play();
            }
            onPressed?.call();
          },
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.40),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.black,
              size: size * 0.55,
            ),
          ),
        );
      },
    );
  }
}

class _VideoSeekBar extends StatelessWidget {
  const _VideoSeekBar({required this.handler, this.onScrub});
  final AudioPlayerService handler;
  final VoidCallback? onScrub;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: handler.positionStream,
      builder: (_, posSnap) {
        return StreamBuilder<Duration>(
          stream: handler.durationStream,
          builder: (_, durSnap) {
            final pos = posSnap.data ?? handler.position;
            final dur = durSnap.data ?? handler.duration;
            final maxVal = dur.inMilliseconds.toDouble();
            final curVal = pos.inMilliseconds
                .toDouble()
                .clamp(0.0, maxVal > 0 ? maxVal : 1.0);

            return Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    _fmt(pos),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.80),
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4.0,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7.0, elevation: 3),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14.0),
                      activeTrackColor: AppTheme.accent,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: curVal,
                      min: 0,
                      max: maxVal > 0 ? maxVal : 1.0,
                      onChanged: maxVal > 0
                          ? (val) {
                              handler
                                  .seek(Duration(milliseconds: val.toInt()));
                              onScrub?.call();
                            }
                          : null,
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    _fmt(dur),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.80),
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

