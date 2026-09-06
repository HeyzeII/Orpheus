import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/services/media_cache_service.dart';

void main() {
  late Directory tempDir;
  late MediaCacheService cacheService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('orpheus_cache_test_');
    cacheService = MediaCacheService.instance;
    cacheService.customBaseDir = Directory('${tempDir.path}/.orpheus_cache');
  });

  tearDown(() async {
    cacheService.customBaseDir = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('MediaCacheService Tests', () {
    test('computeMediaHash generates deterministic normalized hash', () {
      final hash1 = cacheService.computeMediaHash(' The Weeknd ', ' Blinding Lights ');
      final hash2 = cacheService.computeMediaHash('the weeknd', 'blinding lights');
      expect(hash1, equals(hash2));
      expect(hash1.length, equals(64)); // SHA-256 hex length
    });

    test('saveCover and getCachedCover store and read cover images correctly', () async {
      final fakeBytes = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]; // sample jpeg header
      final savedPath = await cacheService.saveCover('Dua Lipa', 'Levitating', fakeBytes);

      expect(savedPath, contains('.orpheus_cache/covers'));
      expect(File(savedPath).existsSync(), isTrue);

      final cachedFile = await cacheService.getCachedCover('Dua Lipa', 'Levitating');
      expect(cachedFile, isNotNull);
      expect(cachedFile!.path, equals(savedPath));
      expect(await cachedFile.readAsBytes(), equals(fakeBytes));

      final hasCover = await cacheService.hasCachedCover('Dua Lipa', 'Levitating');
      expect(hasCover, isTrue);
    });

    test('saveLyrics and getCachedLyrics store and read lyrics correctly', () async {
      const lrcContent = '[00:12.00]If you wanna run away with me, I know a galaxy';
      final savedPath = await cacheService.saveLyrics('Dua Lipa', 'Levitating', lrcContent);

      expect(savedPath, contains('.orpheus_cache/lyrics'));
      expect(File(savedPath).existsSync(), isTrue);

      final cachedLrc = await cacheService.getCachedLyrics('Dua Lipa', 'Levitating');
      expect(cachedLrc, equals(lrcContent));

      final hasLyrics = await cacheService.hasCachedLyrics('Dua Lipa', 'Levitating');
      expect(hasLyrics, isTrue);
    });

    test('saveMetadataEntry and getMetadataEntry persist to metadata_index.json', () async {
      final payload = {
        'title': 'Save Your Tears',
        'artist': 'The Weeknd & Ariana Grande',
        'album': 'After Hours (Deluxe)',
        'artists': ['The Weeknd', 'Ariana Grande'],
        'isEdited': true,
      };

      await cacheService.saveMetadataEntry('The Weeknd', 'Save Your Tears', payload);

      final indexFile = File('${cacheService.customBaseDir!.path}/metadata_index.json');
      expect(indexFile.existsSync(), isTrue);

      final entry = await cacheService.getMetadataEntry('The Weeknd', 'Save Your Tears');
      expect(entry, isNotNull);
      expect(entry!['title'], equals('Save Your Tears'));
      expect(entry['artist'], equals('The Weeknd & Ariana Grande'));
      expect(entry['album'], equals('After Hours (Deluxe)'));
      expect(entry['artists'], equals(['The Weeknd', 'Ariana Grande']));
      expect(entry['isEdited'], isTrue);
      expect(entry['updatedAt'], isNotNull);
    });
  });
}
