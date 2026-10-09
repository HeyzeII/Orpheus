import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/services/media_cache_service.dart';
import 'package:orpheus/core/utils/string_sanitizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MediaCacheService mediaCache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('orpheus_stats_test_');
    mediaCache = MediaCacheService.instance;
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Library Stats Persistence & Rehydration Tests', () {
    test('exportLibraryStats and readLibraryStats write and read valid JSON', () async {
      final track = Track()
        ..trackId = 'track_1'
        ..title = 'Bohemian Rhapsody'
        ..artist = 'Queen'
        ..album = 'A Night at the Opera'
        ..duration = 354
        ..filePath = '${tempDir.path}/queen.flac'
        ..playCount = 42
        ..skipCount = 2
        ..isLiked = true
        ..rmsEnergy = 0.72
        ..peakDensity = 0.58
        ..spectralBalance = 0.64
        ..isScanned = true
        ..lastPlayedAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);

      await mediaCache.exportLibraryStats(
        allTracks: [track],
        musicDirectoryPath: tempDir.path,
      );

      final statsData = await mediaCache.readLibraryStats(tempDir.path);
      expect(statsData['version'], equals(1));
      expect(statsData['stats'], isA<Map>());

      final statsMap = statsData['stats'] as Map<String, dynamic>;
      final fp = StringSanitizer.generateTrackFingerprint(
        artist: 'Queen',
        title: 'Bohemian Rhapsody',
        durationMs: 354000,
      );

      expect(statsMap.containsKey(fp), isTrue);
      final entry = statsMap[fp] as Map<String, dynamic>;
      expect(entry['artist'], equals('Queen'));
      expect(entry['title'], equals('Bohemian Rhapsody'));
      expect(entry['playCount'], equals(42));
      expect(entry['skipCount'], equals(2));
      expect(entry['isLiked'], isTrue);
      expect(entry['lastPlayedAt'], equals(1700000000000));

      final acoustic = entry['acoustic'] as Map<String, dynamic>;
      expect(acoustic['isScanned'], isTrue);
      expect(acoustic['rmsEnergy'], equals(0.72));
      expect(acoustic['peakDensity'], equals(0.58));
      expect(acoustic['spectralBalance'], equals(0.64));
    });

    test('Smart merge preserves existing entries for missing tracks', () async {
      final track1 = Track()
        ..trackId = 't1'
        ..title = 'Song One'
        ..artist = 'Artist A'
        ..duration = 200
        ..filePath = '${tempDir.path}/song1.mp3'
        ..isScanned = true
        ..rmsEnergy = 0.5;

      await mediaCache.exportLibraryStats(
        allTracks: [track1],
        musicDirectoryPath: tempDir.path,
      );

      final track2 = Track()
        ..trackId = 't2'
        ..title = 'Song Two'
        ..artist = 'Artist B'
        ..duration = 180
        ..filePath = '${tempDir.path}/song2.mp3'
        ..isScanned = true
        ..rmsEnergy = 0.8;

      // Export only track 2 — track 1 should remain in stats
      await mediaCache.exportLibraryStats(
        allTracks: [track2],
        musicDirectoryPath: tempDir.path,
      );

      final statsData = await mediaCache.readLibraryStats(tempDir.path);
      final statsMap = statsData['stats'] as Map<String, dynamic>;

      final fp1 = StringSanitizer.generateTrackFingerprint(
        artist: 'Artist A',
        title: 'Song One',
        durationMs: 200000,
      );
      final fp2 = StringSanitizer.generateTrackFingerprint(
        artist: 'Artist B',
        title: 'Song Two',
        durationMs: 180000,
      );

      expect(statsMap.containsKey(fp1), isTrue);
      expect(statsMap.containsKey(fp2), isTrue);
    });
  });
}
