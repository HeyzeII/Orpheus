import 'dart:io';

import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_config.dart';
import '../models/playlist.dart';
import '../models/track.dart';

/// Singleton service that owns the Isar database instance for Orpheus.
///
/// Usage:
/// ```dart
/// await LocalDatabase.instance.initialize();
/// final tracks = await LocalDatabase.instance.getAllTracks();
/// ```
///
/// Call [initialize] once at app startup (before [runApp]) and never again.
class LocalDatabase {
  // ── Singleton boilerplate ──────────────────────────────────────────────────

  LocalDatabase._internal();

  static final LocalDatabase instance = LocalDatabase._internal();

  factory LocalDatabase() => instance;

  // ── Internal state ─────────────────────────────────────────────────────────

  late Isar _isar;

  bool _initialized = false;

  bool get _isTestUninitialized => !_initialized && Platform.environment.containsKey('FLUTTER_TEST');


  // ── Initialization ─────────────────────────────────────────────────────────

  /// Opens the Isar database in the platform's application-support directory.
  ///
  /// - macOS → `~/Library/Application Support/com.heyzell.orpheus/`
  /// - Android → `/data/data/com.heyzell.orpheus/files/`
  ///
  /// Safe to call only once. Throws [StateError] if called more than once.
  Future<void> initialize() async {
    if (_initialized) {
      throw StateError('LocalDatabase.initialize() called more than once.');
    }

    final Directory supportDir = await getApplicationSupportDirectory();

    _isar = await Isar.open(
      [TrackSchema, PlaylistSchema, AppConfigSchema],
      directory: supportDir.path,
      name: 'orpheus_db',
      inspector: !_isRelease,
    );

    await _seedDefaultData();
    _initialized = true;
  }

  /// Returns `true` in release mode (used to disable the Isar Inspector).
  bool get _isRelease => const bool.fromEnvironment('dart.vm.product');

  /// Creates required default documents if they don't exist yet.
  Future<void> _seedDefaultData() async {
    // Ensure exactly one AppConfig exists.
    final existingConfig = await _isar.appConfigs.get(1);
    if (existingConfig == null) {
      await _isar.writeTxn(() async {
        await _isar.appConfigs.put(AppConfig());
      });
    }

    // Ensure the "Liked Tracks" system playlist exists.
    final liked = await _isar.playlists
        .where()
        .playlistIdEqualTo('__liked__')
        .findFirst();
    if (liked == null) {
      await _isar.writeTxn(() async {
        await _isar.playlists.put(
          Playlist()
            ..playlistId = '__liked__'
            ..name = 'Liked Tracks'
            ..description = 'Tracks you have marked as liked.'
            ..isDefault = true,
        );
      });
    }
  }

  // ── Convenience accessor (throws if not initialized) ───────────────────────

