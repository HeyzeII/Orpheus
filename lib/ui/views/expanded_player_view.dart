import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/models.dart';
import '../../core/services/audio_player_service.dart';
import '../theme/app_theme.dart';
import 'lyrics_view.dart';

/// The premium Now Playing "Theater View" (Expanded Player) replacing Explore.
///
/// - **Desktop (≥ 600 px):** two-column layout: artwork + controls on the left,
///   lyrics/queue tab panel on the right. Identical to the original design.
/// - **Mobile  (< 600 px):** full-screen vertical Tidal-style layout:
///   collapse button → square cover art → title/artist → progress slider →
///   playback controls → bottom swipeable tab bar (Letras / Cola).
class ExpandedPlayerView extends StatelessWidget {
  const ExpandedPlayerView({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: StreamBuilder<Track?>(
          stream: AudioPlayerService.instance.currentTrackStream,
          initialData: AudioPlayerService.instance.currentTrack,
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
                      ? _MobileVerticalLayout(track: track)
                      : _DesktopHorizontalLayout(track: track),

                // 3. Collapse button — top-right on desktop, top-center on mobile
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
                  const Color(0xFF141414).withOpacity(0.55),
                  const Color(0xFF141414).withOpacity(0.92),
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

class _MobileVerticalLayout extends StatefulWidget {
  const _MobileVerticalLayout({required this.track});
  final Track track;

  @override
  State<_MobileVerticalLayout> createState() => _MobileVerticalLayoutState();
}

class _MobileVerticalLayoutState extends State<_MobileVerticalLayout> {
  _MobileOverlayMode _mode = _MobileOverlayMode.artwork;

  void _toggleMode(_MobileOverlayMode target) {
    setState(() {
      if (_mode == target) {
        _mode = _MobileOverlayMode.artwork;
      } else {
        _mode = target;
      }
    });
  }

  void _handleSwipe(DragEndDetails details) {
    if (details.primaryVelocity != null) {
      if (details.primaryVelocity! < -200) {
        AudioPlayerService.instance.next();
      } else if (details.primaryVelocity! > 200) {
        AudioPlayerService.instance.previous();
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
    final isLyricsOrQueue = _mode != _MobileOverlayMode.artwork;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, topPad + 4, 16, bottomPad + 8),
        child: Column(
          children: [
            // ── Top Bar: Minimize handle + Action buttons (Letras / Cola) ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      size: 32, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Minimizar',
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.lyrics_rounded,
                        color: _mode == _MobileOverlayMode.lyrics
                            ? AppTheme.accent
                            : Colors.white54,
                        size: 24,
                      ),
                      onPressed: () => _toggleMode(_MobileOverlayMode.lyrics),
                      tooltip: 'Letras',
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.queue_music_rounded,
                        color: _mode == _MobileOverlayMode.queue
                            ? AppTheme.accent
                            : Colors.white54,
                        size: 24,
                      ),
                      onPressed: () => _toggleMode(_MobileOverlayMode.queue),
                      tooltip: 'Cola de reproducción',
                    ),
                  ],
                ),
              ],
            ),

            // ── Animated Cover Art Container (aligns top-left & resizes smoothly when lyrics/queue mode is active) ──
            AnimatedAlign(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              alignment: isLyricsOrQueue ? Alignment.topLeft : Alignment.topCenter,
              child: GestureDetector(
                onHorizontalDragEnd: _handleSwipe,
                onTap: isLyricsOrQueue ? () => setState(() => _mode = _MobileOverlayMode.artwork) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  width: isLyricsOrQueue ? 72 : 280,
                  height: isLyricsOrQueue ? 72 : 280,
                  margin: EdgeInsets.only(
                    top: isLyricsOrQueue ? 0 : 16,
                    bottom: isLyricsOrQueue ? 4 : 16,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: isLyricsOrQueue ? 12 : 36,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    image: hasArt
                        ? DecorationImage(
                            image: FileImage(File(coverPath!)),
                            fit: BoxFit.cover,
                          )
                        : null,
                    color: hasArt ? null : const Color(0xFF282828),
                  ),
                  child: hasArt
                      ? null
                      : Center(
                          child: Icon(Icons.music_note_rounded,
                              size: isLyricsOrQueue ? 28 : 72, color: Colors.white24),
                        ),
                ),
              ),
            ),

