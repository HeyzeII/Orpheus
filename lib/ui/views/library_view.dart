import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/database/local_database.dart';
import '../../core/models/models.dart';
import '../../core/services/app_navigation_coordinator.dart';
import '../../core/services/audio_handler.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/sync_download_manager.dart';
import '../dialogs/edit_metadata_dialog.dart';
import '../theme/app_theme.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/animated_equalizer.dart';
import '../widgets/app_toast.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/radio_launch_sheet.dart';
import '../widgets/sync_progress_panel.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/video_badge.dart';

enum LibraryTab { tracks, albums, artists, playlists, videos }
enum _DuplicateResolution { onlyNew, all, cancel }

/// Main Library View — Browsing and playback controller for the local music database.
class LibraryView extends StatefulWidget {
  const LibraryView({super.key});

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  LibraryTab _activeTab = LibraryTab.tracks;

  // DB datasets
  List<Track> _allTracks = [];
  List<String> _uniqueAlbums = [];
  List<String> _uniqueArtists = [];
  List<Playlist> _playlists = [];
  Set<String> _likedTrackIds = {};

  // Dynamic cover cache-busting versions
  final Map<String, int> _coverVersions = {};

  // UI state
  String _searchQuery = '';
  bool _isLoading = true;

  // Pre-computed O(1) in-memory indexes for zero-cost grid & list building
  Map<int, Track> _tracksById = {};
  Map<String, Track> _firstTrackByAlbum = {};
  Map<String, int> _trackCountByArtist = {};

  // ── Nested Navigator (library detail views) ────────────────────────────────
  // Routes rendered here stay within the LibraryView slot of the IndexedStack,
  // keeping the floating glass pill visible and touchable at all times.
  final GlobalKey<NavigatorState> _libraryNavKey = GlobalKey<NavigatorState>();
  // Cached bottomPad so the nested Navigator's page builder can read it.
  double _currentBottomPad = 0;

  /// Pushes an album detail view into the library's own nested Navigator.
  /// The floating bottom panel remains visible because the push stays within
  /// the LibraryView slot of the root IndexedStack.
  void _openAlbum(String albumName, [double? bottomPad]) {
    if (bottomPad != null) _currentBottomPad = bottomPad;
    _libraryNavKey.currentState?.push(
      PageRouteBuilder(
        pageBuilder: (ctx, _, __) => Scaffold(
          backgroundColor: AppTheme.bgDeep,
          body: _buildAlbumDetails(albumName, bottomPad: _currentBottomPad),
        ),
        transitionsBuilder: (ctx, animation, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        ),
      ),
    );
  }

  /// Pushes an artist detail view into the library's own nested Navigator.
  void _openArtist(String artistName, [double? bottomPad]) {
    if (bottomPad != null) _currentBottomPad = bottomPad;
    _libraryNavKey.currentState?.push(
      PageRouteBuilder(
        pageBuilder: (ctx, _, __) => Scaffold(
          backgroundColor: AppTheme.bgDeep,
          body: _buildArtistDetails(artistName, bottomPad: _currentBottomPad),
        ),
        transitionsBuilder: (ctx, animation, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        ),
      ),
    );
  }

  /// Pushes a playlist detail view into the library's own nested Navigator.
  void _openPlaylist(Playlist playlist, [double? bottomPad]) {
    if (bottomPad != null) _currentBottomPad = bottomPad;
    _libraryNavKey.currentState?.push(
      PageRouteBuilder(
        pageBuilder: (ctx, _, __) => Scaffold(
          backgroundColor: AppTheme.bgDeep,
          body: _buildPlaylistDetails(playlist, bottomPad: _currentBottomPad),
        ),
        transitionsBuilder: (ctx, animation, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        ),
      ),
    );
  }

  StreamSubscription<void>? _tracksSubscription;
  StreamSubscription<void>? _playlistsSubscription;

  @override
  void initState() {
    super.initState();
    AppNavigationCoordinator.instance.onOpenAlbum = _openAlbum;
    AppNavigationCoordinator.instance.onOpenArtist = _openArtist;
    _refreshData(showSpinner: true);
    _tracksSubscription = LocalDatabase.instance.watchTracks().listen((_) {
      _refreshData(showSpinner: false);
    });
    _playlistsSubscription = LocalDatabase.instance.watchPlaylists().listen((_) {
      _refreshData(showSpinner: false);
    });
  }

