import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/models/app_config.dart';
import 'package:orpheus/core/models/playlist.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/services/audio_scanner.dart';
import 'package:orpheus/core/services/media_cache_service.dart';
import 'package:orpheus/core/utils/string_sanitizer.dart';

Uint8List createMockFlacWithVorbisComments(Map<String, String> comments) {
  final commentBytesList = <List<int>>[];
  for (final entry in comments.entries) {
    final commentStr = '${entry.key}=${entry.value}';
    final commentUtf8 = utf8.encode(commentStr);
    final lenBytes = ByteData(4)..setUint32(0, commentUtf8.length, Endian.little);
    commentBytesList.add(lenBytes.buffer.asUint8List());
    commentBytesList.add(commentUtf8);
  }

  final vendorUtf8 = utf8.encode('reference libFLAC 1.4.0');
  final vendorLenBytes = ByteData(4)..setUint32(0, vendorUtf8.length, Endian.little);
  final userCountBytes = ByteData(4)..setUint32(0, comments.length, Endian.little);

  final vorbisPayload = <int>[
    ...vendorLenBytes.buffer.asUint8List(),
    ...vendorUtf8,
    ...userCountBytes.buffer.asUint8List(),
    for (final cb in commentBytesList) ...cb,
  ];

  final vorbisLen = vorbisPayload.length;
  final vorbisHeader = [
    0x84, // isLast = true | blockType = 4 (VORBIS_COMMENT)
    (vorbisLen >> 16) & 0xFF,
    (vorbisLen >> 8) & 0xFF,
    vorbisLen & 0xFF,
  ];

  final streamInfoPayload = List<int>.filled(34, 0);
  final streamInfoHeader = [
    0x00, // isLast = false | blockType = 0 (STREAMINFO)
    0x00,
    0x00,
    34,
  ];

  return Uint8List.fromList([
    0x66, 0x4C, 0x61, 0x43, // 'fLaC' magic
    ...streamInfoHeader,
    ...streamInfoPayload,
    ...vorbisHeader,
    ...vorbisPayload,
  ]);
}

class FakeLocalDatabase extends LocalDatabase {
  FakeLocalDatabase() : super.internal() {
    _playlists['__liked__'] = Playlist()
      ..playlistId = '__liked__'
      ..name = 'Liked Tracks'
      ..description = 'Tracks you have marked as liked.'
      ..isDefault = true;
  }

  final Map<String, Track> _tracks = {};
  final Map<String, Playlist> _playlists = {};
  int _autoId = 1;

  @override
  Future<AppConfig> getConfig() async => AppConfig();

  @override
  Future<void> saveTrack(Track track) async {
    if (track.id == 0) {
      track.id = _autoId++;
    }
    _tracks[track.trackId] = track;
  }