            // ── Expanded space for Lyrics or Queue ──
            if (isLyricsOrQueue)
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _mode == _MobileOverlayMode.lyrics
                      ? Container(
                          key: const ValueKey('mobile_lyrics_pane'),
                          margin: EdgeInsets.zero,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: LyricsView(
                                track: track, transparentBackground: true),
                          ),
                        )
                      : Container(
                          key: const ValueKey('mobile_queue_pane'),
                          margin: EdgeInsets.zero,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const _QueueTab(),
                        ),
                ),
              )
            else
              const Spacer(),

            // ── Track Title & Artist ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Progress Slider ───────────────────────────────────────────
            const _ExpandedProgressBar(),

            const SizedBox(height: 12),

            // ── Playback Controls ─────────────────────────────────────────
            const _ExpandedPlaybackControls(),
          ],
        ),
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
                        AudioPlayerService.instance.next();
                      } else if (details.primaryVelocity! > 200) {
                        AudioPlayerService.instance.previous();
                      }
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
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
          Text(
            track.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            track.displayArtist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.7),
            ),
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
    final player = AudioPlayerService.instance;

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, posSnap) {
        return StreamBuilder<Duration>(
          stream: player.durationStream,
          builder: (context, durSnap) {
            final pos = posSnap.data ?? player.position;
            final dur = durSnap.data ?? player.duration;
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
                      color: Colors.white.withOpacity(0.6),
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
                      inactiveTrackColor: Colors.white.withOpacity(0.2),
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: curVal,
                      min: 0,
                      max: maxVal > 0 ? maxVal : 1.0,
                      onChanged: maxVal > 0
                          ? (val) => player
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
                      color: Colors.white.withOpacity(0.6),
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
    final player = AudioPlayerService.instance;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Shuffle
        StreamBuilder<bool>(
          stream: player.shuffleStream,
          builder: (_, snap) {
            final on = snap.data ?? player.shuffleEnabled;
            return IconButton(
              icon: Icon(Icons.shuffle_rounded,
                  color: on ? AppTheme.accent : Colors.white54, size: 26),
              onPressed: player.toggleShuffle,
            );
          },
        ),
        const SizedBox(width: 16),
        // Previous
        IconButton(
          icon:
              const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 38),
          onPressed: player.previous,
        ),
        const SizedBox(width: 16),
        // Play / Pause (prominent circle)
        StreamBuilder<bool>(
          stream: player.isPlayingStream,
          builder: (_, snap) {
            final playing = snap.data ?? player.isPlaying;
            return GestureDetector(
              onTap: playing ? player.pause : player.play,
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
        // Next
        IconButton(
          icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 38),
          onPressed: player.next,
        ),
        const SizedBox(width: 16),
        // Repeat
        StreamBuilder<PlayerRepeatMode>(
          stream: player.repeatStream,
          builder: (_, snap) {
            final mode = snap.data ?? player.repeatMode;
            final on = mode != PlayerRepeatMode.off;
            final isSingle = mode == PlayerRepeatMode.single;
            return IconButton(
              icon: Icon(
                isSingle ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                color: on ? AppTheme.accent : Colors.white54,
                size: 26,
              ),
              onPressed: player.toggleRepeat,
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

class _QueueTab extends StatelessWidget {
  const _QueueTab();

  Widget _buildCover(Track track, {double size = 42}) {
    final coverPath = track.customMetadata.customCoverPath;
    final hasArt = coverPath != null && coverPath.isNotEmpty && File(coverPath).existsSync();

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: size,
        height: size,
        child: hasArt
            ? Image.file(File(coverPath!), fit: BoxFit.cover, cacheWidth: (size * 2).toInt())
            : const ColoredBox(
                color: AppTheme.bgHover,
                child: Icon(Icons.music_note_rounded, color: AppTheme.textHint, size: 20),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = AudioPlayerService.instance;
    return StreamBuilder<List<Track>>(
      stream: player.queueStream,
      initialData: player.queue,
      builder: (context, snap) {
        final queue = snap.data ?? player.queue;
        final currentIndex = player.currentIndex;
        final currentTrack = player.currentTrack;

        if (queue.isEmpty && currentTrack == null) {
          return const Center(
            child: Text('La cola está vacía',
                style: TextStyle(color: Colors.white54, fontSize: 15)),
          );
        }

        final upcomingTracks = currentIndex >= 0 && currentIndex < queue.length - 1
            ? queue.sublist(currentIndex + 1)
            : (currentIndex < 0 ? queue : <Track>[]);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. REPRODUCIENDO ACTUALMENTE
            if (currentTrack != null) ...[
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
                trailing: const Icon(Icons.volume_up_rounded, color: AppTheme.accent, size: 22),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(color: AppTheme.divider, height: 1),
              ),
            ],

            // 2. A CONTINUACIÓN:
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
                    onPressed: player.clearQueue,
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

            // 3. ListView.builder with upcoming tracks and drag handles
            Expanded(
              child: upcomingTracks.isEmpty
                  ? const Center(
                      child: Text('No hay canciones a continuación',
                          style: TextStyle(color: Colors.white38, fontSize: 13)),
                    )
                  : ListView.builder(
                      itemCount: upcomingTracks.length,
                      itemBuilder: (context, index) {
                        final track = upcomingTracks[index];
                        final actualIndex = currentIndex + 1 + index;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          onTap: () async => player.loadPlaylist(queue, initialIndex: actualIndex),
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
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                          ),
                          trailing: const Icon(
                            Icons.drag_handle_rounded,
                            color: Colors.white38,
                            size: 20,
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
