import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/services/album_art_fetcher_service.dart';
import 'package:orpheus/core/services/media_cache_service.dart';

class FakeHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest request) onSend;

  FakeHttpClient(this.onSend);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await onSend(request);
    final controller = StreamController<List<int>>();
    controller.add(response.bodyBytes);
    unawaited(controller.close());
    return http.StreamedResponse(
      controller.stream,
      response.statusCode,
      headers: response.headers,
      request: request,
      contentLength: response.bodyBytes.length,
    );
  }
}

class FakeLocalDatabase extends LocalDatabase {
  FakeLocalDatabase() : super.internal();

  final Map<String, Track> _tracks = {};

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
  Future<Track?> getTrackByTrackId(String trackId) async {
    return _tracks[trackId];
  }

  @override
  Future<void> updateTrackLyrics(Track track, String lrcContent) async {
    track.syncedLyrics = lrcContent;
    await saveTrack(track);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Mock path_provider method channel
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.';
      },
    );

    // Mock connectivity_plus method channel to return Wi-Fi connection
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'check') {
          return ['wifi'];
        }
        return null;
      },
    );
  });

  group('AlbumArtFetcherService tests', () {
    test('Successful lookup and download updates Isar and track custom metadata', () async {
      final db = FakeLocalDatabase();
      final track = Track()
        ..trackId = 'track1'
        ..filePath = '/music/test1.mp3'
        ..title = 'Clean Title'
        ..artist = 'Clean Artist'
        ..fileType = FileType.mp3;

      await db.saveTrack(track);

      // Create a client that returns search results first, then the image bytes
      final client = FakeHttpClient((request) async {
        if (request.url.host == 'itunes.apple.com') {
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'artistName': 'Clean Artist',
                  'trackName': 'Clean Title',
                  'artworkUrl100': 'https://example.com/artwork100x100bb.jpg',
                }
              ]
            }),
            200,
          );
        } else if (request.url.host == 'example.com') {
          return http.Response.bytes([1, 2, 3, 4], 200);
        }
        return http.Response('', 404);
      });

      final fetcher = AlbumArtFetcherService.internal(db: db, client: client);
      
      // Let's verify initial state
      expect(track.artStatus, equals(FetchStatus.none));
      expect(track.customMetadata.customCoverPath, isNull);

      await fetcher.processLibrary();

      // Get updated track from Isar
      final updated = await db.getTrackByTrackId('track1');
      expect(updated, isNotNull);
      expect(updated!.artStatus, equals(FetchStatus.success));
      expect(updated.customMetadata.customCoverPath, isNotNull);
      final expectedHash = MediaCacheService.instance.computeMediaHash(updated.displayArtist, updated.displayTitle);
      expect(updated.customMetadata.customCoverPath!.contains(expectedHash), isTrue);

      // Clean up files created
      final file = File(updated.customMetadata.customCoverPath!);
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

    test('Candidate with completely different artist is rejected as notFound', () async {
      final db = FakeLocalDatabase();
      final track = Track()
        ..trackId = 'track_mismatch'
        ..filePath = '/music/test_mismatch.mp3'
        ..title = 'Unique Song'
        ..artist = 'Target Artist'
        ..fileType = FileType.mp3;

      await db.saveTrack(track);

      final client = FakeHttpClient((request) async {
        if (request.url.host == 'itunes.apple.com') {
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'artistName': 'Completely Unrelated Artist',
                  'trackName': 'Unique Song',
                  'artworkUrl100': 'https://example.com/wrong_cover.jpg',
                }
              ]
            }),
            200,
          );
        }
        return http.Response('', 404);
      });

      final fetcher = AlbumArtFetcherService.internal(db: db, client: client);
      await fetcher.processLibrary();

      final updated = await db.getTrackByTrackId('track_mismatch');
      expect(updated, isNotNull);
      expect(updated!.artStatus, equals(FetchStatus.notFound));
      expect(updated.customMetadata.customCoverPath, isNull);
    });

    test('Candidate with high similarity (accents and suffixes) is accepted', () async {
      final db = FakeLocalDatabase();
      final track = Track()
        ..trackId = 'track_fuzzy'
        ..filePath = '/music/test_fuzzy.mp3'
        ..title = 'Canción de Prueba'
        ..artist = 'Café Tacvba'
        ..album = 'Re (Remastered)'
        ..fileType = FileType.mp3;

      await db.saveTrack(track);

      final client = FakeHttpClient((request) async {
        if (request.url.host == 'itunes.apple.com') {
          expect(request.url.queryParameters['limit'], equals('5'));
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'artistName': 'Cafe Tacvba',
                  'trackName': 'Cancion de Prueba',
                  'collectionName': 'Re',
                  'artworkUrl100': 'https://example.com/tacvba100x100bb.jpg',
                }
              ]
            }),
            200,
          );
        } else if (request.url.host == 'example.com') {
          return http.Response.bytes([10, 20, 30], 200);
        }
        return http.Response('', 404);
      });

      final fetcher = AlbumArtFetcherService.internal(db: db, client: client);
      await fetcher.processLibrary();

      final updated = await db.getTrackByTrackId('track_fuzzy');
      expect(updated, isNotNull);
      expect(updated!.artStatus, equals(FetchStatus.success));
      expect(updated.customMetadata.customCoverPath, isNotNull);

      // Clean up file created
      final file = File(updated.customMetadata.customCoverPath!);
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

    test('404 response sets artStatus to notFound', () async {
      final db = FakeLocalDatabase();
      final track = Track()
        ..trackId = 'track2'
        ..filePath = '/music/test2.mp3'
        ..title = 'Clean Title 2'
        ..artist = 'Clean Artist 2'
        ..fileType = FileType.mp3;

      await db.saveTrack(track);

      final client = FakeHttpClient((request) async {
        return http.Response('Not Found', 404);
      });

      final fetcher = AlbumArtFetcherService.internal(db: db, client: client);

      await fetcher.processLibrary();

      final updated = await db.getTrackByTrackId('track2');
      expect(updated, isNotNull);
      expect(updated!.artStatus, equals(FetchStatus.notFound));
      expect(updated.customMetadata.customCoverPath, isNull);
    });

    test('Empty results from API sets artStatus to notFound', () async {
      final db = FakeLocalDatabase();
      final track = Track()
        ..trackId = 'track3'
        ..filePath = '/music/test3.mp3'
        ..title = 'Clean Title 3'
        ..artist = 'Clean Artist 3'
        ..fileType = FileType.mp3;

      await db.saveTrack(track);

      final client = FakeHttpClient((request) async {
        return http.Response(jsonEncode({'results': []}), 200);
      });

      final fetcher = AlbumArtFetcherService.internal(db: db, client: client);

      await fetcher.processLibrary();

      final updated = await db.getTrackByTrackId('track3');
      expect(updated, isNotNull);
      expect(updated!.artStatus, equals(FetchStatus.notFound));
    });

    test('Query term is deduplicated when artist and title are identical', () async {
      final db = FakeLocalDatabase();
      final track = Track()
        ..trackId = 'track_dup'
        ..filePath = '/music/Imagine Dragons - Imagine Dragons.mp3'
        ..title = 'Imagine Dragons'
        ..artist = 'Imagine Dragons'
        ..fileType = FileType.mp3;

      await db.saveTrack(track);

      String? requestedTerm;
      final client = FakeHttpClient((request) async {
        requestedTerm = request.url.queryParameters['term'];
        return http.Response(jsonEncode({'results': []}), 200);
      });

      final fetcher = AlbumArtFetcherService.internal(db: db, client: client);
      await fetcher.processLibrary();

      expect(requestedTerm, equals('Imagine Dragons'));
    });

    test('Uses custom metadata overrides instead of falling back to raw fields/path', () async {
      final db = FakeLocalDatabase();
      final track = Track()
        ..trackId = 'track_custom'
        ..filePath = '/music/Como sonaria LINKIN PARK en Espanol Nico Borie_360p-mc-mc.mp3'
        ..fileType = FileType.mp3;

      track.hasCustomMetadata = true;
      track.customMetadata.title = 'In the End en Español';
      track.customMetadata.artist = 'Nico Borie';

      await db.saveTrack(track);

      String? requestedTerm;
      final client = FakeHttpClient((request) async {
        requestedTerm = request.url.queryParameters['term'];
        return http.Response(jsonEncode({'results': []}), 200);
      });

      final fetcher = AlbumArtFetcherService.internal(db: db, client: client);
      await fetcher.processLibrary();

      // Should search for "Nico Borie In the End en Español" instead of "Como sonaria..." filename fallback
      expect(requestedTerm, equals('Nico Borie In the End en Español'));
    });

    test('resetTrackArtStatus resets artStatus to none and clears cached cover file', () async {
      final db = FakeLocalDatabase();
      final track = Track()
        ..trackId = 'track_reset'
        ..filePath = '/music/test_reset.mp3'
        ..title = 'Reset Title'
        ..artist = 'Reset Artist'
        ..artStatus = FetchStatus.notFound
        ..fileType = FileType.mp3;

      // Save a mock cover in media cache
      final savedCover = await MediaCacheService.instance.saveCover(
        'Reset Artist',
        'Reset Title',
        [1, 2, 3, 4, 5],
      );
      track.customMetadata.customCoverPath = savedCover;
      track.artStatus = FetchStatus.success;
      await db.saveTrack(track);

      expect(File(savedCover).existsSync(), isTrue);

      final fetcher = AlbumArtFetcherService.internal(db: db);
      await fetcher.resetTrackArtStatus(track, deleteCachedFile: true);

      final updated = await db.getTrackByTrackId('track_reset');
      expect(updated, isNotNull);
      expect(updated!.artStatus, equals(FetchStatus.none));
      expect(updated.customMetadata.customCoverPath, isNull);
      expect(File(savedCover).existsSync(), isFalse);
    });

    test('updateTrackMetadata resets artStatus to none on text change and to custom on manual cover', () async {
      final db = FakeLocalDatabase();
      final track = Track()
        ..trackId = 'track_edit'
        ..filePath = '/music/test_edit.mp3'
        ..title = 'Old Title'
        ..artist = 'Old Artist'
        ..artStatus = FetchStatus.notFound
        ..fileType = FileType.mp3;

      await db.saveTrack(track);

      // 1. Text edit without custom cover with resetMediaFlags -> artStatus becomes none
      await db.updateTrackMetadata(
        track,
        newTitle: 'New Title',
        newArtist: 'New Artist',
        newAlbum: 'New Album',
        resetMediaFlags: true,
      );

      final updated1 = await db.getTrackByTrackId('track_edit');
      expect(updated1!.customMetadata.isEdited, isTrue);
      expect(updated1.displayTitle, equals('New Title'));
      expect(updated1.displayArtist, equals('New Artist'));
      expect(updated1.artStatus, equals(FetchStatus.none));

      // 2. Edit with custom cover path -> artStatus becomes custom
      await db.updateTrackMetadata(
        track,
        newTitle: 'New Title',
        newArtist: 'New Artist',
        newAlbum: 'New Album',
        newCustomCoverPath: '/path/to/custom_cover.jpg',
      );

      final updated2 = await db.getTrackByTrackId('track_edit');
      expect(updated2!.customMetadata.isEdited, isTrue);
      expect(updated2.customMetadata.customCoverPath, equals('/path/to/custom_cover.jpg'));
      expect(updated2.artStatus, equals(FetchStatus.custom));
    });
  });
}
