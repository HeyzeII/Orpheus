import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/database/local_database.dart';
import '../../core/models/models.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/permission_service.dart';
import '../dialogs/edit_metadata_dialog.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';

enum LibraryTab { tracks, albums, artists, playlists }

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

  // Detail view state
  String? _selectedAlbum;
  String? _selectedArtist;
  Playlist? _selectedPlaylist;
  Color _playlistColor = const Color(0xFF1E1E1E);

  StreamSubscription<void>? _tracksSubscription;

  @override
  void initState() {
    super.initState();
    _refreshData(showSpinner: true);
    _tracksSubscription = LocalDatabase.instance.watchTracks().listen((_) {
      _refreshData(showSpinner: false);
    });
  }

  @override
  void dispose() {
    _tracksSubscription?.cancel();
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

    final likedPlaylist = await db.getPlaylistById('__liked__');
    final likedIds = likedPlaylist?.trackIds
            .map((id) => tracks.firstWhere((t) => t.id == id, orElse: () => Track()).trackId)
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
      _isLoading = false;

      if (_selectedPlaylist != null) {
        final updated = playlists.firstWhere(
          (p) => p.playlistId == _selectedPlaylist!.playlistId,
          orElse: () => _selectedPlaylist!,
        );
        _selectedPlaylist = updated;
        _updatePlaylistColor(updated);
      }
    });
  }

  void _selectPlaylist(Playlist playlist) {
    setState(() {
      _selectedPlaylist = playlist;
    });
    _updatePlaylistColor(playlist);
  }

  Future<void> _updatePlaylistColor(Playlist playlist) async {
    Color extracted = const Color(0xFF1E1E1E);
    final customPath = playlist.customCoverPath;

    if (customPath != null && customPath.isNotEmpty && File(customPath).existsSync()) {
      extracted = await _extractAverageColor(customPath);
    } else {
      final playlistTracks = playlist.trackIds
          .map((id) => _allTracks.firstWhere((t) => t.id == id, orElse: () => Track()))
          .where((t) => t.trackId.isNotEmpty)
          .toList();

      if (playlistTracks.isNotEmpty) {
        final firstTrack = playlistTracks.first;
        final coverPath = firstTrack.customMetadata.customCoverPath;
        if (coverPath != null && coverPath.isNotEmpty && File(coverPath).existsSync()) {
          extracted = await _extractAverageColor(coverPath);
        }
      }
    }

    if (mounted) {
      setState(() {
        _playlistColor = extracted;
      });
    }
  }

  Future<Color> _extractAverageColor(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return const Color(0xFF1E1E1E);
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 10, targetHeight: 10);
      final frameInfo = await codec.getNextFrame();
      final uiImage = frameInfo.image;
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return const Color(0xFF1E1E1E);

      int r = 0, g = 0, b = 0;
      int count = 0;
      for (int i = 0; i < byteData.lengthInBytes; i += 4) {
        r += byteData.getUint8(i);
        g += byteData.getUint8(i + 1);
        b += byteData.getUint8(i + 2);
        count++;
      }
      if (count == 0) return const Color(0xFF1E1E1E);
      return Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
    } catch (e) {
      print('Error extracting color: $e');
      return const Color(0xFF1E1E1E);
    }
  }

  // Playback integration
  Future<void> _playTracks(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty) return;
    await AudioPlayerService.instance.loadPlaylist(tracks, initialIndex: startIndex);
  }

  Future<void> _shufflePlayTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final shuffled = List<Track>.from(tracks)..shuffle();
    await AudioPlayerService.instance.loadPlaylist(shuffled, initialIndex: 0);
  }

  // Favorite toggle
  Future<void> _toggleLike(Track track) async {
    final db = LocalDatabase.instance;
    final likedPlaylist = await db.getPlaylistById('__liked__');
    if (likedPlaylist == null) return;
    if (db.likedTrackIdsNotifier.value.contains(track.trackId)) {
      await db.removeTrackFromPlaylist(playlist: likedPlaylist, trackId: track.trackId);
    } else {
      await db.addTrackToPlaylist(playlist: likedPlaylist, trackId: track.trackId);
    }
  }

  // Add track to custom playlist
  Future<void> _addTrackToPlaylist(Track track, Playlist playlist) async {
    await LocalDatabase.instance.addTrackToPlaylist(
      playlist: playlist,
      trackId: track.trackId,
    );
    if (!mounted) return;
    AppToast.showAddedToPlaylist(
      context,
      track: track,
      playlist: playlist,
    );
    _refreshData();
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

  /// Express playlist creation from the track context menu.
  /// Creates the playlist and immediately adds the given track to it.
  Future<void> _createAndAddTrackToPlaylist(Track track) async {
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
      await LocalDatabase.instance.addTrackToPlaylist(
        playlist: playlist,
        trackId: track.trackId,
      );
      _refreshData();
      if (!mounted) return;
      AppToast.showAddedToPlaylist(
        context,
        track: track,
        playlist: playlist,
      );
    }
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
    if (mounted) _updatePlaylistColor(playlist);
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
    if (mounted) _updatePlaylistColor(playlist);
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
      setState(() {
        _selectedPlaylist = null;
      });
      _refreshData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accent),
      );
    }

    // ── Route detail view if any selected ────────────────────────────────────
    if (_selectedAlbum != null) {
      return _buildAlbumDetails(_selectedAlbum!);
    }
    if (_selectedArtist != null) {
      return _buildArtistDetails(_selectedArtist!);
    }
    if (_selectedPlaylist != null) {
      return _buildPlaylistDetails(_selectedPlaylist!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Tabs Header ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 36, 32, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tu Biblioteca',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _buildTabButton(LibraryTab.tracks, 'Canciones'),
                  _buildTabButton(LibraryTab.albums, 'Álbumes'),
                  _buildTabButton(LibraryTab.artists, 'Artistas'),
                  _buildTabButton(LibraryTab.playlists, 'Playlists'),
                ],
              ),
            ],
          ),
        ),
        const Divider(color: AppTheme.divider, height: 1),

        // ── Active Tab View Content ──────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: switch (_activeTab) {
              LibraryTab.tracks => _buildTracksTab(),
              LibraryTab.albums => _buildAlbumsTab(),
              LibraryTab.artists => _buildArtistsTab(),
              LibraryTab.playlists => _buildPlaylistsTab(),
            },
          ),
        ),
      ],
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
  Widget _buildTracksTab() {
    final filtered = _allTracks.where((t) {
      final query = _searchQuery.toLowerCase();
      return t.displayTitle.toLowerCase().contains(query) ||
          t.displayArtist.toLowerCase().contains(query) ||
          (t.displayAlbum.toLowerCase().contains(query));
    }).toList();

    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState('No se encontraron canciones.')
              : _buildTrackTable(filtered),
        ),
      ],
    );
  }

  // ── Albums Tab ─────────────────────────────────────────────────────────────
  Widget _buildAlbumsTab() {
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

    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(vertical: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.8,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, idx) {
              final albumName = filtered[idx];
              // Find first track of album to use as cover
              final firstTrack = _allTracks.firstWhere(
                (t) => t.displayAlbum == albumName,
                orElse: () => _allTracks.first,
              );
              final coverPath = firstTrack.customMetadata.customCoverPath;

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(() => _selectedAlbum = albumName),
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
                              child: coverPath != null
                                  ? Image.file(File(coverPath), fit: BoxFit.cover)
                                  : Container(
                                      color: AppTheme.bgHover,
                                      child: const Icon(Icons.album_rounded,
                                          color: AppTheme.textHint, size: 48),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          albumName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          firstTrack.displayArtist,
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
          ),
        ),
      ],
    );
  }

  // ── Artists Tab ────────────────────────────────────────────────────────────
  Widget _buildArtistsTab() {
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
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: filtered.length,
            itemBuilder: (context, idx) {
              final artistName = filtered[idx];
              final count = _allTracks.where((t) => t.displayArtist == artistName).length;

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
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.bgHover,
                      child: const Icon(Icons.person_rounded, color: AppTheme.accent),
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
                    onTap: () => setState(() => _selectedArtist = artistName),
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
  Widget _buildPlaylistsTab() {
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
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.78,
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
                                onTap: () => _selectPlaylist(livePlaylist),
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
  Widget _buildAlbumDetails(String albumName) {
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
                onPressed: () => setState(() => _selectedAlbum = null),
              ),
              const SizedBox(width: 8),
              const Text('Volver a Álbumes', style: TextStyle(color: AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 160,
                  height: 160,
                  child: coverPath != null
                      ? Image.file(File(coverPath), fit: BoxFit.cover)
                      : Container(
                          color: AppTheme.bgSurface,
                          child: const Icon(Icons.album_rounded, color: AppTheme.textHint, size: 64),
                        ),
                ),
              ),
              const SizedBox(width: 24),
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
                          fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      albumTracks.isNotEmpty ? albumTracks.first.displayArtist : 'Artista Desconocido',
                      style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${albumTracks.length} canciones',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: _buildTrackTable(albumTracks),
          ),
        ],
      ),
    );
  }

  // ── Artist Details View ────────────────────────────────────────────────────
  Widget _buildArtistDetails(String artistName) {
    final artistTracks = _allTracks.where((t) => t.displayArtist == artistName).toList();

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
                onPressed: () => setState(() => _selectedArtist = null),
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
                      '${artistTracks.length} canciones en tu biblioteca',
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: _buildTrackTable(artistTracks),
          ),
        ],
      ),
    );
  }

  // ── Playlist Details View ──────────────────────────────────────────────────
  Widget _buildPlaylistDetails(Playlist initialPlaylist) {
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
                        onPressed: () => setState(() => _selectedPlaylist = null),
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
                            _PlaylistCoverPicker(
                              playlist: playlist,
                              allTracks: _allTracks,
                              onPickCover: isLiked ? null : () => _pickPlaylistCover(playlist),
                              onClearCover: (isLiked || playlist.customCoverPath == null)
                                  ? null
                                  : () => _clearPlaylistCover(playlist),
                              coverVersion: _coverVersions[playlist.playlistId],
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
                        : _buildTrackTable(playlistTracks, playlistSource: playlist),
                  ),
                ],
              ),
            ),
          ],
        );
      },
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
          '${playlistTracks.length} canciones',
          style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
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
              onPressed: () => _shufflePlayTracks(playlistTracks),
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
          ],
        ),
      ],
    );
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

  Widget _buildTrackTable(List<Track> tracks, {Playlist? playlistSource}) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool isMobile = screenWidth < 600;

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
            const Expanded(flex: 3, child: Text('TÍTULO', style: TextStyle(color: AppTheme.textHint, fontSize: 11, fontWeight: FontWeight.bold))),
            const Expanded(flex: 2, child: Text('ARTISTA', style: TextStyle(color: AppTheme.textHint, fontSize: 11, fontWeight: FontWeight.bold))),
            if (!isMobile)
              const Expanded(flex: 2, child: Text('ÁLBUM', style: TextStyle(color: AppTheme.textHint, fontSize: 11, fontWeight: FontWeight.bold))),
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
        durationStr: durationStr,
        isLiked: isLiked,
        customPlaylists: _playlists.where((p) => p.playlistId != '__liked__').toList(),
        playlistSource: playlistSource,
        onPlay: () => _playTracks(tracks, index),
        onPlayNext: () => AudioPlayerService.instance.playNext(track),
        onAddToQueue: () => AudioPlayerService.instance.addToQueue(track),
        onToggleLike: () => _toggleLike(track),
        onCreatePlaylistWithTrack: () => _createAndAddTrackToPlaylist(track),
        onAddToPlaylist: (p) => _addTrackToPlaylist(track, p),
        onRemoveFromPlaylist: (p) => _removeTrackFromPlaylist(track, p),
        onDelete: () => _deleteTrack(track),
        onEditMetadata: () => _editTrackMetadata(track),
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

