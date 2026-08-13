import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'audio_player_service.dart';
import '../database/local_database.dart';
import '../models/track.dart';
import '../utils/debug_logger.dart';

/// Bridges the Flutter audio engine (media_kit) to the native OS Media Session controls.
/// Handles background commands from OS lock screen, notifications, and Bluetooth devices.
class OrpheusAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  static OrpheusAudioHandler? _instance;

  /// Global singleton instance of [OrpheusAudioHandler] initialized by [AudioService.init].
  static OrpheusAudioHandler get instance {
    if (_instance == null) {
      throw StateError('OrpheusAudioHandler has not been initialized yet.');
    }
    return _instance!;
  }

  OrpheusAudioHandler() {
    _instance = this;
    DebugLogger.log('OrpheusAudioHandler: Instancia del Handler creada en memoria.');
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
    DebugLogger.log('OrpheusAudioHandler: Estado inicial emitido (playing: false, ready).');
  }

  bool _disposed = false;
  bool _isUpdatePending = false;
  final List<StreamSubscription> _subscriptions = [];

  void initAfterDatabaseReady() {
    DebugLogger.log('OrpheusAudioHandler.initAfterDatabaseReady() iniciado...');
    try {
      LocalDatabase.instance.likedTrackIdsNotifier.addListener(_updatePlaybackState);
      DebugLogger.log('OrpheusAudioHandler: Listener likedTrackIds adjuntado.');
    } catch (e) {
      DebugLogger.log('OrpheusAudioHandler ERROR adjuntando listener likedTrackIds: $e');
    }

    final player = AudioPlayerService.instance;
    final current = player.currentTrack;
    if (current != null) {
      final item = _mapTrackToMediaItem(current);
      mediaItem.add(item);
      DebugLogger.log('OrpheusAudioHandler: MediaItem inicial cargado (id: ${item.id}, title: "${item.title}").');
    }
    _updatePlaybackState();
    DebugLogger.log('OrpheusAudioHandler.initAfterDatabaseReady() finalizado.');
  }

  void _initSinks() {
    final player = AudioPlayerService.instance;

    // 1. Sincronizar cola de reproducción
    _subscriptions.add(player.queueStream.listen(
      (tracks) {
        try {
          queue.add(tracks.map((t) => _mapTrackToMediaItem(t)).toList());
        } catch (e, s) {
          debugPrint('Error updating queue in AudioHandler: $e\n$s');
        }
      },
      onError: (err) => debugPrint('Error in queueStream: $err'),
    ));

    // 2. Sincronizar track actual
    _subscriptions.add(player.currentTrackStream.listen(
      (track) {
        try {
          if (track == null) {
            mediaItem.add(null);
          } else {
            mediaItem.add(_mapTrackToMediaItem(track));
          }
          _updatePlaybackState();
        } catch (e, s) {
          debugPrint('Error updating currentTrack in AudioHandler: $e\n$s');
        }
      },
      onError: (err) => debugPrint('Error in currentTrackStream: $err'),
    ));

    // 3. Sincronizar estado de reproducción (play/pause)
    _subscriptions.add(player.isPlayingStream.listen(
      (_) {
        try {
          _updatePlaybackState();
        } catch (e, s) {
          debugPrint('Error updating isPlaying in AudioHandler: $e\n$s');
        }
      },
      onError: (err) => debugPrint('Error in isPlayingStream: $err'),
    ));

    // 4. Sincronizar duración — re-emitir MediaItem con la duración real
    _subscriptions.add(player.durationStream.listen(
      (_) {
        try {
          final track = player.currentTrack;
          if (track != null) {
            mediaItem.add(_mapTrackToMediaItem(track));
          }
          _updatePlaybackState();
        } catch (e, s) {
          debugPrint('Error updating duration in AudioHandler: $e\n$s');
        }
      },
      onError: (err) => debugPrint('Error in durationStream: $err'),
    ));

    // Note: the liked-track listener (LocalDatabase.instance.likedTrackIdsNotifier)
    // is attached in initAfterDatabaseReady(), NOT here, because _initSinks() is
    // called from the constructor which runs before LocalDatabase is initialized.
  }

  MediaItem _mapTrackToMediaItem(Track track) {
    final player = AudioPlayerService.instance;
    final coverPath = track.customMetadata.customCoverPath;
    final hasArt = coverPath != null &&
        coverPath.isNotEmpty &&
        File(coverPath).existsSync();

    final safeId = track.trackId.trim().isNotEmpty
        ? track.trackId.trim()
        : 'unknown_track_${DateTime.now().millisecondsSinceEpoch}';

    final safeTitle = track.displayTitle.trim().isNotEmpty
        ? track.displayTitle.trim()
        : (track.title?.trim().isNotEmpty == true
            ? track.title!.trim()
            : 'Pista desconocida');

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
    if (_disposed) return;
    try {
      final player = AudioPlayerService.instance;
      final isPlaying = player.isPlaying;
      final currentTrack = player.currentTrack;
      final isLiked = currentTrack != null &&
          LocalDatabase.instance.likedTrackIdsNotifier.value.contains(currentTrack.trackId);

      // Always re-emit the current mediaItem — audio_service requires at least one
      // unconditional emission to start the Foreground Service. The id-equality guard
      // was silently suppressing this emission on repeated playback of the same track.
      if (currentTrack != null) {
        final newItem = _mapTrackToMediaItem(currentTrack);
        mediaItem.add(newItem);
        DebugLogger.log('OrpheusAudioHandler: mediaItem.add forzado -> id: ${newItem.id}, title: "${newItem.title}"');
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

      playbackState.add(newState);
      DebugLogger.log('OrpheusAudioHandler: playbackState.add -> playing: ${newState.playing}, state: ready, pos: ${player.position.inSeconds}s');
    } catch (e, s) {
      DebugLogger.log('OrpheusAudioHandler ERROR en _executeUpdatePlaybackState: $e\n$s');
    }
  }

  // ── Delegated Actions from OS / Bluetooth / UI controls ─────────────────

  /// High-level API used by UI components to load and play a queue of tracks.
  ///
  /// Immediately injects the [MediaItem] of the initial track before calling the
  /// audio engine so that [audio_service] has all required metadata to start the
  /// Foreground Service without waiting for stream events to propagate.
  Future<void> loadQueue(List<Track> tracks, {int initialIndex = 0}) async {
    DebugLogger.log('OrpheusAudioHandler.loadQueue() invocado con ${tracks.length} tracks, index: $initialIndex');

    if (tracks.isNotEmpty && initialIndex >= 0 && initialIndex < tracks.length) {
      final initialTrack = tracks[initialIndex];
      final initialItem = _mapTrackToMediaItem(initialTrack);
      mediaItem.add(initialItem);
      DebugLogger.log('OrpheusAudioHandler: mediaItem forzado en loadQueue -> id: ${initialItem.id}, title: "${initialItem.title}"');
    }

    await AudioPlayerService.instance.loadPlaylist(tracks, initialIndex: initialIndex);
  }

  /// High-level API used by UI components to play a single track with optional context queue.
  Future<void> playTrack(Track track, {List<Track>? contextQueue}) async {
    DebugLogger.log('OrpheusAudioHandler.playTrack() invocado para track: "${track.displayTitle}"');
    if (contextQueue != null && contextQueue.isNotEmpty) {
      final index = contextQueue.indexWhere((t) => t.trackId == track.trackId);
      await loadQueue(contextQueue, initialIndex: index == -1 ? 0 : index);
    } else {
      await loadQueue([track], initialIndex: 0);
    }
  }

  /// Toggles playback between playing and paused.
  Future<void> togglePlayPause() async {
    DebugLogger.log('OrpheusAudioHandler.togglePlayPause() invocado');
    if (AudioPlayerService.instance.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// Inserts a track to be played next in the queue.
  void playNext(Track track) {
    DebugLogger.log('OrpheusAudioHandler.playNext() invocado para "${track.displayTitle}"');
    AudioPlayerService.instance.playNext(track);
  }

  /// Appends a track to the end of the current queue.
  void addToQueueTrack(Track track) {
    DebugLogger.log('OrpheusAudioHandler.addToQueueTrack() invocado para "${track.displayTitle}"');
    AudioPlayerService.instance.addToQueue(track);
  }

  @override
  Future<void> play() async {
    DebugLogger.log('OrpheusAudioHandler.play() [OS/UI Action] invocado -> enviando play a media_kit');
    await AudioPlayerService.instance.play();
  }

  @override
  Future<void> pause() async {
    DebugLogger.log('OrpheusAudioHandler.pause() [OS/UI Action] invocado -> enviando pause a media_kit');
    await AudioPlayerService.instance.pause();
  }

  @override
  Future<void> stop() async {
    DebugLogger.log('OrpheusAudioHandler.stop() [OS/UI Action] invocado -> enviando stop a media_kit');
    await AudioPlayerService.instance.stop();
  }

  @override
  Future<void> seek(Duration position) => AudioPlayerService.instance.seek(position);

  @override
  Future<void> skipToNext() => AudioPlayerService.instance.next();

  @override
  Future<void> skipToPrevious() => AudioPlayerService.instance.previous();

  @override
  Future<void> skipToQueueItem(int index) =>
      AudioPlayerService.instance.loadPlaylist(AudioPlayerService.instance.queue, initialIndex: index);

  /// Handles custom actions from the media notification (such as toggle_like)
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
        debugPrint('Error toggling like from notification customAction: $e\n$s');
      }
    }
    return super.customAction(name, extras);
  }

  /// Called by Android when the user swipes the app from Recents.
  ///
  /// Safe cleanup: stops playback, releases audio focus, and stops the service
  /// cleanly without throwing uncaught exceptions or triggering native OS kills.
  @override
  Future<void> onTaskRemoved() async {
    debugPrint('OrpheusAudioHandler: onTaskRemoved triggered cleanly');
    try {
      await AudioPlayerService.instance.stop();
    } catch (e, s) {
      debugPrint('Error stopping AudioPlayerService in onTaskRemoved: $e\n$s');
    }
    try {
      await super.stop();
    } catch (e, s) {
      debugPrint('Error in super.stop() in onTaskRemoved: $e\n$s');
    }
  }

  void dispose() {
    _disposed = true;
    try {
      LocalDatabase.instance.likedTrackIdsNotifier.removeListener(_updatePlaybackState);
    } catch (e) {
      // Ignore during teardown
    }
    for (var sub in _subscriptions) {
      sub.cancel();
    }
  }
}
