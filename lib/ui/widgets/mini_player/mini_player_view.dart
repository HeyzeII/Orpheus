import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/database/local_database.dart';
import '../../../core/models/track.dart';
import '../../../core/services/audio_handler.dart';
import '../../../core/services/desktop_window_service.dart';
import '../../theme/app_theme.dart';
import 'vinyl_disc_widget.dart';

/// Ultra-compact, floating glassmorphic Mini Player view for macOS and Linux.
///
/// Layout (320 × 320 px):
/// - Top: Drag grip area and "Restore main window" action button.
/// - Center: Rotating vinyl disc displaying circular album artwork.
/// - Bottom: Track title, artist, progress arc/bar, and transport controls
///   (Previous, Play/Pause, Next, and Isar-backed Favorite toggle).
class MiniPlayerView extends StatelessWidget {
  const MiniPlayerView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xEC0E0F14), // Smoky glassmorphism background
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withOpacity(0.12),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.65),
              blurRadius: 28,
              spreadRadius: 4,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(27),
          child: const _MiniPlayerContent(),
        ),
      ),
    );
  }
}

class _MiniPlayerContent extends StatelessWidget {
  const _MiniPlayerContent();

  @override
  Widget build(BuildContext context) {
    final handler = OrpheusAudioHandler.hasInstance ? OrpheusAudioHandler.instance : null;
    final trackStream = handler?.currentTrackStream;
    final playingStream = handler?.isPlayingStream;

    return StreamBuilder<Track?>(
      stream: trackStream,
      initialData: handler?.currentTrack,
      builder: (context, trackSnap) {
        final track = trackSnap.data;

        return StreamBuilder<bool>(
          stream: playingStream,
          initialData: handler?.isPlaying ?? false,
          builder: (context, playingSnap) {
            final isPlaying = playingSnap.data ?? false;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 1. Top bar: Drag hint badge + Restore button
                  _buildTopBar(context),

                  // 2. Vinyl disc turntable center
                  Expanded(
                    child: DragToMoveArea(
                      child: Center(
                        child: VinylDiscWidget(
                          coverPath: track?.customMetadata.customCoverPath,
                          isPlaying: isPlaying,
                          size: 132,
                        ),
                      ),
                    ),
                  ),

                  // 3. Track metadata & progress bar
                  _buildTrackMetaAndProgress(track, handler),

                  const SizedBox(height: 6),

                  // 4. Transport playback controls
                  _buildTransportControls(context, track, isPlaying, handler),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // App branding pill and draggable title area
        Expanded(
          child: DragToMoveArea(
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Orpheus',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Restore main window button
        Tooltip(
          message: 'Restaurar ventana principal',
          child: IconButton(
            icon: Icon(
              Icons.open_in_full_rounded,
              size: 15,
              color: Colors.white.withOpacity(0.75),
            ),
            splashRadius: 16,
            visualDensity: VisualDensity.compact,
            onPressed: () => DesktopWindowService.instance.exitMiniPlayer(),
          ),
        ),
      ],
    );
  }

  Widget _buildTrackMetaAndProgress(Track? track, OrpheusAudioHandler? handler) {
    final title = track?.displayTitle ?? 'Sin reproducción';
    final artist = track?.displayArtist ?? 'Orpheus Player';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Outfit',
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 11,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        // Micro progress bar
        StreamBuilder<Duration>(
          stream: handler?.positionStream,
          builder: (context, posSnap) {
            return StreamBuilder<Duration>(
              stream: handler?.durationStream,
              builder: (context, durSnap) {
                final pos = posSnap.data ?? Duration.zero;
                final dur = durSnap.data ?? (track != null ? Duration(seconds: track.duration) : Duration.zero);

                double ratio = 0.0;
                if (dur.inMilliseconds > 0) {
                  ratio = (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
                }

                return ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 2.5,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildTransportControls(
    BuildContext context,
    Track? track,
    bool isPlaying,
    OrpheusAudioHandler? handler,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Like / Favorite button (reactive with Isar database)
        if (track != null)
          ValueListenableBuilder<Set<String>>(
            valueListenable: LocalDatabase.instance.likedTrackIdsNotifier,
            builder: (context, likedIds, _) {
              final isLiked = likedIds.contains(track.trackId);
              return _MiniIconButton(
                icon: isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                iconColor: isLiked ? Colors.pinkAccent : AppTheme.textSecondary,
                size: 18,
                tooltip: isLiked ? 'Quitar de favoritos' : 'Añadir a favoritos',
                onTap: () => LocalDatabase.instance.toggleLikeOptimistic(track.trackId),
              );
            },
          )
        else
          const SizedBox(width: 28),

        // Previous
        _MiniIconButton(
          icon: Icons.skip_previous_rounded,
          size: 20,
          tooltip: 'Anterior',
          onTap: () => handler?.skipToPrevious(),
        ),

        // Play / Pause prominent button
        GestureDetector(
          onTap: () {
            if (handler == null) return;
            if (isPlaying) {
              handler.pause();
            } else {
              handler.play();
            }
          },
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.textPrimary,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accent.withOpacity(0.35),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: AppTheme.bgDeep,
              size: 22,
            ),
          ),
        ),

        // Next
        _MiniIconButton(
          icon: Icons.skip_next_rounded,
          size: 20,
          tooltip: 'Siguiente',
          onTap: () => handler?.skipToNext(),
        ),

        // Spacer to balance the like button on left
        const SizedBox(width: 28),
      ],
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.onTap,
    this.size = 18.0,
    this.iconColor = AppTheme.textSecondary,
    this.tooltip = '',
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color iconColor;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          hoverColor: Colors.white.withOpacity(0.08),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              icon,
              size: size,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
