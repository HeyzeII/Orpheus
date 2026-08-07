import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'audio_player_service.dart';
import '../database/local_database.dart';
import '../models/track.dart';

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
    _initSinks();

    // Prime initial mediaItem & playbackState on initialization
    final player = AudioPlayerService.instance;
    final current = player.currentTrack;
    if (current != null) {
      mediaItem.add(_mapTrackToMediaItem(current));
    }
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (player.isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: player.isPlaying,
    ));
  }

  bool _disposed = false;
  final List<StreamSubscription> _subscriptions = [];

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

    // 5. Sincronizar estado de favoritos ("Me gusta")
    LocalDatabase.instance.likedTrackIdsNotifier.addListener(_updatePlaybackState);
  }

  MediaItem _mapTrackToMediaItem(Track track) {
    final player = AudioPlayerService.instance;
    final coverPath = track.customMetadata.customCoverPath;
    final hasArt = coverPath != null &&
        coverPath.isNotEmpty &&
        File(coverPath).existsSync();

    return MediaItem(
      id: track.trackId,
      album: track.displayAlbum,
      title: track.displayTitle,
      artist: track.displayArtist,
      duration: player.currentTrack?.trackId == track.trackId
          ? player.duration
          : null,
      artUri: hasArt ? Uri.file(coverPath) : null,
      extras: hasArt ? <String, dynamic>{'artCacheFile': coverPath} : null,
    );
  }

  void _updatePlaybackState() {
    if (_disposed) return;
    try {
      final player = AudioPlayerService.instance;
      final isPlaying = player.isPlaying;
      final currentTrack = player.currentTrack;
      final isLiked = currentTrack != null &&
          LocalDatabase.instance.likedTrackIdsNotifier.value.contains(currentTrack.trackId);

      // Ensure mediaItem is set with active track metadata before pushing state
      if (currentTrack != null) {
        final newItem = _mapTrackToMediaItem(currentTrack);
        if (mediaItem.value?.id != newItem.id || mediaItem.value?.duration != newItem.duration) {
          mediaItem.add(newItem);
        }
      }

      final likeControl = MediaControl.custom(
        androidIcon: isLiked ? 'drawable/ic_heart_filled' : 'drawable/ic_heart_empty',
        label: isLiked ? 'Quitar de Me gusta' : 'Añadir a Me gusta',
        name: 'toggle_like',
      );

      playbackState.add(PlaybackState(
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
      ));
    } catch (e) {
      debugPrint('Safely caught error updating playbackState: $e');
    }
  }

  // ── Delegated Actions from OS / Bluetooth / UI controls ─────────────────

  /// High-level API used by UI components to load and play a queue of tracks.
  Future<void> loadQueue(List<Track> tracks, {int initialIndex = 0}) async {
    await AudioPlayerService.instance.loadPlaylist(tracks, initialIndex: initialIndex);
  }

  /// High-level API used by UI components to play a single track with optional context queue.
  Future<void> playTrack(Track track, {List<Track>? contextQueue}) async {
    if (contextQueue != null && contextQueue.isNotEmpty) {
      final index = contextQueue.indexWhere((t) => t.trackId == track.trackId);
      await loadQueue(contextQueue, initialIndex: index == -1 ? 0 : index);
    } else {
      await loadQueue([track], initialIndex: 0);
    }
  }

  /// Toggles playback between playing and paused.
  Future<void> togglePlayPause() async {
    if (AudioPlayerService.instance.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> play() => AudioPlayerService.instance.play();

  @override
  Future<void> pause() => AudioPlayerService.instance.pause();

  @override
  Future<void> stop() => AudioPlayerService.instance.stop();

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
