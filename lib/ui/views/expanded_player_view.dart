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
    return Scaffold(
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
                  child: _CollapseButton(alignment: 'right'),
                ),
            ],
          );
        },
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
          filter: ui.ImageFilter.blur(sigmaX: 90.0, sigmaY: 90.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF141414).withOpacity(0.5),
                  const Color(0xFF141414).withOpacity(0.88),
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
// MOBILE: Full-screen vertical Tidal-style layout
// ─────────────────────────────────────────────────────────────────────────────

class _MobileVerticalLayout extends StatefulWidget {
  const _MobileVerticalLayout({required this.track});
  final Track track;

  @override
  State<_MobileVerticalLayout> createState() => _MobileVerticalLayoutState();
}

class _MobileVerticalLayoutState extends State<_MobileVerticalLayout>
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
    final track = widget.track;
    final coverPath = track.customMetadata.customCoverPath;
    final hasArt =
        coverPath != null && coverPath.isNotEmpty && File(coverPath).existsSync();
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Column(
        children: [
          SizedBox(height: topPad + 12),

          // ── Collapse button (centered, top) ────────────────────────────
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white38,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Album cover (square, 280×280) ──────────────────────────────
          Center(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
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
                  : const Center(
                      child: Icon(Icons.music_note_rounded,
                          size: 72, color: Colors.white24),
                    ),
            ),
          ),

          const SizedBox(height: 28),

          // ── Title & Artist ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  track.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Progress slider ───────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: _ExpandedProgressBar(),
          ),

          const SizedBox(height: 16),

          // ── Playback controls ─────────────────────────────────────────
          const _ExpandedPlaybackControls(),

          const SizedBox(height: 12),

          // ── Tab bar: Letras / Cola ────────────────────────────────────
          TabBar(
            controller: _tabController,
            isScrollable: false,
            indicatorColor: AppTheme.accent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white38,
            labelStyle: const TextStyle(
                fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(
                fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w400),
            dividerColor: Colors.white12,
            tabs: const [Tab(text: 'Letras'), Tab(text: 'Cola')],
          ),

          // ── Tab content ───────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(0)),
                  child: LyricsView(track: track, transparentBackground: true),
                ),
                const _QueueTab(),
              ],
            ),
          ),

          SizedBox(height: bottomPad),
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

// ── Queue Tab ─────────────────────────────────────────────────────────────────

class _QueueTab extends StatelessWidget {
  const _QueueTab();

  @override
  Widget build(BuildContext context) {
    final player = AudioPlayerService.instance;
    return StreamBuilder<List<Track>>(
      stream: player.queueStream,
      initialData: player.queue,
      builder: (context, snap) {
        final queue = snap.data ?? player.queue;
        final currentIndex = player.currentIndex;

        if (queue.isEmpty) {
          return const Center(
            child: Text('La cola está vacía',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
          );
        }

        return Column(
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'A continuación',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                TextButton.icon(
                  onPressed: player.clearQueue,
                  icon: const Icon(Icons.clear_all_rounded,
                      size: 18, color: Colors.white70),
                  label: const Text('Limpiar',
                      style: TextStyle(
                          color: Colors.white70, fontFamily: 'Inter')),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: queue.length,
                itemBuilder: (context, index) {
                  final track = queue[index];
                  final isCurrent = index == currentIndex;

                  return InkWell(
                    onDoubleTap: () async =>
                        player.loadPlaylist(queue, initialIndex: index),
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 12),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? AppTheme.accent.withOpacity(0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border(
                          left: BorderSide(
                            color: isCurrent
                                ? AppTheme.accent
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            child: isCurrent
                                ? const Icon(Icons.volume_up_rounded,
                                    color: AppTheme.accent, size: 18)
                                : Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.4),
                                      fontSize: 13,
                                      fontFamily: 'Inter',
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isCurrent
                                        ? AppTheme.accent
                                        : Colors.white,
                                    fontSize: 14,
                                    fontWeight: isCurrent
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    shadows: isCurrent
                                        ? [
                                            Shadow(
                                              color: AppTheme.accent
                                                  .withOpacity(0.5),
                                              blurRadius: 8,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  track.displayArtist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
