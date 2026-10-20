import 'dart:ui';
import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../core/models/models.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';
import 'playlist_cover.dart';

/// Unified bottom sheet modal for adding single or multiple tracks to a playlist.
///
/// Features:
/// - Full root overlay via [useRootNavigator: true].
/// - Tidal-inspired dark glassmorphism styling with backdrop blur.
/// - Dynamic ordering by recent usage ([Playlist.updatedAt] descending).
/// - Real thumbnail rendering using [PlaylistCover].
/// - Ergonomically bounded container (max 5 visible playlists, ~310-330px list height)
///   with an active, styled [Scrollbar].
/// - Express "Nueva playlist" action at top.
/// - Centralized duplicate handling for single and multi-track scenarios.
class AddToPlaylistSheet extends StatefulWidget {
  final List<Track> tracks;
  final String? collectionTitle;
  final VoidCallback? onPlaylistUpdated;

  const AddToPlaylistSheet({
    super.key,
    required this.tracks,
    this.collectionTitle,
    this.onPlaylistUpdated,
  });

  /// Presents the [AddToPlaylistSheet] modal bottom sheet above all UI elements.
  static Future<void> show(
    BuildContext context, {
    required List<Track> tracks,
    String? collectionTitle,
    VoidCallback? onPlaylistUpdated,
  }) async {
    if (tracks.isEmpty || !context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddToPlaylistSheet(
        tracks: tracks,
        collectionTitle: collectionTitle,
        onPlaylistUpdated: onPlaylistUpdated,
      ),
    );
  }

  @override
  State<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<AddToPlaylistSheet> {
  final ScrollController _scrollController = ScrollController();
  List<Playlist> _playlists = [];
  List<Track> _allTracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final db = LocalDatabase.instance;
    final results = await Future.wait([
      db.getAllPlaylistsSortedByRecent(),
      db.getAllTracks(),
    ]);

    if (!mounted) return;

    final rawPlaylists = results[0] as List<Playlist>;
    final allTracks = results[1] as List<Track>;

    setState(() {
      // Exclude system-managed Liked Tracks playlist (managed via heart icon)
      _playlists = rawPlaylists.where((p) => p.playlistId != '__liked__').toList();
      _allTracks = allTracks;
      _isLoading = false;
    });
  }

