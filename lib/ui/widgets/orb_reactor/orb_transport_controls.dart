import 'package:flutter/material.dart';

import '../../../core/database/local_database.dart';
import '../../../core/models/track.dart';
import '../../../core/services/audio_handler.dart';
import '../../../core/services/desktop_window_service.dart';
import '../../theme/app_theme.dart';

/// Top metadata and action header for the Orb Reactor.
class OrbHeaderRow extends StatelessWidget {
  const OrbHeaderRow({
    super.key,
    required this.track,
    this.leftClearance,
  });

  final Track? track;
  final double? leftClearance;

  @override
  Widget build(BuildContext context) {
    final title = track?.displayTitle ?? 'Orpheus';
    final artist = track?.displayArtist ?? 'Escucha algo grandioso';
    final double safeLeft = leftClearance ?? 0.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (safeLeft > 0) SizedBox(width: safeLeft),

        // Track Title & Artist (Top-left)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 16.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11.0,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 8),

        // Favorite (Like) Button (reactive with LocalDatabase)
        if (track != null)
          ValueListenableBuilder<Set<String>>(
            valueListenable: LocalDatabase.instance.likedTrackIdsNotifier,
            builder: (context, likedIds, _) {
              final isLiked = likedIds.contains(track!.trackId);
              return _OrbActionButton(
                icon: isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                iconColor: isLiked ? Colors.pinkAccent : AppTheme.textSecondary,
                tooltip: isLiked ? 'Quitar de favoritos' : 'Añadir a favoritos',
                onTap: () => LocalDatabase.instance.toggleLikeOptimistic(track!.trackId),
              );
            },
          ),

        const SizedBox(width: 2),

        // Restore Standard Window Button
        _OrbActionButton(
          icon: Icons.open_in_full_rounded,
          iconColor: Colors.white.withOpacity(0.70),
          tooltip: 'Restaurar ventana',
          onTap: () => DesktopWindowService.instance.exitMiniPlayer(),
        ),
      ],
    );
  }
}

/// Bottom progress bar and transport playback controls.
class OrbBottomTransport extends StatelessWidget {
  const OrbBottomTransport({
    super.key,
    required this.track,
    required this.isPlaying,
    required this.handler,
  });

  final Track? track;
  final bool isPlaying;
  final OrpheusAudioHandler? handler;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Micro Progress Bar with Elapsed & Total Timestamps
        StreamBuilder<Duration>(
          stream: handler?.positionStream,
          builder: (context, posSnap) {
            return StreamBuilder<Duration>(
              stream: handler?.durationStream,
              builder: (context, durSnap) {
                final pos = posSnap.data ?? Duration.zero;
                final dur = durSnap.data ??
                    (track != null ? Duration(seconds: track!.duration) : Duration.zero);

                double ratio = 0.0;
                if (dur.inMilliseconds > 0) {
                  ratio = (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
                }

                return Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text(
                        _formatDuration(pos),
                        textAlign: TextAlign.start,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2.5),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 2.8,
                          backgroundColor: Colors.white.withOpacity(0.08),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 32,
                      child: Text(
                        _formatDuration(dur),
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),

        const SizedBox(height: 8),

        // Transport Controls Row (Previous, Play/Pause, Next)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Previous
            _OrbTransportIconButton(
              icon: Icons.skip_previous_rounded,
              size: 26,
              tooltip: 'Anterior',
              onTap: () => handler?.skipToPrevious(),
            ),

            const SizedBox(width: 18),

            // Prominent Play / Pause Core Button
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (handler == null) return;
                if (isPlaying) {
                  handler!.pause();
                } else {
                  handler!.play();
                }
              },
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.textPrimary,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accent.withOpacity(0.40),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: AppTheme.bgDeep,
                  size: 28,
                ),
              ),
            ),

            const SizedBox(width: 18),

            // Next
            _OrbTransportIconButton(
              icon: Icons.skip_next_rounded,
              size: 26,
              tooltip: 'Siguiente',
              onTap: () => handler?.skipToNext(),
            ),
          ],
        ),
      ],
    );
  }
}

class _OrbActionButton extends StatelessWidget {
  const _OrbActionButton({
    required this.icon,
    required this.onTap,
    required this.iconColor,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
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
          borderRadius: BorderRadius.circular(14),
          hoverColor: Colors.white.withOpacity(0.08),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 20, color: iconColor),
          ),
        ),
      ),
    );
  }
}

class _OrbTransportIconButton extends StatelessWidget {
  const _OrbTransportIconButton({
    required this.icon,
    required this.size,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final String tooltip;
  final VoidCallback onTap;

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
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: size,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

