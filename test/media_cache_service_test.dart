import 'dart:convert';
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

    test('saveMetadataEntry does not overwrite edited entries if incoming is not edited', () async {
      final editedPayload = {
        'title': 'Custom Title',
        'artist': 'Custom Artist',
        'isEdited': true,
      };
      await cacheService.saveMetadataEntry('Artist', 'Title', editedPayload);

      // Attempt overwrite with unedited payload (e.g. from auto-scanner)
      final autoPayload = {
        'title': 'Overwritten Title',
        'artist': 'Overwritten Artist',
        'isEdited': false,
      };
      await cacheService.saveMetadataEntry('Artist', 'Title', autoPayload);

      final entry = await cacheService.getMetadataEntry('Artist', 'Title');
      expect(entry!['title'], equals('Custom Title'));
      expect(entry['artist'], equals('Custom Artist'));
      expect(entry['isEdited'], isTrue);
    });

    test('findLocalLrcFile locates matching .lrc file in audio directory', () async {
      final audioFile = File('${tempDir.path}/Track01.mp3');
      await audioFile.writeAsString('audio');

      final lrcFile = File('${tempDir.path}/Track01.lrc');
      await lrcFile.writeAsString('[00:01.00]Local lyric line');

      final found = await cacheService.findLocalLrcFile(audioFile.path);
      expect(found, isNotNull);
      expect(found!.path, equals(lrcFile.path));
      expect(await found.readAsString(), contains('Local lyric line'));
    });

    test('findLocalCoverFile locates cover.jpg or stem image in audio directory', () async {
      final audioFile = File('${tempDir.path}/Song.mp3');
      await audioFile.writeAsString('audio');

      final coverFile = File('${tempDir.path}/cover.jpg');
      await coverFile.writeAsBytes([0x01, 0x02, 0x03]);

      final found = await cacheService.findLocalCoverFile(audioFile.path);
      expect(found, isNotNull);
      expect(found!.path, equals(coverFile.path));
    });

    test('saveTrackMetadataEntry stores multi-key payload in metadata_index.json', () async {
      final fakeFilePath = '${tempDir.path}/Music/Artist/Album/Song.mp3';
      final scanRoot = '${tempDir.path}/Music';

      final payload = <String, dynamic>{
        'title': 'Edited Title',
        'artist': 'Edited Artist',
        'album': 'Edited Album',
        'artists': ['Edited Artist'],
        'customCoverPath': null,
        'isEdited': true,
      };

      await cacheService.saveTrackMetadataEntry(
        filePath: fakeFilePath,
        scanRootPath: scanRoot,
        originalArtist: 'Raw Artist',
        originalTitle: 'Raw Title',
        editedArtist: 'Edited Artist',
        editedTitle: 'Edited Title',
        payload: payload,
      );

      final indexFile = File('${cacheService.customBaseDir!.path}/metadata_index.json');
      expect(indexFile.existsSync(), isTrue);

      final index = jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;

      // All expected keys should be present
      expect(index.containsKey('file:$fakeFilePath'), isTrue);
      expect(index.containsKey('stem:Song'), isTrue);

      // Payload should carry identity fields
      final entry = index['stem:Song'] as Map<String, dynamic>;
      expect(entry['filePath'], equals(fakeFilePath));
      expect(entry['originalArtist'], equals('Raw Artist'));
      expect(entry['originalTitle'], equals('Raw Title'));
      expect(entry['fileStem'], equals('Song'));
      expect(entry['isEdited'], isTrue);
    });

    test('findMetadataEntry resolves by relative path, stem, and raw hash', () async {
      final scanRoot = '${tempDir.path}/Music';
      final fakeFilePath = '$scanRoot/Artist/Song.mp3';

      final payload = <String, dynamic>{
        'title': 'Edited Title',
        'artist': 'Edited Artist',
        'album': 'Edited Album',
        'artists': ['Edited Artist'],
        'isEdited': true,
      };

      // Persist with multi-key entry
      await cacheService.saveTrackMetadataEntry(
        filePath: fakeFilePath,
        scanRootPath: scanRoot,
        originalArtist: 'Raw Artist',
        originalTitle: 'Raw Title',
        editedArtist: 'Edited Artist',
        editedTitle: 'Edited Title',
        payload: payload,
      );

      // 1. Find by exact file path
      final byFilePath = await cacheService.findMetadataEntry(
        filePath: fakeFilePath,
        scanRootPath: scanRoot,
        rawArtist: 'Raw Artist',
        rawTitle: 'Raw Title',
      );
      expect(byFilePath, isNotNull);
      expect(byFilePath!['isEdited'], isTrue);
      expect(byFilePath['title'], equals('Edited Title'));

      // 2. Find by stem key (different artist/title to force non-hash hit)
      final byStem = await cacheService.findMetadataEntry(
        filePath: fakeFilePath,
        scanRootPath: scanRoot,
        rawArtist: 'Completely Different Artist',
        rawTitle: 'Completely Different Title',
      );
      expect(byStem, isNotNull);
      expect(byStem!['fileStem'], equals('Song'));

      // 3. Find by raw hash (original artist + title)
      final byHash = await cacheService.findMetadataEntry(
        filePath: '/new/install/path/Music/Artist/Song.mp3', // different absolute path
        scanRootPath: '/new/install/path/Music',
        rawArtist: 'Raw Artist',
        rawTitle: 'Raw Title',
      );
      // Raw hash keys ('hash:<hash>' and '<hash>') should match
      expect(byHash, isNotNull);
    });

    test('saveTrackMetadataEntry prunes orphan hash keys when re-editing a track', () async {
      final scanRoot = '${tempDir.path}/Music';
      final fakeFilePath = '$scanRoot/Artist/Song.mp3';

      final payloadV1 = <String, dynamic>{
        'title': 'Title v1',
        'artist': 'Artist v1',
        'album': 'Album v1',
        'artists': ['Artist v1'],
        'isEdited': true,
      };

      // First edit
      await cacheService.saveTrackMetadataEntry(
        filePath: fakeFilePath,
        scanRootPath: scanRoot,
        originalArtist: 'Raw Artist',
        originalTitle: 'Raw Title',
        editedArtist: 'Artist v1',
        editedTitle: 'Title v1',
        payload: payloadV1,
      );

      final hashV1 = cacheService.computeMediaHash('Artist v1', 'Title v1');
      final rawHash = cacheService.computeMediaHash('Raw Artist', 'Raw Title');

      final indexFile = File('${cacheService.customBaseDir!.path}/metadata_index.json');
      var index = jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;

      expect(index.containsKey('hash:$hashV1'), isTrue);
      expect(index.containsKey(hashV1), isTrue);
      expect(index.containsKey('hash:$rawHash'), isTrue);

      // Second edit (re-editing the same file)
      final payloadV2 = <String, dynamic>{
        'title': 'Title v2',
        'artist': 'Artist v2',
        'album': 'Album v2',
        'artists': ['Artist v2'],
        'isEdited': true,
      };

      await cacheService.saveTrackMetadataEntry(
        filePath: fakeFilePath,
        scanRootPath: scanRoot,
        originalArtist: 'Raw Artist',
        originalTitle: 'Raw Title',
        editedArtist: 'Artist v2',
        editedTitle: 'Title v2',
        payload: payloadV2,
      );

      final hashV2 = cacheService.computeMediaHash('Artist v2', 'Title v2');
      index = jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;

      // Old v1 hashes should be completely pruned
      expect(index.containsKey('hash:$hashV1'), isFalse);
      expect(index.containsKey(hashV1), isFalse);

      // New v2 hashes and raw hashes should be present
      expect(index.containsKey('hash:$hashV2'), isTrue);
      expect(index.containsKey(hashV2), isTrue);
      expect(index.containsKey('hash:$rawHash'), isTrue);

      // File-identity keys should reflect the updated payload
      final fileEntry = index['file:$fakeFilePath'] as Map<String, dynamic>;
      expect(fileEntry['title'], equals('Title v2'));
      expect(fileEntry['artist'], equals('Artist v2'));
    });
  });
}

