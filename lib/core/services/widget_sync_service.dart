import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../database/local_database.dart';
import '../models/track.dart';
import '../utils/debug_logger.dart';
import 'audio_player_service.dart';
import 'media_cache_service.dart';

/// Top-level background callback triggered by HomeWidgetBackgroundReceiver
/// when user taps interactive elements (like the favorite button) on native widgets.
@pragma('vm:entry-point')
Future<void> orpheusWidgetBackgroundCallback(Uri? uri) async {
  if (uri != null && (uri.host == 'toggle_like' || uri.toString().contains('toggle_like'))) {
    try {
      final currentTrack = AudioPlayerService.instance.currentTrack;
      if (currentTrack != null) {
        await LocalDatabase.instance.toggleLikeOptimistic(currentTrack.trackId);
        await WidgetSyncService.instance.syncLikeState();
      }
    } catch (e) {
      DebugLogger.log('orpheusWidgetBackgroundCallback: Error al procesar toggle_like: $e');
    }
  }
}

/// Singleton service that reacts to changes in [AudioPlayerService] and [LocalDatabase]
/// to synchronize metadata, playback state, like status, and album art with
/// the native Android home screen widgets (OrpheusWidgetProvider & OrpheusCompactWidgetProvider).
class WidgetSyncService {
  WidgetSyncService._internal({
    AudioPlayerService? playerService,
    LocalDatabase? database,
    MediaCacheService? mediaCache,
  })  : _playerService = playerService ?? AudioPlayerService.instance,
        _database = database ?? LocalDatabase.instance,
        _mediaCache = mediaCache ?? MediaCacheService.instance;

  static final WidgetSyncService instance = WidgetSyncService._internal();

  factory WidgetSyncService({
    AudioPlayerService? playerService,
    LocalDatabase? database,
    MediaCacheService? mediaCache,
  }) {
    if (playerService != null || database != null || mediaCache != null) {
      return WidgetSyncService._internal(
        playerService: playerService,
        database: database,
        mediaCache: mediaCache,
      );
    }
    return instance;
  }

  /// Class name for the 4x3 full-art immersive widget.
  static const String androidWidgetProvider = 'OrpheusWidgetProvider';

  /// Class name for the 4x1 horizontal compact widget.
  static const String androidCompactWidgetProvider = 'OrpheusCompactWidgetProvider';

  final AudioPlayerService _playerService;
  final LocalDatabase _database;
  final MediaCacheService _mediaCache;

  StreamSubscription<Track?>? _trackSub;
  StreamSubscription<bool>? _playingSub;
  VoidCallback? _likeListener;
  bool _isInitialized = false;

  /// Whether the synchronization service has been initialized.
  bool get isInitialized => _isInitialized;

  /// Initializes reactive subscriptions to audio and database state.
  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    // Register background interactivity callback for native widget clicks
    try {
      unawaited(
        HomeWidget.registerInteractivityCallback(orpheusWidgetBackgroundCallback)
            .catchError((e) {
          DebugLogger.log('WidgetSyncService: Error registering interactivity callback: $e');
          return false;
        }),
      );
    } catch (e) {
      DebugLogger.log('WidgetSyncService: Error registering interactivity callback: $e');
    }

    // 1. React to track changes
    _trackSub = _playerService.currentTrackStream.listen((track) {
      unawaited(syncTrackData(track));
    });

    // 2. React to isPlaying changes
    _playingSub = _playerService.isPlayingStream.listen((isPlaying) {
      unawaited(_syncPlaybackState(isPlaying));
    });

    // 3. React to liked tracks database updates
    _likeListener = () {
      unawaited(syncLikeState());
    };
    _database.likedTrackIdsNotifier.addListener(_likeListener!);

