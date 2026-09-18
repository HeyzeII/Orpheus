import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/models/app_config.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/services/audio_scanner.dart';
import 'package:orpheus/core/services/media_cache_service.dart';

class FakeLocalDatabase extends LocalDatabase {
  FakeLocalDatabase() : super.internal();

  final Map<String, Track> _tracks = {};

  @override
  Future<AppConfig> getConfig() async => AppConfig();

  @override
  Future<void> saveTrack(Track track) async {
    _tracks[track.trackId] = track;
  }

  @override
  Future<void> saveTracks(List<Track> tracks) async {
    for (final track in tracks) {
      _tracks[track.trackId] = track;
    }
  }

  @override
  Future<List<Track>> getAllTracks() async {
    return _tracks.values.toList();
  }

  @override
  Future<Track?> getTrackByFilePath(String filePath) async {
    return _tracks.values.cast<Track?>().firstWhere(
      (t) => t?.filePath == filePath,
      orElse: () => null,
    );
  }

  @override
  Future<Track?> getTrackByTrackId(String trackId) async {
    return _tracks[trackId];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory musicDir;
  late FakeLocalDatabase db;
  late AudioScannerService scanner;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return Directory.systemTemp.path;
      },
    );
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('orpheus_scanner_test_');
    musicDir = Directory('${tempDir.path}/Music');
    await musicDir.create(recursive: true);

    MediaCacheService.instance.customBaseDir =
        Directory('${musicDir.path}/.orpheus_cache');

    db = FakeLocalDatabase();
    scanner = AudioScannerService(db: db);
  });

  tearDown(() async {
    MediaCacheService.instance.customBaseDir = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('AudioScannerService - Deep Recursive & Exclusion Tests', () {
    test('scans multi-level directory structures and skips hidden/system folders & files', () async {
      // 1. Create deep multilevel hierarchy (Artista/Álbum/CD/pistas)
      final cd1Dir = Directory('${musicDir.path}/Daft Punk/Discovery/CD1')..createSync(recursive: true);
      final cd2Dir = Directory('${musicDir.path}/Daft Punk/Discovery/CD2')..createSync(recursive: true);
      final pinkDir = Directory('${musicDir.path}/Pink Floyd/The Wall')..createSync(recursive: true);

      final track1 = File('${cd1Dir.path}/01 - One More Time.flac')..writeAsStringSync('fake-flac-data-1');
      final track2 = File('${cd2Dir.path}/02 - Aerodynamic.mp3')..writeAsStringSync('fake-mp3-data-2');
      final track3 = File('${pinkDir.path}/01 - In the Flesh.wav')..writeAsStringSync('fake-wav-data-3');

      // 2. Create hidden and system directories that MUST be ignored
      final gitDir = Directory('${musicDir.path}/.git')..createSync(recursive: true);
      final cacheDir = Directory('${musicDir.path}/.orpheus_cache/covers')..createSync(recursive: true);
      final macosxDir = Directory('${musicDir.path}/__MACOSX/Daft Punk')..createSync(recursive: true);
      final thumbsDir = Directory('${musicDir.path}/Daft Punk/.thumbnails')..createSync(recursive: true);
      final trashDir = Directory('${musicDir.path}/Daft Punk/.trash')..createSync(recursive: true);

      File('${gitDir.path}/ignored_git.flac').writeAsStringSync('bad');
      File('${cacheDir.path}/ignored_cache.mp3').writeAsStringSync('bad');
      File('${macosxDir.path}/._01 - One More Time.flac').writeAsStringSync('bad');
      File('${thumbsDir.path}/ignored_thumb.m4a').writeAsStringSync('bad');
      File('${trashDir.path}/ignored_trash.flac').writeAsStringSync('bad');

      // 3. Create hidden/ghost files inside valid directories that MUST be ignored
      File('${cd1Dir.path}/._01 - One More Time.flac').writeAsStringSync('apple-double-fork');
      File('${cd1Dir.path}/.DS_Store').writeAsStringSync('macos-metadata');
      File('${cd1Dir.path}/.hidden_track.flac').writeAsStringSync('hidden');
      File('${cd1Dir.path}/notes.txt').writeAsStringSync('non-audio-file');

      // 4. Run scanner
      final results = <ScanResult>[];
      await for (final result in scanner.scanDirectory(musicDir.path)) {
        results.add(result);
      }

      // 5. Verify results
      final scannedPaths = results.map((r) => r.filePath).toList();
      expect(scannedPaths.length, equals(3));
      expect(scannedPaths, contains(track1.path));
      expect(scannedPaths, contains(track2.path));
      expect(scannedPaths, contains(track3.path));

      // Verify no hidden or system paths were scanned
      for (final path in scannedPaths) {
        final segments = path.split('/');
        final filename = segments.last;
        expect(filename.startsWith('.'), isFalse, reason: 'File $filename should not start with .');
        expect(segments.any((s) => s.startsWith('.') && s != '.'), isFalse,
            reason: 'Path $path contains hidden directory segment');
        expect(segments.contains('__MACOSX'), isFalse);
      }

      // 6. Verify database persistence
      final allTracks = await db.getAllTracks();
      expect(allTracks.length, equals(3));
      final trackTitles = allTracks.map((t) => t.displayTitle).toList();
      expect(trackTitles, contains('One More Time'));
      expect(trackTitles, contains('Aerodynamic'));
      expect(trackTitles, contains('In the Flesh'));
    });

    test('guarantees strict read-only immutability of original audio files', () async {
      final albumDir = Directory('${musicDir.path}/Artist/Album')..createSync(recursive: true);
      final audioFile = File('${albumDir.path}/immutable_track.flac');
      const originalContent = 'sample-flac-binary-content-1234567890';
      audioFile.writeAsStringSync(originalContent);

      final originalLength = audioFile.lengthSync();
      final originalModified = audioFile.lastModifiedSync();

      // Run scanner over the folder
      await for (final _ in scanner.scanDirectory(musicDir.path)) {}

      // Verify file was never modified, truncated, or rewritten
      expect(audioFile.existsSync(), isTrue);
      expect(audioFile.readAsStringSync(), equals(originalContent));
      expect(audioFile.lengthSync(), equals(originalLength));
      expect(audioFile.lastModifiedSync(), equals(originalModified));
    });
  });
}
