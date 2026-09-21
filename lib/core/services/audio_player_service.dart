import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:media_kit_video/media_kit_video.dart';

import '../database/local_database.dart';
import '../models/playback_state.dart' as local;
import '../models/track.dart';

enum PlayerRepeatMode {
  off,
  playlist,
  single,
}

/// Singleton service managing the native audio player engine, decoupled play
/// queues (contextQueue, userQueue, historyStack), automated statistics,
/// and persistent playback state (Tidal-style decoupled architecture).
class AudioPlayerService {
  // ── Singleton Boilerplate ──────────────────────────────────────────────────

  AudioPlayerService._internal({LocalDatabase? db})
      : _db = db ?? LocalDatabase.instance {
    _init();
  }

  static final AudioPlayerService instance =
      AudioPlayerService._internal();

  factory AudioPlayerService() => instance;

  // ── Dependencies & Decoupled State ─────────────────────────────────────────

  final LocalDatabase _db;
  late final Player _player;
  /// Exposes the media_kit [VideoController] for rendering frames in [VideoCanvas].
  /// Null in unit-test environments where the Player is never created.
  VideoController? _videoController;

  /// Ordered context tracks (e.g. album, playlist, library).
  /// Invariant: context is not mutated when user tracks play or history is browsed.
  List<Track> _contextTracks = [];

  /// Permutation of [_contextTracks] used when shuffle mode is active.
  List<Track>? _shuffledContextTracks;

  /// Stable index pointer into the active context list ([_activeContext]).
  int _contextIndex = -1;

  /// Pure FIFO queue for tracks explicitly added by user ("Play next" / "Add to queue").
  final List<Track> _userQueue = [];

  /// Chronological log of tracks that have completed playback or were transitioned from.
  final List<Track> _history = [];

  /// Navigation stack for backward traversal (previous()).
  /// Independent of the immutable audit log (_history).
  final List<Track> _navigationStack = [];

  /// Mock position for unit tests in headless environments.
  Duration? _mockPosition;

  /// Currently active track.
  Track? _currentTrack;

  bool _shuffle = false;
  List<int>? _shuffledOriginalIndices;
  PlayerRepeatMode _repeatMode = PlayerRepeatMode.off;

  /// Human-readable label for the context source (e.g. "Album: Abbey Road").
  String _contextName = 'Biblioteca';

  int _consecutiveErrors = 0;

  /// Suppresses the "pause -> save" listener during the hydration phase.
  bool _hydrating = false;
  bool _disposed = false;

  // ── Stream Controllers ─────────────────────────────────────────────────────

  final _currentTrackController = StreamController<Track?>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _volumeController = StreamController<double>.broadcast();
  final _shuffleController = StreamController<bool>.broadcast();
  final _repeatController = StreamController<PlayerRepeatMode>.broadcast();
  final _queueController = StreamController<List<Track>>.broadcast();
  final _canSkipNextController = StreamController<bool>.broadcast();
  final _userQueueController = StreamController<List<Track>>.broadcast();
  final _contextQueueController = StreamController<List<Track>>.broadcast();
  final _historyController = StreamController<List<Track>>.broadcast();
  final _contextNameController = StreamController<String>.broadcast();
  final _pastContextController = StreamController<List<Track>>.broadcast();

  AudioSession? _audioSession;
  final List<StreamSubscription> _subscriptions = [];

  // ── Initialization ─────────────────────────────────────────────────────────

  void _init() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    _player = Player(
      configuration: const PlayerConfiguration(
        pitch: false,
      ),
    );

    // Optimize libmpv properties for background audio continuity:
    // Sinks video-sync to audio clock and prevents frame stalling when the
    // surface/texture is suspended or minimized on mobile OS.
    try {
      (_player.platform as dynamic)?.setProperty('video-sync', 'audio');
      (_player.platform as dynamic)?.setProperty('keep-open', 'yes');
      (_player.platform as dynamic)?.setProperty('hwdec', 'auto-safe');
    } catch (_) {}

    // Bind the VideoController to the same Player so the Video widget can
    // render frames without any extra configuration.
    _videoController = VideoController(_player);

