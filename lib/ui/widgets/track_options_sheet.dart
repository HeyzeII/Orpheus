import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../core/models/models.dart';
import '../../core/services/app_navigation_coordinator.dart';
import '../../core/services/audio_handler.dart';
import '../../core/services/audio_player_service.dart';
import '../dialogs/edit_metadata_dialog.dart';
import '../theme/app_theme.dart';
import 'add_to_playlist_sheet.dart';
import 'app_toast.dart';
import 'radio_launch_sheet.dart';

/// Modal bottom sheet displaying contextual options for a [Track].
///
/// Provides options to play next, add to queue, launch radio, add to playlist,
/// toggle favorites, navigate to album or artist, inspect credits/details,
/// and edit metadata.
class TrackOptionsSheet extends StatelessWidget {
  const TrackOptionsSheet({
    super.key,
    required this.track,
    this.playlistSource,
    this.trackIndexInPlaylist,
    this.onRemoveFromPlaylist,
    this.onOpenAlbum,
    this.onOpenArtist,
    this.onRefreshData,
  });

  final Track track;
  final Playlist? playlistSource;
  final int? trackIndexInPlaylist;
  final VoidCallback? onRemoveFromPlaylist;
  final void Function(String albumName)? onOpenAlbum;
  final void Function(String artistName)? onOpenArtist;
  final VoidCallback? onRefreshData;

