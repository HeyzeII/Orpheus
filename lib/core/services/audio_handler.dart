import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'audio_player_service.dart';
import '../models/track.dart';

/// Bridges the Flutter audio engine (media_kit) to the native OS Media Session controls.
/// Handles background commands from OS lock screen, notifications, and Bluetooth devices.
class OrpheusAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  OrpheusAudioHandler() {
    _initSinks();
  }

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

    // 2. Sincronizar track actual y duración
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
  }

  MediaItem _mapTrackToMediaItem(Track track) {
    final player = AudioPlayerService.instance;
    final coverPath = track.customMetadata.customCoverPath;
    final hasArt = coverPath != null && coverPath.isNotEmpty && File(coverPath).existsSync();

    return MediaItem(
      id: track.trackId,
      album: track.displayAlbum,
      title: track.displayTitle,
      artist: track.displayArtist,
      duration: player.currentTrack?.trackId == track.trackId ? player.duration : null,
      artUri: hasArt ? Uri.file(coverPath) : null,
    );
  }

  void _updatePlaybackState() {
    try {
      final player = AudioPlayerService.instance;
      final isPlaying = player.isPlaying;

      playbackState.add(PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (isPlaying) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: player.currentTrack == null
            ? AudioProcessingState.idle
            : AudioProcessingState.ready,
        playing: isPlaying,
        updatePosition: player.position,
        bufferedPosition: player.position,
        speed: 1.0,
      ));
    } catch (e) {
      debugPrint('Safely caught error updating playbackState: $e');
    }
  }

  // ── Delegated Actions from OS / Bluetooth controls ───────────────────────

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
    for (var sub in _subscriptions) {
      sub.cancel();
    }
  }
}
