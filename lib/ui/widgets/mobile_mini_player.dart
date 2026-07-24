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
/// - When a track is active it renders a clean 64px Tidal-style card with
///   cover art, title/artist, play-pause, skip-next, and a subtle 1.5px
///   progress stripe along the bottom edge.
/// - Tapping the card opens [ExpandedPlayerView] via the same slide-up
///   animation used by the desktop [PlayerBar].
class MobileMiniPlayer extends StatelessWidget {
  const MobileMiniPlayer({super.key});

  // ── Navigation ────────────────────────────────────────────────────────────

  void _openExpandedPlayer(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withAlpha(128),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (ctx, _, __) => const ExpandedPlayerView(),
      transitionBuilder: (ctx, animation, _, child) => SlideTransition(
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _coverArt(Track track) {
    final path = track.customMetadata.customCoverPath;
    final hasArt = path != null && path.isNotEmpty && File(path).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 44,
        height: 44,
        child: hasArt
            ? Image.file(File(path!), fit: BoxFit.cover, cacheWidth: 88)
            : const ColoredBox(
                color: AppTheme.bgHover,
                child: Icon(
                  Icons.music_note_rounded,
                  color: AppTheme.textHint,
                  size: 20,
                ),
              ),
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
      builder: (context, snap) {
        final track = snap.data;
        if (track == null || track.trackId.isEmpty) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => _openExpandedPlayer(context),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              // Clean matte dark card — same tone as the library rows.
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(140),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  // ── Main row ──────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
                    child: Row(
                      children: [
                        _coverArt(track),
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
                                  letterSpacing: 0.1,
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

                        // Play / Pause
                        StreamBuilder<bool>(
                          stream: svc.isPlayingStream,
                          initialData: svc.isPlaying,
                          builder: (context, playSnap) {
                            final playing = playSnap.data ?? false;
                            return _IconBtn(
                              icon: playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: AppTheme.accent,
                              size: 28,
                              onPressed: () =>
                                  playing ? svc.pause() : svc.play(),
                            );
                          },
                        ),

                        // Skip next
                        _IconBtn(
                          icon: Icons.skip_next_rounded,
                          color: AppTheme.textSecondary,
                          size: 24,
                          onPressed: () => svc.next(),
                        ),
                      ],
                    ),
                  ),

                  // ── Progress stripe (1.5 px, bottom of card) ─────────────
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _ProgressStripe(svc: svc),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Private helpers ───────────────────────────────────────────────────────────

/// Small icon button with tight constraints for the mini-player.
class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.color,
    required this.size,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tight(const Size(40, 40)),
        icon: Icon(icon, color: color, size: size),
        onPressed: onPressed,
      );
}

/// 1.5 px solid-colour progress stripe.
/// Extracted into its own widget so the two nested StreamBuilders only
/// rebuild this thin element, not the whole mini-player card.
class _ProgressStripe extends StatelessWidget {
  const _ProgressStripe({required this.svc});

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
            final frac = dur.inMilliseconds > 0
                ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                : 0.0;

            return LayoutBuilder(builder: (context, c) {
              return SizedBox(
                height: 1.5,
                child: Stack(children: [
                  // Background (barely visible, same card tone)
                  Container(color: AppTheme.divider),
                  // Filled portion
                  Container(
                    width: c.maxWidth * frac,
                    color: AppTheme.accent.withAlpha(200),
                  ),
                ]),
              );
            });
          },
        );
      },
    );
  }
}
