import 'dart:io';
import 'package:flutter/material.dart';

import '../../core/models/playlist.dart';
import '../../core/models/track.dart';
import '../theme/app_theme.dart';

/// Renders cover art for a [Playlist].
///
/// Priority:
/// 1. Custom cover file set by the user ([Playlist.customCoverPath]).
/// 2. If it's the default "Liked Tracks" playlist, shows a dedicated vinyl placeholder with a heart.
/// 3. If empty, shows a minimalist dark vinyl/disc placeholder.
/// 4. If 1 to 3 songs, shows the first song's cover art.
/// 5. If 4 or more songs, builds a 2x2 collage using the first four songs.
class PlaylistCover extends StatelessWidget {
  final Playlist playlist;
  final List<Track> allTracks;
  final Map<int, Track>? tracksById;
  final double size;
  final int? coverVersion;

  const PlaylistCover({
    super.key,
    required this.playlist,
    required this.allTracks,
    this.tracksById,
    required this.size,
    this.coverVersion,
  });

  @override
  Widget build(BuildContext context) {
    final isLiked = playlist.playlistId == '__liked__';

    // 1. Custom playlist cover (priority 1) with cache breaker
    final customPath = playlist.customCoverPath;
    if (customPath != null && customPath.isNotEmpty) {
      final version = coverVersion ?? 0;
      return Image.file(
        File(customPath),
        key: ValueKey('${customPath}_$version'),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: 320,
        errorBuilder: (_, __, ___) => _buildVinylPlaceholder(isLiked),
      );
    }

    // 2. "Liked Tracks" special playlist — always uses the heart placeholder
    //    regardless of whether it contains songs, so its identity is consistent.
    if (isLiked) {
      return _buildVinylPlaceholder(true);
    }

    // Resolve tracks in order using the database int ID with O(1) dictionary
    final playlistTracks = playlist.trackIds
        .map((id) =>
            tracksById?[id] ??
            allTracks.firstWhere((t) => t.id == id, orElse: () => Track()))
        .where((t) => t.trackId.isNotEmpty)
        .toList();

    if (playlistTracks.isEmpty) {
      // 0 songs: a minimalist dark vinyl/disc placeholder with music icon or heart
      return _buildVinylPlaceholder(isLiked);
    } else if (playlistTracks.length < 4) {
      // 1 to 3 songs: first song cover with cache breaker
      final firstTrack = playlistTracks.first;
      final coverPath = firstTrack.customMetadata.customCoverPath;
      if (coverPath != null && coverPath.isNotEmpty) {
        return Image.file(
          File(coverPath),
          key: ValueKey('${coverPath}_$coverVersion'),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: 320,
          errorBuilder: (_, __, ___) => _buildTrackPlaceholder(isLiked),
        );
      } else {
        return _buildTrackPlaceholder(isLiked);
      }
    } else {
      // 4 or more songs: 2x2 grid collage of the first 4 tracks.
      // Use indexed keys so duplicate tracks in the list get unique widget slots.
      final first4 = playlistTracks.take(4).toList();
      return SizedBox(
        width: size,
        height: size,
        child: GridView.count(
          crossAxisCount: 2,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          children: first4.asMap().entries.map((entry) {
            final cellIdx = entry.key;
            final track = entry.value;
            final coverPath = track.customMetadata.customCoverPath;
            if (coverPath != null && coverPath.isNotEmpty) {
              return Image.file(
                File(coverPath),
                key: ValueKey('collage_${cellIdx}_${track.id}_$coverVersion'),
                fit: BoxFit.cover,
                cacheWidth: 160,
                errorBuilder: (_, __, ___) =>
                    _buildTrackPlaceholder(false, iconSize: size / 6),
              );
            } else {
              return _buildTrackPlaceholder(false, iconSize: size / 6);
            }
          }).toList(),
        ),
      );
    }
  }

  Widget _buildVinylPlaceholder(bool isLiked) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        gradient: RadialGradient(
          colors: [
            Color(0xFF222222),
            Color(0xFF0C0C0C),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: size * 0.8,
          height: size * 0.8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.transparent,
            border: Border.all(color: Colors.white10, width: 1),
          ),
          child: Center(
            child: Icon(
              isLiked ? Icons.favorite : Icons.music_note_rounded,
              color: isLiked
                  ? Colors.redAccent.withAlpha(180)
                  : AppTheme.accent.withAlpha(160),
              size: size * 0.3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackPlaceholder(bool isLiked, {double? iconSize}) {
    return Container(
      color: AppTheme.bgHover,
      child: Center(
        child: Icon(
          isLiked ? Icons.favorite : Icons.music_note_rounded,
          color: isLiked ? Colors.redAccent.withAlpha(140) : AppTheme.textHint,
          size: iconSize ?? (size * 0.3),
        ),
      ),
    );
  }
}