  /// Convenience static method to display the modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required Track track,
    Playlist? playlistSource,
    int? trackIndexInPlaylist,
    VoidCallback? onRemoveFromPlaylist,
    void Function(String albumName)? onOpenAlbum,
    void Function(String artistName)? onOpenArtist,
    VoidCallback? onRefreshData,
  }) {
    return showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => TrackOptionsSheet(
        track: track,
        playlistSource: playlistSource,
        trackIndexInPlaylist: trackIndexInPlaylist,
        onRemoveFromPlaylist: onRemoveFromPlaylist,
        onOpenAlbum: onOpenAlbum,
        onOpenArtist: onOpenArtist,
        onRefreshData: onRefreshData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coverPath = track.customMetadata.customCoverPath;
    final hasArt = coverPath != null &&
        coverPath.isNotEmpty &&
        File(coverPath).existsSync();
    final db = LocalDatabase.instance;

    return SafeArea(
      top: false,
      bottom: true,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ValueListenableBuilder<Set<String>>(
            valueListenable: db.likedTrackIdsNotifier,
            builder: (context, likedTrackIds, _) {
              final isLiked = likedTrackIds.contains(track.trackId);

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header: Cover + Title + Artist ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: hasArt
                                ? Image.file(
                                    File(coverPath),
                                    fit: BoxFit.cover,
                                    cacheWidth: 96,
                                  )
                                : const ColoredBox(
                                    color: AppTheme.bgHover,
                                    child: Icon(
                                      Icons.music_note_rounded,
                                      color: AppTheme.textHint,
                                      size: 24,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                track.displayArtist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: AppTheme.divider, height: 1),
                  const SizedBox(height: 4),

                  // ── Options List ──
                  ListTile(
                    leading: const Icon(Icons.playlist_play_rounded,
                        color: AppTheme.textPrimary),
                    title: const Text('Reproducir a continuación',
                        style: TextStyle(
                            color: AppTheme.textPrimary, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      OrpheusAudioHandler.instance.playNext(track);
                      AppToast.showText(
                          context, 'Se reproducirá a continuación');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.queue_music_rounded,
                        color: AppTheme.textPrimary),
                    title: const Text('Añadir a la cola',
                        style: TextStyle(
                            color: AppTheme.textPrimary, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      OrpheusAudioHandler.instance.addToQueue(track);
                      AppToast.showText(context, 'Añadida a la cola');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.radio_rounded,
                        color: AppTheme.accent),
                    title: const Text('Iniciar Radio',
                        style: TextStyle(
                            color: AppTheme.textPrimary, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      RadioLaunchSheet.show(context, track);
                    },
                  ),
                  if (onRemoveFromPlaylist != null)
                    ListTile(
                      leading: const Icon(Icons.remove_circle_outline_rounded,
                          color: Colors.redAccent),
                      title: const Text('Quitar de la playlist',
                          style: TextStyle(
                              color: Colors.redAccent, fontSize: 14)),
                      onTap: () {
                        Navigator.pop(context);
                        onRemoveFromPlaylist!();
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.playlist_add_rounded,
                        color: AppTheme.textPrimary),
                    title: const Text('Añadir a playlist',
                        style: TextStyle(
                            color: AppTheme.textPrimary, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      _showAddToPlaylistModal(context, track,
                          onPlaylistUpdated: onRefreshData);
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked ? Colors.redAccent : AppTheme.textPrimary,
                    ),
                    title: Text(
                      isLiked ? 'Quitar de Me gusta' : 'Añadir a Me gusta',
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 14),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      db.toggleLikeOptimistic(track.trackId);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.album_rounded,
                        color: AppTheme.textPrimary),
                    title: const Text('Ir al álbum',
                        style: TextStyle(
                            color: AppTheme.textPrimary, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      if (onOpenAlbum != null) {
                        onOpenAlbum!(track.displayAlbum);
                      } else {
                        AppNavigationCoordinator.instance
                            .openAlbum(context, track.displayAlbum);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.person_rounded,
                        color: AppTheme.textPrimary),
                    title: const Text('Ir al artista',
                        style: TextStyle(
                            color: AppTheme.textPrimary, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      if (onOpenArtist != null) {
                        onOpenArtist!(track.displayArtist);
                      } else {
                        AppNavigationCoordinator.instance
                            .openArtist(context, track.displayArtist);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded,
                        color: AppTheme.textPrimary),
                    title: const Text('Ver créditos y detalles',
                        style: TextStyle(
                            color: AppTheme.textPrimary, fontSize: 14)),
                    onTap: () {
                      Navigator.pop(context);
                      _showTrackDetailsDialog(context, track);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_rounded,
                        color: AppTheme.textPrimary),
                    title: const Text('Editar información',
                        style: TextStyle(
                            color: AppTheme.textPrimary, fontSize: 14)),
                    onTap: () async {
                      Navigator.pop(context);
                      final changed = await showDialog<bool>(
                        context: context,
                        builder: (_) => EditMetadataDialog(track: track),
                      );
                      if (changed == true) {
                        AudioPlayerService.instance.updateTrack(track);
                        onRefreshData?.call();
                      }
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static void _showTrackDetailsDialog(BuildContext context, Track track) {
    final mins = track.duration ~/ 60;
    final secs = (track.duration % 60).toString().padLeft(2, '0');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.divider),
        ),
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded,
                color: AppTheme.accent, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                track.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Artista', track.displayArtist),
              _detailRow('Álbum', track.displayAlbum),
              _detailRow('Formato', track.fileType.name.toUpperCase()),
              _detailRow('Calidad de Audio', track.audioQuality),
              _detailRow('Duración', '$mins:$secs'),
              if (track.genre != null && track.genre!.trim().isNotEmpty)
                _detailRow('Género', track.genre!),
              if (track.downloadSource != null &&
                  track.downloadSource!.trim().isNotEmpty)
                _detailRow('Fuente', track.downloadSource!),
              const SizedBox(height: 8),
              const Text('Ruta de archivo:',
                  style: TextStyle(
                      color: AppTheme.textHint,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              SelectableText(
                track.filePath,
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar',
                style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }

  static Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textHint,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 1),
          Text(value,
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 13)),
        ],
      ),
    );
  }

  static Future<void> _showAddToPlaylistModal(
    BuildContext context,
    Track track, {
    VoidCallback? onPlaylistUpdated,
  }) =>
      AddToPlaylistSheet.show(
        context,
        tracks: [track],
        onPlaylistUpdated: onPlaylistUpdated,
      );
}
