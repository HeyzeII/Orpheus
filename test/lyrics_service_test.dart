import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/models/app_config.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/services/lyrics_service.dart';
import 'package:orpheus/core/services/media_cache_service.dart';
import 'package:orpheus/core/services/network_guard_service.dart';

class FakeConnectivity implements Connectivity {
  List<ConnectivityResult> currentResults = [ConnectivityResult.wifi];
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => currentResults;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;
}

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
  Future<AppConfig> getConfig() async => AppConfig();

  @override
  Future<void> saveTrack(Track track) async {
    _tracks[track.trackId] = track;
  }

  @override
  Future<void> updateTrackLyrics(Track track, String lrcContent) async {
    track.syncedLyrics = lrcContent;
    await saveTrack(track);
  }

  @override
  Future<Track?> getTrackByTrackId(String trackId) async {
    return _tracks[trackId];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

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
    tempDir = await Directory.systemTemp.createTemp('orpheus_lyrics_test_');
    MediaCacheService.instance.customBaseDir =
        Directory('${tempDir.path}/.orpheus_cache');
  });

  tearDown(() async {
    MediaCacheService.instance.customBaseDir = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('LyricsService - Query Sanitization & DB Invariance Tests', () {
    test('sanitizes explicit Unicode 🅴 and explicit suffixes in LRCLIB query parameters', () async {
      final db = FakeLocalDatabase();
      late Uri capturedUri;

      final client = FakeHttpClient((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode({
            'syncedLyrics': '[00:10.00] Welcome to Miami\n[00:15.00] Party in the city',
            'plainLyrics': 'Welcome to Miami',
          }),
          200,
        );
      });

      final connectivity = FakeConnectivity();
      final networkGuard = NetworkGuardService(connectivity: connectivity, db: db);
      final lyricsService = LyricsService(
        db: db,
        client: client,
        networkGuard: networkGuard,
      );

      final track = Track()
        ..trackId = 'track_explicit_1'
        ..filePath = '/music/Will Smith/Miami 🅴.mp3'
        ..title = 'Miami 🅴'
        ..artist = 'Will Smith (Explicit)'
        ..fileType = FileType.mp3;

      await db.saveTrack(track);

      final lrc = await lyricsService.fetchLyrics(track);

      // Verify outgoing URL query parameters are thoroughly cleaned
      expect(capturedUri.queryParameters['track_name'], equals('Miami'));
      expect(capturedUri.queryParameters['artist_name'], equals('Will Smith'));

      // Verify lyrics were parsed and returned
      expect(lrc, contains('[00:10.00] Welcome to Miami'));
      expect(track.lyricsStatus, equals(FetchStatus.success));

      // Verify Track attributes in memory and DB NEVER mutated
      expect(track.title, equals('Miami 🅴'));
      expect(track.artist, equals('Will Smith (Explicit)'));

      final savedTrack = await db.getTrackByTrackId(track.trackId);
      expect(savedTrack?.title, equals('Miami 🅴'));
      expect(savedTrack?.artist, equals('Will Smith (Explicit)'));
      expect(savedTrack?.syncedLyrics, contains('[00:10.00] Welcome to Miami'));
    });

    test('cleans [E] and (Explicit Version) bracketed tags in LRCLIB query', () async {
      final db = FakeLocalDatabase();
      late Uri capturedUri;

      final client = FakeHttpClient((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode({
            'syncedLyrics': '[00:05.00] Guess who\'s back',
            'plainLyrics': 'Guess who\'s back',
          }),
          200,
        );
      });

      final connectivity = FakeConnectivity();
      final networkGuard = NetworkGuardService(connectivity: connectivity, db: db);
      final lyricsService = LyricsService(
        db: db,
        client: client,
        networkGuard: networkGuard,
      );

      final track = Track()
        ..trackId = 'track_explicit_2'
        ..filePath = '/music/Eminem/Without Me.mp3'
        ..title = 'Without Me [E]'
        ..artist = 'Eminem'
        ..fileType = FileType.mp3;

      await db.saveTrack(track);

      await lyricsService.fetchLyrics(track);

      expect(capturedUri.queryParameters['track_name'], equals('Without Me'));
      expect(capturedUri.queryParameters['artist_name'], equals('Eminem'));
      expect(track.title, equals('Without Me [E]'));
    });
  });
}
