import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../database/local_database.dart';
import '../models/track.dart';
import '../utils/debug_logger.dart';
import 'audio_player_service.dart';

/// Canonical [AudioHandler] bridging media_kit to Android/iOS MediaSession.
class OrpheusAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  static OrpheusAudioHandler? _instance;

  /// Returns true if [OrpheusAudioHandler] has been initialized.
  static bool get hasInstance => _instance != null;

  /// Global instance of [OrpheusAudioHandler].
  static OrpheusAudioHandler get instance {
    if (_instance == null) {
      throw StateError('OrpheusAudioHandler has not been initialized yet.');
    }
    return _instance!;
  }

  OrpheusAudioHandler() {
    _instance = this;
    DebugLogger.log('OrpheusAudioHandler: Instancia del Handler creada.');
    _initSinks();

    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: false,
    ));
  }

  bool _disposed = false;
  bool _isUpdatePending = false;
  final List<StreamSubscription> _subscriptions = [];

  void initAfterDatabaseReady() {
    try {
      LocalDatabase.instance.likedTrackIdsNotifier.addListener(_updatePlaybackState);
    } catch (e) {
      DebugLogger.log('Error attaching likedTrackIds listener: $e');
    }

    final current = AudioPlayerService.instance.currentTrack;
    if (current != null) {
      mediaItem.add(_mapTrackToMediaItem(current));
    }
    _updatePlaybackState();
  }

  void _initSinks() {
    final player = AudioPlayerService.instance;

    // 1. Sync Queue
    _subscriptions.add(player.queueStream.listen(
      (tracks) {
        if (_disposed) return;
        queue.add(tracks.map((t) => _mapTrackToMediaItem(t)).toList());
      },
    ));

    // 2. Sync Current Track (only update mediaItem if track changed)
    _subscriptions.add(player.currentTrackStream.listen(
      (track) {
        if (_disposed) return;
        if (track == null) {
          mediaItem.add(null);
        } else {
          final newItem = _mapTrackToMediaItem(track);
          if (mediaItem.value?.id != newItem.id || mediaItem.value?.duration != newItem.duration) {
            mediaItem.add(newItem);
          }
        }
        _updatePlaybackState();
      },
    ));

    // 3. Sync Playing State
    _subscriptions.add(player.isPlayingStream.listen(
      (_) {
        if (_disposed) return;
        _updatePlaybackState();
      },
    ));

    // 4. Sync Duration
    _subscriptions.add(player.durationStream.listen(
      (_) {
        if (_disposed) return;
        final track = player.currentTrack;
        if (track != null) {
          final newItem = _mapTrackToMediaItem(track);
          if (mediaItem.value?.duration != newItem.duration) {
            mediaItem.add(newItem);
          }
        }
        _updatePlaybackState();
      },
    ));
  }

  MediaItem _mapTrackToMediaItem(Track track) {
    final player = AudioPlayerService.instance;
    final coverPath = track.customMetadata.customCoverPath;
    final hasArt = coverPath != null &&
        coverPath.isNotEmpty &&
        File(coverPath).existsSync();

    final safeId = track.trackId.trim().isNotEmpty
        ? track.trackId.trim()
        : 'track_${DateTime.now().millisecondsSinceEpoch}';

    final safeTitle = track.displayTitle.trim().isNotEmpty
        ? track.displayTitle.trim()
        : 'Pista desconocida';

    final safeArtist = track.displayArtist.trim().isNotEmpty
        ? track.displayArtist.trim()
        : 'Artista desconocido';

    final safeAlbum = track.displayAlbum.trim().isNotEmpty
        ? track.displayAlbum.trim()
        : 'Álbum desconocido';

    return MediaItem(
      id: safeId,
      album: safeAlbum,
      title: safeTitle,
      artist: safeArtist,
      duration: player.currentTrack?.trackId == track.trackId
          ? player.duration
          : null,
      artUri: hasArt ? Uri.file(coverPath) : null,
      extras: hasArt ? <String, dynamic>{'artCacheFile': coverPath} : null,
    );
  }

  void _updatePlaybackState() {
    if (_disposed) return;
    if (_isUpdatePending) return;

    _isUpdatePending = true;
    scheduleMicrotask(() {
      _isUpdatePending = false;
      _executeUpdatePlaybackState();
    });
  }

  void _executeUpdatePlaybackState() {
    DebugLogger.log('[TRAZA] _executeUpdatePlaybackState() — isPlaying: ${AudioPlayerService.instance.isPlaying}, mediaItem: "${mediaItem.value?.title}"');
    if (_disposed) return;
    try {
      final player = AudioPlayerService.instance;
      final isPlaying = player.isPlaying;
      final currentTrack = player.currentTrack;
      final isLiked = currentTrack != null &&
          LocalDatabase.instance.likedTrackIdsNotifier.value.contains(currentTrack.trackId);

      // Ensure mediaItem is set before state push if missing
      if (currentTrack != null && mediaItem.value == null) {
        mediaItem.add(_mapTrackToMediaItem(currentTrack));
      }

      final likeControl = MediaControl.custom(
        androidIcon: isLiked ? 'drawable/ic_heart_filled' : 'drawable/ic_heart_empty',
        label: isLiked ? 'Quitar de Me gusta' : 'Añadir a Me gusta',
        name: 'toggle_like',
      );

      final newState = PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          likeControl,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.ready,
        playing: isPlaying,
        updatePosition: player.position,
        bufferedPosition: player.position,
        speed: 1.0,
      );

      // Deduplicate: only add to stream if values actually changed
      final currentVal = playbackState.value;
      if (currentVal.playing != newState.playing ||
          currentVal.processingState != newState.processingState ||
          (currentVal.updatePosition - newState.updatePosition).abs().inSeconds >= 1) {
        playbackState.add(newState);
        DebugLogger.log('OrpheusAudioHandler: playbackState.add -> playing: ${newState.playing}, pos: ${player.position.inSeconds}s');
      }
    } catch (e, s) {
      DebugLogger.log('OrpheusAudioHandler ERROR en _executeUpdatePlaybackState: $e\n$s');
    }
  }

  // ── Delegated Actions from OS / Bluetooth / UI controls ─────────────────

  Future<void> loadQueue(List<Track> tracks, {int initialIndex = 0}) async {
    if (tracks.isNotEmpty && initialIndex >= 0 && initialIndex < tracks.length) {
      final initialTrack = tracks[initialIndex];
      mediaItem.add(_mapTrackToMediaItem(initialTrack));
    }
    await AudioPlayerService.instance.loadPlaylist(tracks, initialIndex: initialIndex);
  }

  Future<void> playTrack(Track track, {List<Track>? contextQueue}) async {
    if (contextQueue != null && contextQueue.isNotEmpty) {
      final index = contextQueue.indexWhere((t) => t.trackId == track.trackId);
      await loadQueue(contextQueue, initialIndex: index == -1 ? 0 : index);
    } else {
      await loadQueue([track], initialIndex: 0);
    }
  }

  Future<void> togglePlayPause() async {
    if (AudioPlayerService.instance.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  void playNext(Track track) {
    AudioPlayerService.instance.playNext(track);
  }

  void addToQueueTrack(Track track) {
    AudioPlayerService.instance.addToQueue(track);
  }

  @override
  Future<void> play() async {
    DebugLogger.log('[TRAZA] OrpheusAudioHandler.play() invocado — delegando a AudioPlayerService.play()');
    await AudioPlayerService.instance.play();
  }

  @override
  Future<void> pause() async {
    DebugLogger.log('[TRAZA] OrpheusAudioHandler.pause() invocado — delegando a AudioPlayerService.pause()');
    await AudioPlayerService.instance.pause();
  }

  @override
  Future<void> stop() async {
    await AudioPlayerService.instance.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await AudioPlayerService.instance.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    await AudioPlayerService.instance.next();
  }

  @override
  Future<void> skipToPrevious() async {
    await AudioPlayerService.instance.previous();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await AudioPlayerService.instance.loadPlaylist(AudioPlayerService.instance.queue, initialIndex: index);
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'toggle_like') {
      try {
        final currentTrack = AudioPlayerService.instance.currentTrack;
        if (currentTrack != null) {
          final db = LocalDatabase.instance;
          final likedPlaylist = await db.getPlaylistById('__liked__');
          if (likedPlaylist != null) {
            final isLiked = db.likedTrackIdsNotifier.value.contains(currentTrack.trackId);
            if (isLiked) {
              await db.removeTrackFromPlaylist(playlist: likedPlaylist, trackId: currentTrack.trackId);
            } else {
              await db.addTrackToPlaylist(playlist: likedPlaylist, trackId: currentTrack.trackId);
            }
          }
        }
      } catch (e, s) {
        debugPrint('Error toggling like from customAction: $e\n$s');
      }
    }
    return super.customAction(name, extras);
  }

  @override
  Future<void> onTaskRemoved() async {
    try {
      await AudioPlayerService.instance.stop();
    } catch (_) {}
    try {
      await super.stop();
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    try {
      LocalDatabase.instance.likedTrackIdsNotifier.removeListener(_updatePlaybackState);
    } catch (_) {}
    for (var sub in _subscriptions) {
      sub.cancel();
    }
  }
}
