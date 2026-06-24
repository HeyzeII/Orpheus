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
    return _isar.tracks.where().findAll();
  }

  /// Returns the [Track] whose [Track.trackId] matches [trackId], or `null`.
  Future<Track?> getTrackByTrackId(String trackId) async {
    return _isar.tracks.where().trackIdEqualTo(trackId).findFirst();
  }

  /// Returns the [Track] whose [Track.filePath] matches [filePath], or `null`.
  Future<Track?> getTrackByFilePath(String filePath) async {
    return _isar.tracks.where().filePathEqualTo(filePath).findFirst();
  }

  /// Returns all [Track]s whose [Track.artist] matches [artist].
  Future<List<Track>> getTracksByArtist(String artist) async {
    return _isar.tracks.filter().artistEqualTo(artist).findAll();
  }

  /// Returns all [Track]s whose [Track.album] matches [album].
  Future<List<Track>> getTracksByAlbum(String album) async {
    return _isar.tracks.filter().albumEqualTo(album).findAll();
  }

  /// Permanently removes a [Track] by its Isar [id].
  /// Also removes it from all playlists that referenced it.
  Future<void> deleteTrack(int id) async {
    final track = await _isar.tracks.get(id);
    if (track == null) return;

    await _isar.writeTxn(() async {
      await _isar.tracks.delete(id);
      // Purge the trackId from every playlist's reference list.
      final allPlaylists = await _isar.playlists.where().findAll();
      for (final playlist in allPlaylists) {
        if (playlist.trackIds.contains(track.trackId)) {
          playlist.trackIds.remove(track.trackId);
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
    return _isar.playlists.where().findAll();
  }

  /// Returns the [Playlist] whose [Playlist.playlistId] matches, or `null`.
  Future<Playlist?> getPlaylistById(String playlistId) async {
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
    playlist.trackIds.add(trackId);
    await savePlaylist(playlist);
  }

  /// Removes [trackId] from [playlist] if present.
  Future<void> removeTrackFromPlaylist({
    required Playlist playlist,
    required String trackId,
  }) async {
    if (!playlist.trackIds.contains(trackId)) return;
    playlist.trackIds.remove(trackId);
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
      config.scanDirectories.add(path);
      await saveConfig(config);
    }
  }

  /// Convenience method to remove a directory path from the scan list.
  Future<void> removeScanDirectory(String path) async {
    final config = await getConfig();
    config.scanDirectories.remove(path);
    await saveConfig(config);
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
      config.conflictResolution.ignoredPairs.add(
        IgnoredArtistPair()
          ..artistA = artistA
          ..artistB = artistB,
      );
      await saveConfig(config);
    }
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
