import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/database/local_database.dart';
import '../../core/models/models.dart';
import '../../core/services/audio_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_equalizer.dart';
import '../widgets/app_toast.dart';
import '../widgets/marquee_text.dart';
import 'lyrics_view.dart';

/// The premium Now Playing "Theater View" (Expanded Player) replacing Explore.
///
/// - **Desktop (≥ 600 px):** two-column layout: artwork + controls on the left,
///   lyrics/queue tab panel on the right. Identical to the original design.
/// - **Mobile  (< 600 px):** full-screen vertical Tidal-style layout:
///   collapse button → square cover art → title/artist → progress slider →
///   playback controls → bottom swipeable tab bar (Letras / Cola).
class ExpandedPlayerView extends StatefulWidget {
  const ExpandedPlayerView({super.key});

  @override
  State<ExpandedPlayerView> createState() => _ExpandedPlayerViewState();
}

class _ExpandedPlayerViewState extends State<ExpandedPlayerView> {
  _MobileOverlayMode _mobileMode = _MobileOverlayMode.artwork;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_mobileMode != _MobileOverlayMode.artwork) {
          setState(() => _mobileMode = _MobileOverlayMode.artwork);
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: StreamBuilder<Track?>(
          stream: OrpheusAudioHandler.instance.currentTrackStream,
          initialData: OrpheusAudioHandler.instance.currentTrack,
          builder: (context, snap) {
            final track = snap.data;
            final isMobile = MediaQuery.sizeOf(context).width < 600;

            return Stack(
              children: [
                // 1. Dynamic blurred background (shared between both layouts)
                if (track != null) _BlurredImageBackground(track: track),

                // 2. Layout switch
                if (track != null)
                  isMobile
                      ? _MobileVerticalLayout(
                          track: track,
                          mode: _mobileMode,
                          onModeChanged: (mode) => setState(() => _mobileMode = mode),
                        )
                      : _DesktopHorizontalLayout(track: track),

                // 3. Collapse button — top-right on desktop
                if (!isMobile)
                  Positioned(
                    top: 40,
                    right: 40,
                    child: const _CollapseButton(alignment: 'right'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED: Background
// ─────────────────────────────────────────────────────────────────────────────

class _BlurredImageBackground extends StatelessWidget {
  const _BlurredImageBackground({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final coverPath = track.customMetadata.customCoverPath;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (coverPath != null && File(coverPath).existsSync())
          Transform.scale(
            scale: 1.15,
            child: Image.file(File(coverPath), fit: BoxFit.cover),
          )
        else
          const ColoredBox(color: Color(0xFF141414)),
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 50.0, sigmaY: 50.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF141414).withValues(alpha: 0.55),
                  const Color(0xFF141414).withValues(alpha: 0.92),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DESKTOP: Two-column layout (original, untouched behaviour)
// ─────────────────────────────────────────────────────────────────────────────

class _DesktopHorizontalLayout extends StatelessWidget {
  const _DesktopHorizontalLayout({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 5, child: _ExpandedArtisticCore(track: track)),
        Expanded(flex: 4, child: _ExpandedUtilityPanel(track: track)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
enum _MobileOverlayMode { artwork, lyrics, queue }

// Lyrics sub-state: peek (artwork still visible) vs. expanded (full-screen)
enum _LyricsPhase { hidden, peek, expanded }

class _MobileVerticalLayout extends StatefulWidget {
  const _MobileVerticalLayout({
    required this.track,
    required this.mode,
    required this.onModeChanged,
  });

  final Track track;
  final _MobileOverlayMode mode;
  final ValueChanged<_MobileOverlayMode> onModeChanged;

  @override
  State<_MobileVerticalLayout> createState() => _MobileVerticalLayoutState();
}

class _MobileVerticalLayoutState extends State<_MobileVerticalLayout> {
  // Phase only relevant when mode == lyrics
  _LyricsPhase _lyricsPhase = _LyricsPhase.hidden;
  Timer? _peekTimer;

  @override
  void didUpdateWidget(_MobileVerticalLayout old) {
    super.didUpdateWidget(old);
    if (widget.mode == _MobileOverlayMode.lyrics &&
        old.mode != _MobileOverlayMode.lyrics) {
      // Just entered lyrics mode: start in peek, auto-expand smoothly after 1.1s
      setState(() => _lyricsPhase = _LyricsPhase.peek);
      _peekTimer?.cancel();
      _peekTimer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted && widget.mode == _MobileOverlayMode.lyrics) {
          setState(() => _lyricsPhase = _LyricsPhase.expanded);
        }
      });
    } else if (widget.mode != _MobileOverlayMode.lyrics) {
      _peekTimer?.cancel();
      setState(() => _lyricsPhase = _LyricsPhase.hidden);
    }
  }

  @override
  void dispose() {
    _peekTimer?.cancel();
    super.dispose();
  }

  void _toggleMode(_MobileOverlayMode target) {
    if (widget.mode == target) {
      widget.onModeChanged(_MobileOverlayMode.artwork);
    } else {
      widget.onModeChanged(target);
    }
  }

  void _handleSwipe(DragEndDetails details) {
    if (details.primaryVelocity != null) {
      if (details.primaryVelocity! < -200) {
        OrpheusAudioHandler.instance.skipToNext();
      } else if (details.primaryVelocity! > 200) {
        OrpheusAudioHandler.instance.skipToPrevious();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final coverPath = track.customMetadata.customCoverPath;
    final hasArt =
        coverPath != null && coverPath.isNotEmpty && File(coverPath).existsSync();
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    final isLyrics = widget.mode == _MobileOverlayMode.lyrics;
    final isQueue = widget.mode == _MobileOverlayMode.queue;
    final isArtwork = widget.mode == _MobileOverlayMode.artwork;
    final isOverlay = isLyrics || isQueue;

    final isLyricsExpanded = isLyrics && _lyricsPhase == _LyricsPhase.expanded;
    final isLyricsPeek = isLyrics && _lyricsPhase == _LyricsPhase.peek;

    String headerTitle = 'REPRODUCIENDO';
    if (isLyrics) headerTitle = 'LETRAS';
    if (isQueue) headerTitle = 'COLA DE REPRODUCCIÓN';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, topPad + 4, 16, bottomPad + 4),
        child: Column(
          children: [
            // ── Top Bar ───────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      size: 32, color: Colors.white70),
                  onPressed: () {
                    if (isOverlay) {
                      widget.onModeChanged(_MobileOverlayMode.artwork);
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                  tooltip: isOverlay ? 'Cerrar' : 'Minimizar',
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    headerTitle,
                    key: ValueKey(headerTitle),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.white54,
                    ),
                  ),
                ),
                _TrackMoreMenu(track: track, iconSize: 22),
              ],
            ),

            // ── Main Body Content with Tidal-style organic transitions ────────
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                switchInCurve: Curves.easeInOutCubic,
                switchOutCurve: Curves.easeInOutCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.02),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: isArtwork
                    ? Column(
                        key: const ValueKey('mobile_artwork_view'),
                        children: [
                          const Spacer(flex: 1),
                          GestureDetector(
                            onHorizontalDragEnd: _handleSwipe,
                            child: Container(
                              width: 280,
                              height: 280,
                              margin: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    blurRadius: 36,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                                image: hasArt
                                    ? DecorationImage(
                                        image: FileImage(File(coverPath)),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                                color: hasArt ? null : const Color(0xFF282828),
                              ),
                              child: hasArt
                                  ? null
                                  : const Center(
                                      child: Icon(Icons.music_note_rounded,
                                          size: 72, color: Colors.white24),
                                    ),
                            ),
                          ),
                          const Spacer(flex: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      MarqueeText(
                                        text: track.displayTitle,
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      MarqueeText(
                                        text: track.displayArtist,
                                        style: TextStyle(
                                          fontFamily: 'Inter',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w400,
                                          color: Colors.white.withValues(alpha: 0.65),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _FavoriteHeartButton(track: track, size: 26),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const _ExpandedProgressBar(),
                          const SizedBox(height: 8),
                          const _ExpandedPlaybackControls(),
                          const SizedBox(height: 8),
                        ],
                      )
                    : isQueue
                        ? Container(
                            key: const ValueKey('mobile_queue_fullscreen_pane'),
                            margin: const EdgeInsets.only(top: 4, bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: const _QueueTab(),
                          )
                        : Column(
                            key: const ValueKey('mobile_lyrics_container'),
                            children: [
                              // Peek header: compact artwork & title in peek phase
                              AnimatedSize(
                                duration: const Duration(milliseconds: 650),
                                curve: Curves.easeInOutCubic,
                                child: isLyricsPeek
                                    ? AnimatedOpacity(
                                        duration: const Duration(milliseconds: 500),
                                        curve: Curves.easeInOutCubic,
                                        opacity: isLyricsPeek ? 1.0 : 0.0,
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                                          child: Row(
                                            children: [
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: SizedBox(
                                                  width: 56,
                                                  height: 56,
                                                  child: hasArt
                                                      ? Image.file(
                                                          File(coverPath),
                                                          fit: BoxFit.cover,
                                                          cacheWidth: 112,
                                                        )
                                                      : const ColoredBox(
                                                          color: Color(0xFF282828),
                                                          child: Icon(
                                                              Icons.music_note_rounded,
                                                              size: 24,
                                                              color: Colors.white24),
                                                        ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      track.displayTitle,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontFamily: 'Inter',
                                                        fontSize: 15,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      track.displayArtist,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontFamily: 'Inter',
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w400,
                                                        color: Colors.white
                                                            .withValues(alpha: 0.6),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              _FavoriteHeartButton(track: track, size: 22),
                                            ],
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),

                              // Lyrics body
                              Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 650),
                                  curve: Curves.easeInOutCubic,
                                  key: const ValueKey('mobile_lyrics_pane'),
                                  margin: EdgeInsets.only(
                                    top: isLyricsExpanded ? 4 : 0,
                                    bottom: 4,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: LyricsView(
                                      track: track,
                                      transparentBackground: true,
                                      showThumbnail: isLyricsExpanded,
                                      onUserScrollStart: () {
                                        if (_lyricsPhase == _LyricsPhase.peek) {
                                          setState(() =>
                                              _lyricsPhase = _LyricsPhase.expanded);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),

                              // Peek controls: progress & playback controls in peek phase
                              AnimatedSize(
                                duration: const Duration(milliseconds: 650),
                                curve: Curves.easeInOutCubic,
                                child: isLyricsPeek
                                    ? AnimatedOpacity(
                                        duration: const Duration(milliseconds: 500),
                                        curve: Curves.easeInOutCubic,
                                        opacity: isLyricsPeek ? 1.0 : 0.0,
                                        child: const Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _ExpandedProgressBar(),
                                            SizedBox(height: 4),
                                            _ExpandedPlaybackControls(),
                                            SizedBox(height: 4),
                                          ],
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
              ),
            ),

            // ── Bottom Utility Row (100% transparent, floating over ambient background) ──
            _BottomUtilityRow(
              track: track,
              isLyrics: isLyrics,
              isQueue: isQueue,
              onLyricsTap: () => _toggleMode(_MobileOverlayMode.lyrics),
              onQueueTap: () => _toggleMode(_MobileOverlayMode.queue),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bottom utility row (100% transparent floating bar) ─────────────────────────
class _BottomUtilityRow extends StatelessWidget {
  const _BottomUtilityRow({
    required this.track,
    required this.isLyrics,
    required this.isQueue,
    required this.onLyricsTap,
    required this.onQueueTap,
  });

  final Track track;
  final bool isLyrics;
  final bool isQueue;
  final VoidCallback onLyricsTap;
  final VoidCallback onQueueTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(
              Icons.lyrics_rounded,
              color: isLyrics ? AppTheme.accent : Colors.white70,
              size: 26,
            ),
            onPressed: onLyricsTap,
            tooltip: 'Letras',
          ),
          _AudioHdBadge(track: track),
          IconButton(
            icon: Icon(
              Icons.queue_music_rounded,
              color: isQueue ? AppTheme.accent : Colors.white70,
              size: 26,
            ),
            onPressed: onQueueTap,
            tooltip: 'Cola de reproducción',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS (used by both layouts)
// ─────────────────────────────────────────────────────────────────────────────

/// Small pill-style collapse button (used on desktop in top-right position).
class _CollapseButton extends StatelessWidget {
  const _CollapseButton({required this.alignment});
  final String alignment;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.keyboard_arrow_down_rounded,
          size: 36, color: Colors.white),
      onPressed: () => Navigator.of(context).pop(),
      tooltip: 'Minimizar',
      hoverColor: Colors.white12,
    );
  }
}

// ── Left: Artistic Core (desktop only) ───────────────────────────────────────

class _ExpandedArtisticCore extends StatelessWidget {
  const _ExpandedArtisticCore({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final coverPath = track.customMetadata.customCoverPath;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Huge Cover Art
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity != null) {
                      if (details.primaryVelocity! < -200) {
                        OrpheusAudioHandler.instance.skipToNext();
                      } else if (details.primaryVelocity! > 200) {
                        OrpheusAudioHandler.instance.skipToPrevious();
                      }
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.40),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        ),
                      ],
                      image: coverPath != null && File(coverPath).existsSync()
                          ? DecorationImage(
                              image: FileImage(File(coverPath)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: coverPath == null || !File(coverPath).existsSync()
                        ? const Center(
                            child: Icon(Icons.music_note_rounded,
                                size: 80, color: Colors.white24),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),

          // Track Info
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MarqueeText(
                      text: track.displayTitle,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    MarqueeText(
                      text: track.displayArtist,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.70),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _FavoriteHeartButton(track: track, size: 28),
              const SizedBox(width: 8),
              _TrackMoreMenu(track: track, iconSize: 26),
            ],
          ),
          const SizedBox(height: 32),

          // Progress Bar
          const _ExpandedProgressBar(),
          const SizedBox(height: 24),

          // Playback Controls
          const _ExpandedPlaybackControls(),
        ],
      ),
    );
  }
}

// ── Progress bar (shared) ─────────────────────────────────────────────────────

class _ExpandedProgressBar extends StatelessWidget {
  const _ExpandedProgressBar();

  @override
  Widget build(BuildContext context) {
    if (!OrpheusAudioHandler.hasInstance) return const SizedBox.shrink();
    final handler = OrpheusAudioHandler.instance;

    return StreamBuilder<Duration>(
      stream: handler.positionStream,
      builder: (context, posSnap) {
        return StreamBuilder<Duration>(
          stream: handler.durationStream,
          builder: (context, durSnap) {
            final pos = posSnap.data ?? handler.position;
            final dur = durSnap.data ?? handler.duration;
            final maxVal = dur.inMilliseconds.toDouble();
            final curVal = (pos.inMilliseconds.toDouble()).clamp(
              0.0,
              maxVal > 0 ? maxVal : 1.0,
            );

            return Row(
              children: [
                SizedBox(
                  width: 45,
                  child: Text(
                    _fmt(pos),
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.60),
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6.0,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 8.0, elevation: 4),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 16.0),
                      activeTrackColor: AppTheme.accent,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.20),
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: curVal,
                      min: 0,
                      max: maxVal > 0 ? maxVal : 1.0,
                      onChanged: maxVal > 0
                          ? (val) => OrpheusAudioHandler.instance
                              .seek(Duration(milliseconds: val.toInt()))
                          : null,
                    ),
                  ),
                ),
                SizedBox(
                  width: 45,
                  child: Text(
                    _fmt(dur),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.60),
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

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ── Playback controls (shared) ────────────────────────────────────────────────

class _ExpandedPlaybackControls extends StatelessWidget {
  const _ExpandedPlaybackControls();

  @override
  Widget build(BuildContext context) {
    if (!OrpheusAudioHandler.hasInstance) return const SizedBox.shrink();
    final handler = OrpheusAudioHandler.instance;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Shuffle
        StreamBuilder<bool>(
          stream: handler.shuffleStream,
          builder: (_, snap) {
            final on = snap.data ?? handler.shuffleEnabled;
            return IconButton(
              icon: Icon(Icons.shuffle_rounded,
                  color: on ? AppTheme.accent : Colors.white54, size: 26),
              onPressed: handler.toggleShuffle,
            );
          },
        ),
        const SizedBox(width: 16),
        // Previous
        StreamBuilder<Track?>(
          stream: handler.currentTrackStream,
          builder: (context, _) {
            final canPrev = handler.canSkipPrevious;
            return IconButton(
              icon: Icon(
                Icons.skip_previous_rounded,
                color: canPrev ? Colors.white : Colors.white24,
                size: 38,
              ),
              onPressed: canPrev ? handler.skipToPrevious : null,
            );
          },
        ),
        const SizedBox(width: 16),
        // Play / Pause (prominent circle)
        StreamBuilder<bool>(
          stream: handler.isPlayingStream,
          builder: (_, snap) {
            final playing = snap.data ?? handler.isPlaying;
            return GestureDetector(
              onTap: handler.togglePlayPause,
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.black,
                  size: 36,
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 16),
        // Next — uses canSkipNextStream for accurate disabled state
        StreamBuilder<bool>(
          stream: handler.canSkipNextStream,
          initialData: handler.canSkipNext,
          builder: (_, snap) {
            final canNext = snap.data ?? handler.canSkipNext;
            return Opacity(
              opacity: canNext ? 1.0 : 0.3,
              child: IconButton(
                icon: const Icon(
                  Icons.skip_next_rounded,
                  color: Colors.white,
                  size: 38,
                ),
                onPressed: canNext ? handler.skipToNext : null,
              ),
            );
          },
        ),
        const SizedBox(width: 16),
        // Repeat
        StreamBuilder<PlayerRepeatMode>(
          stream: handler.repeatStream,
          builder: (_, snap) {
            final mode = snap.data ?? handler.repeatMode;
            final on = mode != PlayerRepeatMode.off;
            final isSingle = mode == PlayerRepeatMode.single;
            return IconButton(
              icon: Icon(
                isSingle ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                color: on ? AppTheme.accent : Colors.white54,
                size: 26,
              ),
              onPressed: handler.toggleRepeat,
            );
          },
        ),
      ],
    );
  }
}

// ── Right: Utility Panel (desktop only — tabs Letras / Cola) ──────────────────

class _ExpandedUtilityPanel extends StatefulWidget {
  const _ExpandedUtilityPanel({required this.track});
  final Track track;

  @override
  State<_ExpandedUtilityPanel> createState() => _ExpandedUtilityPanelState();
}

class _ExpandedUtilityPanelState extends State<_ExpandedUtilityPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80, bottom: 40, right: 40, left: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: AppTheme.accent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(
                fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(
                fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w500),
            dividerColor: Colors.transparent,
            tabAlignment: TabAlignment.start,
            tabs: const [Tab(text: 'Letras'), Tab(text: 'Cola')],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: LyricsView(
                    track: widget.track,
                    transparentBackground: true,
                  ),
                ),
                const _QueueTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Queue Tab (Tidal Style) ───────────────────────────────────────────────────

class _QueueTab extends StatefulWidget {
  const _QueueTab();

  @override
  State<_QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends State<_QueueTab> {
  final _scrollController = ScrollController();
  bool _hasInitialScrolled = false;

  /// Mounts the queue with the currently playing track positioned at ~25% from
  /// the top of the viewport — exactly Tidal-style, without lazy loading failures.
  void _scrollToCurrentTrack(int historyCount) {
    if (!mounted || _hasInitialScrolled) return;
    if (!_scrollController.hasClients) return;
    _hasInitialScrolled = true;

    final viewportHeight = _scrollController.position.viewportDimension;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // Accumulated height of the history section:
    // Header label (~34px) + items (56px each) + Divider (~17px)
    final double historyHeight = historyCount > 0
        ? 34.0 + (historyCount * 56.0) + 17.0
        : 0.0;

    final double targetOffset = historyHeight - (viewportHeight * 0.25);
    final double clampedOffset = targetOffset.clamp(0.0, maxScroll);

    _scrollController.jumpTo(clampedOffset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildCover(Track track, {double size = 42, bool isPast = false}) {
    final coverPath = track.customMetadata.customCoverPath;
    final hasArt = coverPath != null && coverPath.isNotEmpty && File(coverPath).existsSync();

    return Opacity(
      opacity: isPast ? 0.45 : 1.0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: size,
          height: size,
          child: hasArt
              ? Image.file(File(coverPath), fit: BoxFit.cover, cacheWidth: (size * 2).toInt())
              : const ColoredBox(
                  color: AppTheme.bgHover,
                  child: Icon(Icons.music_note_rounded, color: AppTheme.textHint, size: 20),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!OrpheusAudioHandler.hasInstance) return const SizedBox.shrink();
    final handler = OrpheusAudioHandler.instance;
    return StreamBuilder<List<Track>>(
      stream: handler.queueTracksStream,
      initialData: handler.queueTracks,
      builder: (context, snap) {
        final queue = snap.data ?? handler.queueTracks;
        final currentIndex = handler.currentIndex;
        final currentTrack = handler.currentTrack;

        final historyTracks = (currentIndex > 0 && currentIndex < queue.length)
            ? queue.sublist(0, currentIndex)
            : <Track>[];
        final upcomingTracks = (currentIndex >= 0 && currentIndex < queue.length - 1)
            ? queue.sublist(currentIndex + 1)
            : (currentIndex < 0 ? queue : <Track>[]);

        if (!_hasInitialScrolled && currentTrack != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToCurrentTrack(historyTracks.length);
          });
        }

        if (queue.isEmpty && currentTrack == null) {
          return const Center(
            child: Text('La cola está vacía',
                style: TextStyle(color: Colors.white54, fontSize: 15)),
          );
        }

        return ListView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            // ── 1. HISTORIAL DE REPRODUCCIÓN ──────────────────────────────────
            if (historyTracks.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
                child: Text(
                  'HISTORIAL DE REPRODUCCIÓN',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textHint,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              for (int i = 0; i < historyTracks.length; i++) ...[
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  onTap: () => OrpheusAudioHandler.instance.skipToQueueItem(i),
                  leading: _buildCover(historyTracks[i], isPast: true),
                  title: Text(
                    historyTracks[i].displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  subtitle: Text(
                    historyTracks[i].displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
                  ),
                  trailing: Icon(
                    Icons.history_rounded,
                    color: Colors.white.withValues(alpha: 0.3),
                    size: 18,
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(color: AppTheme.divider, height: 1),
              ),
            ],

            // ── 2. REPRODUCIENDO ACTUALMENTE ──────────────────────────────────
            if (currentTrack != null) ...[
              Padding(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Text(
                        'REPRODUCIENDO ACTUALMENTE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textHint,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      leading: _buildCover(currentTrack),
                      title: Text(
                        currentTrack.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        currentTrack.displayArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      trailing: StreamBuilder<bool>(
                        stream: OrpheusAudioHandler.instance.isPlayingStream,
                        initialData: OrpheusAudioHandler.instance.isPlaying,
                        builder: (_, playSnap) => AnimatedEqualizer(
                          isPlaying: playSnap.data ?? false,
                          barCount: 3,
                          barWidth: 2.8,
                          maxHeight: 16.0,
                          minHeight: 4.0,
                          spacing: 2.5,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(color: AppTheme.divider, height: 1),
                    ),
                  ],
                ),
              ),
            ],

            // ── 3. A CONTINUACIÓN ──────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text(
                    'A CONTINUACIÓN:',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textHint,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                if (queue.isNotEmpty)
                  TextButton.icon(
                    onPressed: OrpheusAudioHandler.instance.clearQueue,
                    icon: const Icon(Icons.clear_all_rounded, size: 16, color: Colors.white70),
                    label: const Text('Limpiar',
                        style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Inter')),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                    ),
                  ),
              ],
            ),

            if (upcomingTracks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No hay canciones a continuación',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                ),
              )
            else
              for (int index = 0; index < upcomingTracks.length; index++) ...[
                Builder(builder: (context) {
                  final track = upcomingTracks[index];
                  final actualIndex = currentIndex + 1 + index;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    onTap: () => OrpheusAudioHandler.instance.skipToQueueItem(actualIndex),
                    leading: _buildCover(track),
                    title: Text(
                      track.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      track.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                    ),
                    trailing: const Icon(
                      Icons.drag_handle_rounded,
                      color: Colors.white38,
                      size: 20,
                    ),
                  );
                }),
              ],
          ],
        );
      },
    );
  }
}

class _FavoriteHeartButton extends StatefulWidget {
  const _FavoriteHeartButton({required this.track, this.size = 26});

  final Track track;
  final double size;

  @override
  State<_FavoriteHeartButton> createState() => _FavoriteHeartButtonState();
}

class _FavoriteHeartButtonState extends State<_FavoriteHeartButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.32).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.32, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 55,
      ),
    ]).animate(_animController);
  }

  @override
  void didUpdateWidget(_FavoriteHeartButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.track.trackId != oldWidget.track.trackId) {
      _animController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: LocalDatabase.instance.likedTrackIdsNotifier,
      builder: (context, likedIds, _) {
        final isLiked = likedIds.contains(widget.track.trackId);

        return ScaleTransition(
          scale: _scaleAnimation,
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
              width: widget.size + 14,
              height: widget.size + 14,
            ),
            icon: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              size: widget.size,
              color: isLiked ? Colors.redAccent : Colors.white70,
            ),
            onPressed: () {
              _animController.forward(from: 0.0);
              LocalDatabase.instance.toggleLikeOptimistic(widget.track.trackId);
            },
          ),
        );
      },
    );
  }
}

class _TrackMoreMenu extends StatefulWidget {
  const _TrackMoreMenu({required this.track, this.iconSize = 22});

  final Track track;
  final double iconSize;

  @override
  State<_TrackMoreMenu> createState() => _TrackMoreMenuState();
}

class _TrackMoreMenuState extends State<_TrackMoreMenu> {
  List<Playlist> _playlists = [];
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _fetchPlaylists();
    _sub = LocalDatabase.instance.watchPlaylists().listen((_) => _fetchPlaylists());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _fetchPlaylists() async {
    final list = await LocalDatabase.instance.getAllPlaylists();
    if (mounted) setState(() => _playlists = list);
  }

  @override
  Widget build(BuildContext context) {
    final customPlaylists = _playlists.where((p) => !p.isDefault).toList();

    return PopupMenuButton<dynamic>(
      icon: Icon(
        Icons.more_vert_rounded,
        size: widget.iconSize,
        color: Colors.white70,
      ),
      color: AppTheme.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.divider),
      ),
      onSelected: (value) {
        if (value == 'play_next') {
          OrpheusAudioHandler.instance.playNext(widget.track);
          AppToast.showText(context, 'Se reproducirá a continuación');
        } else if (value == 'add_to_queue') {
          OrpheusAudioHandler.instance.addToQueueTrack(widget.track);
          AppToast.showText(context, 'Añadida a la cola');
        } else if (value is Playlist) {
          LocalDatabase.instance
              .addTrackToPlaylist(
            playlist: value,
            trackId: widget.track.trackId,
          )
              .then((_) {
            if (context.mounted) {
              AppToast.showAddedToPlaylist(
                context,
                track: widget.track,
                playlist: value,
              );
            }
          });
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<dynamic>>[
          const PopupMenuItem(
            value: 'play_next',
            child: Row(
              children: [
                Icon(Icons.playlist_play_rounded, size: 18, color: AppTheme.textSecondary),
                SizedBox(width: 12),
                Text('Reproducir siguiente', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'add_to_queue',
            child: Row(
              children: [
                Icon(Icons.queue_music_rounded, size: 18, color: AppTheme.textSecondary),
                SizedBox(width: 12),
                Text('Añadir a la cola', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
              ],
            ),
          ),
        ];

        if (customPlaylists.isNotEmpty) {
          items.add(const PopupMenuDivider());
          for (final pl in customPlaylists) {
            items.add(
              PopupMenuItem(
                value: pl,
                child: Row(
                  children: [
                    const Icon(Icons.playlist_add_rounded, size: 18, color: AppTheme.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        pl.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }

        return items;
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AUDIO HD / Quality Badge (interactive)
// ─────────────────────────────────────────────────────────────────────────────

/// Tappable quality badge (e.g. "AUDIO HD" / "HI-FI" / "HQ") that opens a
/// bottom sheet with a breakdown of the track's audio format and quality tier.
class _AudioHdBadge extends StatelessWidget {
  const _AudioHdBadge({required this.track});
  final Track track;

  /// Returns (badgeLabel, accentColor) based on audioQuality field.
  (String, Color) get _badgeInfo {
    switch (track.audioQuality.toUpperCase()) {
      case 'HI-FI':
      case 'HIFI':
        return ('HI-FI', const Color(0xFF00D4FF));
      case 'HQ':
        return ('AUDIO HD', const Color(0xFF7C6AF7));
      case 'VIDEO':
        return ('VIDEO', const Color(0xFFF7A26A));
      case 'STREAM':
        return ('STREAM', Colors.white38);
      default:
        return ('AUDIO HD', const Color(0xFF7C6AF7));
    }
  }

  String get _formatLabel {
    switch (track.fileType) {
      case FileType.flac:
        return 'FLAC';
      case FileType.mp3:
        return 'MP3';
      case FileType.wav:
        return 'WAV';
      case FileType.m4a:
        return 'M4A / AAC';
      case FileType.mp4:
        return 'MP4';
      default:
        return track.fileType.name.toUpperCase();
    }
  }

  String get _qualityDescription {
    switch (track.audioQuality.toUpperCase()) {
      case 'HI-FI':
      case 'HIFI':
        return 'Calidad sin pérdidas (Lossless). Fidelidad máxima con compresión '
            'sin pérdida de datos — ideal para audiófilos y equipos de alta gama.';
      case 'HQ':
        return 'Alta calidad (HD). Compresión con alta tasa de bits, '
            'adecuada para la gran mayoría de sistemas de escucha.';
      case 'VIDEO':
        return 'Pista de audio extraída de vídeo. La calidad depende del '
            'bitrate del contenedor de vídeo original.';
      case 'STREAM':
        return 'Calidad estándar de streaming. Optimizada para ancho de banda '
            'reducido; puede presentar ligeras pérdidas perceptibles.';
      default:
        return 'Formato de audio local importado desde tu biblioteca.';
    }
  }

  void _showInfoSheet(BuildContext context) {
    final (label, accent) = _badgeInfo;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle pill
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Badge + Title row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: accent.withValues(alpha: 0.7), width: 1.2),
                      borderRadius: BorderRadius.circular(6),
                      color: accent.withValues(alpha: 0.08),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.4,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Información de Audio',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              const Divider(color: Colors.white10),
              const SizedBox(height: 16),

              // Format row
              _InfoRow(
                icon: Icons.audiotrack_rounded,
                label: 'Formato',
                value: _formatLabel,
                accent: accent,
              ),
              const SizedBox(height: 12),
              _InfoRow(
                icon: Icons.high_quality_rounded,
                label: 'Calidad',
                value: track.audioQuality,
                accent: accent,
              ),

              const SizedBox(height: 20),
              const Divider(color: Colors.white10),
              const SizedBox(height: 14),

              // Description
              Text(
                _qualityDescription,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: Colors.white60,
                  height: 1.6,
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final (label, accent) = _badgeInfo;
    return GestureDetector(
      onTap: () => _showInfoSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: accent.withValues(alpha: 0.5), width: 1),
          borderRadius: BorderRadius.circular(4),
          color: accent.withValues(alpha: 0.06),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: accent.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

/// Simple two-column info row for the audio quality sheet.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: accent.withValues(alpha: 0.7)),
        const SizedBox(width: 10),
        Text(
          '$label:',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: Colors.white54,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