  @override
  Future<void> saveTracks(List<Track> tracks) async {
    for (final track in tracks) {
      if (track.id == 0) {
        track.id = _autoId++;
      }
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

  @override
  Future<Playlist?> getPlaylistById(String playlistId) async {
    return _playlists[playlistId];
  }

  @override
  Future<List<Playlist>> getAllPlaylists() async {
    return _playlists.values.toList();
  }

  @override
  Future<void> savePlaylist(Playlist playlist) async {
    if (playlist.id == 0) {
      playlist.id = _autoId++;
    }
    _playlists[playlist.playlistId] = playlist;
  }

  @override
  Future<Track?> getTrackById(int id) async {
    return _tracks.values.cast<Track?>().firstWhere(
      (t) => t?.id == id,
      orElse: () => null,
    );
  }

  @override
  Future<void> removeTrackFromPlaylistAt({
    required Playlist playlist,
    required int index,
  }) async {
    if (index < 0 || index >= playlist.trackIds.length) return;
    final intId = playlist.trackIds[index];
    final updated = List<int>.from(playlist.trackIds);
    updated.removeAt(index);
    playlist.trackIds = updated;
    await savePlaylist(playlist);

    if (playlist.playlistId == '__liked__') {
      final track = await getTrackById(intId);
      if (track != null && !updated.contains(intId)) {
        final newSet = Set<String>.from(likedTrackIdsNotifier.value);
        newSet.remove(track.trackId);
        likedTrackIdsNotifier.value = newSet;
      }
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory musicDir;

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
    tempDir = await Directory.systemTemp.createTemp('orpheus_portable_test_');
    musicDir = Directory('${tempDir.path}/Music');
    await musicDir.create(recursive: true);
    MediaCacheService.instance.customBaseDir = Directory('${musicDir.path}/.orpheus_cache');
  });

  tearDown(() async {
    MediaCacheService.instance.customBaseDir = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Portable Library State & Vorbis Embedded Lyrics Integration Tests', () {
    test('extracts Vorbis comments lyrics from FLAC during scanning', () async {
      final db = FakeLocalDatabase();
      final scanner = AudioScannerService(db: db);

      const vorbisLrc = '[00:05.00] Bohemian Rhapsody\n[00:10.00] Mama, just killed a man';
      final flacBytes = createMockFlacWithVorbisComments({
        'ARTIST': 'Queen',
        'TITLE': 'Bohemian Rhapsody',
        'LYRICS': vorbisLrc,
      });

      final flacFile = File('${musicDir.path}/Queen - Bohemian Rhapsody.flac');
      await flacFile.writeAsBytes(flacBytes);

      await for (final _ in scanner.scanDirectory(musicDir.path)) {}

      final tracks = await db.getAllTracks();
      expect(tracks.length, equals(1));
      final track = tracks.first;

      expect(track.syncedLyrics, equals(vorbisLrc));
      expect(track.lyricsStatus, equals(FetchStatus.success));
    });

    test('auto-recovers liked tracks and playlists from library_state.json across library moves', () async {
      // 1. Create simulated music tracks in Location A
      final rockDir = Directory('${musicDir.path}/Rock')..createSync(recursive: true);
      File('${rockDir.path}/Queen - Bohemian Rhapsody.mp3').writeAsStringSync('mp3-1');
      File('${rockDir.path}/Pink Floyd - Time.flac').writeAsStringSync('flac-2');

      final fp1 = StringSanitizer.generateTrackFingerprint(
        artist: 'Queen',
        title: 'Bohemian Rhapsody',
        durationMs: 0,
      );
      final fp2 = StringSanitizer.generateTrackFingerprint(
        artist: 'Pink Floyd',
        title: 'Time',
        durationMs: 0,
      );

      // 2. Pre-seed .orpheus_cache/library_state.json with Likes and a Custom Playlist
      final stateJson = {
        'version': 1,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'likedTracks': [
          {
            'fingerprint': fp1,
            'artist': 'Queen',
            'title': 'Bohemian Rhapsody',
            'durationSec': 0,
          }
        ],
        'playlists': [
          {
            'playlistId': 'custom_rock_classics',
            'name': 'Rock Classics',
            'description': 'Best rock anthems',
            'tracks': [
              {
                'fingerprint': fp1,
                'artist': 'Queen',
                'title': 'Bohemian Rhapsody',
                'durationSec': 0,
              },
              {
                'fingerprint': fp2,
                'artist': 'Pink Floyd',
                'title': 'Time',
                'durationSec': 0,
              },
            ],
          }
        ],
      };

      await MediaCacheService.instance.saveLibraryState(stateJson, musicDir.path);

      // 3. Scan the music directory into a fresh database (simulating first scan or reinstalled app)
      final freshDb = FakeLocalDatabase();
      final scanner = AudioScannerService(db: freshDb);

      await for (final _ in scanner.scanDirectory(musicDir.path)) {}

      // 4. Verify that Liked Tracks were restored
      final allTracks = await freshDb.getAllTracks();
      expect(allTracks.length, equals(2));

      final likedPlaylist = await freshDb.getPlaylistById('__liked__');
      expect(likedPlaylist, isNotNull);
      expect(likedPlaylist!.trackIds.length, equals(1));
      expect(freshDb.likedTrackIdsNotifier.value.length, equals(1));

      final likedTrack = allTracks.firstWhere((t) => t.displayTitle.contains('Bohemian Rhapsody'));
      expect(freshDb.likedTrackIdsNotifier.value.contains(likedTrack.trackId), isTrue);

      // 5. Verify that Custom Playlists were restored with both tracks
      final rockPlaylist = await freshDb.getPlaylistById('custom_rock_classics');
      expect(rockPlaylist, isNotNull);
      expect(rockPlaylist!.name, equals('Rock Classics'));
      expect(rockPlaylist.trackIds.length, equals(2));
    });

    test('removeTrackFromPlaylistAt removes exact duplicate instance by position', () async {
      final db = FakeLocalDatabase();
      final trackA = Track()..trackId = 'trackA'..title = 'Song A'..artist = 'Artist A';
      final trackB = Track()..trackId = 'trackB'..title = 'Song B'..artist = 'Artist B';
      await db.saveTrack(trackA);
      await db.saveTrack(trackB);

      // Custom playlist with duplicate tracks: [A, B, A]
      final playlist = Playlist()
        ..playlistId = 'pl_duplicates'
        ..name = 'Duplicate Playlist'
        ..trackIds = [trackA.id, trackB.id, trackA.id];
      await db.savePlaylist(playlist);

      // Remove the 3rd item (index 2: trackA duplicate at the end)
      await db.removeTrackFromPlaylistAt(playlist: playlist, index: 2);

      final updated = await db.getPlaylistById('pl_duplicates');
      expect(updated, isNotNull);
      // Must preserve the first trackA at index 0 and trackB at index 1
      expect(updated!.trackIds, equals([trackA.id, trackB.id]));
    });

    test('Smart Merge in exportLibraryState preserves missing fingerprints when audio files are absent', () async {
      final cacheService = MediaCacheService.instance;

      // 1. Initial portable library state with 2 tracks in playlist
      final fpPresent = StringSanitizer.generateTrackFingerprint(
        artist: 'Artist Present',
        title: 'Song Present',
        durationMs: 180000,
      );
      final fpMissing = StringSanitizer.generateTrackFingerprint(
        artist: 'Artist Missing',
        title: 'Song Missing',
        durationMs: 240000,
      );

      final initialJson = {
        'version': 1,
        'updatedAt': 1000,
        'likedTracks': [
          {
            'fingerprint': fpMissing,
            'artist': 'Artist Missing',
            'title': 'Song Missing',
            'durationSec': 240,
          }
        ],
        'playlists': [
          {
            'playlistId': 'pl_smart_merge',
            'name': 'Smart Merge Playlist',
            'tracks': [
              {
                'fingerprint': fpPresent,
                'artist': 'Artist Present',
                'title': 'Song Present',
                'durationSec': 180,
              },
              {
                'fingerprint': fpMissing,
                'artist': 'Artist Missing',
                'title': 'Song Missing',
                'durationSec': 240,
              }
            ],
          }
        ],
      };
      await cacheService.saveLibraryState(initialJson, musicDir.path);

      // 2. Export library state where DB only has 'Song Present'
      final trackPresent = Track()
        ..id = 1
        ..trackId = 't_present'
        ..title = 'Song Present'
        ..artist = 'Artist Present'
        ..duration = 180;

      final playlistInDb = Playlist()
        ..playlistId = 'pl_smart_merge'
        ..name = 'Smart Merge Playlist'
        ..trackIds = [trackPresent.id];

      await cacheService.exportLibraryState(
        allTracks: [trackPresent],
        likedTrackIds: {},
        customPlaylists: [playlistInDb],
        musicDirectoryPath: musicDir.path,
      );

      // 3. Read back library_state.json and verify both the active track and preserved missing track are retained!
      final mergedState = await cacheService.readLibraryState(musicDir.path);
      expect(mergedState, isNotEmpty);

      // Liked tracks: missing track preserved
      final liked = (mergedState['likedTracks'] as List);
      expect(liked.length, equals(1));
      expect(liked.first['fingerprint'], equals(fpMissing));

      // Playlist tracks: both present and missing tracks are retained
      final playlists = (mergedState['playlists'] as List);
      expect(playlists.length, equals(1));
      final plTracks = (playlists.first['tracks'] as List);
      expect(plTracks.length, equals(2));
      final fps = plTracks.map((t) => t['fingerprint']).toList();
      expect(fps, contains(fpPresent));
      expect(fps, contains(fpMissing));
    });

    test('Deleted playlist is blacklisted, removed from library_state.json and not resurrected during rescan', () async {
      final cacheService = MediaCacheService.instance;

      // 1. Save state with 2 playlists
      final initialJson = {
        'version': 1,
        'updatedAt': 1000,
        'likedTracks': [],
        'playlists': [
          {
            'playlistId': 'pl_active',
            'name': 'Active Playlist',
            'tracks': [],
          },
          {
            'playlistId': 'pl_to_delete',
            'name': 'Playlist To Delete',
            'tracks': [],
          }
        ],
        'deletedPlaylistIds': [],
      };
      await cacheService.saveLibraryState(initialJson, musicDir.path);

      // 2. Mark pl_to_delete as deleted
      cacheService.markPlaylistAsDeleted('pl_to_delete');
      expect(cacheService.deletedPlaylistIds, contains('pl_to_delete'));

      // 3. Export library state with only pl_active
      final activePlaylist = Playlist()
        ..playlistId = 'pl_active'
        ..name = 'Active Playlist';

      await cacheService.exportLibraryState(
        allTracks: [],
        likedTrackIds: {},
        customPlaylists: [activePlaylist],
        musicDirectoryPath: musicDir.path,
      );

      // 4. Read back state and verify pl_to_delete is gone and recorded in deletedPlaylistIds
      final updatedState = await cacheService.readLibraryState(musicDir.path);
      final playlists = (updatedState['playlists'] as List);
      expect(playlists.length, equals(1));
      expect(playlists.first['playlistId'], equals('pl_active'));

      final deletedList = (updatedState['deletedPlaylistIds'] as List);
      expect(deletedList, contains('pl_to_delete'));
    });
  });
}