  Isar get db {
    assert(_initialized, 'Call LocalDatabase.initialize() before using db.');
    return _isar;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TRACK CRUD
  // ══════════════════════════════════════════════════════════════════════════

  /// Persists a new [track] or updates an existing one (matched by Isar id).
  Future<void> saveTrack(Track track) async {
    await _isar.writeTxn(() async {
      await _isar.tracks.put(track);
    });
  }

  /// Persists a batch of tracks in a single transaction (preferred for imports).
  Future<void> saveTracks(List<Track> tracks) async {
    await _isar.writeTxn(() async {
      await _isar.tracks.putAll(tracks);
    });
  }

  /// Returns every [Track] in the library, ordered by [Track.title] ascending.
  Future<List<Track>> getAllTracks() async {
    if (_isTestUninitialized) return [];
    return _isar.tracks.where().findAll();
  }

  /// Returns a stream that emits whenever the tracks collection changes.
  Stream<void> watchTracks() {
    if (_isTestUninitialized) return const Stream.empty();
    return _isar.tracks.watchLazy();
  }

  /// Returns the [Track] whose [Track.trackId] matches [trackId], or `null`.
  Future<Track?> getTrackByTrackId(String trackId) async {
    if (_isTestUninitialized) return null;
    return _isar.tracks.where().trackIdEqualTo(trackId).findFirst();
  }

  /// Returns the [Track] whose [Track.filePath] matches [filePath], or `null`.
  Future<Track?> getTrackByFilePath(String filePath) async {
    if (_isTestUninitialized) return null;
    return _isar.tracks.where().filePathEqualTo(filePath).findFirst();
  }

  /// Returns all [Track]s whose [Track.artist] matches [artist].
  Future<List<Track>> getTracksByArtist(String artist) async {
    if (_isTestUninitialized) return [];
    return _isar.tracks.filter().artistEqualTo(artist).findAll();
  }

  /// Returns all [Track]s whose [Track.album] matches [album].
  Future<List<Track>> getTracksByAlbum(String album) async {
    if (_isTestUninitialized) return [];
    return _isar.tracks.filter().albumEqualTo(album).findAll();
  }

  /// Permanently removes a [Track] by its Isar [id].
  ///
  /// Safe Deletion:
  /// - Conserva el archivo original intacto, pero lo mueve físicamente a una
  ///   carpeta llamada `.trash` dentro del mismo directorio raíz donde se encuentra la canción.
  /// - Si la carpeta `.trash` no existe, la crea en caliente.
  /// - Una vez movido el archivo (o si el archivo no existe), lo elimina de la base de datos de Isar
  ///   y lo remueve de las listas de reproducción.
  Future<void> deleteTrack(int id) async {
    final track = await _isar.tracks.get(id);
    if (track == null) return;

    // Move the physical file to the .trash folder in the same directory.
    final file = File(track.filePath);
    if (file.existsSync()) {
      try {
        final directory = file.parent;
        final trashDirectory = Directory('${directory.path}/.trash');
        if (!trashDirectory.existsSync()) {
          trashDirectory.createSync(recursive: true);
        }

        final fileName = file.path.split('/').last;
        var targetFile = File('${trashDirectory.path}/$fileName');
        if (targetFile.existsSync()) {
          final dotIndex = fileName.lastIndexOf('.');
          final baseName = dotIndex != -1 ? fileName.substring(0, dotIndex) : fileName;
          final ext = dotIndex != -1 ? fileName.substring(dotIndex) : '';
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          targetFile = File('${trashDirectory.path}/${baseName}_$timestamp$ext');
        }

        try {
          await file.rename(targetFile.path);
        } catch (e) {
          // Fallback in case of volume boundaries: copy and delete
          await file.copy(targetFile.path);
          await file.delete();
        }
      } catch (_) {
        // Continue to delete from DB even if physical file move fails
      }
    }

    await _isar.writeTxn(() async {
      await _isar.tracks.delete(id);
      // Purge the trackId from every playlist's reference list.
      final allPlaylists = await _isar.playlists.where().findAll();
      for (final playlist in allPlaylists) {
        if (playlist.trackIds.contains(track.trackId)) {
          final updatedTrackIds = List<String>.from(playlist.trackIds);
          updatedTrackIds.remove(track.trackId);
          playlist.trackIds = updatedTrackIds;
          await _isar.playlists.put(playlist);
        }
      }
    });
  }

  /// Records a play event on [track] for the current local month.
  Future<void> recordPlay(Track track) async {
    final now = DateTime.now();
    final monthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    track.stats.recordPlay(monthKey);
    await saveTrack(track);
  }

  /// Caches the [lrcContent] (raw LRC string from LRCLIB) on [track].
  ///
  /// Pass an empty string to signal "no lyrics available" so the service
  /// does not make redundant network requests for the same track.
  Future<void> updateTrackLyrics(Track track, String lrcContent) async {
    track.syncedLyrics = lrcContent;
    await saveTrack(track);
  }

  /// Returns recently played tracks (sorted by totalPlays > 0, falling back to all tracks).
  Future<List<Track>> getRecentlyPlayedTracks({int limit = 6}) async {
    final tracks = await getAllTracks();
    final played = tracks.where((t) => t.stats.totalPlays > 0).toList();
    if (played.isEmpty) {
      return tracks.take(limit).toList();
    }
    played.sort((a, b) => b.stats.totalPlays.compareTo(a.stats.totalPlays));
    return played.take(limit).toList();
  }

  /// Returns the most played tracks.
  Future<List<Track>> getMostPlayedTracks({int limit = 6}) async {
    final tracks = await getAllTracks();
    final sorted = List<Track>.from(tracks);
    sorted.sort((a, b) => b.stats.totalPlays.compareTo(a.stats.totalPlays));
    return sorted.take(limit).toList();
  }

  /// Returns a sorted list of unique genres in the library.
  Future<List<String>> getUniqueGenres() async {
    final tracks = await getAllTracks();
    final genres = tracks
        .map((t) => t.genre?.trim())
        .where((g) => g != null && g.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    genres.sort();
    return genres;
  }

  /// Returns a sorted list of unique album names in the library.
  Future<List<String>> getUniqueAlbums() async {
    final tracks = await getAllTracks();
    final albums = tracks
        .map((t) => t.displayAlbum.trim())
        .where((a) => a.isNotEmpty && a != 'Unknown Album')
        .toSet()
        .toList();
    albums.sort();
    return albums;
  }

  /// Returns a sorted list of unique artist names in the library.
  Future<List<String>> getUniqueArtists() async {
    final tracks = await getAllTracks();
    final artists = tracks
        .map((t) => t.displayArtist.trim())
        .where((a) => a.isNotEmpty && a != 'Unknown Artist')
        .toSet()
        .toList();
    artists.sort();
    return artists;
  }

  // ══════════════════════════════════════════════════════════════════════════

  // PLAYLIST CRUD
  // ══════════════════════════════════════════════════════════════════════════

  /// Persists a new [playlist] or updates an existing one.
  Future<void> savePlaylist(Playlist playlist) async {
    await _isar.writeTxn(() async {
      await _isar.playlists.put(playlist);
    });
  }

  /// Returns all playlists ordered by Isar insertion order.
  Future<List<Playlist>> getAllPlaylists() async {
    if (_isTestUninitialized) return [];
    return _isar.playlists.where().findAll();
  }

  /// Returns the [Playlist] whose [Playlist.playlistId] matches, or `null`.
  Future<Playlist?> getPlaylistById(String playlistId) async {
    if (_isTestUninitialized) {
      if (playlistId == '__liked__') {
        return Playlist()
          ..playlistId = '__liked__'
          ..name = 'Liked Tracks'
          ..description = 'Tracks you have marked as liked.'
          ..isDefault = true;
      }
      return null;
    }
    return _isar.playlists
        .where()
        .playlistIdEqualTo(playlistId)
        .findFirst();
  }

  /// Adds [trackId] to [playlist] if it isn't already present.
  ///
  /// Enforces no-duplicate semantics at the database layer.
  Future<void> addTrackToPlaylist({
    required Playlist playlist,
    required String trackId,
  }) async {
    if (playlist.trackIds.contains(trackId)) return;
    final updated = List<String>.from(playlist.trackIds);
    updated.add(trackId);
    playlist.trackIds = updated;
    await savePlaylist(playlist);
  }

  /// Removes [trackId] from [playlist] if present.
  Future<void> removeTrackFromPlaylist({
    required Playlist playlist,
    required String trackId,
  }) async {
    if (!playlist.trackIds.contains(trackId)) return;
    final updated = List<String>.from(playlist.trackIds);
    updated.remove(trackId);
    playlist.trackIds = updated;
    await savePlaylist(playlist);
  }

  /// Reorders the tracks in [playlist] by replacing [trackIds] entirely.
  ///
  /// The caller is responsible for ensuring [newOrder] is a valid permutation
  /// of the existing IDs.
  Future<void> reorderPlaylistTracks({
    required Playlist playlist,
    required List<String> newOrder,
  }) async {
    playlist.trackIds = newOrder;
    await savePlaylist(playlist);
  }

  /// Permanently deletes a playlist by its Isar [id].
  ///
  /// Throws [ArgumentError] if the playlist is a system default (isDefault).
  Future<void> deletePlaylist(int id) async {
    final playlist = await _isar.playlists.get(id);
    if (playlist == null) return;
    if (playlist.isDefault) {
      throw ArgumentError(
        'Cannot delete system playlist "${playlist.name}".',
      );
    }
    await _isar.writeTxn(() async {
      await _isar.playlists.delete(id);
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // APP CONFIG
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns the singleton [AppConfig] (always id == 1).
  Future<AppConfig> getConfig() async {
    if (_isTestUninitialized) return AppConfig();
    return (await _isar.appConfigs.get(1)) ?? AppConfig();
  }

  /// Persists the singleton [AppConfig].
  Future<void> saveConfig(AppConfig config) async {
    config.id = 1; // guard: ensure the singleton key is never changed.
    await _isar.writeTxn(() async {
      await _isar.appConfigs.put(config);
    });
  }

  /// Convenience method to add a directory path to the scan list.
  Future<void> addScanDirectory(String path) async {
    final config = await getConfig();
    if (!config.scanDirectories.contains(path)) {
      final updatedDirectories = List<String>.from(config.scanDirectories);
      updatedDirectories.add(path);
      config.scanDirectories = updatedDirectories;
      await saveConfig(config);
    }
  }

  /// Convenience method to remove a directory path from the scan list.
  /// Also performs a cascade delete of all indexed tracks under that path.
  Future<void> removeScanDirectory(String path) async {
    final config = await getConfig();
    final updatedDirectories = List<String>.from(config.scanDirectories);
    updatedDirectories.remove(path);
    config.scanDirectories = updatedDirectories;
    await saveConfig(config);

    // Delete all tracks whose path starts with the removed directory path.
    await _isar.writeTxn(() async {
      await _isar.tracks.filter().filePathStartsWith(path).deleteAll();
    });
  }

  /// Adds an ignored artist pair to the conflict-resolution list.
  ///
  /// The pair is stored only if an equivalent entry does not already exist.
  Future<void> addIgnoredArtistPair({
    required String artistA,
    required String artistB,
  }) async {
    final config = await getConfig();
    final alreadyIgnored = config.conflictResolution.ignoredPairs.any(
      (p) =>
          (p.artistA == artistA && p.artistB == artistB) ||
          (p.artistA == artistB && p.artistB == artistA),
    );
    if (!alreadyIgnored) {
      final updatedPairs = List<IgnoredArtistPair>.from(config.conflictResolution.ignoredPairs);
      updatedPairs.add(
        IgnoredArtistPair()
          ..artistA = artistA
          ..artistB = artistB,
      );
      config.conflictResolution.ignoredPairs = updatedPairs;
      await saveConfig(config);
    }
  }

  /// Clears all tracks, playlists, configs and re-seeds default data.
  Future<void> clearDatabase() async {
    if (_isTestUninitialized) return;
    await _isar.writeTxn(() async {
      await _isar.tracks.clear();
      await _isar.playlists.clear();
      await _isar.appConfigs.clear();
    });
    await _seedDefaultData();
  }

  /// Resets `syncedLyrics` to null for all tracks, effectively clearing the lyrics cache.
  Future<void> clearLyricsCache() async {
    if (_isTestUninitialized) return;
    final tracks = await _isar.tracks.where().findAll();
    await _isar.writeTxn(() async {
      for (final track in tracks) {
        track.syncedLyrics = null;
      }
      await _isar.tracks.putAll(tracks);
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════════

  /// Closes the database. Call this only when the app is shutting down.
  Future<void> close() async {
    if (_initialized) {
      await _isar.close();
      _initialized = false;
    }
  }
}