    // Initial sync
    unawaited(syncTrackData(_playerService.currentTrack));
  }

  /// Cancels all active listeners and resets state.
  void dispose() {
    _trackSub?.cancel();
    _trackSub = null;
    _playingSub?.cancel();
    _playingSub = null;
    if (_likeListener != null) {
      _database.likedTrackIdsNotifier.removeListener(_likeListener!);
      _likeListener = null;
    }
    _isInitialized = false;
  }

  /// Synchronizes full track metadata, artwork and like state to all native widgets.
  Future<void> syncTrackData([Track? track]) async {
    final targetTrack = track ?? _playerService.currentTrack;
    try {
      if (targetTrack == null) {
        await HomeWidget.saveWidgetData<String>('track_title', 'Orpheus');
        await HomeWidget.saveWidgetData<String>('track_artist', 'Escucha algo grandioso');
        await HomeWidget.saveWidgetData<bool>('is_playing', false);
        await HomeWidget.saveWidgetData<bool>('is_liked', false);
        await HomeWidget.saveWidgetData<String>('cover_path', '');
        await _updateAllWidgets();
        return;
      }

      final isLiked = _database.likedTrackIdsNotifier.value.contains(targetTrack.trackId);
      final coverPath = await _resolveCoverPath(targetTrack);

      await HomeWidget.saveWidgetData<String>('track_title', targetTrack.displayTitle);
      await HomeWidget.saveWidgetData<String>('track_artist', targetTrack.displayArtist);
      await HomeWidget.saveWidgetData<bool>('is_playing', _playerService.isPlaying);
      await HomeWidget.saveWidgetData<bool>('is_liked', isLiked);
      await HomeWidget.saveWidgetData<String>('cover_path', coverPath ?? '');

      await _updateAllWidgets();
      DebugLogger.log('WidgetSyncService: Sincronizado widget nativo con "${targetTrack.displayTitle}"');
    } catch (e, s) {
      DebugLogger.log('WidgetSyncService: Error al sincronizar metadatos: $e\n$s');
    }
  }

  /// Synchronizes playback state (playing vs paused) to all native widgets.
  Future<void> _syncPlaybackState(bool isPlaying) async {
    try {
      await HomeWidget.saveWidgetData<bool>('is_playing', isPlaying);
      await _updateAllWidgets();
    } catch (e) {
      DebugLogger.log('WidgetSyncService: Error al actualizar play_pause: $e');
    }
  }

  /// Synchronizes the like status for the currently playing track to all native widgets.
  Future<void> syncLikeState() async {
    try {
      final currentTrack = _playerService.currentTrack;
      if (currentTrack != null) {
        final isLiked = _database.likedTrackIdsNotifier.value.contains(currentTrack.trackId);
        await HomeWidget.saveWidgetData<bool>('is_liked', isLiked);
        await _updateAllWidgets();
      }
    } catch (e) {
      DebugLogger.log('WidgetSyncService: Error al actualizar estado de Me gusta: $e');
    }
  }

  /// Updates all registered native Android widgets simultaneously.
  Future<void> _updateAllWidgets() async {
    try {
      await HomeWidget.updateWidget(name: androidWidgetProvider);
    } catch (_) {}
    try {
      await HomeWidget.updateWidget(name: androidCompactWidgetProvider);
    } catch (_) {}
  }

  /// Resolves the local absolute path of the track's cover art if available on disk.
  Future<String?> _resolveCoverPath(Track track) async {
    // 1. Check custom metadata cover path
    final customPath = track.customMetadata.customCoverPath;
    if (customPath != null && customPath.trim().isNotEmpty) {
      try {
        final file = File(customPath.trim());
        if (await file.exists() && await file.length() > 0) {
          return file.path;
        }
      } catch (_) {}
    }

    // 2. Check cached cover via MediaCacheService
    try {
      final cachedFile = await _mediaCache.getCachedCover(track.displayArtist, track.displayTitle);
      if (cachedFile != null && await cachedFile.exists() && await cachedFile.length() > 0) {
        return cachedFile.path;
      }
    } catch (_) {}

    return null;
  }
}
