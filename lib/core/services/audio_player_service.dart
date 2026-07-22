import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:media_kit/media_kit.dart' hide Track;

import '../database/local_database.dart';
import '../models/playback_state.dart';
import '../models/track.dart';

enum PlayerRepeatMode {
  off,
  playlist,
  single,
}

/// Singleton service managing the native audio player engine, play queue,
/// automated playback statistics tracking, and **persistent playback state**.
///
/// ## Playback-state persistence strategy
///
/// We deliberately avoid timers or periodic writes to keep disk I/O minimal:
///
/// 1. **On pause** — the `playing` stream emits `false`. We capture the exact
///    position at that instant and write to Isar once.
/// 2. **On track change** — before opening a new file we write a snapshot with
///    the new [Track.trackId] and `positionMs = 0`.
/// 3. **On app lifecycle change** — [MainShell] calls [savePlaybackStateNow]
///    when the app transitions to `inactive` or `paused`.
/// 4. **On hydration** — [hydratePlaybackState] is called once from `main()`
///    after the DB is ready. It restores the queue, seeks to the saved
///    position, and leaves the player in the **paused** state.
class AudioPlayerService {
  // ── Singleton Boilerplate ──────────────────────────────────────────────────

  AudioPlayerService._internal({LocalDatabase? db})
      : _db = db ?? LocalDatabase.instance {
    _init();
  }

  static final AudioPlayerService instance =
      AudioPlayerService._internal();

  factory AudioPlayerService() => instance;

  // ── Dependencies & State ───────────────────────────────────────────────────

  final LocalDatabase _db;
  late final Player _player;

  final List<Track> _queue = [];
  List<Track>? _originalQueue;
  int _currentIndex = -1;
  bool _shuffle = false;
  PlayerRepeatMode _repeatMode = PlayerRepeatMode.off;

  int _consecutiveErrors = 0;

  /// Suppresses the "pause → save" listener during the hydration phase so we
  /// don't overwrite the restored state with a position-0 snapshot.
  bool _hydrating = false;

  // ── Stream Controllers ─────────────────────────────────────────────────────

  final _currentTrackController = StreamController<Track?>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _volumeController = StreamController<double>.broadcast();
  final _shuffleController = StreamController<bool>.broadcast();
  final _repeatController = StreamController<PlayerRepeatMode>.broadcast();
  final _queueController = StreamController<List<Track>>.broadcast();

  final List<StreamSubscription> _subscriptions = [];

  // ── Initialization ─────────────────────────────────────────────────────────

  void _init() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    _player = Player();

    // ── Pipe native media_kit streams to our broadcast streams ────────────────

    _subscriptions.add(_player.stream.playing.listen((playing) {
      _isPlayingController.add(playing);

      // 🔑 Event-based save: capture position the moment playback pauses.
      if (!playing && !_hydrating) {
        _saveCurrentPlaybackState();
      }
    }));

    _subscriptions.add(_player.stream.position.listen((pos) {
      _positionController.add(pos);
    }));

    _subscriptions.add(_player.stream.duration.listen((dur) {
      _durationController.add(dur);
    }));

    _subscriptions.add(_player.stream.volume.listen((vol) {
      _volumeController.add(vol / 100.0);
    }));