class _TrackRow extends StatefulWidget {
  const _TrackRow({
    super.key,
    required this.track,
    required this.index,
    required this.durationStr,
    required this.isLiked,
    required this.customPlaylists,
    this.playlistSource,
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onToggleLike,
    required this.onCreatePlaylistWithTrack,
    required this.onAddToPlaylist,
    required this.onRemoveFromPlaylist,
    required this.onDelete,
    required this.onEditMetadata,
  });

  final Track track;
  final int index;
  final String durationStr;
  final bool isLiked;
  final List<Playlist> customPlaylists;
  final Playlist? playlistSource;
  final VoidCallback onPlay;
  final VoidCallback onPlayNext;
  final VoidCallback onAddToQueue;
  final VoidCallback onToggleLike;
  final VoidCallback onCreatePlaylistWithTrack;
  final ValueChanged<Playlist> onAddToPlaylist;
  final ValueChanged<Playlist> onRemoveFromPlaylist;
  final VoidCallback onDelete;
  final VoidCallback onEditMetadata;

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onDoubleTap: widget.onPlay,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.bgHover : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              // Index / Play button
              SizedBox(
                width: 40,
                child: _hovered
                    ? GestureDetector(
                        onTap: widget.onPlay,
                        child: const Icon(Icons.play_arrow_rounded, color: AppTheme.accent, size: 18),
                      )
                    : Text(
                        widget.index.toString(),
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
              ),
              // Title
              Expanded(
                flex: 3,
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
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (widget.track.downloadSource != null) ...[
                      const SizedBox(width: 4),
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
              // Artist
              Expanded(
                flex: 2,
                child: Text(
                  widget.track.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
              // Album
              if (MediaQuery.sizeOf(context).width >= 600)
                Expanded(
                  flex: 2,
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
                              isCurrentlyLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
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
                        } else if (value == 'new_playlist') {
                          widget.onCreatePlaylistWithTrack();
                        } else if (value == 'edit') {
                          widget.onEditMetadata();
                        } else if (value == 'delete') {
                          widget.onDelete();
                        } else if (value is Playlist) {
                          if (widget.playlistSource != null &&
                              widget.playlistSource!.playlistId == value.playlistId) {
                            widget.onRemoveFromPlaylist(value);
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
                        items.add(const PopupMenuDivider(height: 1));

                        // Show option to remove if looking at a custom playlist detail view
                        if (widget.playlistSource != null && !widget.playlistSource!.isDefault) {
                          items.add(
                            PopupMenuItem<dynamic>(
                              value: widget.playlistSource,
                              child: const Row(
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
  }
}

class PlaylistCover extends StatelessWidget {
  final Playlist playlist;
  final List<Track> allTracks;
  final double size;
  final int? coverVersion;

  const PlaylistCover({
    super.key,
    required this.playlist,
    required this.allTracks,
    required this.size,
    this.coverVersion,
  });

  @override
  Widget build(BuildContext context) {
    final isLiked = playlist.playlistId == '__liked__';

    // 1. Custom playlist cover (priority 1) with cache breaker
    final customPath = playlist.customCoverPath;
    if (customPath != null && customPath.isNotEmpty && File(customPath).existsSync()) {
      final file = File(customPath);
      final lastModified = file.lastModifiedSync().millisecondsSinceEpoch;
      final version = coverVersion ?? lastModified;
      return Image.file(
        file,
        key: ValueKey('${customPath}_$version'),
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }

    // Resolve tracks in order using the database int ID
    final playlistTracks = playlist.trackIds
        .map((id) => allTracks.firstWhere((t) => t.id == id, orElse: () => Track()))
        .where((t) => t.trackId.isNotEmpty)
        .toList();

    if (playlistTracks.isEmpty) {
      // 0 songs: a minimalist dark vinyl/disc placeholder with music icon or heart
      return _buildVinylPlaceholder(isLiked);
    } else if (playlistTracks.length < 4) {
      // 1 to 3 songs: first song cover with cache breaker
      final firstTrack = playlistTracks.first;
      final coverPath = firstTrack.customMetadata.customCoverPath;
      if (coverPath != null && coverPath.isNotEmpty && File(coverPath).existsSync()) {
        final file = File(coverPath);
        final lastModified = file.lastModifiedSync().millisecondsSinceEpoch;
        return Image.file(
          file,
          key: ValueKey('${coverPath}_$lastModified'),
          width: size,
          height: size,
          fit: BoxFit.cover,
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
            if (coverPath != null && coverPath.isNotEmpty && File(coverPath).existsSync()) {
              final file = File(coverPath);
              final lastModified = file.lastModifiedSync().millisecondsSinceEpoch;
              return Image.file(
                file,
                key: ValueKey('collage_${cellIdx}_${track.id}_$lastModified'),
                fit: BoxFit.cover,
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
              isLiked ? Icons.favorite_rounded : Icons.music_note_rounded,
              color: isLiked ? Colors.redAccent.withAlpha(180) : AppTheme.accent.withAlpha(160),
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
          isLiked ? Icons.favorite_rounded : Icons.music_note_rounded,
          color: isLiked ? Colors.redAccent.withAlpha(140) : AppTheme.textHint,
          size: iconSize ?? (size * 0.3),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TIDAL-STYLE BLURRED IMAGE BACKGROUND
// ─────────────────────────────────────────────────────────────────────────────

/// Fills its parent with a massively blurred version of [imagePath], overlaid
/// with a dark vignette gradient to ensure foreground text legibility.
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
    this.onPickCover,
    this.onClearCover,
    this.coverVersion,
  });

  final Playlist playlist;
  final List<Track> allTracks;
  final VoidCallback? onPickCover;
  final VoidCallback? onClearCover;
  final int? coverVersion;

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
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PlaylistCover(
                  playlist: widget.playlist,
                  allTracks: widget.allTracks,
                  size: 180,
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

  static const double _previewSize = 420.0;
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
                                    if (mounted) {
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
