import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/services/linux_mpris_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LinuxMprisService Unit Tests', () {
    late LinuxMprisService service;

    setUp(() {
      service = LinuxMprisService.instance;
      service.dispose();
    });

    tearDown(() {
      service.dispose();
    });

    test('isSupported properly detects Linux host', () {
      expect(service.isSupported, Platform.isLinux);
    });

    test('initialize skips on non-Linux platform without forceForTesting', () async {
      if (!Platform.isLinux) {
        await service.initialize();
        expect(service.isInitialized, isFalse);
      }
    });

    test('initialize succeeds and activates with forceForTesting', () async {
      await service.initialize(forceForTesting: true);
      expect(service.isInitialized, isTrue);
    });

    test('metadata synchronization updates metadataNotifier correctly', () async {
      await service.initialize(forceForTesting: true);

      // Verify initial empty state
      expect(service.currentMetadata, isEmpty);

      // Simulate MediaItem broadcast
      const testItem = MediaItem(
        id: 'test_track_1',
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        album: 'A Night at the Opera',
        duration: Duration(minutes: 5, seconds: 55),
        artUri: null,
      );

      // We can verify metadata mapping behavior via mock or handler
      final testMetadata = <String, dynamic>{
        'title': testItem.title,
        'artist': testItem.artist ?? '',
        'album': testItem.album ?? '',
        'duration': testItem.duration,
        'artUrl': testItem.artUri?.toString() ?? '',
      };

      service.metadataNotifier.value = testMetadata;

      expect(service.currentMetadata['title'], 'Bohemian Rhapsody');
      expect(service.currentMetadata['artist'], 'Queen');
      expect(service.currentMetadata['album'], 'A Night at the Opera');
      expect(service.currentMetadata['duration'], const Duration(minutes: 5, seconds: 55));
    });

    test('playback status synchronization updates playbackStatusNotifier', () async {
      await service.initialize(forceForTesting: true);

      service.playbackStatusNotifier.value = MprisPlaybackStatus.playing;
      expect(service.currentStatus, MprisPlaybackStatus.playing);
      expect(service.currentStatus.value, 'Playing');

      service.playbackStatusNotifier.value = MprisPlaybackStatus.paused;
      expect(service.currentStatus, MprisPlaybackStatus.paused);
      expect(service.currentStatus.value, 'Paused');

      service.playbackStatusNotifier.value = MprisPlaybackStatus.stopped;
      expect(service.currentStatus, MprisPlaybackStatus.stopped);
      expect(service.currentStatus.value, 'Stopped');
    });

    test('incoming hardware media command handlers do not crash when handler uninitialized', () async {
      await service.initialize(forceForTesting: true);

      // Verify that all MPRIS remote commands safely no-op without uncaught errors
      await expectLater(service.handlePlay(), completes);
      await expectLater(service.handlePause(), completes);
      await expectLater(service.handlePlayPause(), completes);
      await expectLater(service.handleNext(), completes);
      await expectLater(service.handlePrevious(), completes);
      await expectLater(service.handleSeek(const Duration(seconds: 45)), completes);
    });

    test('dispose resets initialization and detaches cleanly', () async {
      await service.initialize(forceForTesting: true);
      expect(service.isInitialized, isTrue);

      service.dispose();
      expect(service.isInitialized, isFalse);
    });
  });
}
