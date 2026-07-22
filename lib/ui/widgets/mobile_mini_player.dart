import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/track.dart';
import '../../core/services/audio_player_service.dart';
import '../theme/app_theme.dart';
import '../views/expanded_player_view.dart';

/// Floating mini-player card for mobile (Android) that sits above
/// the [BottomNavigationBar].
///
/// - Returns [SizedBox.shrink] when no track is loaded.
/// - When a track is active it renders an 64px card with cover art,
///   title/artist, play-pause and skip-next controls, and a thin
///   cyan progress bar along the bottom edge.
/// - Tapping anywhere on the card opens [ExpandedPlayerView] via the same
///   bottom-sheet slide-up animation used by the desktop [PlayerBar].
class MobileMiniPlayer extends StatelessWidget {
  const MobileMiniPlayer({super.key});

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _openExpandedPlayer(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withAlpha(128),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) =>
          const ExpandedPlayerView(),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          ),
    );
  }

  Widget _buildCoverArt(Track track) {
    final path = track.customMetadata.customCoverPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return Image.file(
        File(path),
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        cacheWidth: 88,   // 2× for density
        cacheHeight: 88,
      );
    }
    return Container(
      width: 44,
      height: 44,
      color: AppTheme.bgHover,
      child: const Icon(
        Icons.music_note_rounded,
        color: AppTheme.textSecondary,
        size: 22,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final svc = AudioPlayerService.instance;

    return StreamBuilder<Track?>(
      stream: svc.currentTrackStream,
      initialData: svc.currentTrack,
      builder: (context, trackSnap) {
        final track = trackSnap.data;
        if (track == null || track.trackId.isEmpty) {
          return const SizedBox.shrink();
        }

        return GestureDetector(
          onTap: () => _openExpandedPlayer(context),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              color: AppTheme.bgSurface.withAlpha(242),  // ~95% opacity
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(102),   // ~40% opacity
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // ── Main row: cover + title/artist + controls ─────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
                  child: Row(
                    children: [
                      // Cover art
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _buildCoverArt(track),
                      ),
                      const SizedBox(width: 12),

                      // Title & artist
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              track.displayArtist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Play / Pause button
                      StreamBuilder<bool>(
                        stream: svc.isPlayingStream,
                        initialData: svc.isPlaying,
                        builder: (context, playSnap) {
                          final playing = playSnap.data ?? false;
                          return IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            icon: Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: AppTheme.accent,
                              size: 28,
                            ),
                            onPressed: () {
                              if (playing) {
                                svc.pause();
                              } else {
                                svc.play();
                              }
                            },
                          );
                        },
                      ),

                      // Skip-next button
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        icon: const Icon(
                          Icons.skip_next_rounded,
                          color: AppTheme.textPrimary,
                          size: 24,
                        ),
                        onPressed: () => svc.next(),
                      ),
                    ],
                  ),
                ),

                // ── Cyan progress bar along the bottom edge ──────────────
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 0,
                  child: _ProgressBar(svc: svc),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Thin 2 px progress bar that updates independently of the main card,
/// avoiding unnecessary rebuilds of the full widget tree.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.svc});

  final AudioPlayerService svc;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: svc.positionStream,
      initialData: svc.position,
      builder: (context, posSnap) {
        return StreamBuilder<Duration>(
          stream: svc.durationStream,
          initialData: svc.duration,
          builder: (context, durSnap) {
            final pos = posSnap.data ?? Duration.zero;
            final dur = durSnap.data ?? Duration.zero;
            final progress = dur.inMilliseconds > 0
                ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                : 0.0;
            return LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    // Background track
                    Container(
                      height: 2,
                      decoration: const BoxDecoration(
                        color: AppTheme.divider,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                      ),
                    ),
                    // Filled portion
                    Container(
                      height: 2,
                      width: constraints.maxWidth * progress,
                      decoration: BoxDecoration(
                        color: AppTheme.accent,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