  @override
  void dispose() {
    if (AppNavigationCoordinator.instance.onOpenAlbum == _openAlbum) {
      AppNavigationCoordinator.instance.onOpenAlbum = null;
    }
    if (AppNavigationCoordinator.instance.onOpenArtist == _openArtist) {
      AppNavigationCoordinator.instance.onOpenArtist = null;
    }
    _tracksSubscription?.cancel();
    _playlistsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshData({bool showSpinner = false}) async {
    if (showSpinner) {
      setState(() => _isLoading = true);
    }
    final db = LocalDatabase.instance;
    final tracks = await db.getAllTracks();
    final albums = await db.getUniqueAlbums();
    final artists = await db.getUniqueArtists();
    final playlists = await db.getAllPlaylists();

    // 1. Build O(1) track lookup dictionary
    final tracksById = <int, Track>{for (final t in tracks) t.id: t};

    // 2. Pre-index first track for each album cover
    final firstTrackByAlbum = <String, Track>{};
    for (final t in tracks) {
      firstTrackByAlbum.putIfAbsent(t.displayAlbum, () => t);
    }

    // 3. Pre-index track counts per artist (avoiding linear scans on every list tile)
    final trackCountByArtist = <String, int>{};
    for (final t in tracks) {
      for (final a in t.individualArtists) {
        final key = a.toLowerCase();
        trackCountByArtist[key] = (trackCountByArtist[key] ?? 0) + 1;
      }
    }

    final likedPlaylist = await db.getPlaylistById('__liked__');
    final likedIds = likedPlaylist?.trackIds
            .map((id) => tracksById[id]?.trackId)
            .whereType<String>()
            .where((tid) => tid.isNotEmpty)
            .toSet() ??
        <String>{};

    if (!mounted) return;
    setState(() {
      _allTracks = tracks;
      _uniqueAlbums = albums;
      _uniqueArtists = artists;
      _playlists = playlists;
      _likedTrackIds = likedIds;
      _tracksById = tracksById;
      _firstTrackByAlbum = firstTrackByAlbum;
      _trackCountByArtist = trackCountByArtist;
      _isLoading = false;
    });
  }

  // Playback integration
  Future<void> _playTracks(List<Track> tracks, int startIndex, {String? contextName}) async {
    if (tracks.isEmpty) return;
    await OrpheusAudioHandler.instance.loadQueue(
      tracks,
      initialIndex: startIndex,
      contextName: contextName,
    );
  }

  Future<void> _shufflePlayTracks(List<Track> tracks, {String? contextName}) async {
    if (tracks.isEmpty) return;
    final handler = OrpheusAudioHandler.instance;
    if (!handler.shuffleEnabled) handler.toggleShuffle();
    final initialIndex = Random().nextInt(tracks.length);
    await handler.loadQueue(
      tracks,
      initialIndex: initialIndex,
      contextName: contextName,
    );
  }

  // Favorite toggle (Optimistic)
  Future<void> _toggleLike(Track track) async {
    await LocalDatabase.instance.toggleLikeOptimistic(track.trackId);
  }

  // Direct persistence helper (bypasses duplicate confirmation)
  Future<void> _addTracksDirectly(
    List<Track> tracks,
    Playlist playlist, {
    String? collectionTitle,
  }) async {
    if (tracks.isEmpty) return;
    await LocalDatabase.instance.addTracksToPlaylist(
      playlist: playlist,
      trackIds: tracks.map((t) => t.trackId).toList(),
    );
    if (!mounted) return;
    if (tracks.length == 1) {
      AppToast.showAddedToPlaylist(
        context,
        track: tracks.first,
        playlist: playlist,
      );
    } else {
      AppToast.showTracksAddedToPlaylist(
        context,
        count: tracks.length,
        playlist: playlist,
        collectionTitle: collectionTitle,
      );
    }
    _refreshData();
  }

  // Centralized interceptor with duplicate detection and user resolution dialogs
  Future<void> _processAddTracksToPlaylist(
    BuildContext context,
    List<Track> tracks,
    Playlist playlist, {
    String? collectionTitle,
  }) async {
    if (tracks.isEmpty) return;

    // For default Liked playlist, LocalDatabase already deduplicates silently
    if (playlist.playlistId == '__liked__') {
      await _addTracksDirectly(tracks, playlist, collectionTitle: collectionTitle);
      return;
    }

    final existingIds = playlist.trackIds.toSet();
    final duplicates = tracks.where((t) => existingIds.contains(t.id)).toList();
    final newTracks = tracks.where((t) => !existingIds.contains(t.id)).toList();

    // CASO 1: Sin duplicados
    if (duplicates.isEmpty) {
      await _addTracksDirectly(tracks, playlist, collectionTitle: collectionTitle);
      return;
    }

    // CASO 2: Pista individual duplicada
    if (tracks.length == 1) {
      final track = tracks.first;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
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
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.bgDeep,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Agregar de todos modos', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await _addTracksDirectly(tracks, playlist, collectionTitle: collectionTitle);
      }
      return;
    }

    // CASO 3: Lote / Colección con duplicados parciales o totales
    if (newTracks.isEmpty) {
      // Todas las canciones del lote ya están en la playlist
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
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
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.bgDeep,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Agregar todas de todos modos', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await _addTracksDirectly(tracks, playlist, collectionTitle: collectionTitle);
      }
    } else {
      // Duplicados parciales
      final result = await showDialog<_DuplicateResolution>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.divider),
          ),
          title: const Text(
            'Canciones repetidas detectadas',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
          ),
          content: Text(
            '${duplicates.length} de ${tracks.length} canciones ya forman parte de "${playlist.name}".',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, _DuplicateResolution.cancel),
              child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: const BorderSide(color: AppTheme.divider),
              ),
              onPressed: () => Navigator.pop(ctx, _DuplicateResolution.all),
              child: const Text('Agregar todas de todos modos'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.bgDeep,
              ),
              onPressed: () => Navigator.pop(ctx, _DuplicateResolution.onlyNew),
              child: Text(
                'Agregar solo las ${newTracks.length} nuevas',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );

      if (result == _DuplicateResolution.onlyNew) {
        await _addTracksDirectly(newTracks, playlist, collectionTitle: collectionTitle);
      } else if (result == _DuplicateResolution.all) {
        await _addTracksDirectly(tracks, playlist, collectionTitle: collectionTitle);
      }
    }
  }

  // Add track to custom playlist (delegates to centralized interceptor)
  Future<void> _addTrackToPlaylist(Track track, Playlist playlist) async {
    await _processAddTracksToPlaylist(context, [track], playlist, collectionTitle: track.displayTitle);
  }
  // Remove track from custom playlist
  Future<void> _removeTrackFromPlaylist(Track track, Playlist playlist) async {
    await LocalDatabase.instance.removeTrackFromPlaylist(
      playlist: playlist,
      trackId: track.trackId,
    );
    setState(() {
      playlist.trackIds.remove(track.id);
    });
    _refreshData();
  }

  // Remove track at specific index from custom playlist (safe for duplicates)
  Future<void> _removeTrackFromPlaylistAt(Playlist playlist, int index) async {
    await LocalDatabase.instance.removeTrackFromPlaylistAt(
      playlist: playlist,
      index: index,
    );
    _refreshData();
  }

  // Edit track metadata
  Future<void> _editTrackMetadata(Track track) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EditMetadataDialog(track: track),
    );
    if (changed == true) _refreshData();
  }

  // Safe Delete Track (moves file to .trash and removes from DB)
  Future<void> _deleteTrack(Track track) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.divider),
          ),
          title: const Text(
            'Eliminar canción',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
          ),
          content: Text(
            '¿Estás seguro de que deseas enviar "${track.displayTitle}" a la papelera (.trash)? El archivo se conservará en tu disco.',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await LocalDatabase.instance.deleteTrack(track.id);
    _refreshData();
  }

  // Create playlist dialog
  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final descriptionController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppTheme.divider),
          ),
          title: const Text(
            'Crear Playlist',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Nombre de la playlist',
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.divider),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.accent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Descripción (Opcional)',
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.divider),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.accent),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.bgDeep,
              ),
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  final playlist = Playlist()
                    ..playlistId = 'playlist_${DateTime.now().millisecondsSinceEpoch}'
                    ..name = name
                    ..description = descriptionController.text.trim()
                    ..isDefault = false;
                  Navigator.pop(context);
                  await LocalDatabase.instance.savePlaylist(playlist);
                  _refreshData();
                }
              },
              child: const Text('Crear', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  /// Express playlist creation and adding multiple tracks to it.
  Future<void> _createAndAddTracksToPlaylist(List<Track> tracks, {String? collectionTitle}) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.divider),
        ),
        title: const Text(
          'Nueva Playlist',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Nombre de la playlist',
            labelStyle: TextStyle(color: AppTheme.textSecondary),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.divider),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppTheme.accent),
            ),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: AppTheme.bgDeep,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Crear y Añadir', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty) {
      final playlist = Playlist()
        ..playlistId = 'playlist_${DateTime.now().millisecondsSinceEpoch}'
        ..name = controller.text.trim()
        ..isDefault = false;
      await LocalDatabase.instance.savePlaylist(playlist);
      if (tracks.isNotEmpty) {
        await _addTracksDirectly(tracks, playlist, collectionTitle: collectionTitle);
      } else {
        _refreshData();
      }
    }
  }

  /// Express playlist creation from the track context menu.
  /// Creates the playlist and immediately adds the given track to it.
  Future<void> _createAndAddTrackToPlaylist(Track track) async {
    await _createAndAddTracksToPlaylist([track], collectionTitle: track.displayTitle);
  }

  /// Opens a file picker to let the user select a custom cover for a [playlist].
  ///
  /// After selection the image is:
  ///   1. Presented in a visual crop dialog for 1:1 framing.
  ///   2. Saved to the app-support cover_art directory with a dynamic timestamped filename.
  ///   3. Any existing custom cover file is deleted to avoid accumulating files on disk.
  ///   4. Flutter's image cache is cleared and coverVersion is bumped to render immediately.
  Future<void> _pickPlaylistCover(Playlist playlist) async {
    final granted = await PermissionService.requestImagePermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Se requieren permisos de almacenamiento/fotos para seleccionar carátulas.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final result = await fp.FilePicker.platform.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final sourcePath = result.files.first.path;
    if (sourcePath == null) return;

    // ── 1. Present Visual Crop Dialog ──────────────────────────────────────
    if (!mounted) return;
    final Uint8List? croppedBytes = await showDialog<Uint8List>(
      context: context,
      builder: (context) => _ImageCropDialog(imagePath: sourcePath),
    );
    if (croppedBytes == null) return;

    // ── 2. Determine paths & delete previous custom cover if exists ─────────
    final supportDir = await getApplicationSupportDirectory();
    final coverDir = Directory('${supportDir.path}/cover_art');
    if (!await coverDir.exists()) await coverDir.create(recursive: true);

    final oldPath = playlist.customCoverPath;
    if (oldPath != null && oldPath.isNotEmpty) {
      final oldFile = File(oldPath);
      if (await oldFile.exists()) {
        try {
          await oldFile.delete();
        } catch (_) {}
      }
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = '${coverDir.path}/custom_playlist_${playlist.playlistId}_$timestamp.png';
    await File(destPath).writeAsBytes(croppedBytes);

    // ── 3. Clear Flutter image cache and update cache buster version ──────
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    _coverVersions[playlist.playlistId] = timestamp;

    playlist.customCoverPath = destPath;
    await LocalDatabase.instance.savePlaylist(playlist);
    _refreshData();
  }

  /// Clears the custom cover of [playlist], falling back to the auto-generated
  /// collage (or track art) and recalculating the background color.
  Future<void> _clearPlaylistCover(Playlist playlist) async {
    final oldPath = playlist.customCoverPath;
    if (oldPath != null && oldPath.isNotEmpty) {
      final oldFile = File(oldPath);
      if (await oldFile.exists()) {
        try {
          await oldFile.delete();
        } catch (_) {}
      }
    }

    playlist.customCoverPath = null;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    _coverVersions[playlist.playlistId] = DateTime.now().millisecondsSinceEpoch;

    await LocalDatabase.instance.savePlaylist(playlist);
    _refreshData();
  }

  // Delete playlist
  Future<void> _deletePlaylist(Playlist playlist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgSurface,
        title: const Text('Eliminar Playlist', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('¿Estás seguro de que deseas eliminar "${playlist.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await LocalDatabase.instance.deletePlaylist(playlist.id);
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      _refreshData();
    }
  }

  /// Builds the base library page content (header + tabs + tab body).
  /// This is the initial route of the nested Navigator.
  Widget _buildLibraryRoot(BuildContext context, double bottomPad) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Tabs Header ────────────────────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 16 : 32,
            isMobile ? (MediaQuery.of(context).padding.top + 12) : 36,
            isMobile ? 16 : 32,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tu Biblioteca',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: isMobile ? 26 : null,
                    ),
              ),
              const SizedBox(height: 18),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildTabButton(LibraryTab.tracks, 'Canciones'),
                    _buildTabButton(LibraryTab.albums, 'Álbumes'),
                    _buildTabButton(LibraryTab.artists, 'Artistas'),
                    _buildTabButton(LibraryTab.playlists, 'Playlists'),
                    _buildTabButton(LibraryTab.videos, 'Vídeos'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(color: AppTheme.divider, height: 1),

        // ── Active Tab View Content ────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 32),
            child: switch (_activeTab) {
              LibraryTab.tracks    => _buildTracksTab(bottomPad: bottomPad),
              LibraryTab.albums    => _buildAlbumsTab(bottomPad: bottomPad),
              LibraryTab.artists   => _buildArtistsTab(bottomPad: bottomPad),
              LibraryTab.playlists => _buildPlaylistsTab(bottomPad: bottomPad),
              LibraryTab.videos    => _buildVideosTab(bottomPad: bottomPad),
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accent),
      );
    }

    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final sysPad = MediaQuery.of(context).padding.bottom;

    return StreamBuilder<Track?>(
      stream: OrpheusAudioHandler.instance.currentTrackStream,
      initialData: OrpheusAudioHandler.instance.currentTrack,
      builder: (context, snap) {
        final hasTrack = snap.data != null && snap.data!.trackId.isNotEmpty;
        // Panel height: nav (60) + gap (12) + mini-player (64 if track loaded).
        final bottomPad = isMobile
            ? (hasTrack ? 60.0 + 64.0 + 12.0 : 60.0 + 12.0) + sysPad + 8.0
            : 0.0;

        // Keep the cached value in sync so pushes without an explicit
        // bottomPad argument (e.g. from context-menu "Ir al álbum") still
        // use the correct current value.
        _currentBottomPad = bottomPad;

        // ── Nested Navigator ──────────────────────────────────────────────────
        // Detail routes (album / artist / playlist) are pushed here instead of
        // the root navigator, so the floating glass pill always remains visible
        // and interactive on top of the MobileNavigationShell Stack.
        //
        // NavigatorPopHandler integrates Android back-button / predictive-back
        // with the nested navigator before the root PopScope intercepts it.
        return NavigatorPopHandler(
          onPop: () {
            _libraryNavKey.currentState?.maybePop();
          },
          child: Navigator(
            key: _libraryNavKey,
            onPopPage: (route, result) {
              final didPop = route.didPop(result);
              if (didPop) {
                // Schedule a post-frame rebuild to flush any GestureArena
                // residue left by the slide-out transition, restoring 100%
                // touch responsiveness to the floating pill on the first tap.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() {});
                });
              }
              return didPop;
            },
            pages: [
              MaterialPage(
                key: const ValueKey('library_root'),
                child: _buildLibraryRoot(context, bottomPad),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabButton(LibraryTab tab, String label) {
    final active = _activeTab == tab;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeTab = tab;
          _searchQuery = '';
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 24),
        padding: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppTheme.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            color: active ? AppTheme.textPrimary : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB BUILDERS
  // ══════════════════════════════════════════════════════════════════════════

  // ── Tracks Tab ─────────────────────────────────────────────────────────────
  Widget _buildTracksTab({double bottomPad = 0}) {
    final filtered = _allTracks.where((t) {
      final query = _searchQuery.toLowerCase();
      return t.displayTitle.toLowerCase().contains(query) ||
          t.displayArtist.toLowerCase().contains(query) ||
          t.individualArtists.any((a) => a.toLowerCase().contains(query)) ||
          (t.displayAlbum.toLowerCase().contains(query));
    }).toList();

    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 600;
      return Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState('No se encontraron canciones.')
                : isMobile
                    ? _buildMobileSongsList(filtered, bottomPad: bottomPad)
                    : _buildTrackTable(filtered, contextName: 'Biblioteca'),
          ),
        ],
      );
    });
  }

  // ── Videos Tab ─────────────────────────────────────────────────────────────
  Widget _buildVideosTab({double bottomPad = 0}) {
    final videoTracks = _allTracks.where((t) {
      final isVid = t.isVideo ||
          t.displayAlbum.toLowerCase() == 'vídeos' ||
          t.displayAlbum.toLowerCase() == 'videos';
      if (!isVid) return false;
      final query = _searchQuery.toLowerCase();
      if (query.isEmpty) return true;
      return t.displayTitle.toLowerCase().contains(query) ||
          t.displayArtist.toLowerCase().contains(query) ||
          t.individualArtists.any((a) => a.toLowerCase().contains(query));
    }).toList();

    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 600;
      return Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: videoTracks.isEmpty
                ? _buildEmptyState(
                    _searchQuery.isNotEmpty
                        ? 'No se encontraron vídeos que coincidan con la búsqueda.'
                        : 'No tienes vídeos en tu biblioteca.\nLos archivos de vídeo (.mp4, .mkv, .webm) agregados a tus carpetas de música aparecerán aquí.',
                  )
                : isMobile
                    ? _buildMobileSongsList(videoTracks, bottomPad: bottomPad)
                    : _buildTrackTable(videoTracks, contextName: 'Vídeos'),
          ),
        ],
      );
    });
  }

  // ── Albums Tab ─────────────────────────────────────────────────────────────
  Widget _buildAlbumsTab({double bottomPad = 0}) {
    final filtered = _uniqueAlbums.where((a) {
      return a.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    if (filtered.isEmpty) {
      return Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildEmptyState('No se encontraron álbumes.')),
        ],
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 600;
      final int cols = isMobile ? 2 : 5;
      const double ratio = 0.72;

      return Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.only(top: 16, bottom: bottomPad > 0 ? bottomPad : 16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 16,
                mainAxisSpacing: 20,
                childAspectRatio: ratio,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, idx) {
                final albumName = filtered[idx];
                final firstTrack = _firstTrackByAlbum[albumName] ??
                    _allTracks.firstWhere(
                      (t) => t.displayAlbum == albumName,
                      orElse: () => _allTracks.isNotEmpty ? _allTracks.first : Track(),
                    );
                final coverPath = firstTrack.customMetadata.customCoverPath;

                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _openAlbum(albumName, bottomPad),
                    onLongPress: () {
                      final albumTracks = _allTracks
                          .where((t) => t.displayAlbum == albumName)
                          .toList();
                      _showAlbumContextMenu(context, albumName, albumTracks, firstTrack);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.bgSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      padding: EdgeInsets.all(isMobile ? 8 : 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: coverPath != null && coverPath.isNotEmpty
                                    ? Image.file(
                                        File(coverPath),
                                        fit: BoxFit.cover,
                                        cacheWidth: 320,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: AppTheme.bgHover,
                                          child: const Icon(Icons.album_rounded,
                                              color: AppTheme.textHint, size: 48),
                                        ),
                                      )
                                    : Container(
                                        color: AppTheme.bgHover,
                                        child: const Icon(Icons.album_rounded,
                                            color: AppTheme.textHint, size: 48),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            albumName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (albumName.trim().toLowerCase() == 'vídeos' || albumName.trim().toLowerCase() == 'videos')
                                ? 'Varios artistas'
                                : firstTrack.displayArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }

  // ── Artists Tab ────────────────────────────────────────────────────────────
  Widget _buildArtistsTab({double bottomPad = 0}) {
    final filtered = _uniqueArtists.where((a) {
      return a.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    if (filtered.isEmpty) {
      return Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildEmptyState('No se encontraron artistas.')),
        ],
      );
    }

    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.only(top: 16, bottom: bottomPad > 0 ? bottomPad : 16),
            itemCount: filtered.length,
            itemBuilder: (context, idx) {
              final artistName = filtered[idx];
              final count = _trackCountByArtist[artistName.toLowerCase()] ?? 0;

              return Material(
                color: AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: AppTheme.bgHover,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_rounded, color: AppTheme.accent, size: 26),
                    ),
                    title: Text(
                      artistName,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      '$count ${count == 1 ? 'canción' : 'canciones'}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary),
                    onTap: () => _openArtist(artistName, bottomPad),
                    onLongPress: () {
                      final artistTracks = _allTracks
                          .where((t) => t.individualArtists.any(
                              (a) => a.toLowerCase() == artistName.toLowerCase()))
                          .toList();
                      _showArtistContextMenu(context, artistName, artistTracks);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Playlists Tab ──────────────────────────────────────────────────────────
  Widget _buildPlaylistsTab({double bottomPad = 0}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TUS PLAYLISTS',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: AppTheme.bgDeep,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                onPressed: _createPlaylist,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Crear Playlist',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _playlists.isEmpty
              ? _buildEmptyState('No tienes playlists creadas.')
              : LayoutBuilder(
                  builder: (context, constraints) {
                    // Adapt grid columns based on available width
                    final width = constraints.maxWidth;
                    final int cols = width >= 1200
                        ? 6
                        : width >= 900
                            ? 5
                            : width >= 650
                                ? 4
                                : width >= 420
                                    ? 3
                                    : 2;
                    return GridView.builder(
                      padding: EdgeInsets.only(bottom: bottomPad > 0 ? bottomPad : 16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 20,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: _playlists.length,
                      itemBuilder: (context, idx) {
                        final playlist = _playlists[idx];

                        return StreamBuilder<Playlist?>(
                          stream: LocalDatabase.instance.watchPlaylistById(playlist.playlistId),
                          initialData: playlist,
                          builder: (context, snapshot) {
                            final livePlaylist = snapshot.data ?? playlist;

                            return MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () => _openPlaylist(livePlaylist, bottomPad),
                                onLongPress: () {
                                  final playlistTracks = livePlaylist.trackIds
                                      .map((id) => _tracksById[id])
                                      .whereType<Track>()
                                      .toList();
                                  _showPlaylistContextMenu(context, livePlaylist, playlistTracks);
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppTheme.bgSurface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppTheme.divider),
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: AspectRatio(
                                            aspectRatio: 1,
                                            child: PlaylistCover(
                                              playlist: livePlaylist,
                                              allTracks: _allTracks,
                                              tracksById: _tracksById,
                                              size: 180,
                                              coverVersion: _coverVersions[livePlaylist.playlistId],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        livePlaylist.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: AppTheme.textPrimary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13),
                                      ),
                                      Text(
                                        '${livePlaylist.trackIds.length} canciones',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DETAIL VIEW BUILDERS
  // ══════════════════════════════════════════════════════════════════════════

  // ── Album Details View ─────────────────────────────────────────────────────
  Widget _buildAlbumDetails(String albumName, {double bottomPad = 0}) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    if (isMobile) return _buildMobileAlbumDetails(albumName, bottomPad: bottomPad);

    final albumTracks = _allTracks.where((t) => t.displayAlbum == albumName).toList();
    final coverPath = albumTracks.isNotEmpty ? albumTracks.first.customMetadata.customCoverPath : null;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
                onPressed: () => _libraryNavKey.currentState?.maybePop(),
              ),
              const SizedBox(width: 8),
              const Text('Volver a Álbumes', style: TextStyle(color: AppTheme.textSecondary)),
            ],
          ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.40),
                        blurRadius: 24,
                        spreadRadius: -2,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 230,
                      height: 230,
                      child: coverPath != null
                          ? Image.file(File(coverPath), fit: BoxFit.cover)
                          : Container(
                              color: AppTheme.bgSurface,
                              child: const Icon(Icons.album_rounded, color: AppTheme.textHint, size: 72),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ÁLBUM',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textSecondary,
                              letterSpacing: 1.5)),
                      const SizedBox(height: 6),
                      Text(
                        albumName,
                        style: const TextStyle(
                            fontSize: 34, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        (albumName.trim().toLowerCase() == 'vídeos' || albumName.trim().toLowerCase() == 'videos')
                            ? 'Varios artistas'
                            : (albumTracks.isNotEmpty ? albumTracks.first.displayArtist : 'Artista Desconocido'),
                        style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        formatTidalDuration(albumTracks),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textHint,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: AppTheme.bgDeep,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              elevation: 0,
                            ),
                            onPressed: () => _shufflePlayTracks(albumTracks, contextName: 'Álbum: $albumName'),
                            icon: const Icon(Icons.shuffle_rounded, size: 16, color: AppTheme.bgDeep),
                            label: const Text(
                              'Reproducción Aleatoria',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.textPrimary,
                              side: const BorderSide(color: AppTheme.divider, width: 1),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            onPressed: () => _playTracks(albumTracks, 0, contextName: 'Álbum: $albumName'),
                            icon: const Icon(Icons.play_arrow_rounded, size: 16),
                            label: const Text('Reproducir',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppTheme.textSecondary),
                            tooltip: 'Más opciones',
                            color: AppTheme.bgSurface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: AppTheme.divider),
                            ),
                            onSelected: (value) {
                              if (value == 'add_to_playlist') {
                                _showAddTracksToPlaylistModal(context, albumTracks, collectionTitle: 'Álbum: $albumName');
                              } else if (value == 'download_offline') {
                                _downloadTracksOffline(albumTracks, title: albumName);
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem<String>(
                                value: 'add_to_playlist',
                                child: Row(
                                  children: [
                                    Icon(Icons.playlist_add_rounded, size: 18, color: AppTheme.textPrimary),
                                    SizedBox(width: 12),
                                    Text('Añadir a playlist', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem<String>(
                                value: 'download_offline',
                                child: Row(
                                  children: [
                                    Icon(Icons.download_for_offline_rounded, size: 18, color: AppTheme.accent),
                                    SizedBox(width: 12),
                                    Text('Descargar sin conexión', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Expanded(
              child: _buildTrackTable(albumTracks, contextName: 'Álbum: $albumName', isAlbumDetail: true),
            ),
          ],
        ),
      );
  }

  // ── Artist Details View ────────────────────────────────────────────────────
  Widget _buildArtistDetails(String artistName, {double bottomPad = 0}) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    if (isMobile) return _buildMobileArtistDetails(artistName, bottomPad: bottomPad);

    final artistTracks = _allTracks
        .where((t) => t.individualArtists
            .any((a) => a.toLowerCase() == artistName.toLowerCase()))
        .toList();

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
                onPressed: () => _libraryNavKey.currentState?.maybePop(),
              ),
              const SizedBox(width: 8),
              const Text('Volver a Artistas', style: TextStyle(color: AppTheme.textSecondary)),
            ],
          ),
            const SizedBox(height: 24),
            Row(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: AppTheme.bgSurface,
                  child: const Icon(Icons.person_rounded, color: AppTheme.accent, size: 48),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ARTISTA',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textSecondary,
                              letterSpacing: 1.5)),
                      const SizedBox(height: 6),
                      Text(
                        artistName,
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formatTidalDuration(artistTracks),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textHint,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: AppTheme.bgDeep,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              elevation: 0,
                            ),
                            onPressed: () => _shufflePlayTracks(artistTracks, contextName: 'Artista: $artistName'),
                            icon: const Icon(Icons.shuffle_rounded, size: 16, color: AppTheme.bgDeep),
                            label: const Text(
                              'Reproducción Aleatoria',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.textPrimary,
                              side: const BorderSide(color: AppTheme.divider, width: 1),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            onPressed: () => _playTracks(artistTracks, 0, contextName: 'Artista: $artistName'),
                            icon: const Icon(Icons.play_arrow_rounded, size: 16),
                            label: const Text('Reproducir',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppTheme.textSecondary),
                            tooltip: 'Más opciones',
                            color: AppTheme.bgSurface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: AppTheme.divider),
                            ),
                            onSelected: (value) {
                              if (value == 'add_to_playlist') {
                                _showAddTracksToPlaylistModal(context, artistTracks, collectionTitle: 'Artista: $artistName');
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem<String>(
                                value: 'add_to_playlist',
                                child: Row(
                                  children: [
                                    Icon(Icons.playlist_add_rounded, size: 18, color: AppTheme.textPrimary),
                                    SizedBox(width: 12),
                                    Text('Añadir a playlist', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Expanded(
              child: _buildTrackTable(artistTracks, contextName: 'Artista: $artistName', isArtistDetail: true),
            ),
          ],
        ),
      );
  }

  // ── Mobile Album Details View ──────────────────────────────────────────────
  Widget _buildMobileAlbumDetails(String albumName, {double bottomPad = 0}) {
    final albumTracks = _allTracks.where((t) => t.displayAlbum == albumName).toList();
    final coverPath = albumTracks.isNotEmpty ? albumTracks.first.customMetadata.customCoverPath : null;
    final isVideosAlbum = albumName.trim().toLowerCase() == 'vídeos' || albumName.trim().toLowerCase() == 'videos';
    final artistName = isVideosAlbum
        ? 'Varios artistas'
        : (albumTracks.isNotEmpty ? albumTracks.first.displayArtist : 'Artista Desconocido');
    final contextName = 'Álbum: $albumName';
    final screenWidth = MediaQuery.sizeOf(context).width;
    final heroSize = (screenWidth * 0.58).clamp(180.0, 230.0);
    final ValueNotifier<double> scrollProgressNotifier = ValueNotifier<double>(0.0);

    return SafeArea(
      child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final progress = (notification.metrics.pixels / 140.0).clamp(0.0, 1.0);
            if (scrollProgressNotifier.value != progress) {
              scrollProgressNotifier.value = progress;
            }
            return false;
          },
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                floating: false,
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                flexibleSpace: ValueListenableBuilder<double>(
                  valueListenable: scrollProgressNotifier,
                  builder: (context, t, _) {
                    if (t <= 0.001) {
                      return const SizedBox.expand();
                    }
                    final blurSigma = 16.0 * t;
                    final tintAlpha = 0.80 * t;
                    final borderAlpha = 0.08 * t;
                    return ClipRect(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.bgDeep.withOpacity(tintAlpha),
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.white.withOpacity(borderAlpha),
                                width: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
                  onPressed: () => _libraryNavKey.currentState?.maybePop(),
                ),
                title: ValueListenableBuilder<double>(
                  valueListenable: scrollProgressNotifier,
                  builder: (context, t, _) {
                    final titleOpacity = Curves.easeOutCubic.transform(t);
                    return Opacity(
                      opacity: titleOpacity,
                      child: Text(
                        albumName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    );
                  },
                ),
                actions: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppTheme.textSecondary),
                    tooltip: 'Más opciones',
                    color: AppTheme.bgSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppTheme.divider),
                    ),
                    onSelected: (value) {
                      if (value == 'add_to_playlist') {
                        _showAddTracksToPlaylistModal(context, albumTracks, collectionTitle: albumName);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem<String>(
                        value: 'add_to_playlist',
                        child: Row(
                          children: [
                            Icon(Icons.playlist_add_rounded, size: 18, color: AppTheme.textPrimary),
                            SizedBox(width: 12),
                            Text('Añadir a playlist', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Hero Cover Art
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.55),
                              blurRadius: 36,
                              spreadRadius: -4,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            width: heroSize,
                            height: heroSize,
                            child: coverPath != null
                                ? Image.file(File(coverPath), fit: BoxFit.cover, cacheWidth: 460)
                                : Container(
                                    color: AppTheme.bgSurface,
                                    child: const Icon(Icons.album_rounded, color: AppTheme.textHint, size: 64),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        albumName,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        artistName,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatTidalDuration(albumTracks),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textHint,
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Action buttons
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: AppTheme.bgDeep,
                              minimumSize: const Size(0, 38),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              elevation: 0,
                            ),
                            onPressed: () => _shufflePlayTracks(albumTracks, contextName: contextName),
                            icon: const Icon(Icons.shuffle_rounded, size: 16, color: AppTheme.bgDeep),
                            label: const Text('Aleatorio',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.textPrimary,
                              side: const BorderSide(color: AppTheme.divider, width: 1),
                              minimumSize: const Size(0, 38),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            onPressed: () => _playTracks(albumTracks, 0, contextName: contextName),
                            icon: const Icon(Icons.play_arrow_rounded, size: 16),
                            label: const Text('Reproducir',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: AppTheme.divider, height: 1),
                    ],
                  ),
                ),
              ),
              if (albumTracks.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: _buildEmptyState('No hay canciones en este álbum.'),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.only(bottom: bottomPad > 0 ? bottomPad : 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, idx) {
                      final track = albumTracks[idx];
                      final coverPt = track.customMetadata.customCoverPath;
                      final hasArt = coverPt != null && coverPt.isNotEmpty && File(coverPt).existsSync();
                      final durationStr = _formatDuration(track.duration);

                      return StreamBuilder<Track?>(
                        stream: OrpheusAudioHandler.instance.currentTrackStream,
                        initialData: OrpheusAudioHandler.instance.currentTrack,
                        builder: (context, snap) {
                          final currentTrack = snap.data;
                          final isPlayingThisTrack = currentTrack != null && currentTrack.trackId == track.trackId;
                          final currentCtxIdx = AudioPlayerService.instance.currentOriginalIndex;
                          final activeCtxName = AudioPlayerService.instance.contextName;
                          final isSameContext = activeCtxName == contextName;
                          final isCurrent = isPlayingThisTrack && isSameContext && (currentCtxIdx == idx);

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isCurrent ? AppTheme.accent.withOpacity(0.12) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: isCurrent
                                  ? Border.all(color: AppTheme.accent.withOpacity(0.40), width: 1.2)
                                  : null,
                              boxShadow: isCurrent
                                  ? [BoxShadow(
                                      color: AppTheme.accent.withOpacity(0.18),
                                      blurRadius: 12,
                                      spreadRadius: 0.5,
                                      offset: const Offset(0, 2),
                                    )]
                                  : null,
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              borderRadius: BorderRadius.circular(10),
                              child: ListTile(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                onTap: () => _playTracks(albumTracks, idx, contextName: contextName),
                                onLongPress: () => _showTrackOptionsModal(context, track),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 44, height: 44,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        hasArt
                                            ? Image.file(File(coverPt), fit: BoxFit.cover, cacheWidth: 88)
                                            : const ColoredBox(
                                                color: AppTheme.bgHover,
                                                child: Icon(Icons.music_note_rounded,
                                                    color: AppTheme.textHint, size: 20),
                                              ),
                                        if (isCurrent)
                                          Container(
                                            color: Colors.black54,
                                            child: Center(
                                              child: StreamBuilder<bool>(
                                                stream: OrpheusAudioHandler.instance.isPlayingStream,
                                                initialData: OrpheusAudioHandler.instance.isPlaying,
                                                builder: (_, playSnap) => AnimatedEqualizer(
                                                  isPlaying: playSnap.data ?? false,
                                                  barCount: 3,
                                                  barWidth: 3.0,
                                                  maxHeight: 18.0,
                                                  minHeight: 4.0,
                                                  spacing: 2.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        track.displayTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isCurrent ? AppTheme.accent : AppTheme.textPrimary,
                                          fontSize: 13,
                                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (track.isVideo) ...[
                                      const SizedBox(width: 6),
                                      const VideoBadge(compact: true),
                                    ],
                                  ],
                                ),
                                // In album detail, artist is redundant; show duration as subtitle instead.
                                subtitle: Text(
                                  durationStr,
                                  style: TextStyle(
                                    color: isCurrent ? AppTheme.accent.withOpacity(0.8) : AppTheme.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: Icon(Icons.more_vert_rounded,
                                      color: isCurrent ? AppTheme.accent : AppTheme.textSecondary, size: 20),
                                  onPressed: () => _showTrackOptionsModal(context, track),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                    childCount: albumTracks.length,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  // ── Mobile Artist Details View ─────────────────────────────────────────────
  Widget _buildMobileArtistDetails(String artistName, {double bottomPad = 0}) {
    final artistTracks = _allTracks
        .where((t) => t.individualArtists
            .any((a) => a.toLowerCase() == artistName.toLowerCase()))
        .toList();
    final contextName = 'Artista: $artistName';

    return SafeArea(
      child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back button
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
                          onPressed: () => _libraryNavKey.currentState?.maybePop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        const Text('Artistas', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Header: Avatar + Metadata
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: AppTheme.bgSurface,
                          child: const Icon(Icons.person_rounded, color: AppTheme.accent, size: 40),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('ARTISTA',
                                  style: TextStyle(
                                      fontSize: 10, fontWeight: FontWeight.bold,
                                      color: AppTheme.textSecondary, letterSpacing: 1.4)),
                              const SizedBox(height: 4),
                              Text(
                                artistName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                formatTidalDuration(artistTracks),
                                style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Action buttons
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: AppTheme.bgDeep,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            elevation: 0,
                          ),
                          onPressed: () => _shufflePlayTracks(artistTracks, contextName: contextName),
                          icon: const Icon(Icons.shuffle_rounded, size: 16, color: AppTheme.bgDeep),
                          label: const Text('Aleatorio',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textPrimary,
                            side: const BorderSide(color: AppTheme.divider, width: 1),
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          onPressed: () => _playTracks(artistTracks, 0, contextName: contextName),
                          icon: const Icon(Icons.play_arrow_rounded, size: 16),
                          label: const Text('Reproducir',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppTheme.textSecondary),
                          tooltip: 'Más opciones',
                          color: AppTheme.bgSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: AppTheme.divider),
                          ),
                          onSelected: (value) {
                            if (value == 'add_to_playlist') {
                              _showAddTracksToPlaylistModal(context, artistTracks, collectionTitle: artistName);
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem<String>(
                              value: 'add_to_playlist',
                              child: Row(
                                children: [
                                  Icon(Icons.playlist_add_rounded, size: 18, color: AppTheme.textPrimary),
                                  SizedBox(width: 12),
                                  Text('Añadir a playlist', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(color: AppTheme.divider, height: 1),
                  ],
                ),
              ),
            ),
            if (artistTracks.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: _buildEmptyState('No hay canciones de este artista.'),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.only(bottom: bottomPad > 0 ? bottomPad : 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, idx) {
                      final track = artistTracks[idx];
                      final coverPt = track.customMetadata.customCoverPath;
                      final hasArt = coverPt != null && coverPt.isNotEmpty && File(coverPt).existsSync();
                      final durationStr = _formatDuration(track.duration);

                      return StreamBuilder<Track?>(
                        stream: OrpheusAudioHandler.instance.currentTrackStream,
                        initialData: OrpheusAudioHandler.instance.currentTrack,
                        builder: (context, snap) {
                          final currentTrack = snap.data;
                          final isPlayingThisTrack = currentTrack != null && currentTrack.trackId == track.trackId;
                          final currentCtxIdx = AudioPlayerService.instance.currentOriginalIndex;
                          final activeCtxName = AudioPlayerService.instance.contextName;
                          final isSameContext = activeCtxName == contextName;
                          final isCurrent = isPlayingThisTrack && isSameContext && (currentCtxIdx == idx);

                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isCurrent ? AppTheme.accent.withOpacity(0.12) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: isCurrent
                                  ? Border.all(color: AppTheme.accent.withOpacity(0.40), width: 1.2)
                                  : null,
                              boxShadow: isCurrent
                                  ? [BoxShadow(
                                      color: AppTheme.accent.withOpacity(0.18),
                                      blurRadius: 12,
                                      spreadRadius: 0.5,
                                      offset: const Offset(0, 2),
                                    )]
                                  : null,
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              borderRadius: BorderRadius.circular(10),
                              child: ListTile(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                onTap: () => _playTracks(artistTracks, idx, contextName: contextName),
                                onLongPress: () => _showTrackOptionsModal(context, track),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 44, height: 44,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        hasArt
                                            ? Image.file(File(coverPt), fit: BoxFit.cover, cacheWidth: 88)
                                            : const ColoredBox(
                                                color: AppTheme.bgHover,
                                                child: Icon(Icons.music_note_rounded,
                                                    color: AppTheme.textHint, size: 20),
                                              ),
                                        if (isCurrent)
                                          Container(
                                            color: Colors.black54,
                                            child: Center(
                                              child: StreamBuilder<bool>(
                                                stream: OrpheusAudioHandler.instance.isPlayingStream,
                                                initialData: OrpheusAudioHandler.instance.isPlaying,
                                                builder: (_, playSnap) => AnimatedEqualizer(
                                                  isPlaying: playSnap.data ?? false,
                                                  barCount: 3,
                                                  barWidth: 3.0,
                                                  maxHeight: 18.0,
                                                  minHeight: 4.0,
                                                  spacing: 2.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        track.displayTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isCurrent ? AppTheme.accent : AppTheme.textPrimary,
                                          fontSize: 13,
                                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (track.isVideo) ...[
                                      const SizedBox(width: 6),
                                      const VideoBadge(compact: true),
                                    ],
                                  ],
                                ),
                                // In artist detail, show Album • Duration as subtitle.
                                subtitle: Text(
                                  '${track.displayAlbum} · $durationStr',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isCurrent ? AppTheme.accent.withOpacity(0.8) : AppTheme.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: Icon(Icons.more_vert_rounded,
                                      color: isCurrent ? AppTheme.accent : AppTheme.textSecondary, size: 20),
                                  onPressed: () => _showTrackOptionsModal(context, track),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                    childCount: artistTracks.length,
                  ),
                ),
              ),
          ],
        ),
      );
  }

  // ── Playlist Details View ──────────────────────────────────────────────────
  Widget _buildPlaylistDetails(Playlist initialPlaylist, {double bottomPad = 0}) {
    return StreamBuilder<Playlist?>(
        stream: LocalDatabase.instance.watchPlaylistById(initialPlaylist.playlistId),
        initialData: initialPlaylist,
        builder: (context, snapshot) {
          final playlist = snapshot.data ?? initialPlaylist;
          // Resolve tracks in order
          final playlistTracks = playlist.trackIds
              .map((id) => _allTracks.firstWhere((t) => t.id == id, orElse: () => Track()))
              .where((t) => t.trackId.isNotEmpty)
              .toList();

          final isLiked = playlist.playlistId == '__liked__';

          // Determine the background image path for the blurred Tidal atmosphere:
          // priority: playlist customCoverPath > first track with cover
          String? bgImagePath = playlist.customCoverPath;
          if (bgImagePath == null || bgImagePath.isEmpty || !File(bgImagePath).existsSync()) {
            for (final t in playlistTracks) {
              final cp = t.customMetadata.customCoverPath;
              if (cp != null && cp.isNotEmpty && File(cp).existsSync()) {
                bgImagePath = cp;
                break;
              }
            }
          }

          final isMobile = MediaQuery.sizeOf(context).width < 600;
          if (isMobile) {
            return _buildMobilePlaylistDetails(
              playlist,
              playlistTracks,
              isLiked,
              bgImagePath,
              bottomPad: bottomPad,
            );
          }

          return Stack(
            children: [
              // ───────────────────────────────────────────────────────────────────
              // 🎨 TIDAL-STYLE BLURRED IMAGE BACKGROUND
              // ───────────────────────────────────────────────────────────────────
              Positioned.fill(
                child: ClipRect(
                  child: bgImagePath != null
                      ? _BlurredImageBackground(imagePath: bgImagePath)
                      : Container(color: const Color(0xFF141414)),
                ),
              ),

              // ───────────────────────────────────────────────────────────────────
              // 🔮 MAIN CONTENT
              // ───────────────────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back button
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
                          onPressed: () => _libraryNavKey.currentState?.maybePop(),
                        ),
                        const SizedBox(width: 8),
                        const Text('Volver a Playlists', style: TextStyle(color: AppTheme.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Header row: cover + metadata + actions (Responsive Column/Row layout)
                    MediaQuery.sizeOf(context).width < 600
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: _PlaylistCoverPicker(
                                  playlist: playlist,
                                  allTracks: _allTracks,
                                  tracksById: _tracksById,
                                  onPickCover: isLiked ? null : () => _pickPlaylistCover(playlist),
                                  onClearCover: (isLiked || playlist.customCoverPath == null)
                                      ? null
                                      : () => _clearPlaylistCover(playlist),
                                  coverVersion: _coverVersions[playlist.playlistId],
                                ),
                              ),
                              const SizedBox(height: 20),
                              _buildPlaylistHeaderMetadata(playlist, playlistTracks, isLiked, true),
                            ],
                          )
                        : Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.40),
                                  blurRadius: 24,
                                  spreadRadius: -2,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: _PlaylistCoverPicker(
                              playlist: playlist,
                              allTracks: _allTracks,
                              tracksById: _tracksById,
                              size: 230,
                              borderRadius: BorderRadius.circular(12),
                              onPickCover: isLiked ? null : () => _pickPlaylistCover(playlist),
                              onClearCover: (isLiked || playlist.customCoverPath == null)
                                  ? null
                                  : () => _clearPlaylistCover(playlist),
                              coverVersion: _coverVersions[playlist.playlistId],
                            ),
                          ),
                            const SizedBox(width: 28),
                            Expanded(
                              child: _buildPlaylistHeaderMetadata(playlist, playlistTracks, isLiked, false),
                            ),
                          ],
                        ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: playlistTracks.isEmpty
                        ? _buildEmptyState('No hay canciones en esta playlist.')
                        : _buildTrackTable(
                            playlistTracks,
                            playlistSource: playlist,
                            contextName: playlist.playlistId == '__liked__'
                                ? 'Canciones que te gustan'
                                : 'Playlist: ${playlist.name}',
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Mobile-optimised Playlist Detail View using CustomScrollView and pinned SliverAppBar.
  Widget _buildMobilePlaylistDetails(
    Playlist playlist,
    List<Track> playlistTracks,
    bool isLiked,
    String? bgImagePath, {
    double bottomPad = 0,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final heroSize = (screenWidth * 0.58).clamp(180.0, 230.0);
    final ValueNotifier<double> scrollProgressNotifier = ValueNotifier<double>(0.0);

    return Stack(
      children: [
        Positioned.fill(
          child: ClipRect(
            child: bgImagePath != null
                ? _BlurredImageBackground(imagePath: bgImagePath)
                : Container(color: const Color(0xFF141414)),
          ),
        ),
        SafeArea(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              final progress = (notification.metrics.pixels / 140.0).clamp(0.0, 1.0);
              if (scrollProgressNotifier.value != progress) {
                scrollProgressNotifier.value = progress;
              }
              return false;
            },
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  floating: false,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  flexibleSpace: ValueListenableBuilder<double>(
                    valueListenable: scrollProgressNotifier,
                    builder: (context, t, _) {
                      if (t <= 0.001) {
                        return const SizedBox.expand();
                      }
                      final blurSigma = 16.0 * t;
                      final tintAlpha = 0.80 * t;
                      final borderAlpha = 0.08 * t;
                      return ClipRect(
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.bgDeep.withOpacity(tintAlpha),
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.white.withOpacity(borderAlpha),
                                  width: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
                    onPressed: () => _libraryNavKey.currentState?.maybePop(),
                  ),
                  title: ValueListenableBuilder<double>(
                    valueListenable: scrollProgressNotifier,
                    builder: (context, t, _) {
                      final titleOpacity = Curves.easeOutCubic.transform(t);
                      return Opacity(
                        opacity: titleOpacity,
                        child: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      );
                    },
                  ),
                  actions: [
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppTheme.textSecondary),
                      tooltip: 'Más opciones',
                      color: AppTheme.bgSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppTheme.divider),
                      ),
                      onSelected: (value) {
                        if (value == 'add_to_playlist') {
                          _showAddTracksToPlaylistModal(context, playlistTracks, collectionTitle: playlist.name);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem<String>(
                          value: 'add_to_playlist',
                          child: Row(
                            children: [
                              Icon(Icons.playlist_add_rounded, size: 18, color: AppTheme.textPrimary),
                              SizedBox(width: 12),
                              Text('Añadir a playlist', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Hero Cover Art
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.55),
                                blurRadius: 36,
                                spreadRadius: -4,
                                offset: const Offset(0, 16),
                              ),
                            ],
                          ),
                          child: _PlaylistCoverPicker(
                            playlist: playlist,
                            allTracks: _allTracks,
                            tracksById: _tracksById,
                            size: heroSize,
                            borderRadius: BorderRadius.circular(16),
                            onPickCover: isLiked ? null : () => _pickPlaylistCover(playlist),
                            onClearCover: (isLiked || playlist.customCoverPath == null)
                                ? null
                                : () => _clearPlaylistCover(playlist),
                            coverVersion: _coverVersions[playlist.playlistId],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          playlist.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (playlist.description != null && playlist.description!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            playlist.description!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          formatTidalDuration(playlistTracks),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textHint,
                          ),
                        ),
                        const SizedBox(height: 18),
                        // Action buttons — Wrap prevents RenderFlex overflow on narrow screens
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.accent,
                                foregroundColor: AppTheme.bgDeep,
                                minimumSize: const Size(0, 38),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                elevation: 0,
                              ),
                              onPressed: () => _shufflePlayTracks(
                                playlistTracks,
                                contextName: playlist.playlistId == '__liked__'
                                    ? 'Canciones que te gustan'
                                    : 'Playlist: ${playlist.name}',
                              ),
                              icon: const Icon(Icons.shuffle_rounded, size: 16, color: AppTheme.bgDeep),
                              label: const Text(
                                'Aleatorio',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                            if (!isLiked)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                  side: const BorderSide(color: Colors.redAccent, width: 1),
                                  minimumSize: const Size(0, 38),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                                onPressed: () => _deletePlaylist(playlist),
                                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                label: const Text('Eliminar',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: AppTheme.divider, height: 1),
                      ],
                    ),
                  ),
                ),
              if (playlistTracks.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: _buildEmptyState('No hay canciones en esta playlist.'),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.only(bottom: bottomPad > 0 ? bottomPad : 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, idx) {
                        final track = playlistTracks[idx];
                        final coverPath = track.customMetadata.customCoverPath;
                        final hasArt = coverPath != null &&
                            coverPath.isNotEmpty &&
                            File(coverPath).existsSync();

                        final effectiveContextName = playlist.playlistId == '__liked__'
                            ? 'Canciones que te gustan'
                            : 'Playlist: ${playlist.name}';

                        return StreamBuilder<Track?>(
                          stream: OrpheusAudioHandler.instance.currentTrackStream,
                          initialData: OrpheusAudioHandler.instance.currentTrack,
                          builder: (context, snap) {
                            final currentTrack = snap.data;
                            final isPlayingThisTrack = currentTrack != null && currentTrack.trackId == track.trackId;
                            final currentCtxIdx = AudioPlayerService.instance.currentOriginalIndex;
                            final activeCtxName = AudioPlayerService.instance.contextName;

                            // Disambiguate duplicate songs in playlist when the current context is this playlist
                            final isSamePlaylistContext = activeCtxName == effectiveContextName ||
                                activeCtxName == playlist.name ||
                                activeCtxName == 'Playlist: ${playlist.name}' ||
                                (activeCtxName == 'Canciones que te gustan' && playlist.playlistId == '__liked__');

                            final isCurrent = isPlayingThisTrack && isSamePlaylistContext && (currentCtxIdx == idx);

                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isCurrent ? AppTheme.accent.withOpacity(0.12) : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: isCurrent
                                    ? Border.all(color: AppTheme.accent.withOpacity(0.40), width: 1.2)
                                    : null,
                                boxShadow: isCurrent
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.accent.withOpacity(0.18),
                                          blurRadius: 12,
                                          spreadRadius: 0.5,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Material(
                                type: MaterialType.transparency,
                                borderRadius: BorderRadius.circular(10),
                                child: ListTile(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                  onTap: () => _playTracks(playlistTracks, idx, contextName: effectiveContextName),
                                  onLongPress: () => _showTrackOptionsModal(
                                    context,
                                    track,
                                    playlistSource: playlist,
                                    trackIndexInPlaylist: idx,
                                  ),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        hasArt
                                            ? Image.file(File(coverPath), fit: BoxFit.cover, cacheWidth: 88)
                                            : const ColoredBox(
                                                color: AppTheme.bgHover,
                                                child: Icon(Icons.music_note_rounded,
                                                    color: AppTheme.textHint, size: 20),
                                              ),
                                        if (isCurrent)
                                          Container(
                                            color: Colors.black54,
                                            child: Center(
                                              child: StreamBuilder<bool>(
                                                stream: OrpheusAudioHandler.instance.isPlayingStream,
                                                initialData: OrpheusAudioHandler.instance.isPlaying,
                                                builder: (_, playSnap) => AnimatedEqualizer(
                                                  isPlaying: playSnap.data ?? false,
                                                  barCount: 3,
                                                  barWidth: 3.0,
                                                  maxHeight: 18.0,
                                                  minHeight: 4.0,
                                                  spacing: 2.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        track.displayTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isCurrent ? AppTheme.accent : AppTheme.textPrimary,
                                          fontSize: 13,
                                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (track.isVideo) ...[
                                      const SizedBox(width: 6),
                                      const VideoBadge(compact: true),
                                    ],
                                  ],
                                ),
                                subtitle: Text(
                                  track.displayArtist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isCurrent ? AppTheme.accent.withOpacity(0.8) : AppTheme.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: Icon(Icons.more_vert_rounded,
                                      color: isCurrent ? AppTheme.accent : AppTheme.textSecondary, size: 20),
                                  onPressed: () => _showTrackOptionsModal(
                                    context,
                                    track,
                                    playlistSource: playlist,
                                    trackIndexInPlaylist: idx,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        );
                      },
                      childCount: playlistTracks.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
  }

  Widget _buildPlaylistHeaderMetadata(Playlist playlist, List<Track> playlistTracks, bool isLiked, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PLAYLIST',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary,
                letterSpacing: 1.5)),
        const SizedBox(height: 6),
        Text(
          playlist.name,
          style: TextStyle(
              fontSize: isMobile ? 26 : 36,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary),
        ),
        if (playlist.description != null && playlist.description!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            playlist.description!,
            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          formatTidalDuration(playlistTracks),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.textHint,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 16),

        // ── Action buttons row (Wrap prevents overflow on narrow windows) ──
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.bgDeep,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
              onPressed: () => _shufflePlayTracks(
                playlistTracks,
                contextName: playlist.playlistId == '__liked__'
                    ? 'Canciones que te gustan'
                    : 'Playlist: ${playlist.name}',
              ),
              icon: const Icon(Icons.shuffle_rounded, size: 16, color: AppTheme.bgDeep),
              label: const Text(
                'Reproducción Aleatoria',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            if (!isLiked)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent, width: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () => _deletePlaylist(playlist),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Eliminar',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppTheme.textSecondary),
              tooltip: 'Más opciones',
              color: AppTheme.bgSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.divider),
              ),
              onSelected: (value) {
                if (value == 'add_to_playlist') {
                  _showAddTracksToPlaylistModal(context, playlistTracks, collectionTitle: playlist.name);
                } else if (value == 'download_offline') {
                  _downloadTracksOffline(playlistTracks, title: playlist.name, playlist: playlist);
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem<String>(
                  value: 'add_to_playlist',
                  child: Row(
                    children: [
                      Icon(Icons.playlist_add_rounded, size: 18, color: AppTheme.textPrimary),
                      SizedBox(width: 12),
                      Text('Añadir a playlist', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'download_offline',
                  child: Row(
                    children: [
                      Icon(Icons.download_for_offline_rounded, size: 18, color: AppTheme.accent),
                      SizedBox(width: 12),
                      Text('Descargar sin conexión', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  void _downloadTracksOffline(List<Track> tracks, {required String title, Playlist? playlist}) {
    final remoteTracks = tracks.where((t) => AudioPlayerService.isRemoteUri(t.filePath)).toList();
    if (remoteTracks.isEmpty) {
      AppToast.showText(
        context,
        'Todas las pistas ya están disponibles localmente',
        icon: Icons.check_circle_outline_rounded,
      );
      return;
    }
    if (playlist != null) {
      SyncDownloadManager.instance.enqueuePlaylist(playlist, remoteTracks);
    } else {
      SyncDownloadManager.instance.enqueueTracks(remoteTracks);
    }
    AppToast.showText(
      context,
      'Descargando ${remoteTracks.length} pista(s) de "$title"',
      icon: Icons.downloading_rounded,
    );
    SyncProgressPanel.showModal(context);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SHARED SUBWIDGETS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: TextField(
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Buscar en tu biblioteca...',
          hintStyle: const TextStyle(color: AppTheme.textHint, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textSecondary, size: 18),
          filled: true,
          fillColor: AppTheme.bgSurface,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.accent),
          ),
        ),
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
          });
        },
      ),
    );
  }

  // ── Collection-level context menus ──────────────────────────────────────

  /// Bottom sheet with quick actions for an Album.
  void _showAlbumContextMenu(
    BuildContext context,
    String albumName,
    List<Track> albumTracks,
    Track representativeTrack,
  ) {
    if (albumTracks.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final coverPath = representativeTrack.customMetadata.customCoverPath;
        final hasArt = coverPath != null &&
            coverPath.isNotEmpty &&
            File(coverPath).existsSync();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: hasArt
                            ? Image.file(File(coverPath), fit: BoxFit.cover, cacheWidth: 104)
                            : const ColoredBox(
                                color: AppTheme.bgHover,
                                child: Center(
                                  child: Icon(Icons.album_rounded,
                                      color: AppTheme.textHint, size: 28),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(albumName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(
                            '${albumTracks.length} ${albumTracks.length == 1 ? 'canción' : 'canciones'}',
                            style: const TextStyle(
                                color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: AppTheme.divider, height: 1),
                const SizedBox(height: 8),
                // Actions
                _ContextMenuTile(
                  icon: Icons.play_arrow_rounded,
                  label: 'Reproducir álbum',
                  onTap: () {
                    Navigator.pop(ctx);
                    _playTracks(albumTracks, 0,
                        contextName: 'Álbum: $albumName');
                  },
                ),
                _ContextMenuTile(
                  icon: Icons.shuffle_rounded,
                  label: 'Reproducir en aleatorio',
                  onTap: () {
                    Navigator.pop(ctx);
                    _shufflePlayTracks(albumTracks,
                        contextName: 'Álbum: $albumName');
                  },
                ),
                _ContextMenuTile(
                  icon: Icons.add_to_queue_rounded,
                  label: 'Agregar todas a la cola',
                  onTap: () {
                    Navigator.pop(ctx);
                    for (final t in albumTracks) {
                      OrpheusAudioHandler.instance.addToQueue(t);
                    }
                    AppToast.showText(context,
                        '${albumTracks.length} canciones añadidas a la cola');
                  },
                ),
                _ContextMenuTile(
                  icon: Icons.playlist_add_rounded,
                  label: 'Añadir todas a playlist',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showAddTracksToPlaylistModal(context, albumTracks,
                        collectionTitle: albumName);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Bottom sheet with quick actions for an Artist.
  void _showArtistContextMenu(
    BuildContext context,
    String artistName,
    List<Track> artistTracks,
  ) {
    if (artistTracks.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: AppTheme.bgHover,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_rounded,
                        color: AppTheme.accent, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(artistName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(
                          '${artistTracks.length} ${artistTracks.length == 1 ? 'canción' : 'canciones'}',
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppTheme.divider, height: 1),
              const SizedBox(height: 8),
              // Actions
              _ContextMenuTile(
                icon: Icons.play_arrow_rounded,
                label: 'Reproducir artista',
                onTap: () {
                  Navigator.pop(ctx);
                  _playTracks(artistTracks, 0,
                      contextName: 'Artista: $artistName');
                },
              ),
              _ContextMenuTile(
                icon: Icons.shuffle_rounded,
                label: 'Reproducir en aleatorio',
                onTap: () {
                  Navigator.pop(ctx);
                  _shufflePlayTracks(artistTracks,
                      contextName: 'Artista: $artistName');
                },
              ),
              _ContextMenuTile(
                icon: Icons.add_to_queue_rounded,
                label: 'Agregar todas a la cola',
                onTap: () {
                  Navigator.pop(ctx);
                  for (final t in artistTracks) {
                    OrpheusAudioHandler.instance.addToQueue(t);
                  }
                  AppToast.showText(context,
                      '${artistTracks.length} canciones añadidas a la cola');
                },
              ),
              _ContextMenuTile(
                icon: Icons.playlist_add_rounded,
                label: 'Añadir todas a playlist',
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddTracksToPlaylistModal(context, artistTracks,
                      collectionTitle: artistName);
                },
              ),
              _ContextMenuTile(
                icon: Icons.radio_rounded,
                label: 'Iniciar radio del artista',
                onTap: () {
                  Navigator.pop(ctx);
                  RadioLaunchSheet.show(context, artistTracks.first);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom sheet with quick actions for a Playlist.
  void _showPlaylistContextMenu(
    BuildContext context,
    Playlist playlist,
    List<Track> playlistTracks,
  ) {
    final isLiked = playlist.playlistId == '__liked__';
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: PlaylistCover(
                        playlist: playlist,
                        allTracks: _allTracks,
                        tracksById: _tracksById,
                        size: 52,
                        coverVersion: _coverVersions[playlist.playlistId],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(playlist.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(
                          '${playlistTracks.length} ${playlistTracks.length == 1 ? 'canción' : 'canciones'}',
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppTheme.divider, height: 1),
              const SizedBox(height: 8),
              // Actions
              _ContextMenuTile(
                icon: Icons.play_arrow_rounded,
                label: 'Reproducir playlist',
                onTap: () {
                  Navigator.pop(ctx);
                  if (playlistTracks.isNotEmpty) {
                    _playTracks(
                      playlistTracks,
                      0,
                      contextName: isLiked
                          ? 'Canciones que te gustan'
                          : 'Playlist: ${playlist.name}',
                    );
                  }
                },
              ),
              _ContextMenuTile(
                icon: Icons.shuffle_rounded,
                label: 'Reproducir en aleatorio',
                onTap: () {
                  Navigator.pop(ctx);
                  if (playlistTracks.isNotEmpty) {
                    _shufflePlayTracks(
                      playlistTracks,
                      contextName: isLiked
                          ? 'Canciones que te gustan'
                          : 'Playlist: ${playlist.name}',
                    );
                  }
                },
              ),
              _ContextMenuTile(
                icon: Icons.add_to_queue_rounded,
                label: 'Agregar todas a la cola',
                onTap: () {
                  Navigator.pop(ctx);
                  for (final t in playlistTracks) {
                    OrpheusAudioHandler.instance.addToQueue(t);
                  }
                  AppToast.showText(context,
                      '${playlistTracks.length} canciones añadidas a la cola');
                },
              ),
              if (!isLiked) ...[
                _ContextMenuTile(
                  icon: Icons.edit_rounded,
                  label: 'Editar playlist',
                  onTap: () {
                    Navigator.pop(ctx);
                    _openPlaylist(playlist, _currentBottomPad);
                  },
                ),
                _ContextMenuTile(
                  icon: Icons.delete_outline_rounded,
                  label: 'Eliminar playlist',
                  color: Colors.redAccent,
                  onTap: () {
                    Navigator.pop(ctx);
                    _deletePlaylist(playlist);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showTrackOptionsModal(
    BuildContext context,
    Track track, {
    Playlist? playlistSource,
    int? trackIndexInPlaylist,
  }) {
    TrackOptionsSheet.show(
      context,
      track: track,
      playlistSource: playlistSource,
      trackIndexInPlaylist: trackIndexInPlaylist,
      onRemoveFromPlaylist: (playlistSource != null &&
              !playlistSource.isDefault &&
              trackIndexInPlaylist != null)
          ? () =>
              _removeTrackFromPlaylistAt(playlistSource, trackIndexInPlaylist)
          : null,
      onOpenAlbum: _openAlbum,
      onOpenArtist: _openArtist,
      onRefreshData: _refreshData,
    );
  }

  void _showAddTracksToPlaylistModal(
    BuildContext context,
    List<Track> tracks, {
    String? collectionTitle,
  }) {
    if (tracks.isEmpty) return;
    AddToPlaylistSheet.show(
      context,
      tracks: tracks,
      collectionTitle: collectionTitle,
      onPlaylistUpdated: _refreshData,
    );
  }

  /// Mobile-optimised songs list: clean ListTile rows with rounded cover art,
  /// title, artist, and an IconButton opening the BottomSheet menu.
  Widget _buildMobileSongsList(List<Track> tracks, {double bottomPad = 0}) {
    return ListView.separated(
      padding: EdgeInsets.only(bottom: bottomPad > 0 ? bottomPad : 16),
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const Divider(
        color: AppTheme.divider,
        height: 1,
        indent: 68,
      ),
      itemBuilder: (context, idx) {
        final track = tracks[idx];
        final coverPath = track.customMetadata.customCoverPath;
        final hasArt = coverPath != null &&
            coverPath.isNotEmpty &&
            File(coverPath).existsSync();

        return StreamBuilder<Track?>(
          stream: OrpheusAudioHandler.instance.currentTrackStream,
          initialData: OrpheusAudioHandler.instance.currentTrack,
          builder: (context, snap) {
            final currentTrack = snap.data;
            final isPlayingThisTrack = currentTrack != null && currentTrack.trackId == track.trackId;
            final currentCtxIdx = AudioPlayerService.instance.currentOriginalIndex;
            final activeCtxName = AudioPlayerService.instance.contextName;
            final isSameContext = activeCtxName == 'Biblioteca';
            final isCurrent = isPlayingThisTrack && (isSameContext ? currentCtxIdx == idx : true);

            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: isCurrent ? AppTheme.accent.withOpacity(0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: isCurrent
                    ? Border.all(color: AppTheme.accent.withOpacity(0.40), width: 1.2)
                    : null,
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: AppTheme.accent.withOpacity(0.18),
                          blurRadius: 12,
                          spreadRadius: 0.5,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                type: MaterialType.transparency,
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  onTap: () => _playTracks(tracks, idx),
                  onLongPress: () => _showTrackOptionsModal(context, track),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        hasArt
                            ? Image.file(File(coverPath), fit: BoxFit.cover, cacheWidth: 92)
                            : const ColoredBox(
                                color: AppTheme.bgHover,
                                child: Icon(Icons.music_note_rounded,
                                    color: AppTheme.textHint, size: 20),
                              ),
                        if (isCurrent)
                          Container(
                            color: Colors.black54,
                            child: Center(
                              child: StreamBuilder<bool>(
                                stream: OrpheusAudioHandler.instance.isPlayingStream,
                                initialData: OrpheusAudioHandler.instance.isPlaying,
                                builder: (_, playSnap) => AnimatedEqualizer(
                                  isPlaying: playSnap.data ?? false,
                                  barCount: 3,
                                  barWidth: 3.0,
                                  maxHeight: 18.0,
                                  minHeight: 4.0,
                                  spacing: 2.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        track.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? AppTheme.accent : AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (track.isVideo) ...[
                      const SizedBox(width: 6),
                      const VideoBadge(compact: true),
                    ],
                  ],
                ),
                subtitle: Text(
                  track.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCurrent ? AppTheme.accent.withOpacity(0.8) : AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.more_vert_rounded,
                      color: isCurrent ? AppTheme.accent : AppTheme.textSecondary, size: 20),
                  onPressed: () => _showTrackOptionsModal(context, track),
                ),
              ),
            ),
          );
          },
        );
      },
    );
  }


  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_note_rounded, color: AppTheme.textHint.withAlpha(80), size: 48),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackTable(
    List<Track> tracks, {
    Playlist? playlistSource,
    String? contextName,
    bool isAlbumDetail = false,
    bool isArtistDetail = false,
  }) {
    // Column visibility: hide redundant columns in context-specific views.
    // In album detail: ÁLBUM is redundant — hide it and expand TÍTULO/ARTISTA.
    // In artist detail: ARTISTA is redundant — hide it and expand TÍTULO/ÁLBUM.
    // In general view: show TÍTULO(5), ARTISTA(3), ÁLBUM(2) only on wide screens.
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool showAlbumCol = !isAlbumDetail && screenWidth >= 600;
    final bool showArtistCol = !isArtistDetail;

    // Flex values adapt to which columns are visible.
    final int titleFlex = (isAlbumDetail || isArtistDetail) ? 6 : 5;
    final int artistFlex = isAlbumDetail ? 3 : 2;
    final int albumFlex = isArtistDetail ? 3 : 2;

    // Fixed header — always visible above the scrollable list.
    final header = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.divider, width: 1)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 40, child: Text('#', style: TextStyle(color: AppTheme.textHint, fontSize: 11, fontWeight: FontWeight.bold))),
            Expanded(flex: titleFlex, child: const Text('TÍTULO', style: TextStyle(color: AppTheme.textHint, fontSize: 11, fontWeight: FontWeight.bold))),
            if (showArtistCol)
              Expanded(flex: artistFlex, child: const Text('ARTISTA', style: TextStyle(color: AppTheme.textHint, fontSize: 11, fontWeight: FontWeight.bold))),
            if (showAlbumCol)
              Expanded(flex: albumFlex, child: const Text('ÁLBUM', style: TextStyle(color: AppTheme.textHint, fontSize: 11, fontWeight: FontWeight.bold))),
            const SizedBox(width: 70, child: Align(alignment: Alignment.centerRight, child: Text('DURACIÓN', style: TextStyle(color: AppTheme.textHint, fontSize: 11, fontWeight: FontWeight.bold)))),
            const SizedBox(width: 110),
          ],
        ),
      ),
    );

    Widget buildRow(int index) {
      final track = tracks[index];
      final durationStr = _formatDuration(track.duration);
      final isLiked = _likedTrackIds.contains(track.trackId);
      return _TrackRow(
        key: ValueKey('row_${index}_${track.id}'),
        track: track,
        index: index + 1, // 1-based display number
        itemIndex: index,
        contextName: contextName,
        playlistIndex: index,
        durationStr: durationStr,
        isLiked: isLiked,
        isAlbumDetail: isAlbumDetail,
        isArtistDetail: isArtistDetail,
        customPlaylists: _playlists.where((p) => p.playlistId != '__liked__').toList(),
        playlistSource: playlistSource,
        onPlay: () => _playTracks(tracks, index, contextName: contextName),
        onPlayNext: () => OrpheusAudioHandler.instance.playNext(track),
        onAddToQueue: () => OrpheusAudioHandler.instance.addToQueue(track),
        onToggleLike: () => _toggleLike(track),
        onCreatePlaylistWithTrack: () => _createAndAddTrackToPlaylist(track),
        onAddToPlaylist: (p) => _addTrackToPlaylist(track, p),
        onRemoveFromPlaylist: (p) => _removeTrackFromPlaylist(track, p),
        onRemoveFromPlaylistAt: playlistSource != null
            ? () => _removeTrackFromPlaylistAt(playlistSource, index)
            : null,
        onDelete: () => _deleteTrack(track),
        onEditMetadata: () => _editTrackMetadata(track),
        onStartRadio: () => RadioLaunchSheet.show(context, track),
        onLongPress: () => _showTrackOptionsModal(
          context,
          track,
          playlistSource: playlistSource,
          trackIndexInPlaylist: index,
        ),
      );
    }

    // When viewing a playlist, allow drag-to-reorder.
    if (playlistSource != null) {
      return Column(
        children: [
          header,
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: tracks.length,
              onReorder: (oldIndex, newIndex) =>
                  _onReorderTracks(playlistSource, oldIndex, newIndex),
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                child: child,
              ),
              itemBuilder: (context, index) => ReorderableDragStartListener(
                key: ValueKey('drag_handle_${tracks[index].id}_$index'),
                index: index,
                child: buildRow(index),
              ),
            ),
          ),
        ],
      );
    }

    // Default: non-reorderable list (Tracks tab, Albums, Artists).
    return Column(
      children: [
        header,
        Expanded(
          child: ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (context, index) => buildRow(index),
          ),
        ),
      ],
    );
  }

  /// Handles a drag-reorder gesture on the playlist track list.
  void _onReorderTracks(Playlist playlist, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final newOrder = List<int>.from(playlist.trackIds);
    final moved = newOrder.removeAt(oldIndex);
    newOrder.insert(newIndex, moved);
    LocalDatabase.instance.reorderPlaylistTracks(
      playlist: playlist,
      newOrder: newOrder,
    );
    _refreshData();
  }

  String _formatDuration(int sec) {
    if (sec <= 0) return '—';
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Calculates and formats aggregate track count and duration in Tidal style.
/// e.g. "1 canción • 3 min 45 s", "14 canciones • 52 min", "32 canciones • 2 h 15 min".
String formatTidalDuration(List<Track> tracks) {
  if (tracks.isEmpty) return '0 canciones';
  final countLabel = '${tracks.length} ${tracks.length == 1 ? 'canción' : 'canciones'}';
  final totalSeconds = tracks.fold<int>(
    0,
    (acc, t) => acc + (t.duration > 0 ? t.duration : 0),
  );
  if (totalSeconds <= 0) return countLabel;

  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  String timeLabel;
  if (hours > 0) {
    timeLabel = minutes > 0 ? '$hours h $minutes min' : '$hours h';
  } else if (minutes > 0) {
    timeLabel = '$minutes min';
  } else {
    timeLabel = '$seconds s';
  }

  return '$countLabel • $timeLabel';
}

class _TrackRow extends StatefulWidget {
  const _TrackRow({
    super.key,
    required this.track,
    required this.index,
    required this.itemIndex,
    this.contextName,
    required this.playlistIndex,
    required this.durationStr,
    required this.isLiked,
    this.isAlbumDetail = false,
    this.isArtistDetail = false,
    required this.customPlaylists,
    this.playlistSource,
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onToggleLike,
    required this.onCreatePlaylistWithTrack,
    required this.onAddToPlaylist,
    required this.onRemoveFromPlaylist,
    this.onRemoveFromPlaylistAt,
    required this.onDelete,
    required this.onEditMetadata,
    required this.onStartRadio,
    this.onLongPress,
  });

  final Track track;
  final int index;
  final int itemIndex;
  final String? contextName;
  final int playlistIndex;
  final String durationStr;
  final bool isLiked;
  final bool isAlbumDetail;
  final bool isArtistDetail;
  final List<Playlist> customPlaylists;
  final Playlist? playlistSource;
  final VoidCallback onPlay;
  final VoidCallback onPlayNext;
  final VoidCallback onAddToQueue;
  final VoidCallback onToggleLike;
  final VoidCallback onCreatePlaylistWithTrack;
  final ValueChanged<Playlist> onAddToPlaylist;
  final ValueChanged<Playlist> onRemoveFromPlaylist;
  final VoidCallback? onRemoveFromPlaylistAt;
  final VoidCallback onDelete;
  final VoidCallback onEditMetadata;
  final VoidCallback onStartRadio;
  final VoidCallback? onLongPress;

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Track?>(
      stream: OrpheusAudioHandler.instance.currentTrackStream,
      initialData: OrpheusAudioHandler.instance.currentTrack,
      builder: (context, snap) {
        final currentTrack = snap.data;
        final isPlayingThisTrack = currentTrack != null && currentTrack.trackId == widget.track.trackId;
        final currentCtxIdx = AudioPlayerService.instance.currentOriginalIndex;
        final activeCtxName = AudioPlayerService.instance.contextName;

        final isSameContext = widget.contextName != null
            ? (activeCtxName == widget.contextName ||
                (widget.playlistSource != null &&
                    (activeCtxName == widget.playlistSource!.name ||
                        activeCtxName == 'Playlist: ${widget.playlistSource!.name}' ||
                        (activeCtxName == 'Canciones que te gustan' && widget.playlistSource!.playlistId == '__liked__'))))
            : true;

        final isCurrent = isPlayingThisTrack && isSameContext && (currentCtxIdx == widget.itemIndex);

        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onDoubleTap: widget.onPlay,
            onLongPress: widget.onLongPress,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: isCurrent
                    ? AppTheme.accent.withOpacity(0.12)
                    : (_hovered ? AppTheme.bgHover : Colors.transparent),
                borderRadius: BorderRadius.circular(8),
                border: isCurrent
                    ? Border.all(color: AppTheme.accent.withOpacity(0.40), width: 1.2)
                    : null,
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: AppTheme.accent.withOpacity(0.16),
                          blurRadius: 10,
                          spreadRadius: 0.5,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  // Index / Play / Equalizer
                  SizedBox(
                    width: 40,
                    child: _hovered
                        ? GestureDetector(
                            onTap: widget.onPlay,
                            child: const Icon(Icons.play_arrow_rounded, color: AppTheme.accent, size: 18),
                          )
                        : (isCurrent
                            ? StreamBuilder<bool>(
                                stream: OrpheusAudioHandler.instance.isPlayingStream,
                                initialData: OrpheusAudioHandler.instance.isPlaying,
                                builder: (_, playSnap) => Center(
                                  child: AnimatedEqualizer(
                                    isPlaying: playSnap.data ?? false,
                                    barCount: 3,
                                    barWidth: 2.5,
                                    maxHeight: 14.0,
                                    minHeight: 3.0,
                                  ),
                                ),
                              )
                            : Text(
                                widget.index.toString(),
                                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                              )),
                  ),
                  // Title column: flex adapts to which other columns are visible
                  Expanded(
                    flex: (widget.isAlbumDetail || widget.isArtistDetail) ? 6 : 5,
                    child: Row(
                      children: [
                        if (widget.track.customMetadata.customCoverPath != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: Image.file(
                              File(widget.track.customMetadata.customCoverPath!),
                              width: 24,
                              height: 24,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            widget.track.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent ? AppTheme.accent : AppTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (widget.track.isVideo) ...[
                          const SizedBox(width: 8),
                          const VideoBadge(),
                        ],
                    if (widget.track.downloadSource != null) ...[
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 60),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.divider,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            widget.track.downloadSource!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 8, color: AppTheme.accent),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Artist — hidden in artist-detail view (redundant)
              if (!widget.isArtistDetail)
                Expanded(
                  flex: widget.isAlbumDetail ? 3 : 2,
                  child: Text(
                    widget.track.displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ),
              // Album — hidden in album-detail view (redundant); always shown in artist-detail
              if (!widget.isAlbumDetail && (widget.isArtistDetail || MediaQuery.sizeOf(context).width >= 600))
                Expanded(
                  flex: widget.isArtistDetail ? 3 : 2,
                  child: Text(
                    widget.track.displayAlbum,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ),
              // Duration
              SizedBox(
                width: 70,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    widget.durationStr,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ),
              ),
              // Actions
              SizedBox(
                width: 110,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Quick remove from playlist button (shows on hover when in a custom playlist)
                    if (_hovered && widget.playlistSource != null && !widget.playlistSource!.isDefault) ...[
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(
                          Icons.remove_circle_outline_rounded,
                          size: 16,
                          color: Colors.redAccent,
                        ),
                        onPressed: () => widget.onRemoveFromPlaylist(widget.playlistSource!),
                        tooltip: 'Quitar de la playlist',
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Like button (shows on hover or if liked)
                    ValueListenableBuilder<Set<String>>(
                      valueListenable: LocalDatabase.instance.likedTrackIdsNotifier,
                      builder: (context, likedIds, _) {
                        final isCurrentlyLiked = likedIds.contains(widget.track.trackId);
                        if (_hovered || isCurrentlyLiked) {
                          return IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              isCurrentlyLiked ? Icons.favorite : Icons.favorite_border,
                              size: 16,
                              color: isCurrentlyLiked ? Colors.redAccent : AppTheme.textSecondary,
                            ),
                            onPressed: widget.onToggleLike,
                          );
                        } else {
                          return const SizedBox(width: 24);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    // Menu actions
                    PopupMenuButton<dynamic>(
                      icon: const Icon(Icons.more_vert_rounded, size: 16, color: AppTheme.textSecondary),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: AppTheme.bgSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: AppTheme.divider),
                      ),
                      onSelected: (value) {
                        if (value == 'play_next') {
                          widget.onPlayNext();
                        } else if (value == 'add_to_queue') {
                          widget.onAddToQueue();
                        } else if (value == 'start_radio') {
                          widget.onStartRadio();
                        } else if (value == 'remove_from_current_playlist') {
                          if (widget.onRemoveFromPlaylistAt != null) {
                            widget.onRemoveFromPlaylistAt!();
                          } else if (widget.playlistSource != null) {
                            widget.onRemoveFromPlaylist(widget.playlistSource!);
                          }
                        } else if (value == 'new_playlist') {
                          widget.onCreatePlaylistWithTrack();
                        } else if (value == 'edit') {
                          widget.onEditMetadata();
                        } else if (value == 'delete') {
                          widget.onDelete();
                        } else if (value is Playlist) {
                          if (widget.playlistSource != null &&
                              widget.playlistSource!.playlistId == value.playlistId) {
                            if (widget.onRemoveFromPlaylistAt != null) {
                              widget.onRemoveFromPlaylistAt!();
                            } else {
                              widget.onRemoveFromPlaylist(value);
                            }
                          } else {
                            widget.onAddToPlaylist(value);
                          }
                        }
                      },
                      itemBuilder: (context) {
                        final items = <PopupMenuEntry<dynamic>>[];

                        items.add(
                          const PopupMenuItem<dynamic>(
                            value: 'play_next',
                            child: Row(
                              children: [
                                Icon(Icons.playlist_play_rounded, size: 14, color: AppTheme.textPrimary),
                                SizedBox(width: 8),
                                Text('Reproducir siguiente', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                              ],
                            ),
                          ),
                        );
                        items.add(
                          const PopupMenuItem<dynamic>(
                            value: 'add_to_queue',
                            child: Row(
                              children: [
                                Icon(Icons.queue_music_rounded, size: 14, color: AppTheme.textPrimary),
                                SizedBox(width: 8),
                                Text('Añadir a cola', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                              ],
                            ),
                          ),
                        );
                        items.add(
                          const PopupMenuItem<dynamic>(
                            value: 'start_radio',
                            child: Row(
                              children: [
                                Icon(Icons.radio_rounded, size: 14, color: AppTheme.accent),
                                SizedBox(width: 8),
                                Text('Iniciar Radio', style: TextStyle(color: AppTheme.accent, fontSize: 12)),
                              ],
                            ),
                          ),
                        );
                        items.add(const PopupMenuDivider(height: 1));

                        // Show option to remove if looking at a custom playlist detail view
                        if (widget.playlistSource != null && !widget.playlistSource!.isDefault) {
                          items.add(
                            const PopupMenuItem<dynamic>(
                              value: 'remove_from_current_playlist',
                              child: Row(
                                children: [
                                  Icon(Icons.remove_circle_outline_rounded,
                                      size: 14, color: Colors.redAccent),
                                  SizedBox(width: 8),
                                  Text('Quitar de esta playlist',
                                      style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                                ],
                              ),
                            ),
                          );
                          items.add(const PopupMenuDivider(height: 1));
                        }

                        items.add(
                          const PopupMenuItem<dynamic>(
                            enabled: false,
                            child: Text(
                              'AGREGAR A PLAYLIST',
                              style: TextStyle(
                                  color: AppTheme.textHint,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0),
                            ),
                          ),
                        );

                        items.add(
                          const PopupMenuItem<dynamic>(
                            value: 'new_playlist',
                            child: Row(
                              children: [
                                Icon(Icons.add_rounded, size: 14, color: AppTheme.textPrimary),
                                SizedBox(width: 8),
                                Text('Nueva playlist...', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                              ],
                            ),
                          ),
                        );

                        if (widget.customPlaylists.isNotEmpty) {
                          for (final p in widget.customPlaylists) {
                            items.add(
                              PopupMenuItem<dynamic>(
                                value: p,
                                child: Row(
                                  children: [
                                    const Icon(Icons.playlist_add_rounded,
                                        size: 14, color: AppTheme.textSecondary),
                                    const SizedBox(width: 8),
                                    Text(p.name,
                                        style: const TextStyle(
                                            color: AppTheme.textPrimary, fontSize: 12)),
                                  ],
                                ),
                              ),
                            );
                          }
                        }

                        // Edit metadata option
                        items.add(const PopupMenuDivider(height: 1));
                        items.add(
                          const PopupMenuItem<dynamic>(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_rounded,
                                    size: 14, color: AppTheme.textSecondary),
                                SizedBox(width: 8),
                                Text('Editar Información',
                                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                              ],
                            ),
                          ),
                        );

                        // Always append option to delete track from library
                        items.add(const PopupMenuDivider(height: 1));
                        items.add(
                          const PopupMenuItem<dynamic>(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline_rounded,
                                    size: 14, color: Colors.redAccent),
                                SizedBox(width: 8),
                                Text('Eliminar de biblioteca',
                                    style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                              ],
                            ),
                          ),
                        );

                        return items;
                      },
                    ),
                  ],
                ),
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

// ─────────────────────────────────────────────────────────────────────────────
// TIDAL-STYLE BLURRED IMAGE BACKGROUND
// ─────────────────────────────────────────────────────────────────────────────

/// Fills its parent with a massively blurred version of [imagePath], overlaid
/// with a dark vignette gradient to ensure foreground text legibility.
/// Reusable tile row used inside collection-level context menus.
class _ContextMenuTile extends StatelessWidget {
  const _ContextMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppTheme.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: effectiveColor),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: effectiveColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlurredImageBackground extends StatelessWidget {
  const _BlurredImageBackground({required this.imagePath});
  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Over-scaled source image
        Positioned.fill(
          child: Transform.scale(
            scale: 1.15, // slight scale-up so blur edges stay outside bounds
            child: Image.file(
              File(imagePath),
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        ),
        // 2. Gaussian blur filter
        Positioned.fill(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: const SizedBox.expand(),
          ),
        ),
        // 3. Dark overlay gradient — top 40% subtle tint, fades to near-black
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x88000000), // translucent top
                  Color(0xCC141414), // mid
                  Color(0xFF141414), // solid bottom
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INTERACTIVE PLAYLIST COVER PICKER
// ─────────────────────────────────────────────────────────────────────────────

/// Shows the [PlaylistCover] with a camera-overlay button on hover so the user
/// can select or clear a custom cover image.
///
/// - If [onClearCover] is non-null (i.e. a custom cover exists), hovering shows
///   a popup menu with "Cambiar imagen" and "Eliminar imagen".
/// - Otherwise, tapping directly calls [onPickCover].
class _PlaylistCoverPicker extends StatefulWidget {
  const _PlaylistCoverPicker({
    required this.playlist,
    required this.allTracks,
    this.tracksById,
    this.onPickCover,
    this.onClearCover,
    this.coverVersion,
    this.size = 180,
    this.borderRadius,
  });

  final Playlist playlist;
  final List<Track> allTracks;
  final Map<int, Track>? tracksById;
  final VoidCallback? onPickCover;
  final VoidCallback? onClearCover;
  final int? coverVersion;
  final double size;
  final BorderRadius? borderRadius;

  @override
  State<_PlaylistCoverPicker> createState() => _PlaylistCoverPickerState();
}

class _PlaylistCoverPickerState extends State<_PlaylistCoverPicker> {
  bool _hovered = false;

  bool get _hasCustomCover => widget.onClearCover != null;
  bool get _canEdit => widget.onPickCover != null;

  /// Shows the two-option popup menu anchored to the cover widget.
  void _showCoverMenu(BuildContext context) async {
    final RenderBox box = context.findRenderObject()! as RenderBox;
    final Offset topLeft = box.localToGlobal(Offset.zero);
    final RelativeRect position = RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + box.size.height,
      topLeft.dx + box.size.width,
      0,
    );
    final choice = await showMenu<String>(
      context: context,
      position: position,
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppTheme.divider),
      ),
      items: [
        const PopupMenuItem(
          value: 'change',
          child: Row(
            children: [
              Icon(Icons.photo_rounded, size: 16, color: AppTheme.textSecondary),
              SizedBox(width: 10),
              Text('Cambiar imagen', style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'clear',
          child: Row(
            children: [
              Icon(Icons.hide_image_outlined, size: 16, color: Colors.redAccent),
              SizedBox(width: 10),
              Text('Eliminar imagen', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
    if (choice == 'change') widget.onPickCover?.call();
    if (choice == 'clear') widget.onClearCover?.call();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(8);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: _canEdit ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: _canEdit
            ? (_hasCustomCover
                ? () => _showCoverMenu(context)
                : widget.onPickCover)
            : null,
        child: ClipRRect(
          borderRadius: radius,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PlaylistCover(
                  playlist: widget.playlist,
                  allTracks: widget.allTracks,
                  tracksById: widget.tracksById,
                  size: widget.size,
                  coverVersion: widget.coverVersion,
                ),
                if (_hovered && _canEdit)
                  AnimatedOpacity(
                    opacity: _hovered ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      color: Colors.black54,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.camera_alt_rounded,
                                color: Colors.white, size: 36),
                            const SizedBox(height: 6),
                            Text(
                              _hasCustomCover ? 'Editar portada' : 'Cambiar portada',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Visual Square Crop Dialog ─────────────────────────────────────────────────

/// A dialog that displays [imagePath] inside an [InteractiveViewer], letting
/// the user pan and zoom to frame a 1:1 crop area. A square accent border
/// shows exactly what will be captured.
///
/// Returns a [Uint8List] (PNG) of the cropped area on "Recortar", or `null`
/// on cancel.
class _ImageCropDialog extends StatefulWidget {
  const _ImageCropDialog({required this.imagePath});

  final String imagePath;

  @override
  State<_ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<_ImageCropDialog> {
  final _repaintKey = GlobalKey();
  final _transformController = TransformationController();

  bool _processing = false;

  late final Future<ui.Image> _imageLoaderFuture;

  @override
  void initState() {
    super.initState();
    _imageLoaderFuture = _loadImage();
  }

  Future<ui.Image> _loadImage() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<Uint8List?> _captureCrop() async {
    try {
      final boundary = _repaintKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      // Capture at 2.0x pixel ratio for sharp cover art results
      final uiImage = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    // Preview square: 60% of the shortest screen dimension, clamped [260, 500]
    final previewSize = (screenSize.shortestSide * 0.6).clamp(260.0, 500.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: previewSize + 48,
          maxHeight: screenSize.height * 0.9,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: FutureBuilder<ui.Image>(
            future: _imageLoaderFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done || !snapshot.hasData) {
                return SizedBox(
                  height: previewSize + 100,
                  child: const Center(
                    child: CircularProgressIndicator(color: AppTheme.accent),
                  ),
                );
              }

              final img = snapshot.data!;
              final double imageAspectRatio = img.width / img.height;
              double childWidth = previewSize;
              double childHeight = previewSize;

              if (imageAspectRatio >= 1.0) {
                childWidth = previewSize * imageAspectRatio;
                childHeight = previewSize;
              } else {
                childWidth = previewSize;
                childHeight = previewSize / imageAspectRatio;
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ───────────────────────────────────────────────
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 20, 24, 4),
                    child: Row(
                      children: [
                        Icon(Icons.crop_square_rounded, color: AppTheme.accent, size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Encuadrar portada',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
                    child: Text(
                      'Usa scroll o pellizco para zoom; arrastra para encuadrar.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: AppTheme.textHint,
                      ),
                    ),
                  ),

                  // ── Interactive preview — Flexible so it shrinks on short screens ──
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Stack(
                            children: [
                              RepaintBoundary(
                                key: _repaintKey,
                                child: InteractiveViewer(
                                  transformationController: _transformController,
                                  minScale: 1.0,
                                  maxScale: 5.0,
                                  constrained: false,
                                  boundaryMargin: EdgeInsets.zero,
                                  child: Image.file(
                                    File(widget.imagePath),
                                    width: childWidth,
                                    height: childHeight,
                                    fit: BoxFit.fill,
                                  ),
                                ),
                              ),
                              IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: AppTheme.accent.withOpacity(0.8),
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Actions ───────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white24),
                              foregroundColor: AppTheme.textSecondary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(null),
                            child: const Text('Cancelar', style: TextStyle(fontFamily: 'Inter')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _processing
                                ? null
                                : () async {
                                    setState(() => _processing = true);
                                    final bytes = await _captureCrop();
                                    if (context.mounted) {
                                      Navigator.of(context).pop(bytes);
                                    }
                                  },
                            icon: _processing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.crop_rounded, size: 18),
                            label: Text(
                              _processing ? 'Procesando…' : 'Recortar',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
