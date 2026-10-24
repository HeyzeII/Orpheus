import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orpheus/core/models/custom_metadata.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/network/local_sync_client.dart';
import 'package:orpheus/core/network/local_sync_server.dart';
import 'package:orpheus/core/network/orpheus_beacon_service.dart';
import 'package:orpheus/core/services/audio_player_service.dart';
import 'package:shelf/shelf.dart' as shelf;

void main() {
  const testBaseUrl = 'http://192.168.1.50:50505';

  group('LocalSyncClient URL Construction and Normalization', () {
    test('normalizes base URLs correctly', () {
      expect(
        LocalSyncClient.normalizeBaseUrl('192.168.1.50:50505'),
        'http://192.168.1.50:50505',
      );
      expect(
        LocalSyncClient.normalizeBaseUrl('http://192.168.1.50:50505/'),
        'http://192.168.1.50:50505',
      );
      expect(
        LocalSyncClient.normalizeBaseUrl('https://orpheus.local/'),
        'https://orpheus.local',
      );
    });

    test('builds stream, artwork, and download URLs properly', () {
      final client = LocalSyncClient(baseUrl: testBaseUrl);

      expect(
        client.getStreamUrl('track_abc'),
        'http://192.168.1.50:50505/api/v1/stream/track_abc',
      );
      expect(
        client.buildStreamUrl('track_abc'),
        'http://192.168.1.50:50505/api/v1/stream/track_abc',
      );
      expect(
        client.getArtUrl('track_abc'),
        'http://192.168.1.50:50505/api/v1/art/track_abc',
      );
      expect(
        client.buildArtUrl('track_abc'),
        'http://192.168.1.50:50505/api/v1/art/track_abc',
      );
      expect(
        client.getDownloadUrl('track_abc'),
        'http://192.168.1.50:50505/api/v1/download/track_abc',
      );
      expect(
        client.buildDownloadUrl('track_abc'),
        'http://192.168.1.50:50505/api/v1/download/track_abc',
      );

      expect(
        client.getStreamUri('track_abc'),
        Uri.parse('http://192.168.1.50:50505/api/v1/stream/track_abc'),
      );
    });

    test('allows overriding base URL per call', () {
      final client = LocalSyncClient(baseUrl: testBaseUrl);
      const customNode = 'http://10.0.0.99:50505';

      expect(
        client.getStreamUrl('track_123', customNode),
        'http://10.0.0.99:50505/api/v1/stream/track_123',
      );
      expect(
        client.buildArtUrl('track_123', baseUrl: customNode),
        'http://10.0.0.99:50505/api/v1/art/track_123',
      );
    });

    test('throws LocalSyncClientException if no baseUrl is configured', () {
      final client = LocalSyncClient();
      expect(
        () => client.getStreamUrl('track_1'),
        throwsA(isA<LocalSyncClientException>()),
      );
    });

    test('initialization from DiscoveredNode inherits baseUrl', () {
      final node = DiscoveredNode(
        deviceId: 'dev_1',
        deviceName: 'MacBook Pro',
        platform: 'macos',
        port: 50505,
        address: InternetAddress('192.168.1.80'),
        version: '1.0.0',
        lastSeen: DateTime.now(),
      );

      final client = LocalSyncClient.fromNode(node);
      expect(client.baseUrl, 'http://192.168.1.80:50505');
      expect(
        client.getStreamUrl('track_xyz'),
        'http://192.168.1.80:50505/api/v1/stream/track_xyz',
      );
    });
  });

  group('LocalSyncClient pingNode()', () {
    test('successfully validates active Orpheus node', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/api/v1/ping');
        expect(request.method, 'GET');

        final payload = {
          'status': 'ok',
          'service': 'orpheus-sync',
          'version': '1.0.0',
          'deviceName': 'Studio-Desktop',
          'platform': 'linux',
          'port': 50505,
          'timestamp': '2026-10-24T18:00:00.000Z',
        };
        return http.Response(
          jsonEncode(payload),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final client = LocalSyncClient(baseUrl: testBaseUrl, client: mock);
      final ping = await client.pingNode();

      expect(ping.isOk, isTrue);
      expect(ping.service, 'orpheus-sync');
      expect(ping.version, '1.0.0');
      expect(ping.deviceName, 'Studio-Desktop');
      expect(ping.platform, 'linux');
      expect(ping.port, 50505);
      expect(ping.timestamp, DateTime.parse('2026-10-24T18:00:00.000Z'));
    });

    test('throws LocalSyncClientException on HTTP non-200 response', () async {
      final mock = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final client = LocalSyncClient(baseUrl: testBaseUrl, client: mock);

      expect(
        () => client.pingNode(),
        throwsA(
          predicate<LocalSyncClientException>(
            (e) => e.statusCode == 500 && e.message.contains('500'),
          ),
        ),
      );
    });

    test('throws LocalSyncClientException on timeout', () async {
      final mock = MockClient((request) async {
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response('ok', 200);
      });

      final client = LocalSyncClient(
        baseUrl: testBaseUrl,
        client: mock,
        timeout: const Duration(milliseconds: 10),
      );

      expect(
        () => client.pingNode(),
        throwsA(
          predicate<LocalSyncClientException>(
            (e) => e.message.contains('timed out'),
          ),
        ),
      );
    });

    test('throws LocalSyncClientException on malformed response body', () async {
      final mock = MockClient((request) async {
        return http.Response('This is not json', 200);
      });

      final client = LocalSyncClient(baseUrl: testBaseUrl, client: mock);

      expect(
        () => client.pingNode(),
        throwsA(isA<LocalSyncClientException>()),
      );
    });
  });

  group('LocalSyncClient fetchLibrary()', () {
    test('successfully parses remote library and constructs playback-ready Tracks', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/api/v1/library');

        final payload = {
          'status': 'ok',
          'count': 2,
          'tracks': [
            {
              'trackId': 'track_flac_001',
              'title': 'Stairway to Heaven',
              'artist': 'Led Zeppelin',
              'album': 'Led Zeppelin IV',
              'duration': 482,
              'fileType': 'flac',
              'audioQuality': 'HI-FI',
              'hasCover': true,
              'isLiked': true,
              'streamUrl': '/api/v1/stream/track_flac_001',
              'artUrl': '/api/v1/art/track_flac_001',
              'downloadUrl': '/api/v1/download/track_flac_001',
            },
            {
              'trackId': 'track_mp3_002',
              'title': 'Comfortably Numb',
              'artist': 'Pink Floyd',
              'album': 'The Wall',
              'duration': 382,
              'fileType': 'mp3',
              'audioQuality': 'HQ',
              'hasCover': false,
              'isLiked': false,
              'streamUrl': '/api/v1/stream/track_mp3_002',
              'artUrl': null,
              'downloadUrl': '/api/v1/download/track_mp3_002',
            },
          ],
        };

        return http.Response(
          jsonEncode(payload),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final client = LocalSyncClient(baseUrl: testBaseUrl, client: mock);
      final tracks = await client.fetchLibrary();

      expect(tracks.length, 2);

      // Track 1: FLAC with Cover Art
      final t1 = tracks[0];
      expect(t1.trackId, 'track_flac_001');
      expect(t1.title, 'Stairway to Heaven');
      expect(t1.displayTitle, 'Stairway to Heaven');
      expect(t1.artist, 'Led Zeppelin');
      expect(t1.album, 'Led Zeppelin IV');
      expect(t1.duration, 482);
      expect(t1.fileType, FileType.flac);
      expect(t1.audioQuality, 'HI-FI');
      expect(t1.isLiked, isTrue);
      expect(
        t1.filePath,
        'http://192.168.1.50:50505/api/v1/stream/track_flac_001',
      );
      expect(t1.hasCustomMetadata, isTrue);
      expect(
        t1.customMetadata.customCoverPath,
        'http://192.168.1.50:50505/api/v1/art/track_flac_001',
      );
      expect(
        t1.downloadSource,
        'http://192.168.1.50:50505/api/v1/download/track_flac_001',
      );

      // Track 2: MP3 without Cover Art
      final t2 = tracks[1];
      expect(t2.trackId, 'track_mp3_002');
      expect(t2.title, 'Comfortably Numb');
      expect(t2.artist, 'Pink Floyd');
      expect(t2.fileType, FileType.mp3);
      expect(t2.isLiked, isFalse);
      expect(
        t2.filePath,
        'http://192.168.1.50:50505/api/v1/stream/track_mp3_002',
      );
      expect(t2.hasCustomMetadata, isFalse);
      expect(t2.customMetadata.customCoverPath, isNull);
    });

    test('handles empty remote catalog cleanly', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({'status': 'ok', 'count': 0, 'tracks': []}),
          200,
        );
      });

      final client = LocalSyncClient(baseUrl: testBaseUrl, client: mock);
      final tracks = await client.fetchLibrary();
      expect(tracks, isEmpty);
    });

    test('throws LocalSyncClientException when server reports error status', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({'status': 'error', 'error': 'Database locked'}),
          200,
        );
      });

      final client = LocalSyncClient(baseUrl: testBaseUrl, client: mock);
      expect(
        () => client.fetchLibrary(),
        throwsA(isA<LocalSyncClientException>()),
      );
    });

    test('throws LocalSyncClientException on invalid non-list tracks field', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({'status': 'ok', 'tracks': 'invalid'}),
          200,
        );
      });

      final client = LocalSyncClient(baseUrl: testBaseUrl, client: mock);
      expect(
        () => client.fetchLibrary(),
        throwsA(isA<LocalSyncClientException>()),
      );
    });
  });

  group('LocalSyncClient downloadTrack() and SHA-256 Verification', () {
    test('downloads binary data and verifies SHA-256 successfully', () async {
      final dummyBytes = List<int>.generate(2048, (i) => i % 256);
      final expectedSha = sha256.convert(dummyBytes).toString();

      final mock = MockClient((request) async {
        expect(request.url.path, '/api/v1/download/track_999');
        return http.Response.bytes(
          dummyBytes,
          200,
          headers: {'X-Orpheus-SHA256': expectedSha},
        );
      });

      final client = LocalSyncClient(baseUrl: testBaseUrl, client: mock);
      final downloaded = await client.downloadTrack('track_999');

      expect(downloaded, equals(dummyBytes));
    });

    test('throws LocalSyncClientException when checksum fails', () async {
      final dummyBytes = [1, 2, 3, 4, 5];

      final mock = MockClient((request) async {
        return http.Response.bytes(
          dummyBytes,
          200,
          headers: {'X-Orpheus-SHA256': 'bad_sha256_hash_here'},
        );
      });

      final client = LocalSyncClient(baseUrl: testBaseUrl, client: mock);

      expect(
        () => client.downloadTrack('track_999'),
        throwsA(
          predicate<LocalSyncClientException>(
            (e) => e.message.contains('integrity verification failed'),
          ),
        ),
      );
    });
  });

  group('AudioPlayerService Remote Streaming & URI Integration', () {
    test('isRemoteUri accurately identifies remote vs local schemes', () {
      expect(AudioPlayerService.isRemoteUri('http://192.168.1.50:50505/api/v1/stream/t1'), isTrue);
      expect(AudioPlayerService.isRemoteUri('https://example.com/stream.mp3'), isTrue);
      expect(AudioPlayerService.isRemoteUri('HTTP://LAN-NODE/stream'), isTrue);

      expect(AudioPlayerService.isRemoteUri('/home/user/Music/song.flac'), isFalse);
      expect(AudioPlayerService.isRemoteUri('C:\\Users\\User\\Music\\song.mp3'), isFalse);
      expect(AudioPlayerService.isRemoteUri(''), isFalse);
      expect(AudioPlayerService.isRemoteUri(null), isFalse);
    });

    test('formatMediaUri formats local paths and preserves remote URLs', () {
      expect(
        AudioPlayerService.formatMediaUri('http://192.168.1.50:50505/api/v1/stream/t1'),
        'http://192.168.1.50:50505/api/v1/stream/t1',
      );
      expect(
        AudioPlayerService.formatMediaUri('/storage/song.flac'),
        'file:///storage/song.flac',
      );
    });

    test('formatArtUri handles remote cover URLs, local paths and null values', () {
      expect(
        AudioPlayerService.formatArtUri('http://192.168.1.50:50505/api/v1/art/t1'),
        'http://192.168.1.50:50505/api/v1/art/t1',
      );
      expect(
        AudioPlayerService.formatArtUri('/storage/cover.jpg'),
        'file:///storage/cover.jpg',
      );
      expect(AudioPlayerService.formatArtUri(null), isNull);
      expect(AudioPlayerService.formatArtUri('   '), isNull);
    });

    test('AudioPlayerService accepts remote HTTP stream track seamlessly', () async {
      final player = AudioPlayerService.instance;
      await player.stopAndReset(clearHistory: true);

      final remoteTrack = Track()
        ..trackId = 'remote_stream_1'
        ..title = 'Cloud Symphony'
        ..artist = 'Remote Artist'
        ..album = 'Remote Album'
        ..duration = 320
        ..filePath = 'http://192.168.1.50:50505/api/v1/stream/remote_stream_1'
        ..hasCustomMetadata = true
        ..customMetadata = (CustomMetadata()
          ..customCoverPath = 'http://192.168.1.50:50505/api/v1/art/remote_stream_1');

      player.addToQueue(remoteTrack);

      expect(player.queue.length, 1);
      expect(player.currentTrack?.trackId, 'remote_stream_1');
      expect(player.currentTrack?.filePath, 'http://192.168.1.50:50505/api/v1/stream/remote_stream_1');
      expect(
        AudioPlayerService.isRemoteUri(player.currentTrack!.filePath),
        isTrue,
      );
    });
  });

  group('Hermetic Integration: LocalSyncClient with LocalSyncServer', () {
    late Directory tempDir;
    late File audioFile;
    late File artFile;
    late Track testTrack;
    late LocalSyncServer server;
    late LocalSyncClient client;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('orpheus_client_integration_');
      audioFile = File('${tempDir.path}/track.flac');
      await audioFile.writeAsBytes(List.generate(1024, (i) => i % 256));

      artFile = File('${tempDir.path}/cover.jpg');
      await artFile.writeAsBytes([10, 20, 30, 40]);

      testTrack = Track()
        ..trackId = 'integration_track_01'
        ..filePath = audioFile.path
        ..title = 'Direct Wire Track'
        ..artist = 'Direct Wire Artist'
        ..album = 'Direct Wire Album'
        ..duration = 195
        ..fileType = FileType.flac
        ..audioQuality = 'HI-FI'
        ..isLiked = true
        ..hasCustomMetadata = true
        ..customMetadata = (CustomMetadata()..customCoverPath = artFile.path);

      server = LocalSyncServer(
        deviceName: 'Hermetic-Node',
        tracksProvider: () async => [testTrack],
        trackByIdProvider: (id) async => id == testTrack.trackId ? testTrack : null,
      );

      // Bind to direct shelf handler via simulated mock client
      final mock = MockClient((request) async {
        final shelfRequest = shelfRequestFromHttp(request);
        final shelfResponse = await server.handler(shelfRequest);
        return httpResponseFromShelf(shelfResponse);
      });

      client = LocalSyncClient(baseUrl: 'http://localhost:50505', client: mock);
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('pingNode fetches server metadata from real handler', () async {
      final ping = await client.pingNode();
      expect(ping.isOk, isTrue);
      expect(ping.deviceName, 'Hermetic-Node');
      expect(ping.service, 'orpheus-sync');
    });

    test('fetchLibrary decodes real server catalog and populates stream & art URLs', () async {
      final tracks = await client.fetchLibrary();
      expect(tracks.length, 1);
      final t = tracks.first;

      expect(t.trackId, 'integration_track_01');
      expect(t.displayTitle, 'Direct Wire Track');
      expect(t.displayArtist, 'Direct Wire Artist');
      expect(t.filePath, 'http://localhost:50505/api/v1/stream/integration_track_01');
      expect(t.hasCustomMetadata, isTrue);
      expect(
        t.customMetadata.customCoverPath,
        'http://localhost:50505/api/v1/art/integration_track_01',
      );
    });

    test('downloadTrack receives full binary with valid SHA-256', () async {
      final bytes = await client.downloadTrack('integration_track_01');
      expect(bytes.length, 1024);
      expect(sha256.convert(bytes).toString(), sha256.convert(await audioFile.readAsBytes()).toString());
    });
  });
}

// ── Helpers to bridge shelf and http for mock client hermetic tests ──────────

shelf.Request shelfRequestFromHttp(http.Request request) {
  return shelf.Request(
    request.method,
    request.url,
    headers: request.headers,
    body: request.bodyBytes,
  );
}

Future<http.Response> httpResponseFromShelf(shelf.Response response) async {
  final bodyBytes = await response.read().fold<List<int>>(
        <int>[],
        (prev, chunk) => prev..addAll(chunk),
      );
  return http.Response.bytes(
    bodyBytes,
    response.statusCode,
    headers: response.headers,
  );
}