  Future<void> _createNewPlaylist() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.divider),
        ),
        title: const Text(
          'Nueva Playlist',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          cursorColor: AppTheme.accent,
          decoration: const InputDecoration(
            hintText: 'Nombre de la playlist',
            hintStyle: TextStyle(color: AppTheme.textHint),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.divider),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.accent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.bgDeep,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              final trimmed = nameCtrl.text.trim();
              if (trimmed.isNotEmpty) {
                Navigator.pop(dialogCtx, trimmed);
              }
            },
            child: const Text('Crear', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty || !mounted) return;

    final newPl = Playlist()
      ..playlistId = 'playlist_${DateTime.now().millisecondsSinceEpoch}'
      ..name = name
      ..isDefault = false
      ..updatedAt = DateTime.now();

    final db = LocalDatabase.instance;
    await db.savePlaylist(newPl);

    final trackIds = widget.tracks.map((t) => t.trackId).toList();
    await db.addTracksToPlaylist(playlist: newPl, trackIds: trackIds);

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (widget.tracks.length == 1) {
      AppToast.showAddedToPlaylist(context, track: widget.tracks.first, playlist: newPl);
    } else {
      AppToast.showTracksAddedToPlaylist(
        context,
        count: widget.tracks.length,
        playlist: newPl,
        collectionTitle: widget.collectionTitle,
      );
    }

    widget.onPlaylistUpdated?.call();
  }

  Future<void> _handleSelectPlaylist(Playlist playlist) async {
    final existingIds = playlist.trackIds.toSet();
    final duplicates = widget.tracks.where((t) => existingIds.contains(t.id)).toList();
    final newTracks = widget.tracks.where((t) => !existingIds.contains(t.id)).toList();

    // Case 1: No duplicates
    if (duplicates.isEmpty) {
      await _commitAdd(playlist, widget.tracks);
      return;
    }

    // Case 2: Single track duplicate
    if (widget.tracks.length == 1) {
      final track = widget.tracks.first;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: AppTheme.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppTheme.divider),
          ),
          title: const Text(
            'Canción duplicada',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
          ),
          content: Text(
            '"${track.displayTitle}" ya está en "${playlist.name}". ¿Deseas agregarla de todos modos?',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.bgDeep,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Agregar de todos modos', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        await _commitAdd(playlist, widget.tracks);
      }
      return;
    }

    // Case 3: Batch duplicates (all or partial)
    if (newTracks.isEmpty) {
      // All tracks are duplicates
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: AppTheme.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppTheme.divider),
          ),
          title: const Text(
            'Canciones repetidas detectadas',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Todas las canciones (${duplicates.length}) ya forman parte de "${playlist.name}". ¿Deseas agregarlas de todos modos?',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.bgDeep,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Agregar todas de todos modos', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        await _commitAdd(playlist, widget.tracks);
      }
      return;
    }

    // Partial duplicates
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.divider),
        ),
        title: const Text(
          'Canciones duplicadas',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '${duplicates.length} de ${widget.tracks.length} canciones ya forman parte de "${playlist.name}". ¿Cómo deseas proceder?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, 'cancel'),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.accent),
              foregroundColor: AppTheme.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dialogCtx, 'all'),
            child: const Text('Agregar todas'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.bgDeep,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dialogCtx, 'new'),
            child: Text(
              'Solo nuevas (${newTracks.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (choice == 'all' && mounted) {
      await _commitAdd(playlist, widget.tracks);
    } else if (choice == 'new' && mounted) {
      await _commitAdd(playlist, newTracks);
    }
  }

  Future<void> _commitAdd(Playlist playlist, List<Track> tracksToAdd) async {
    if (tracksToAdd.isEmpty) return;

    final db = LocalDatabase.instance;
    final trackIds = tracksToAdd.map((t) => t.trackId).toList();
    await db.addTracksToPlaylist(playlist: playlist, trackIds: trackIds);

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (tracksToAdd.length == 1) {
      AppToast.showAddedToPlaylist(context, track: tracksToAdd.first, playlist: playlist);
    } else {
      AppToast.showTracksAddedToPlaylist(
        context,
        count: tracksToAdd.length,
        playlist: playlist,
        collectionTitle: widget.collectionTitle,
      );
    }

    widget.onPlaylistUpdated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.collectionTitle != null
        ? 'Añadir "${widget.collectionTitle}" a playlist'
        : (widget.tracks.length == 1
            ? 'Añadir "${widget.tracks.first.displayTitle}" a playlist'
            : 'Añadir ${widget.tracks.length} canciones a playlist');

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.bgSurface.withValues(alpha: 0.90),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: AppTheme.divider.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top drag indicator ─────────────────────────────────
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // ── Header Row ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary, size: 20),
                          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                          tooltip: 'Cerrar',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 4),

                  // ── "Nueva playlist" Action Tile ───────────────────────
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.accent.withAlpha(35),
                      child: const Icon(Icons.add_rounded, color: AppTheme.accent, size: 22),
                    ),
                    title: const Text(
                      'Nueva playlist',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Crear e incluir canciones directamente',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                    ),
                    onTap: _createNewPlaylist,
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Divider(color: AppTheme.divider.withValues(alpha: 0.4), height: 1),
                  ),

                  // ── Playlists List with bounded height (max ~5 visible) ──
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                        ),
                      ),
                    )
                  else if (_playlists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                      child: Center(
                        child: Text(
                          'No tienes playlists creadas todavía.',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 310),
                      child: RawScrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        thumbColor: AppTheme.accent.withAlpha(90),
                        radius: const Radius.circular(4),
                        thickness: 3.5,
                        child: ListView.builder(
                          controller: _scrollController,
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _playlists.length,
                          itemBuilder: (context, idx) {
                            final playlist = _playlists[idx];
                            final trackCount = playlist.trackIds.length;

                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: PlaylistCover(
                                    playlist: playlist,
                                    allTracks: _allTracks,
                                    size: 42,
                                  ),
                                ),
                              ),
                              title: Text(
                                playlist.name,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '$trackCount ${trackCount == 1 ? "canción" : "canciones"}',
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: AppTheme.textHint,
                                size: 18,
                              ),
                              onTap: () => _handleSelectPlaylist(playlist),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
