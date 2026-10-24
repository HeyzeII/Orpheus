import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:flutter/foundation.dart';

import '../utils/debug_logger.dart';
import 'audio_handler.dart';

/// Status representation for MPRIS PlaybackStatus.
enum MprisPlaybackStatus {
  playing('Playing'),
  paused('Paused'),
  stopped('Stopped');

  const MprisPlaybackStatus(this.value);
  final String value;
}

/// Linux MPRIS (Media Player Remote Interfacing Specification) service.
///
/// Bridges Orpheus with the Linux D-Bus desktop interface (GNOME Shell,
/// KDE Plasma, media keys, sound applets, and lock screens).
///
/// Ensures bidirectional synchronization:
/// - Incoming hardware/D-Bus media events: Play, Pause, PlayPause, Next, Previous, Seek.
/// - Outgoing metadata and playback status: title, artist, album, duration, artUrl, status.
class LinuxMprisService {
  LinuxMprisService._internal();

  static final LinuxMprisService _instance = LinuxMprisService._internal();

  /// Global singleton instance.
  static LinuxMprisService get instance => _instance;

  bool _isInitialized = false;
  final List<StreamSubscription> _subscriptions = [];

  // Mirrored metadata and playback status
  final ValueNotifier<MprisPlaybackStatus> playbackStatusNotifier =
      ValueNotifier<MprisPlaybackStatus>(MprisPlaybackStatus.stopped);

  final ValueNotifier<Map<String, dynamic>> metadataNotifier =
      ValueNotifier<Map<String, dynamic>>({});

  /// Returns true if MPRIS is active and initialized.
  bool get isInitialized => _isInitialized;

  /// Returns true if the host platform is Linux.
  bool get isSupported => Platform.isLinux;

  /// Current MPRIS playback status.
  MprisPlaybackStatus get currentStatus => playbackStatusNotifier.value;

  /// Current MPRIS metadata payload.
  Map<String, dynamic> get currentMetadata => metadataNotifier.value;

  /// Initializes the MPRIS D-Bus bridge.
  ///
  /// Safe to call on any platform; will cleanly no-op unless [Platform.isLinux]
  /// is true (or [forceForTesting] is explicitly enabled).
  Future<void> initialize({bool forceForTesting = false}) async {
    if (_isInitialized) return;

    if (!isSupported && !forceForTesting) {
      DebugLogger.log('LinuxMprisService: Omitting initialization on non-Linux platform.');
      return;
    }

    try {
      DebugLogger.log('LinuxMprisService: Initializing D-Bus MPRIS platform integration...');

      // Register MPRIS platform implementation for AudioService
      AudioServiceMpris.registerWith();

      _isInitialized = true;
      DebugLogger.log('LinuxMprisService: MPRIS registered successfully.');

      // Attach stream listeners if OrpheusAudioHandler is already available
      if (OrpheusAudioHandler.hasInstance) {
        attachAudioHandler(OrpheusAudioHandler.instance);
      }
    } catch (e, s) {
      DebugLogger.log('LinuxMprisService: Failed to initialize MPRIS: $e\n$s');
    }
  }

  /// Binds bidirectional stream synchronization with the provided [OrpheusAudioHandler].
  void attachAudioHandler(OrpheusAudioHandler handler) {
    _cancelSubscriptions();

    // 1. Sync outgoing metadata (Track info -> D-Bus MPRIS Metadata)
    _subscriptions.add(
      handler.mediaItem.listen((item) {
        _syncMediaItem(item);
      }),
    );

    // 2. Sync outgoing playback status (Playing/Paused/Stopped -> D-Bus PlaybackStatus)
    _subscriptions.add(
      handler.playbackState.listen((state) {
        _syncPlaybackState(state);
      }),
    );

    // Initial sync
    _syncMediaItem(handler.mediaItem.value);
    _syncPlaybackState(handler.playbackState.value);

    DebugLogger.log('LinuxMprisService: Attached listeners to OrpheusAudioHandler.');
  }

  void _syncMediaItem(MediaItem? item) {
    if (item == null) {
      metadataNotifier.value = {};
      return;
    }

    final metadata = <String, dynamic>{
      'title': item.title,
      'artist': item.artist ?? '',
      'album': item.album ?? '',
      'duration': item.duration,
      'artUrl': item.artUri?.toString() ?? '',
    };

    metadataNotifier.value = metadata;
    DebugLogger.log(
        'LinuxMprisService: Synced metadata -> "${item.title}" by "${item.artist}"');
  }

  void _syncPlaybackState(PlaybackState state) {
    MprisPlaybackStatus newStatus;
    if (state.processingState == AudioProcessingState.idle) {
      newStatus = MprisPlaybackStatus.stopped;
    } else if (state.playing) {
      newStatus = MprisPlaybackStatus.playing;
    } else {
      newStatus = MprisPlaybackStatus.paused;
    }

    if (playbackStatusNotifier.value != newStatus) {
      playbackStatusNotifier.value = newStatus;
      DebugLogger.log('LinuxMprisService: Synced status -> ${newStatus.value}');
    }
  }

  // ── Hardware & D-Bus Incoming Media Key Handlers ──────────────────────────

  /// Dispatches Play command to [OrpheusAudioHandler].
  Future<void> handlePlay() async {
    if (OrpheusAudioHandler.hasInstance) {
      await OrpheusAudioHandler.instance.play();
    }
  }

  /// Dispatches Pause command to [OrpheusAudioHandler].
  Future<void> handlePause() async {
    if (OrpheusAudioHandler.hasInstance) {
      await OrpheusAudioHandler.instance.pause();
    }
  }

  /// Dispatches PlayPause toggle command to [OrpheusAudioHandler].
  Future<void> handlePlayPause() async {
    if (OrpheusAudioHandler.hasInstance) {
      await OrpheusAudioHandler.instance.togglePlayPause();
    }
  }

  /// Dispatches Next command to [OrpheusAudioHandler].
  Future<void> handleNext() async {
    if (OrpheusAudioHandler.hasInstance) {
      await OrpheusAudioHandler.instance.next();
    }
  }

  /// Dispatches Previous command to [OrpheusAudioHandler].
  Future<void> handlePrevious() async {
    if (OrpheusAudioHandler.hasInstance) {
      await OrpheusAudioHandler.instance.previous();
    }
  }

  /// Dispatches Seek command to [OrpheusAudioHandler].
  Future<void> handleSeek(Duration position) async {
    if (OrpheusAudioHandler.hasInstance) {
      await OrpheusAudioHandler.instance.seek(position);
    }
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  /// Releases resources and detaches listeners.
  void dispose() {
    _cancelSubscriptions();
    _isInitialized = false;
  }
}