    // Auto-advance and statistics logging on track completion
    _subscriptions.add(_player.stream.completed.listen((completed) async {
      if (completed) {
        final finishedTrack = currentTrack;
        if (finishedTrack != null) {
          try {
            await _db.recordPlay(finishedTrack);
          } catch (_) {
            // Non-fatal if database writing fails during playback
          }
        }

        if (_repeatMode == PlayerRepeatMode.single) {
          await _player.seek(Duration.zero);
          await _player.play();
        } else {
          await next();
        }
      }
    }));
  }

  // ── Getters ────────────────────────────────────────────────────────────────

  Track? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;

  bool get isPlaying =>
      Platform.environment.containsKey('FLUTTER_TEST') ? false : _player.state.playing;

  Duration get position =>
      Platform.environment.containsKey('FLUTTER_TEST') ? Duration.zero : _player.state.position;

  Duration get duration =>
      Platform.environment.containsKey('FLUTTER_TEST') ? Duration.zero : _player.state.duration;

  /// Volume represented as a range from `0.0` (muted) to `1.0` (max).
  double get volume =>
      Platform.environment.containsKey('FLUTTER_TEST') ? 1.0 : _player.state.volume / 100.0;

  bool get shuffleEnabled => _shuffle;

  bool get repeatEnabled => _repeatMode != PlayerRepeatMode.off;

  PlayerRepeatMode get repeatMode => _repeatMode;

  List<Track> get queue => List.unmodifiable(_queue);

  int get currentIndex => _currentIndex;

  // ── Streams for UI ─────────────────────────────────────────────────────────

  Stream<Track?> get currentTrackStream => _currentTrackController.stream;

  Stream<bool> get isPlayingStream => _isPlayingController.stream;

  Stream<Duration> get positionStream => _positionController.stream;

  Stream<Duration> get durationStream => _durationController.stream;

  Stream<double> get volumeStream => _volumeController.stream;

  Stream<bool> get shuffleStream => _shuffleController.stream;

  Stream<PlayerRepeatMode> get repeatStream => _repeatController.stream;

  Stream<List<Track>> get queueStream => _queueController.stream;

  // ── Control API ────────────────────────────────────────────────────────────

  /// Replaces the current queue with [tracks] and starts playing at [initialIndex].
  Future<void> loadPlaylist(List<Track> tracks, {int initialIndex = 0}) async {
    // Check if the tracks list is exactly the same as our current _queue (same trackId and same order)
    bool isCurrentQueue = false;
    if (tracks.length == _queue.length) {
      isCurrentQueue = true;
      for (int i = 0; i < tracks.length; i++) {
        if (tracks[i].trackId != _queue[i].trackId) {
          isCurrentQueue = false;
          break;
        }
      }
    }

    if (isCurrentQueue) {
      if (_queue.isNotEmpty) {
        final targetIdx = initialIndex.clamp(0, _queue.length - 1);
        await _playIndex(targetIdx);
      }
      return;
    }

    _queue.clear();
    _queue.addAll(tracks);
    _consecutiveErrors = 0;
    _originalQueue = null;

    if (_queue.isEmpty) {
      _currentIndex = -1;
      await stop();
      _notifyState();
      return;
    }

    var startIndex = initialIndex;
    if (startIndex < 0 || startIndex >= _queue.length) {
      startIndex = 0;
    }

    if (_shuffle) {
      _originalQueue = List<Track>.from(_queue);
      final current = _queue[startIndex];
      final remaining = List<Track>.from(_queue)..removeAt(startIndex);
      remaining.shuffle(Random());
      _queue.clear();
      _queue.add(current);
      _queue.addAll(remaining);
      startIndex = 0;
    }

    // 🔑 Save state before opening the new track (position resets to 0).
    await _saveCurrentPlaybackState(overrideTrackId: _queue[startIndex].trackId, overridePositionMs: 0);
    await _playIndex(startIndex);
  }

  Future<void> play() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    await _player.play();
    _notifyState();
  }

  Future<void> pause() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    await _player.pause();
    _notifyState();
  }

  Future<void> stop() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    await _player.stop();
    _currentIndex = -1;
    _notifyState();
  }

  /// Completely stops playback and resets the internal state, clearing the queue and current track.
  Future<void> stopAndReset() async {
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      await _player.stop();
    }
    _queue.clear();
    _originalQueue = null;
    _currentIndex = -1;
    _currentTrackController.add(null);
    _notifyState();
  }

  Future<void> seek(Duration position) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    await _player.seek(position);
    _notifyState();
  }

  /// Sets volume. Expects a range between `0.0` (muted) and `1.0` (max).
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _volumeController.add(clamped);
      return;
    }
    await _player.setVolume(clamped * 100.0);
    _volumeController.add(clamped);
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    if (_shuffle) {
      _originalQueue = List<Track>.from(_queue);
      if (_queue.isNotEmpty) {
        final current = currentTrack;
        final remaining = List<Track>.from(_queue);
        if (current != null) {
          remaining.removeWhere((t) => t.trackId == current.trackId);
        }
        remaining.shuffle(Random());
        _queue.clear();
        if (current != null) {
          _queue.add(current);
        }
        _queue.addAll(remaining);
        _currentIndex = current != null ? 0 : -1;
      }
    } else {
      if (_originalQueue != null) {
        final current = currentTrack;
        _queue.clear();
        _queue.addAll(_originalQueue!);
        _originalQueue = null;
        if (current != null) {
          _currentIndex = _queue.indexWhere((t) => t.trackId == current.trackId);
        }
      }
    }
    _shuffleController.add(_shuffle);
    _notifyState();
  }

  void toggleRepeat() {
    switch (_repeatMode) {
      case PlayerRepeatMode.off:
        _repeatMode = PlayerRepeatMode.playlist;
        break;
      case PlayerRepeatMode.playlist:
        _repeatMode = PlayerRepeatMode.single;
        break;
      case PlayerRepeatMode.single:
        _repeatMode = PlayerRepeatMode.off;
        break;
    }
    _repeatController.add(_repeatMode);
    _notifyState();
  }

  /// Advances to the next track in the queue, handling shuffle options.
  Future<void> next() async {
    if (_queue.isEmpty) return;

    final nextIndex = _currentIndex + 1;
    if (nextIndex >= _queue.length) {
      if (_repeatMode == PlayerRepeatMode.playlist) {
        await _playIndex(0); // loop back
      } else {
        await stop();
      }
    } else {
      await _playIndex(nextIndex);
    }
  }

  /// Plays the previous track, or restarts the current track if past 3 seconds.
  Future<void> previous() async {
    if (_queue.isEmpty) return;

    // Premium behavior: restarts song if past 3 seconds.
    if (position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    final prevIndex = _currentIndex - 1;
    if (prevIndex < 0) {
      if (_repeatMode == PlayerRepeatMode.playlist) {
        await _playIndex(_queue.length - 1);
      } else {
        await seek(Duration.zero);
      }
    } else {
      await _playIndex(prevIndex);
    }
  }

  /// Inserts [track] immediately after the currently playing track.
  ///
  /// If the queue is empty, starts playing [track] immediately.
  void playNext(Track track) {
    if (_queue.isEmpty || _currentIndex < 0) {
      _queue.add(track);
      _currentIndex = 0;
      _notifyState();
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        _playIndex(0);
      }
      return;
    }
    // Remove any existing instance first (prevents duplicates mid-queue)
    final existingIdx = _queue.indexWhere((t) => t.trackId == track.trackId);
    if (existingIdx >= 0 && existingIdx != _currentIndex + 1) {
      _queue.removeAt(existingIdx);
      if (existingIdx <= _currentIndex) _currentIndex--;
    }
    final insertAt = _currentIndex + 1;
    _queue.insert(insertAt, track);

    // Sync original queue if shuffle is ON
    if (_originalQueue != null) {
      final origIdx = _originalQueue!.indexWhere((t) => t.trackId == track.trackId);
      if (origIdx >= 0) _originalQueue!.removeAt(origIdx);
      final currentTrackId = currentTrack?.trackId;
      final origCurrentIdx = _originalQueue!.indexWhere((t) => t.trackId == currentTrackId);
      if (origCurrentIdx >= 0) {
        _originalQueue!.insert(origCurrentIdx + 1, track);
      } else {
        _originalQueue!.add(track);
      }
    }

    _notifyState();
  }

  /// Appends [track] to the end of the current queue.
  ///
  /// If the queue is empty, starts playing [track] immediately.
  void addToQueue(Track track) {
    if (_queue.isEmpty || _currentIndex < 0) {
      _queue.add(track);
      _currentIndex = 0;
      _notifyState();
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        _playIndex(0);
      }
      return;
    }
    _queue.add(track);

    // Sync original queue if shuffle is ON
    if (_originalQueue != null) {
      final origIdx = _originalQueue!.indexWhere((t) => t.trackId == track.trackId);
      if (origIdx >= 0) _originalQueue!.removeAt(origIdx);
      _originalQueue!.add(track);
    }

    _notifyState();
  }

  /// Clears all tracks from the queue except the currently playing one.
  void clearQueue() {
    if (_queue.isEmpty || _currentIndex < 0) return;
    final current = _queue[_currentIndex];
    _queue.clear();
    _queue.add(current);
    _currentIndex = 0;
    _originalQueue = null;
    _notifyState();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  /// Captures and persists the current playback state to Isar.
  ///
  /// All parameters are optional overrides used internally (e.g. when
  /// switching tracks we know the next [trackId] before the player opens it).
  Future<void> _saveCurrentPlaybackState({
    String? overrideTrackId,
    int? overridePositionMs,
  }) async {
    try {
      final trackId = overrideTrackId ?? currentTrack?.trackId;
      if (trackId == null) return; // Nothing to save yet.

      final posMs = overridePositionMs ?? position.inMilliseconds;
      final queueIds = _queue.map((t) => t.trackId).toList();

      final state = PlaybackState()
        ..trackId = trackId
        ..positionMs = posMs
        ..queueTrackIds = queueIds;

      await _db.savePlaybackState(state);
    } catch (_) {
      // Non-fatal: persistence failures should never interrupt playback.
    }
  }

  /// Public entry point called by [MainShell] on lifecycle transitions
  /// (inactive / paused) to capture an immediate snapshot before the OS
  /// may suspend the process.
  Future<void> savePlaybackStateNow() => _saveCurrentPlaybackState();

  /// Restores the last saved playback state on app startup.
  ///
  /// Call this **after** [LocalDatabase.initialize] and **before** [runApp].
  /// The method:
  /// 1. Reads the persisted [PlaybackState] from Isar.
  /// 2. Looks up every [Track] in [queueTrackIds] from the library.
  /// 3. Loads the queue without auto-playing (the `_hydrating` flag prevents
  ///    the "pause → save" listener from immediately overwriting the state).
  /// 4. Seeks to [positionMs] and leaves the player paused.
  Future<void> hydratePlaybackState() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    try {
      final saved = await _db.getPlaybackState();
      if (saved == null || saved.trackId == null) return;

      // Resolve Track objects from their stable trackIds.
      final resolvedTracks = <Track>[];
      for (final id in saved.queueTrackIds) {
        final track = await _db.getTrackByTrackId(id);
        if (track != null) resolvedTracks.add(track);
      }
      if (resolvedTracks.isEmpty) return;

      // Find the index of the track that was playing.
      final startIndex = resolvedTracks.indexWhere(
        (t) => t.trackId == saved.trackId,
      );
      if (startIndex == -1) return;

      // Populate the in-memory queue without triggering persistence callbacks.
      _hydrating = true;
      _queue
        ..clear()
        ..addAll(resolvedTracks);
      _currentIndex = startIndex;

      final track = _queue[_currentIndex];
      final file = File(track.filePath);
      if (!file.existsSync()) {
        _hydrating = false;
        return;
      }

      // Open the file and pause immediately after the engine is ready.
      await _player.open(
        Media(Uri.file(track.filePath).toString()),
        play: false,
      );

      // Give media_kit's native engine a moment to load metadata/duration
      await Future.delayed(const Duration(milliseconds: 300));

      // Seek to the saved position once the duration becomes available.
      if (saved.positionMs > 0) {
        await _player.seek(Duration(milliseconds: saved.positionMs));
      }

      _hydrating = false;
      _notifyState();
    } catch (_) {
      _hydrating = false;
      // Non-fatal: if hydration fails the app starts fresh.
    }
  }

  // ── Helper Methods ─────────────────────────────────────────────────────────

  Future<void> _playIndex(int index) async {
    if (_queue.isEmpty) {
      _currentIndex = -1;
      _notifyState();
      return;
    }

    if (index < 0 || index >= _queue.length) {
      if (_repeatMode != PlayerRepeatMode.off) {
        _currentIndex = 0;
      } else {
        await stop();
        return;
      }
    } else {
      _currentIndex = index;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _notifyState();
      return;
    }

    final track = _queue[_currentIndex];
    final file = File(track.filePath);

    // Strict handling of missing files
    if (!file.existsSync()) {
      _consecutiveErrors++;
      if (_consecutiveErrors >= _queue.length) {
        _consecutiveErrors = 0;
        await stop();
        return;
      }

      _currentTrackController.add(null);
      Future.delayed(const Duration(milliseconds: 100), () {
        next();
      });
      return;
    }

    _consecutiveErrors = 0;

    try {
      // 🔑 Save state before opening (new track, position = 0).
      await _saveCurrentPlaybackState(
        overrideTrackId: track.trackId,
        overridePositionMs: 0,
      );
      await _player.open(
        Media(
          Uri.file(track.filePath).toString(),
          extras: {
            'title': track.displayTitle,
            'artist': track.displayArtist,
            'album': track.displayAlbum,
            if (track.customMetadata.customCoverPath != null &&
                track.customMetadata.customCoverPath!.isNotEmpty)
              'artUri': Uri.file(track.customMetadata.customCoverPath!).toString(),
          },
        ),
        play: true,
      );
      _notifyState();
    } catch (e) {
      Future.delayed(const Duration(milliseconds: 100), () {
        next();
      });
    }
  }

  void _notifyState() {
    _currentTrackController.add(currentTrack);
    _isPlayingController.add(isPlaying);
    _positionController.add(position);
    _durationController.add(duration);
    _volumeController.add(volume);
    _shuffleController.add(_shuffle);
    _repeatController.add(_repeatMode);
    _queueController.add(queue);
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _player.dispose();

    await _currentTrackController.close();
    await _isPlayingController.close();
    await _positionController.close();
    await _durationController.close();
    await _volumeController.close();
    await _shuffleController.close();
    await _repeatController.close();
    await _queueController.close();
  }
}
