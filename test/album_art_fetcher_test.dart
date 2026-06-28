import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/services/album_art_fetcher_service.dart';

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
      expect(updated.customMetadata.customCoverPath!.contains('track1'), isTrue);

      // Clean up files created
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
  });
}
