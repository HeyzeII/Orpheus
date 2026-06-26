import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:media_kit/media_kit.dart' hide Track;

import '../database/local_database.dart';
import '../models/track.dart';

/// Singleton service managing the native audio player engine, play queue,
/// and automated playback statistics tracking.
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
  int _currentIndex = -1;
  bool _shuffle = false;
  bool _repeat = false;

  int _consecutiveErrors = 0;

  // ── Stream Controllers ─────────────────────────────────────────────────────

  final _currentTrackController = StreamController<Track?>.broadcast();
  final _isPlayingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _volumeController = StreamController<double>.broadcast();
  final _shuffleController = StreamController<bool>.broadcast();
  final _repeatController = StreamController<bool>.broadcast();

  final List<StreamSubscription> _subscriptions = [];

  // ── Initialization ─────────────────────────────────────────────────────────

  void _init() {
    _player = Player();

    // Pipe native media_kit streams to our broadcast streams
    _subscriptions.add(_player.stream.playing.listen((playing) {
      _isPlayingController.add(playing);
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

    // Auto-advance and statistics logging on completion
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

        if (_repeat) {
          // Repeat current track (repeat-one style)
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

  bool get isPlaying => _player.state.playing;

  Duration get position => _player.state.position;

  Duration get duration => _player.state.duration;

  /// Volume represented as a range from `0.0` (muted) to `1.0` (max).
  double get volume => _player.state.volume / 100.0;

  bool get shuffleEnabled => _shuffle;

  bool get repeatEnabled => _repeat;

  List<Track> get queue => List.unmodifiable(_queue);

  int get currentIndex => _currentIndex;

  // ── Streams for UI ─────────────────────────────────────────────────────────

  Stream<Track?> get currentTrackStream => _currentTrackController.stream;

  Stream<bool> get isPlayingStream => _isPlayingController.stream;

  Stream<Duration> get positionStream => _positionController.stream;

  Stream<Duration> get durationStream => _durationController.stream;

  Stream<double> get volumeStream => _volumeController.stream;

  Stream<bool> get shuffleStream => _shuffleController.stream;

  Stream<bool> get repeatStream => _repeatController.stream;

  // ── Control API ────────────────────────────────────────────────────────────

  /// Replaces the current queue with [tracks] and starts playing at [initialIndex].
  Future<void> loadPlaylist(List<Track> tracks, {int initialIndex = 0}) async {
    _queue.clear();
    _queue.addAll(tracks);
    _consecutiveErrors = 0;

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
    await _playIndex(startIndex);
  }

  Future<void> play() async {
    await _player.play();
    _notifyState();
  }

  Future<void> pause() async {
    await _player.pause();
    _notifyState();
  }

  Future<void> stop() async {
    await _player.stop();
    _currentIndex = -1;
    _notifyState();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _notifyState();
  }

  /// Sets volume. Expects a range between `0.0` (muted) and `1.0` (max).
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    await _player.setVolume(clamped * 100.0);
    _volumeController.add(clamped);
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    _shuffleController.add(_shuffle);
  }

  void toggleRepeat() {
    _repeat = !_repeat;
    _repeatController.add(_repeat);
  }

  /// Advances to the next track in the queue, handling shuffle options.
  Future<void> next() async {
    if (_queue.isEmpty) return;

    if (_shuffle) {
      final nextIndex = Random().nextInt(_queue.length);
      await _playIndex(nextIndex);
    } else {
      final nextIndex = _currentIndex + 1;
      if (nextIndex >= _queue.length) {
        if (_repeat) {
          await _playIndex(0); // loop back
        } else {
          await stop();
        }
      } else {
        await _playIndex(nextIndex);
      }
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

    if (_shuffle) {
      final prevIndex = Random().nextInt(_queue.length);
      await _playIndex(prevIndex);
    } else {
      final prevIndex = _currentIndex - 1;
      if (prevIndex < 0) {
        if (_repeat) {
          await _playIndex(_queue.length - 1);
        } else {
          await seek(Duration.zero);
        }
      } else {
        await _playIndex(prevIndex);
      }
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
      if (_repeat) {
        _currentIndex = 0;
      } else {
        await stop();
        return;
      }
    } else {
      _currentIndex = index;
    }

    final track = _queue[_currentIndex];
    final file = File(track.filePath);

    // Strict handling of missing files
    if (!file.existsSync()) {
      _consecutiveErrors++;
      if (_consecutiveErrors >= _queue.length) {
        // Prevent infinite loop if all files in the playlist are missing
        _consecutiveErrors = 0;
        await stop();
        return;
      }

      // Skip this missing file and trigger next automatically
      _currentTrackController.add(null);
      Future.delayed(const Duration(milliseconds: 100), () {
        next();
      });
      return;
    }

    _consecutiveErrors = 0;

    try {
      await _player.open(Media(track.filePath), play: true);
      _notifyState();
    } catch (e) {
      // Jump to next file if playback fails to initialize
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
    _repeatController.add(_repeat);
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
  }
}