    _initAudioSession();

    _subscriptions.add(_player.stream.playing.listen((playing) {
      if (_disposed) return;
      _isPlayingController.add(playing);

      if (!playing && !_hydrating) {
        _saveCurrentPlaybackState();
      }
    }));

    _subscriptions.add(_player.stream.position.listen((pos) {
      if (_disposed) return;
      _positionController.add(pos);
    }));

    _subscriptions.add(_player.stream.duration.listen((dur) {
      if (_disposed) return;
      _durationController.add(dur);
    }));

    _subscriptions.add(_player.stream.volume.listen((vol) {
      if (_disposed) return;
      _volumeController.add(vol / 100.0);
    }));

    _subscriptions.add(_player.stream.completed.listen((completed) async {
      if (_disposed) return;
      if (completed) {
        final finishedTrack = currentTrack;
        if (finishedTrack != null) {
          try {
            await _db.recordPlay(finishedTrack);
          } catch (_) {}
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

  Future<void> _safeSetActive(bool active) async {
    try {
      await _audioSession?.setActive(active);
    } catch (e) {
      debugPrint('AudioSession.setActive($active) caught error: $e');
    }
  }

  Future<void> _initAudioSession() async {
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final session = await AudioSession.instance;
      _audioSession = session;
      await session.configure(const AudioSessionConfiguration.music());

      _subscriptions.add(session.interruptionEventStream.listen((event) async {
        if (_disposed) return;
        try {
          if (event.begin) {
            switch (event.type) {
              case AudioInterruptionType.duck:
              case AudioInterruptionType.pause:
              case AudioInterruptionType.unknown:
                await pause();
                break;
            }
          } else {
            if (event.type != AudioInterruptionType.duck && isPlaying) {
              await _safeSetActive(true);
            }
          }
        } catch (e, s) {
          debugPrint('Error handling audio interruption event: $e\n$s');
        }
      }));

      _subscriptions.add(session.becomingNoisyEventStream.listen((_) async {
        if (_disposed) return;
        try {
          await pause();
        } catch (e, s) {
          debugPrint('Error handling becomingNoisy event: $e\n$s');
        }
      }));
    } catch (e) {
      debugPrint('Error configuring AudioSession: $e');
    }
  }

  // ── Internal Helpers ───────────────────────────────────────────────────────

  List<Track> get _activeContext =>
      _shuffle ? (_shuffledContextTracks ?? _contextTracks) : _contextTracks;

  List<Track> get _upcomingContext {
    final active = _activeContext;
    if (_contextIndex < 0 || _contextIndex >= active.length - 1) {
      return const <Track>[];
    }
    return active.sublist(_contextIndex + 1);
  }

  void _pushHistory(Track track) {
    if (_history.isNotEmpty && _history.last.trackId == track.trackId) {
      return;
    }
    _history.add(track);
    if (_history.length > 100) {
      _history.removeAt(0);
    }
  }

  void _pushNavigation(Track track) {
    _navigationStack.add(track);
    if (_navigationStack.length > 100) {
      _navigationStack.removeAt(0);
    }
  }

  // ── Public Getters ─────────────────────────────────────────────────────────

  Track? get currentTrack => _currentTrack;

  /// The [VideoController] bound to the active [Player].
  /// Returns `null` when running in a test environment.
  VideoController? get videoController => _videoController;

  bool get isPlaying =>
      Platform.environment.containsKey('FLUTTER_TEST') ? false : _player.state.playing;

  Duration get position =>
      Platform.environment.containsKey('FLUTTER_TEST')
          ? (_mockPosition ?? Duration.zero)
          : _player.state.position;

  Duration get duration =>
      Platform.environment.containsKey('FLUTTER_TEST') ? Duration.zero : _player.state.duration;

  double get volume =>
      Platform.environment.containsKey('FLUTTER_TEST') ? 1.0 : _player.state.volume / 100.0;

  bool get shuffleEnabled => _shuffle;

  bool get repeatEnabled => _repeatMode != PlayerRepeatMode.off;

  PlayerRepeatMode get repeatMode => _repeatMode;

  /// Pure FIFO user queue tracks in upcoming order.
  List<Track> get userQueue => List.unmodifiable(_userQueue);

  /// Upcoming context tracks starting after the current context position.
  List<Track> get contextQueue => List.unmodifiable(_upcomingContext);

  /// Context tracks that have already been played ([0 .. _contextIndex - 1]).
  /// Used by the pivot-style queue view (Tidal model) to show past album/playlist tracks.
  List<Track> get pastContext {
    if (_contextIndex <= 0 || _activeContext.isEmpty) return const <Track>[];
    return List.unmodifiable(_activeContext.sublist(0, _contextIndex));
  }

  /// Chronological history stack of tracks played prior to the current track.
  List<Track> get history => List.unmodifiable(_history);

  /// Consolidated list in visual order [History + Current + UserQueue + UpcomingContext]
  /// for OS MediaNotification, lockscreen controls, and system reactivity.
  List<Track> get queue => List.unmodifiable([
        ..._history,
        ?_currentTrack,
        ..._userQueue,
        ..._upcomingContext,
      ]);

  String get contextName => _contextName;

  /// Stable index pointer into the active context list ([_activeContext]).
  int get currentContextIndex => _contextIndex;

  /// Original index pointer into [_contextTracks] (mapped correctly even in shuffle mode).
  int get currentOriginalIndex {
    if (_contextIndex < 0) return -1;
    if (_shuffle && _shuffledOriginalIndices != null) {
      if (_contextIndex >= 0 && _contextIndex < _shuffledOriginalIndices!.length) {
        return _shuffledOriginalIndices![_contextIndex];
      }
    }
    return _contextIndex;
  }

  /// Ordered context tracks (e.g. album, playlist, library).
  List<Track> get contextTracks => List.unmodifiable(_contextTracks);

  /// Virtual index within the consolidated [queue] pointing to the current track.
  int get currentIndex => _currentTrack == null ? -1 : _history.length;

  bool get canSkipNext =>
      _userQueue.isNotEmpty ||
      (_contextIndex < _activeContext.length - 1) ||
      _repeatMode == PlayerRepeatMode.playlist;

  bool get canSkipPrevious =>
      _navigationStack.isNotEmpty ||
      position > const Duration(seconds: 3) ||
      _contextIndex > 0 ||
      _repeatMode == PlayerRepeatMode.playlist ||
      _repeatMode == PlayerRepeatMode.single;

  @visibleForTesting
  void setMockPosition(Duration pos) {
    _mockPosition = pos;
    _positionController.add(pos);
  }

  // ── Streams for UI ─────────────────────────────────────────────────────────

  Stream<Track?> get currentTrackStream => _currentTrackController.stream;
  Stream<bool> get isPlayingStream => _isPlayingController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<double> get volumeStream => _volumeController.stream;
  Stream<bool> get shuffleStream => _shuffleController.stream;
  Stream<PlayerRepeatMode> get repeatStream => _repeatController.stream;
  Stream<List<Track>> get queueStream => _queueController.stream;
  Stream<bool> get canSkipNextStream => _canSkipNextController.stream;
  Stream<List<Track>> get userQueueStream => _userQueueController.stream;
  Stream<List<Track>> get contextQueueStream => _contextQueueController.stream;
  Stream<List<Track>> get historyStream => _historyController.stream;
  Stream<String> get contextNameStream => _contextNameController.stream;
  Stream<List<Track>> get pastContextStream => _pastContextController.stream;

  // ── Control API ────────────────────────────────────────────────────────────

  /// Starts playback from an external context (Album, Playlist, Library),
  /// seamlessly preserving pending user-queue tracks.
  Future<void> playFromExternalContext(
    Track track,
    List<Track> newContext, {
    int? initialIndex,
    String? contextName,
  }) async {
    if (newContext.isEmpty) {
      await stopAndReset();
      return;
    }

    if (contextName != null) _contextName = contextName;
    _consecutiveErrors = 0;
    _navigationStack.clear();

    if (_currentTrack != null) {
      _pushHistory(_currentTrack!);
    }

    _contextTracks = List<Track>.from(newContext);
    final int actualIdx;
    if (initialIndex != null &&
        initialIndex >= 0 &&
        initialIndex < _contextTracks.length &&
        _contextTracks[initialIndex].trackId == track.trackId) {
      actualIdx = initialIndex;
    } else {
      final targetIdx = _contextTracks.indexWhere((t) => t.trackId == track.trackId);
      actualIdx = targetIdx >= 0 ? targetIdx : 0;
    }

    if (_shuffle) {
      final remainingIndices = List<int>.generate(_contextTracks.length, (i) => i)..removeAt(actualIdx);
      remainingIndices.shuffle(Random());
      _shuffledOriginalIndices = [actualIdx, ...remainingIndices];
      _shuffledContextTracks = _shuffledOriginalIndices!.map((i) => _contextTracks[i]).toList();
      _contextIndex = 0;
      _currentTrack = _shuffledContextTracks![0];
    } else {
      _shuffledContextTracks = null;
      _shuffledOriginalIndices = null;
      _contextIndex = actualIdx;
      _currentTrack = _contextTracks[_contextIndex];
    }

    await _openTrack(_currentTrack!);
    _notifyState();
  }

  /// Sets the playback context with [tracks] starting at [initialIndex].
  Future<void> loadPlaylist(
    List<Track> tracks, {
    int initialIndex = 0,
    String? contextName,
  }) async {
    if (tracks.isEmpty) {
      await stopAndReset();
      return;
    }
    final targetIdx = initialIndex.clamp(0, tracks.length - 1);
    await playFromExternalContext(
      tracks[targetIdx],
      tracks,
      initialIndex: targetIdx,
      contextName: contextName,
    );
  }

  Future<void> play() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    await _safeSetActive(true);
    try {
      await _player.play();
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
    _notifyState();
  }

  Future<void> pause() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      await _player.pause();
    } catch (e) {
      debugPrint('Error pausing audio: $e');
    }
    _notifyState();
  }

  Future<void> stop() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('Error stopping audio: $e');
    }
    await _safeSetActive(false);
    _currentTrack = null;
    _notifyState();
  }

