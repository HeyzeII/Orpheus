import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../core/models/models.dart';
import '../../core/services/audio_player_service.dart';
import '../theme/app_theme.dart';

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

  // UI state
  String _searchQuery = '';
  bool _isLoading = true;

  // Detail view state
  String? _selectedAlbum;
  String? _selectedArtist;
  Playlist? _selectedPlaylist;

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
    final likedIds = likedPlaylist?.trackIds.toSet() ?? {};

    if (!mounted) return;
    setState(() {
      _allTracks = tracks;
      _uniqueAlbums = albums;
      _uniqueArtists = artists;
      _playlists = playlists;
      _likedTrackIds = likedIds;
      _isLoading = false;
    });
  }

  // Playback integration
  Future<void> _playTracks(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty) return;
    await AudioPlayerService.instance.loadPlaylist(tracks, initialIndex: startIndex);
  }

  // Favorite toggle
  Future<void> _toggleLike(Track track) async {
    final db = LocalDatabase.instance;
    final likedPlaylist = await db.getPlaylistById('__liked__');
    if (likedPlaylist == null) return;

    if (_likedTrackIds.contains(track.trackId)) {
      await db.removeTrackFromPlaylist(playlist: likedPlaylist, trackId: track.trackId);
      setState(() {
        _likedTrackIds.remove(track.trackId);
      });
    } else {
      await db.addTrackToPlaylist(playlist: likedPlaylist, trackId: track.trackId);
      setState(() {
        _likedTrackIds.add(track.trackId);
      });
    }
  }

  // Add track to custom playlist
  Future<void> _addTrackToPlaylist(Track track, Playlist playlist) async {
    await LocalDatabase.instance.addTrackToPlaylist(
      playlist: playlist,
      trackId: track.trackId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${track.displayTitle}" agregado a "${playlist.name}"'),
        backgroundColor: AppTheme.bgSurface,
        duration: const Duration(seconds: 2),
      ),
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
      playlist.trackIds.remove(track.trackId);
    });
    _refreshData();
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

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
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
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: _playlists.length,
                  itemBuilder: (context, idx) {
                    final playlist = _playlists[idx];
                    final isLiked = playlist.playlistId == '__liked__';

                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedPlaylist = playlist),
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
                                    child: isLiked
                                        ? Container(
                                            color: AppTheme.bgHover,
                                            child: const Icon(Icons.favorite_rounded,
                                                color: Colors.redAccent, size: 48),
                                          )
                                        : Container(
                                            color: AppTheme.bgHover,
                                            child: const Icon(Icons.playlist_play_rounded,
                                                color: AppTheme.accent, size: 48),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                playlist.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${playlist.trackIds.length} canciones',
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
  Widget _buildPlaylistDetails(Playlist playlist) {
    // Resolve tracks in order
    final playlistTracks = playlist.trackIds
        .map((id) => _allTracks.firstWhere((t) => t.trackId == id, orElse: () => Track()))
        .where((t) => t.trackId.isNotEmpty)
        .toList();

    final isLiked = playlist.playlistId == '__liked__';

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 160,
                  height: 160,
                  child: Container(
                    color: AppTheme.bgSurface,
                    child: Icon(
                      isLiked ? Icons.favorite_rounded : Icons.playlist_play_rounded,
                      color: isLiked ? Colors.redAccent : AppTheme.accent,
                      size: 64,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
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
                      style: const TextStyle(
                          fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    if (playlist.description != null && playlist.description!.isNotEmpty) ...[
                      const SizedBox(height: 6),
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
                  ],
                ),
              ),
              if (!isLiked) ...[
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  onPressed: () => _deletePlaylist(playlist),
                  tooltip: 'Eliminar Playlist',
                ),
              ],
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
    return ListView.builder(
      itemCount: tracks.length + 1,
      itemBuilder: (context, idx) {
        if (idx == 0) {
          // Table Header
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.divider, width: 1)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 40, child: Text('#', style: TextStyle(color: AppTheme.textHint, fontSize: 11, fontWeight: FontWeight.bold))),
                Expanded(flex: 3, child: Text('TÍTULO', style: TextStyle(color: AppTheme.textHint, fontSize: 11, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('ARTISTA', style: TextStyle(color: AppTheme.textHint, fontSize: 11, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('ÁLBUM', style: TextStyle(color: AppTheme.textHint, fontSize: 11, fontWeight: FontWeight.bold))),
                SizedBox(width: 70, child: Align(alignment: Alignment.centerRight, child: Text('DURACIÓN', style: TextStyle(color: AppTheme.textHint, fontSize: 11, fontWeight: FontWeight.bold)))),
                SizedBox(width: 90), // actions column
              ],
            ),
          );
        }

        final track = tracks[idx - 1];
        final durationStr = _formatDuration(track.duration);
        final isLiked = _likedTrackIds.contains(track.trackId);

        return _TrackRow(
          track: track,
          index: idx,
          durationStr: durationStr,
          isLiked: isLiked,
          customPlaylists: _playlists.where((p) => p.playlistId != '__liked__').toList(),
          playlistSource: playlistSource,
          onPlay: () => _playTracks(tracks, idx - 1),
          onToggleLike: () => _toggleLike(track),
          onAddToPlaylist: (p) => _addTrackToPlaylist(track, p),
          onRemoveFromPlaylist: (p) => _removeTrackFromPlaylist(track, p),
          onDelete: () => _deleteTrack(track),
        );
      },
    );
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
    required this.track,
    required this.index,
    required this.durationStr,
    required this.isLiked,
    required this.customPlaylists,
    this.playlistSource,
    required this.onPlay,
    required this.onToggleLike,
    required this.onAddToPlaylist,
    required this.onRemoveFromPlaylist,
    required this.onDelete,
  });

  final Track track;
  final int index;
  final String durationStr;
  final bool isLiked;
  final List<Playlist> customPlaylists;
  final Playlist? playlistSource;
  final VoidCallback onPlay;
  final VoidCallback onToggleLike;
  final ValueChanged<Playlist> onAddToPlaylist;
  final ValueChanged<Playlist> onRemoveFromPlaylist;
  final VoidCallback onDelete;

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
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        widget.track.displayTitle,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (widget.track.downloadSource != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.divider,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          widget.track.downloadSource!,
                          style: const TextStyle(fontSize: 8, color: AppTheme.accent),
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
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
              // Album
              Expanded(
                flex: 2,
                child: Text(
                  widget.track.displayAlbum,
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
                width: 90,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Like button (shows on hover or if liked)
                    if (_hovered || widget.isLiked) ...[
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          widget.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 16,
                          color: widget.isLiked ? Colors.redAccent : AppTheme.textSecondary,
                        ),
                        onPressed: widget.onToggleLike,
                      ),
                    ] else ...[
                      const SizedBox(width: 24),
                    ],
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
                        if (value == 'delete') {
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

                        if (widget.customPlaylists.isEmpty) {
                          items.add(
                            const PopupMenuItem<dynamic>(
                              enabled: false,
                              child: Text(
                                'Crea una playlist primero',
                                style: TextStyle(color: AppTheme.textHint, fontSize: 12),
                              ),
                            ),
                          );
                        } else {
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
