import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/models/app_config.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/services/album_art_fetcher_service.dart';
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

  void emit(List<ConnectivityResult> results) {
    currentResults = results;
    _controller.add(results);
  }
}

class FakeLocalDatabase extends LocalDatabase {
  FakeLocalDatabase() : super.internal();

  AppConfig _config = AppConfig();
  final Map<String, Track> _tracks = {};

  @override
  Future<AppConfig> getConfig() async => _config;

  @override
  Future<void> saveConfig(AppConfig config) async {
    _config = config;
  }

  @override
  Future<void> saveTrack(Track track) async {
    _tracks[track.trackId] = track;
  }

  @override
  Future<void> updateTrackLyrics(Track track, String lyrics) async {
    track.syncedLyrics = lyrics;
    _tracks[track.trackId] = track;
  }
}

class FakeHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest request) onSend;
  int sendCallCount = 0;

  FakeHttpClient(this.onSend);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCallCount++;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FakeConnectivity fakeConnectivity;
  late FakeLocalDatabase fakeDb;
  late NetworkGuardService networkGuard;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return '.';
      },
    );
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('network_guard_test_');
    MediaCacheService.instance.customBaseDir =
        Directory('${tempDir.path}/.orpheus_cache');
    fakeConnectivity = FakeConnectivity();
    fakeDb = FakeLocalDatabase();
    networkGuard = NetworkGuardService(
      connectivity: fakeConnectivity,
      db: fakeDb,
    );
  });

  tearDown(() async {
    MediaCacheService.instance.customBaseDir = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('NetworkGuardService - General Access Tests', () {
    test('allows general access when connected to Wi-Fi and offline mode is disabled', () async {
      fakeDb._config.strictOfflineMode = false;
      fakeConnectivity.currentResults = [ConnectivityResult.wifi];

      final result = await networkGuard.checkGeneralAccess();
      expect(result, equals(NetworkAccessResult.allowed));
      expect(await networkGuard.canMakeGeneralRequest(), isTrue);
    });

    test('allows general access when connected to Mobile Data and offline mode is disabled', () async {
      fakeDb._config.strictOfflineMode = false;
      fakeConnectivity.currentResults = [ConnectivityResult.mobile];

      final result = await networkGuard.checkGeneralAccess();
      expect(result, equals(NetworkAccessResult.allowed));
    });

    test('blocks general access immediately when Strict Offline Mode is enabled', () async {
      fakeDb._config.strictOfflineMode = true;
      fakeConnectivity.currentResults = [ConnectivityResult.wifi];

      final result = await networkGuard.checkGeneralAccess();
      expect(result, equals(NetworkAccessResult.blockedByOfflineMode));
      expect(await networkGuard.canMakeGeneralRequest(), isFalse);
    });

    test('blocks general access when device has no network connectivity', () async {
      fakeDb._config.strictOfflineMode = false;
      fakeConnectivity.currentResults = [ConnectivityResult.none];

      final result = await networkGuard.checkGeneralAccess();
      expect(result, equals(NetworkAccessResult.noInternetConnection));
      expect(await networkGuard.canMakeGeneralRequest(), isFalse);
    });
  });

  group('NetworkGuardService - Cover Download Policy Tests', () {
    test('wifiOnly policy allows download on Wi-Fi and Ethernet', () async {
      fakeDb._config.strictOfflineMode = false;
      fakeDb._config.coverDownloadPolicy = CoverDownloadPolicy.wifiOnly;

      fakeConnectivity.currentResults = [ConnectivityResult.wifi];
      expect(await networkGuard.checkCoverDownloadAccess(), equals(NetworkAccessResult.allowed));
      expect(await networkGuard.canDownloadCover(), isTrue);

      fakeConnectivity.currentResults = [ConnectivityResult.ethernet];
      expect(await networkGuard.checkCoverDownloadAccess(), equals(NetworkAccessResult.allowed));
    });

    test('wifiOnly policy blocks download on Mobile/Cellular data', () async {
      fakeDb._config.strictOfflineMode = false;
      fakeDb._config.coverDownloadPolicy = CoverDownloadPolicy.wifiOnly;
      fakeConnectivity.currentResults = [ConnectivityResult.mobile];

      final result = await networkGuard.checkCoverDownloadAccess();
      expect(result, equals(NetworkAccessResult.blockedByCellularPolicy));
      expect(await networkGuard.canDownloadCover(), isFalse);
    });

    test('always policy allows download on Mobile Data', () async {
      fakeDb._config.strictOfflineMode = false;
      fakeDb._config.coverDownloadPolicy = CoverDownloadPolicy.always;
      fakeConnectivity.currentResults = [ConnectivityResult.mobile];

      final result = await networkGuard.checkCoverDownloadAccess();
      expect(result, equals(NetworkAccessResult.allowed));
      expect(await networkGuard.canDownloadCover(), isTrue);
    });

    test('never policy blocks download even on Wi-Fi', () async {
      fakeDb._config.strictOfflineMode = false;
      fakeDb._config.coverDownloadPolicy = CoverDownloadPolicy.never;
      fakeConnectivity.currentResults = [ConnectivityResult.wifi];

      final result = await networkGuard.checkCoverDownloadAccess();
      expect(result, equals(NetworkAccessResult.blockedByCellularPolicy));
      expect(await networkGuard.canDownloadCover(), isFalse);
    });

    test('strictOfflineMode overrides cover download policies', () async {
      fakeDb._config.strictOfflineMode = true;
      fakeDb._config.coverDownloadPolicy = CoverDownloadPolicy.always;
      fakeConnectivity.currentResults = [ConnectivityResult.wifi];

      final result = await networkGuard.checkCoverDownloadAccess();
      expect(result, equals(NetworkAccessResult.blockedByOfflineMode));
      expect(await networkGuard.canDownloadCover(), isFalse);
    });
  });

  group('NetworkGuardService - State Mutators', () {
    test('setOfflineMode and setCoverDownloadPolicy persist to database', () async {
      await networkGuard.setOfflineMode(true);
      expect(fakeDb._config.strictOfflineMode, isTrue);
      expect(await networkGuard.isOfflineMode(), isTrue);

      await networkGuard.setCoverDownloadPolicy(CoverDownloadPolicy.always);
      expect(fakeDb._config.coverDownloadPolicy, equals(CoverDownloadPolicy.always));
    });
  });

  group('Service Interception Integration Tests', () {
    test('LyricsService blocks HTTP request when Strict Offline Mode is active', () async {
      fakeDb._config.strictOfflineMode = true;
      fakeConnectivity.currentResults = [ConnectivityResult.wifi];

      final fakeHttp = FakeHttpClient((_) async => http.Response('{"syncedLyrics": "line"}', 200));

      final lyricsService = LyricsService(
        db: fakeDb,
        client: fakeHttp,
        networkGuard: networkGuard,
      );

      final track = Track()
        ..trackId = 'track_test_1'
        ..filePath = '/music/Artist/Song.mp3'
        ..artist = 'The Beatles'
        ..title = 'Hey Jude';

      final result = await lyricsService.fetchLyrics(track);

      // Should return null (transient skip) and never touch the network
      expect(result, isNull);
      expect(fakeHttp.sendCallCount, equals(0));
    });

    test('AlbumArtFetcherService blocks HTTP request when policy is wifiOnly and on mobile data', () async {
      fakeDb._config.strictOfflineMode = false;
      fakeDb._config.coverDownloadPolicy = CoverDownloadPolicy.wifiOnly;
      fakeConnectivity.currentResults = [ConnectivityResult.mobile];

      final fakeHttp = FakeHttpClient((_) async => http.Response('{"results": []}', 200));

      final artService = AlbumArtFetcherService(
        db: fakeDb,
        client: fakeHttp,
        networkGuard: networkGuard,
      );

      final track = Track()
        ..trackId = 'track_art_test_1'
        ..filePath = '/music/Artist/Album/Song.mp3'
        ..artist = 'Queen'
        ..title = 'Bohemian Rhapsody'
        ..album = 'A Night at the Opera';

      await artService.processTrack(track);

      // Network call must NOT be triggered
      expect(fakeHttp.sendCallCount, equals(0));
      // Status should remain none (not marked notFound permanently)
      expect(track.artStatus, equals(FetchStatus.none));
    });
  });
}
