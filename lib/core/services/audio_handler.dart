import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../database/local_database.dart';
import '../models/track.dart';
import '../utils/debug_logger.dart';
import 'audio_player_service.dart';

export 'audio_player_service.dart' show PlayerRepeatMode;

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

    // Estado inicial minimalista: idle + sin velocidad.
    // audio_service usará este estado hasta que _emitAtomicState emita
    // el primer PlaybackState real con playing=true / processingState=ready.
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.custom(
          androidIcon: 'drawable/ic_heart_outline',
          label: 'Añadir a Me gusta',
          name: 'toggle_like',
        ),
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.stop,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.idle,
      playing: false,
      // speed = 0 en idle para no confundir a audio_service antes de reproducir.
      speed: 0.0,
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
    ));
  }

  bool _disposed = false;
  DateTime? _lastPositionEmit;
  final List<StreamSubscription> _subscriptions = [];

  void initAfterDatabaseReady() {
    try {
      LocalDatabase.instance.likedTrackIdsNotifier.addListener(_emitAtomicState);
    } catch (e) {
      DebugLogger.log('Error attaching likedTrackIds listener: $e');
    }

    _emitAtomicState();
  }

  void _initSinks() {
    final player = AudioPlayerService.instance;

    // 1. Sync Queue
    _subscriptions.add(player.queueStream.listen((tracks) {
      if (_disposed) return;
      queue.add(tracks.map((t) => _mapTrackToMediaItem(t)).toList());
      _emitAtomicState();
    }));

    // 2. Sync Current Track
    _subscriptions.add(player.currentTrackStream.listen((_) {
      if (_disposed) return;
      _emitAtomicState();
    }));

    // 3. Sync Playing State
    _subscriptions.add(player.isPlayingStream.listen((_) {
      if (_disposed) return;
      _emitAtomicState();
    }));

    // 4. Sync Duration
    _subscriptions.add(player.durationStream.listen((_) {
      if (_disposed) return;
      _emitAtomicState();
    }));

    // 5. Sync Skip availability
    _subscriptions.add(player.canSkipNextStream.listen((_) {
      if (_disposed) return;
      _emitAtomicState();
    }));

    // 6. Position throttle — Android 15 exige ver updatePosition fresco
    //    para no considerar el ForegroundService inactivo y matarlo.
    //    Emitimos PlaybackState cada ~1 segundo durante la reproducción.
    _subscriptions.add(
      player.positionStream
          .where((_) => !_disposed && player.isPlaying)
          // Throttle: solo emitir si han pasado ≥ 800 ms desde la última emisión.
          .transform(
            StreamTransformer.fromHandlers(
              handleData: (pos, sink) {
                final now = DateTime.now();
                if (_lastPositionEmit == null ||
                    now.difference(_lastPositionEmit!).inMilliseconds >= 800) {
                  _lastPositionEmit = now;
                  sink.add(pos);
                }
              },
            ),
          )
          .listen((_) {
            if (_disposed) return;
            _emitAtomicState();
          }),
    );
  }

  Uri? _resolveArtUri(String? coverPath) {
    if (coverPath == null || coverPath.trim().isEmpty) return null;
    try {
      final file = File(coverPath);
      if (file.existsSync() && file.lengthSync() > 0) {
        return Uri.file(file.absolute.path);
      }
    } catch (_) {
      // Catch file-system or path resolution errors cleanly
    }
    return null;
  }

  MediaItem _mapTrackToMediaItem(Track track) {
    final player = AudioPlayerService.instance;
    final coverPath = track.customMetadata.customCoverPath;
    final artUri = _resolveArtUri(coverPath);

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
      artUri: artUri,
      extras: artUri != null ? <String, dynamic>{'artCacheFile': coverPath} : null,
    );
  }

  void _emitAtomicState() {
    if (_disposed) return;
    try {
      final player = AudioPlayerService.instance;
      final currentTrack = player.currentTrack;
      final isPlaying = player.isPlaying;
      final position = player.position;
      final isLiked = currentTrack != null &&
          LocalDatabase.instance.likedTrackIdsNotifier.value.contains(currentTrack.trackId);

      // 1. Sincronización atómica de MediaItem
      if (currentTrack == null) {
        if (mediaItem.value != null) {
          mediaItem.add(null);
          DebugLogger.log('OrpheusAudioHandler: mediaItem.add(null) emitido');
        }
      } else {
        final newItem = _mapTrackToMediaItem(currentTrack);
        if (mediaItem.value == null ||
            mediaItem.value?.id != newItem.id ||
            mediaItem.value?.title != newItem.title ||
            mediaItem.value?.artist != newItem.artist ||
            mediaItem.value?.duration != newItem.duration) {
          mediaItem.add(newItem);
          DebugLogger.log('OrpheusAudioHandler: mediaItem.add -> title: "${newItem.title}", artist: "${newItem.artist}", duration: ${newItem.duration?.inSeconds}s, id: "${newItem.id}"');
        }
      }

      // 2. Control dinámico de "Me gusta"
      final likeControl = MediaControl.custom(
        androidIcon: isLiked ? 'drawable/ic_heart_filled' : 'drawable/ic_heart_outline',
        label: isLiked ? 'Quitar de Me gusta' : 'Añadir a Me gusta',
        name: 'toggle_like',
      );

      // 3. Controles dinámicos nativos: Anterior, Play/Pause, Siguiente, Me gusta
      final controls = [
        MediaControl.skipToPrevious,
        if (isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        likeControl,
      ];

      // processingState es ready mientras haya una pista cargada (reproduciendo o en pausa)
      // Solo transiciona a idle si la cola y la pista están completamente vacías
      final isIdle = player.queue.isEmpty && currentTrack == null;
      final processingStateVal = isIdle ? AudioProcessingState.idle : AudioProcessingState.ready;

      // 4. PlaybackState unificado con velocidad, posición y acciones
      final newState = PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.stop,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingStateVal,
        playing: isPlaying,
        updatePosition: position,
        bufferedPosition: position,
        speed: isPlaying ? 1.0 : 0.0,
        queueIndex: player.currentIndex >= 0 ? player.currentIndex : null,
      );

      // 5. Emisión al stream nativo.
      // El gate de frecuencia para posición está en el throttle del stream (800 ms).
      // Aquí solo filtramos re-emisiones de estado idéntico (sin cambio real).
      final currentVal = playbackState.value;
      final shouldEmit = currentVal.playing != newState.playing ||
          currentVal.processingState != newState.processingState ||
          currentVal.queueIndex != newState.queueIndex ||
          currentVal.controls.length != newState.controls.length ||
          (currentVal.controls.length > 1 &&
              newState.controls.length > 1 &&
              currentVal.controls[1].label != newState.controls[1].label) ||
          // Siempre emitir si hay posición nueva (ya throttleada a 800 ms)
          // para que Android vea updatePosition fresco y no mate el servicio.
          (isPlaying &&
              (currentVal.updatePosition - newState.updatePosition)
                      .abs()
                      .inMilliseconds >=
                  500);

      if (shouldEmit) {
        playbackState.add(newState);
        DebugLogger.log('OrpheusAudioHandler: Estado atómico emitido -> track: "${currentTrack?.displayTitle}", playing: $isPlaying, processingState: $processingStateVal, pos: ${position.inSeconds}s, speed: ${newState.speed}');
      }
    } catch (e, s) {
      DebugLogger.log('OrpheusAudioHandler ERROR en _emitAtomicState: $e\n$s');
    }
  }

  // ── Facade Getters & Streams for UI ──────────────────────────────────────

  Track? get currentTrack => AudioPlayerService.instance.currentTrack;
  bool get isPlaying => AudioPlayerService.instance.isPlaying;
  Duration get position => AudioPlayerService.instance.position;
  Duration get duration => AudioPlayerService.instance.duration;
  double get volume => AudioPlayerService.instance.volume;
  bool get shuffleEnabled => AudioPlayerService.instance.shuffleEnabled;
  bool get repeatEnabled => AudioPlayerService.instance.repeatEnabled;
  PlayerRepeatMode get repeatMode => AudioPlayerService.instance.repeatMode;
  List<Track> get queueTracks => AudioPlayerService.instance.queue;
  int get currentIndex => AudioPlayerService.instance.currentIndex;
  bool get canSkipNext => AudioPlayerService.instance.canSkipNext;
  bool get canSkipPrevious => AudioPlayerService.instance.canSkipPrevious;

  Stream<Track?> get currentTrackStream => AudioPlayerService.instance.currentTrackStream;
  Stream<bool> get isPlayingStream => AudioPlayerService.instance.isPlayingStream;
  Stream<Duration> get positionStream => AudioPlayerService.instance.positionStream;
  Stream<Duration> get durationStream => AudioPlayerService.instance.durationStream;
  Stream<double> get volumeStream => AudioPlayerService.instance.volumeStream;
  Stream<bool> get shuffleStream => AudioPlayerService.instance.shuffleStream;
  Stream<PlayerRepeatMode> get repeatStream => AudioPlayerService.instance.repeatStream;
  Stream<List<Track>> get queueTracksStream => AudioPlayerService.instance.queueStream;
  Stream<bool> get canSkipNextStream => AudioPlayerService.instance.canSkipNextStream;

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

  Future<void> next() => skipToNext();

  Future<void> previous() => skipToPrevious();

  Future<void> skipToIndex(int index) => AudioPlayerService.instance.skipToIndex(index);

  Future<void> setVolume(double volume) => AudioPlayerService.instance.setVolume(volume);

  void toggleShuffle() => AudioPlayerService.instance.toggleShuffle();

  void setShuffle(bool enable) {
    if (AudioPlayerService.instance.shuffleEnabled != enable) {
      AudioPlayerService.instance.toggleShuffle();
    }
  }

  void toggleRepeat() => AudioPlayerService.instance.toggleRepeat();

  void setPlayerRepeatMode(PlayerRepeatMode mode) {
    while (AudioPlayerService.instance.repeatMode != mode) {
      AudioPlayerService.instance.toggleRepeat();
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        setPlayerRepeatMode(PlayerRepeatMode.off);
        break;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        setPlayerRepeatMode(PlayerRepeatMode.playlist);
        break;
      case AudioServiceRepeatMode.one:
        setPlayerRepeatMode(PlayerRepeatMode.single);
        break;
    }
  }

  void playNext(Track track) {
    AudioPlayerService.instance.playNext(track);
  }

  void addToQueue(Track track) {
    AudioPlayerService.instance.addToQueue(track);
  }

  void addToQueueTrack(Track track) {
    AudioPlayerService.instance.addToQueue(track);
  }

  void clearQueue() {
    AudioPlayerService.instance.clearQueue();
  }

  Future<void> stopAndReset() async {
    await AudioPlayerService.instance.stopAndReset();
  }

  Future<void> savePlaybackStateNow() async {
    await AudioPlayerService.instance.savePlaybackStateNow();
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
            _emitAtomicState();
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
      LocalDatabase.instance.likedTrackIdsNotifier.removeListener(_emitAtomicState);
    } catch (_) {}
    for (var sub in _subscriptions) {
      sub.cancel();
    }
  }
}