  /// Stops playback and resets queue state.
  /// Set [clearHistory] to true only for explicit test cleanup or complete app resets.
  Future<void> stopAndReset({bool clearHistory = false}) async {
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      await _player.stop();
    }
    await _safeSetActive(false);
    _contextTracks.clear();
    _shuffledContextTracks = null;
    _shuffledOriginalIndices = null;
    _contextIndex = -1;
    _userQueue.clear();
    _navigationStack.clear();
    _mockPosition = null;
    _shuffle = false;
    _repeatMode = PlayerRepeatMode.off;
    if (clearHistory) {
      _history.clear();
    }
    _currentTrack = null;
    _currentTrackController.add(null);
    _notifyState();
  }

  Future<void> seek(Duration position) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _mockPosition = position;
      _positionController.add(position);
      _notifyState();
      return;
    }
    await _player.seek(position);
    _notifyState();
  }

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
      if (_contextTracks.isNotEmpty) {
        final currentIdx = (_contextIndex >= 0 && _contextIndex < _contextTracks.length)
            ? _contextIndex
            : 0;
        final remainingIndices = List<int>.generate(_contextTracks.length, (i) => i)..removeAt(currentIdx);
        remainingIndices.shuffle(Random());
        _shuffledOriginalIndices = [currentIdx, ...remainingIndices];
        _shuffledContextTracks = _shuffledOriginalIndices!.map((i) => _contextTracks[i]).toList();
        _contextIndex = 0;
      }
    } else {
      if (_shuffledOriginalIndices != null &&
          _contextIndex >= 0 &&
          _contextIndex < _shuffledOriginalIndices!.length) {
        _contextIndex = _shuffledOriginalIndices![_contextIndex];
      } else if (_currentTrack != null) {
        final origIdx = _contextTracks.indexWhere((t) => t.trackId == _currentTrack!.trackId);
        _contextIndex = origIdx != -1 ? origIdx : _contextIndex.clamp(0, _contextTracks.length - 1);
      }
      _shuffledContextTracks = null;
      _shuffledOriginalIndices = null;
    }
    _navigationStack.clear();
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

  /// Advances playback with FIFO user-queue priority without context mutation.
  Future<void> next() async {
    if (_currentTrack != null) {
      _pushHistory(_currentTrack!);
    }

    // 1. Priority: consume next FIFO item from userQueue
    if (_userQueue.isNotEmpty) {
      if (_currentTrack != null) {
        _pushNavigation(_currentTrack!);
      }
      _currentTrack = _userQueue.removeAt(0);
      await _openTrack(_currentTrack!);
      _notifyState();
      return;
    }

    // Resuming/advancing in context: clear navigation stack so previous() is purely index-based
    _navigationStack.clear();

    // 2. Otherwise advance in contextQueue
    final active = _activeContext;
    if (active.isEmpty) {
      await stop();
      return;
    }

    if (_contextIndex + 1 < active.length) {
      _contextIndex++;
      _currentTrack = active[_contextIndex];
      await _openTrack(_currentTrack!);
    } else {
      if (_repeatMode == PlayerRepeatMode.playlist) {
        _contextIndex = 0;
        _currentTrack = active[0];
        await _openTrack(_currentTrack!);
      } else {
        if (!Platform.environment.containsKey('FLUTTER_TEST')) {
          await _player.seek(Duration.zero);
          await _player.pause();
        }
      }
    }
    _notifyState();
  }

  /// Reverse navigation through deterministic index / navigation stack with 3-second restart rule.
  Future<void> previous() async {
    // 0. Modo repetir canción actual: reiniciar a 0:00 siempre
    if (_repeatMode == PlayerRepeatMode.single) {
      await seek(Duration.zero);
      await play();
      _notifyState();
      return;
    }

    // 1. Regla de los 3 segundos: reiniciar pista si ya transcurrieron > 3s
    if (position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      await play();
      return;
    }

    // 2. Desandar la pila de navegación (reservada para pistas fuera de contexto como userQueue)
    if (_navigationStack.isNotEmpty) {
      final prevTrack = _navigationStack.removeLast();
      if (_currentTrack != null) {
        _pushHistory(_currentTrack!);
      }
      final active = _activeContext;
      final matchIdx = active.lastIndexOf(prevTrack);
      if (matchIdx != -1) {
        _contextIndex = matchIdx;
      }
      _currentTrack = prevTrack;
      await _openTrack(_currentTrack!);
      _notifyState();
      return;
    }

    // 3. Navegación estrictamente ordinal sobre el contexto activo (secuencial o shuffle determinista)
    if (_activeContext.isNotEmpty && _contextIndex > 0) {
      if (_currentTrack != null) {
        _pushHistory(_currentTrack!);
      }
      _contextIndex--;
      _currentTrack = _activeContext[_contextIndex];
      await _openTrack(_currentTrack!);
      _notifyState();
      return;
    }

    // 4. Sin contexto anterior: reiniciar a 0
    await seek(Duration.zero);
    await play();
    _notifyState();
  }

  /// Jumps directly to an item by its consolidated index in [queue].
  Future<void> skipToIndex(int index) async {
    final histLen = _history.length;
    if (index < 0) return;

    if (index < histLen) {
      await playHistoryItem(index);
      return;
    }

    final hasCurrent = _currentTrack != null;
    final currentIdx = hasCurrent ? histLen : -1;
    if (index == currentIdx) {
      await seek(Duration.zero);
      return;
    }

    final userQueueStart = histLen + (hasCurrent ? 1 : 0);
    final userQueueLen = _userQueue.length;
    if (index >= userQueueStart && index < userQueueStart + userQueueLen) {
      await playUserQueueItem(index - userQueueStart);
      return;
    }

    final contextStart = userQueueStart + userQueueLen;
    final upcomingLen = _upcomingContext.length;
    if (index >= contextStart && index < contextStart + upcomingLen) {
      await playContextQueueItem(index - contextStart);
    }
  }

  /// Inserts [track] to play next (front of userQueue).
  void playNext(Track track) {
    _userQueue.insert(0, track);
    if (_currentTrack == null && _activeContext.isEmpty) {
      _currentTrack = _userQueue.removeAt(0);
      _openTrack(_currentTrack!);
    }
    _notifyState();
  }

  /// Appends [track] to the end of userQueue.
  void addToQueue(Track track) {
    if (_currentTrack == null && _activeContext.isEmpty && _userQueue.isEmpty) {
      _currentTrack = track;
      _openTrack(track);
    } else {
      _userQueue.add(track);
    }
    _notifyState();
  }

  /// Updates metadata of an existing track across all collections.
  void updateTrack(Track updatedTrack) {
    bool changed = false;

    if (_currentTrack?.trackId == updatedTrack.trackId) {
      _currentTrack = updatedTrack;
      changed = true;
    }

    for (int i = 0; i < _userQueue.length; i++) {
      if (_userQueue[i].trackId == updatedTrack.trackId) {
        _userQueue[i] = updatedTrack;
        changed = true;
      }
    }

    for (int i = 0; i < _contextTracks.length; i++) {
      if (_contextTracks[i].trackId == updatedTrack.trackId) {
        _contextTracks[i] = updatedTrack;
        changed = true;
      }
    }

    if (_shuffledContextTracks != null) {
      for (int i = 0; i < _shuffledContextTracks!.length; i++) {
        if (_shuffledContextTracks![i].trackId == updatedTrack.trackId) {
          _shuffledContextTracks![i] = updatedTrack;
          changed = true;
        }
      }
    }

    for (int i = 0; i < _history.length; i++) {
      if (_history[i].trackId == updatedTrack.trackId) {
        _history[i] = updatedTrack;
        changed = true;
      }
    }

    if (changed) {
      _notifyState();
    }
  }

  /// Clears only the tracks in userQueue.
  void clearUserQueue() {
    if (_userQueue.isEmpty) return;
    _userQueue.clear();
    _notifyState();
  }

  /// Clears userQueue and upcoming context except the current track, preserving the immutable history log.
  void clearQueue() {
    _userQueue.clear();
    if (_currentTrack != null) {
      _contextTracks = [_currentTrack!];
      _shuffledContextTracks = null;
      _shuffledOriginalIndices = null;
      _contextIndex = 0;
    } else {
      _contextTracks.clear();
      _shuffledContextTracks = null;
      _shuffledOriginalIndices = null;
      _contextIndex = -1;
    }
    _notifyState();
  }

  /// Reorders an item within the userQueue.
  void reorderUserQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _userQueue.length ||
        newIndex < 0 ||
        newIndex > _userQueue.length ||
        oldIndex == newIndex) return;

    final track = _userQueue.removeAt(oldIndex);
    final targetIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
    _userQueue.insert(targetIdx.clamp(0, _userQueue.length), track);
    _notifyState();
  }

  /// Reorders an item within the upcoming contextQueue.
  void reorderContextQueue(int oldIndex, int newIndex) {
    final upcoming = _upcomingContext;
    if (oldIndex < 0 ||
        oldIndex >= upcoming.length ||
        newIndex < 0 ||
        newIndex > upcoming.length ||
        oldIndex == newIndex) return;

    final track = upcoming[oldIndex];
    final targetContext = _shuffle ? _shuffledContextTracks! : _contextTracks;
    final absOld = _contextIndex + 1 + oldIndex;
    targetContext.removeAt(absOld);
    final targetRelIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final absNew = _contextIndex + 1 + targetRelIdx;
    targetContext.insert(absNew.clamp(0, targetContext.length), track);

    if (_shuffle && _shuffledOriginalIndices != null && absOld < _shuffledOriginalIndices!.length) {
      final origIdx = _shuffledOriginalIndices!.removeAt(absOld);
      _shuffledOriginalIndices!.insert(absNew.clamp(0, _shuffledOriginalIndices!.length), origIdx);
    }

    _notifyState();
  }

  /// Plays item [index] from [userQueue] immediately.
  Future<void> playUserQueueItem(int index) async {
    if (index < 0 || index >= _userQueue.length) return;
    if (_currentTrack != null) {
      _pushHistory(_currentTrack!);
      _pushNavigation(_currentTrack!);
    }

    final target = _userQueue[index];
    _userQueue.removeRange(0, index + 1);

    final active = _activeContext;
    final matchIdx = active.lastIndexOf(target);
    if (matchIdx != -1) {
      _contextIndex = matchIdx;
    }

    _currentTrack = target;
    await _openTrack(target);
    _notifyState();
  }

  /// Plays item [relativeIndex] from upcoming [contextQueue] without mutating userQueue.
  /// Only the currently active track is pushed to history (skipped intermediate tracks are ignored).
  Future<void> playContextQueueItem(int relativeIndex) async {
    final active = _activeContext;
    final targetIndex = _contextIndex + 1 + relativeIndex;
    if (targetIndex < 0 || targetIndex >= active.length) return;

    if (_currentTrack != null) {
      _pushHistory(_currentTrack!);
    }
    _navigationStack.clear();

    _contextIndex = targetIndex;
    _currentTrack = active[_contextIndex];
    await _openTrack(_currentTrack!);
    _notifyState();
  }

  /// Plays a past context track by its [absoluteIndex] in [_activeContext] (pivot model).
  ///
  /// Precondition: [absoluteIndex] must be in [0, _contextIndex - 1].
  /// Invariants preserved:
  ///   • [_userQueue] is NOT touched.
  ///   • [_history] accumulates (immutable log — no truncation).
  ///   • [_contextTracks] order is NOT mutated.
  Future<void> playContextPastItem(int absoluteIndex) async {
    final active = _activeContext;
    if (absoluteIndex < 0 || absoluteIndex >= _contextIndex || active.isEmpty) return;

    if (_currentTrack != null) {
      _pushHistory(_currentTrack!);
    }
    _navigationStack.clear();

    _contextIndex = absoluteIndex;
    _currentTrack = active[_contextIndex];
    await _openTrack(_currentTrack!);
    _notifyState();
  }

  /// Plays item [index] from [history] without altering userQueue and preserving the immutable history log.
  Future<void> playHistoryItem(int index) async {
    if (index < 0 || index >= _history.length) return;

    final targetTrack = _history[index];

    if (_currentTrack?.trackId == targetTrack.trackId) {
      await seek(Duration.zero);
      await play();
      return;
    }

    if (_currentTrack != null) {
      _pushHistory(_currentTrack!);
    }

    final active = _activeContext;
    final matchIdx = active.lastIndexOf(targetTrack);
    if (matchIdx != -1) {
      _navigationStack.clear();
      _contextIndex = matchIdx;
    } else {
      if (_currentTrack != null) {
        _pushNavigation(_currentTrack!);
      }
    }

    _currentTrack = targetTrack;
    await _openTrack(targetTrack);
    _notifyState();
  }

  void setContextName(String name) {
    if (_contextName == name) return;
    _contextName = name;
    _contextNameController.add(name);
  }

  // ── Engine Opener & Persistence ────────────────────────────────────────────

  Future<void> _openTrack(Track track) async {
    await _saveCurrentPlaybackState(
      overrideTrackId: track.trackId,
      overridePositionMs: 0,
    );

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }

    final file = File(track.filePath);
    if (!file.existsSync()) {
      _consecutiveErrors++;
      if (_consecutiveErrors >= _activeContext.length + _userQueue.length + 1) {
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
      await _safeSetActive(true);
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
    } catch (e) {
      Future.delayed(const Duration(milliseconds: 100), () {
        next();
      });
    }
  }

  Future<void> _saveCurrentPlaybackState({
    String? overrideTrackId,
    int? overridePositionMs,
  }) async {
    try {
      final trackId = overrideTrackId ?? _currentTrack?.trackId;
      if (trackId == null) return;

      final posMs = overridePositionMs ?? position.inMilliseconds;
      final queueIds = _contextTracks.map((t) => t.trackId).toList();
      final userIds = _userQueue.map((t) => t.trackId).toList();

      final state = local.PlaybackState()
        ..trackId = trackId
        ..positionMs = posMs
        ..queueTrackIds = queueIds
        ..shuffleModeEnabled = _shuffle
        ..userQueueTrackIds = userIds;

      await _db.savePlaybackState(state);
    } catch (_) {}
  }

  Future<void> savePlaybackStateNow() => _saveCurrentPlaybackState();

  Future<void> hydratePlaybackState() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    try {
      final saved = await _db.getPlaybackState();
      if (saved == null || saved.trackId == null) return;

      final resolvedContext = <Track>[];
      for (final id in saved.queueTrackIds) {
        final t = await _db.getTrackByTrackId(id);
        if (t != null) resolvedContext.add(t);
      }
      final resolvedUserQueue = <Track>[];
      for (final id in saved.userQueueTrackIds) {
        final t = await _db.getTrackByTrackId(id);
        if (t != null) resolvedUserQueue.add(t);
      }

      if (resolvedContext.isEmpty && resolvedUserQueue.isEmpty) return;

      _contextTracks = resolvedContext;
      _userQueue
        ..clear()
        ..addAll(resolvedUserQueue);

      final matchCtxIdx = _contextTracks.indexWhere((t) => t.trackId == saved.trackId);
      if (matchCtxIdx != -1) {
        _contextIndex = matchCtxIdx;
        _currentTrack = _contextTracks[_contextIndex];
      } else {
        final matchUserIdx = _userQueue.indexWhere((t) => t.trackId == saved.trackId);
        if (matchUserIdx != -1) {
          _currentTrack = _userQueue.removeAt(matchUserIdx);
        } else if (_contextTracks.isNotEmpty) {
          _contextIndex = 0;
          _currentTrack = _contextTracks[0];
        }
      }

      if (_currentTrack == null) return;

      final file = File(_currentTrack!.filePath);
      if (!file.existsSync()) return;

      _hydrating = true;
      await _player.open(
        Media(Uri.file(_currentTrack!.filePath).toString()),
        play: false,
      );
      await Future.delayed(const Duration(milliseconds: 300));

      if (saved.shuffleModeEnabled && _contextTracks.isNotEmpty) {
        _shuffle = true;
        final targetIdx = _contextTracks.indexWhere((t) => t.trackId == _currentTrack!.trackId);
        final actualIdx = targetIdx >= 0 ? targetIdx : 0;
        final remainingIndices = List<int>.generate(_contextTracks.length, (i) => i)..removeAt(actualIdx);
        remainingIndices.shuffle(Random());
        _shuffledOriginalIndices = [actualIdx, ...remainingIndices];
        _shuffledContextTracks = _shuffledOriginalIndices!.map((i) => _contextTracks[i]).toList();
        _contextIndex = 0;
        _shuffleController.add(true);
      }

      if (saved.positionMs > 0) {
        await _player.seek(Duration(milliseconds: saved.positionMs));
      }

      _hydrating = false;
      _notifyState();
    } catch (_) {
      _hydrating = false;
    }
  }

  void _notifyState() {
    if (_disposed) return;
    _currentTrackController.add(currentTrack);
    _isPlayingController.add(isPlaying);
    _positionController.add(position);
    _durationController.add(duration);
    _volumeController.add(volume);
    _shuffleController.add(_shuffle);
    _repeatController.add(_repeatMode);
    _queueController.add(queue);
    _historyController.add(history);
    _userQueueController.add(userQueue);
    _contextQueueController.add(contextQueue);
    _pastContextController.add(pastContext);
    _contextNameController.add(_contextName);
    _canSkipNextController.add(canSkipNext);
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _disposed = true;
    await _safeSetActive(false);
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _videoController = null; // release before player disposal
    await _player.dispose();

    await _currentTrackController.close();
    await _isPlayingController.close();
    await _positionController.close();
    await _durationController.close();
    await _volumeController.close();
    await _shuffleController.close();
    await _repeatController.close();
    await _queueController.close();
    await _canSkipNextController.close();
    await _userQueueController.close();
    await _contextQueueController.close();
    await _historyController.close();
    await _pastContextController.close();
    await _contextNameController.close();
  }
}
