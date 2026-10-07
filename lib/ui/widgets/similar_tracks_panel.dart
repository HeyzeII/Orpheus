import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/track.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/recommendation_engine_service.dart';
import '../theme/app_theme.dart';
import 'radio_launch_sheet.dart';

/// A horizontally scrollable panel that shows tracks acoustically similar to
/// [currentTrack]. Designed to be embedded in the Expanded Player view.
///
/// Uses a [FutureBuilder] keyed on [currentTrack.trackId] so the query resets
/// automatically when the playing track changes. Wrapped in [RepaintBoundary]
/// to isolate repaints from the rest of the player UI.
class SimilarTracksPanel extends StatelessWidget {
  const SimilarTracksPanel({super.key, required this.currentTrack});

  final Track currentTrack;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FutureBuilder<List<Track>>(
        key: ValueKey('similar_${currentTrack.trackId}'),
        future: RecommendationEngineService.instance
            .getSimilarTracks(currentTrack, count: 8),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _SimilarPanelShimmer();
          }
          if (!snap.hasData || snap.data!.isEmpty) {
            return const SizedBox.shrink();
          }

          final tracks = snap.data!;
          return _SimilarPanelContent(tracks: tracks);
        },
      ),
    );
  }
}

// ── Content ───────────────────────────────────────────────────────────────────

class _SimilarPanelContent extends StatelessWidget {
  const _SimilarPanelContent({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          child: Row(
            children: [
              const Icon(Icons.recommend_rounded,
                  size: 14, color: AppTheme.accent),
              const SizedBox(width: 6),
              Text(
                'PISTAS SIMILARES',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: tracks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) =>
                _SimilarTrackCard(track: tracks[index]),
          ),
        ),
      ],
    );
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _SimilarTrackCard extends StatelessWidget {
  const _SimilarTrackCard({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final coverPath = track.customMetadata.customCoverPath;
    final hasArt =
        coverPath != null && coverPath.isNotEmpty && File(coverPath).existsSync();

    return GestureDetector(
      onTap: () => AudioPlayerService.instance.addToQueue(track),
      onLongPress: () => RadioLaunchSheet.show(context, track),
      child: SizedBox(
        width: 86,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover art
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 86,
                height: 86,
                child: hasArt
                    ? Image.file(
                        File(coverPath),
                        fit: BoxFit.cover,
                        cacheWidth: 172,
                        errorBuilder: (_, __, ___) => _FallbackCover(),
                      )
                    : _FallbackCover(),
              ),
            ),
            const SizedBox(height: 6),
            // Title
            Text(
              track.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            // Artist
            Text(
              track.displayArtist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FallbackCover extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppTheme.bgHover,
      child: Center(
        child: Icon(Icons.music_note_rounded, size: 28, color: AppTheme.textHint),
      ),
    );
  }
}

// ── Shimmer ───────────────────────────────────────────────────────────────────

class _SimilarPanelShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => SizedBox(
          width: 86,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: 70,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 50,
                height: 9,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
