import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/services/audio_player_service.dart';
import '../theme/app_theme.dart';
import 'lyrics_view.dart';

/// The premium Now Playing "Theater View" (Expanded Player) replacing Explore.
class ExpandedPlayerView extends StatelessWidget {
  const ExpandedPlayerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Background will be blurred image
      body: StreamBuilder<Track?>(
        stream: AudioPlayerService.instance.currentTrackStream,
        initialData: AudioPlayerService.instance.currentTrack,
        builder: (context, snap) {
          final track = snap.data;

          return Stack(
            children: [
              // 1. Dynamic Blurred Background
              if (track != null) _BlurredImageBackground(track: track),

              // 2. Main content split layout
              if (track != null)
                Row(
                  children: [
                    // Left Side: Artwork & Controls
                    Expanded(
                      flex: 5,
                      child: _ExpandedArtisticCore(track: track),
                    ),
                    // Right Side: Utility Panel (Lyrics / Queue)
                    Expanded(
                      flex: 4,
                      child: _ExpandedUtilityPanel(track: track),
                    ),
                  ],
                ),

              // 3. Close (Minimize) Button
              Positioned(
                top: 40,
                right: 40,
                child: IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 36, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Minimizar',
                  hoverColor: Colors.white12,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Background Atmosphere ───────────────────────────────────────────────────

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
            child: Image.file(
              File(coverPath),
              fit: BoxFit.cover,
            ),
          )
        else
          Container(color: const Color(0xFF141414)), // Fallback color

        // Blur effect
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 90.0, sigmaY: 90.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF141414).withOpacity(0.5),
                  const Color(0xFF141414).withOpacity(0.85),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Left: Artistic Core ─────────────────────────────────────────────────────

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
                          child: Icon(Icons.music_note_rounded, size: 80, color: Colors.white24),
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

          // Progress Bar (Thicker)
          const _ExpandedProgressBar(),
          const SizedBox(height: 24),

          // Playback Controls
          const _ExpandedPlaybackControls(),
        ],
      ),
    );
  }
}

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
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0, elevation: 4),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
                      activeTrackColor: AppTheme.accent,
                      inactiveTrackColor: Colors.white.withOpacity(0.2),
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: curVal,
                      min: 0,
                      max: maxVal > 0 ? maxVal : 1.0,
                      onChanged: maxVal > 0
                          ? (val) => player.seek(Duration(milliseconds: val.toInt()))
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

class _ExpandedPlaybackControls extends StatelessWidget {
  const _ExpandedPlaybackControls();

  @override
  Widget build(BuildContext context) {
    final player = AudioPlayerService.instance;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        StreamBuilder<bool>(
          stream: player.shuffleStream,
          builder: (_, snap) {
            final on = snap.data ?? player.shuffleEnabled;
            return IconButton(
              icon: Icon(Icons.shuffle_rounded, color: on ? AppTheme.accent : Colors.white54, size: 28),
              onPressed: player.toggleShuffle,
            );
          },
        ),
        const SizedBox(width: 24),
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 40),
          onPressed: player.previous,
        ),
        const SizedBox(width: 24),
        StreamBuilder<bool>(
          stream: player.isPlayingStream,
          builder: (_, snap) {
            final playing = snap.data ?? player.isPlaying;
            return GestureDetector(
              onTap: playing ? player.pause : player.play,
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.black,
                  size: 40,
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 24),
        IconButton(
          icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 40),
          onPressed: player.next,
        ),
        const SizedBox(width: 24),
        StreamBuilder<bool>(
          stream: player.repeatStream,
          builder: (_, snap) {
            final on = snap.data ?? player.repeatEnabled;
            return IconButton(
              icon: Icon(Icons.repeat_rounded, color: on ? AppTheme.accent : Colors.white54, size: 28),
              onPressed: player.toggleRepeat,
            );
          },
        ),
      ],
    );
  }
}

// ── Right: Utility Panel (Tabs) ─────────────────────────────────────────────

class _ExpandedUtilityPanel extends StatefulWidget {
  const _ExpandedUtilityPanel({required this.track});

  final Track track;

  @override
  State<_ExpandedUtilityPanel> createState() => _ExpandedUtilityPanelState();
}

class _ExpandedUtilityPanelState extends State<_ExpandedUtilityPanel> with SingleTickerProviderStateMixin {
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
            labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 18, fontWeight: FontWeight.w500),
            dividerColor: Colors.transparent,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Letras'),
              Tab(text: 'Cola'),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Lyrics
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: LyricsView(
                    track: widget.track,
                    transparentBackground: true, // We blend into the blurred background!
                  ),
                ),
                // Tab 2: Queue
                const _QueueTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueTab extends StatelessWidget {
  const _QueueTab();

  @override
  Widget build(BuildContext context) {
    final player = AudioPlayerService.instance;
    // We listen to the current track stream to rebuild the queue UI when tracks change.
    return StreamBuilder<Track?>(
      stream: player.currentTrackStream,
      builder: (context, _) {
        final queue = player.queue;
        final currentIndex = player.currentIndex;

        if (queue.isEmpty) {
          return const Center(
            child: Text(
              'La cola está vacía',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          );
        }

        return Column(
          children: [
            // Queue Header
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
                  onPressed: () {
                    player.clearQueue();
                  },
                  icon: const Icon(Icons.clear_all_rounded, size: 18, color: Colors.white70),
                  label: const Text(
                    'Limpiar',
                    style: TextStyle(color: Colors.white70, fontFamily: 'Inter'),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    onDoubleTap: () async {
                      // Skip to this track in the queue.
                      // The current architecture requires us to simulate skipping.
                      // In a real app we'd have a `playQueueIndex` method.
                      // For now, if we have loadPlaylist we can use it.
                      await player.loadPlaylist(queue, initialIndex: index);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      decoration: BoxDecoration(
                        color: isCurrent ? Colors.white.withOpacity(0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          // Index or Playing Icon
                          SizedBox(
                            width: 30,
                            child: isCurrent
                                ? const Icon(Icons.volume_up_rounded, color: AppTheme.accent, size: 18)
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
                                    color: isCurrent ? AppTheme.accent : Colors.white,
                                    fontSize: 14,
                                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
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
