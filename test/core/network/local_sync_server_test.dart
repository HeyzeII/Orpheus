import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:orpheus/core/models/custom_metadata.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/network/local_sync_server.dart';
import 'package:shelf/shelf.dart';

void main() {
  late Directory tempDir;
  late File sampleAudioFile;
  late File sampleArtFile;
  late Track mockTrackWithArt;
  late Track mockTrackWithoutArt;
  late List<int> audioData;
  late List<int> artData;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('orpheus_server_test_');

    // 100 KB test dummy audio file
    audioData = List.generate(100 * 1024, (i) => i % 256);
    sampleAudioFile = File('${tempDir.path}/test_song.flac');
    await sampleAudioFile.writeAsBytes(audioData);

    // 10 KB dummy cover art file
    artData = List.generate(10 * 1024, (i) => (i * 3) % 256);
    sampleArtFile = File('${tempDir.path}/test_cover.jpg');
    await sampleArtFile.writeAsBytes(artData);

    mockTrackWithArt = Track()
      ..trackId = 'track_12345'
      ..filePath = sampleAudioFile.path
      ..title = 'Orpheus Symphony'
      ..artist = 'Master Musician'
      ..album = 'Sound of Eternity'
      ..duration = 240
      ..fileType = FileType.flac
      ..audioQuality = 'HI-FI'
      ..isLiked = true
      ..hasCustomMetadata = true
      ..customMetadata = (CustomMetadata()..customCoverPath = sampleArtFile.path);

    mockTrackWithoutArt = Track()
      ..trackId = 'track_67890'
      ..filePath = sampleAudioFile.path
      ..title = 'Raw Track'
      ..artist = 'Indie Artist'
      ..duration = 180
      ..fileType = FileType.mp3
      ..audioQuality = 'HQ';
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  LocalSyncServer createTestServer() {
    return LocalSyncServer(
      deviceName: 'Test-Orpheus-Machine',
      tracksProvider: () async => [mockTrackWithArt, mockTrackWithoutArt],
      trackByIdProvider: (trackId) async {
        if (trackId == mockTrackWithArt.trackId) return mockTrackWithArt;
        if (trackId == mockTrackWithoutArt.trackId) return mockTrackWithoutArt;
        return null;
      },
    );
  }

  group('LocalSyncServer Handlers (Direct Shelf Handler)', () {
    test('GET /api/v1/ping returns 200 with node metadata', () async {
      final server = createTestServer();
      final request = Request('GET', Uri.parse('http://localhost/api/v1/ping'));
      final response = await server.handler(request);

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('application/json'));

      final json = jsonDecode(await response.readAsString());
      expect(json['status'], 'ok');
      expect(json['service'], 'orpheus-sync');
      expect(json['version'], '1.0.0');
      expect(json['deviceName'], 'Test-Orpheus-Machine');
      expect(json['platform'], isNotEmpty);
      expect(json['timestamp'], isNotNull);
    });

    test('GET /api/v1/library returns track list catalog', () async {
      final server = createTestServer();
      final request = Request('GET', Uri.parse('http://localhost/api/v1/library'));
      final response = await server.handler(request);

      expect(response.statusCode, 200);
      final json = jsonDecode(await response.readAsString());
      expect(json['status'], 'ok');
      expect(json['count'], 2);

      final tracks = json['tracks'] as List;
      expect(tracks.length, 2);

      final t1 = tracks.firstWhere((t) => t['trackId'] == 'track_12345');
      expect(t1['title'], 'Orpheus Symphony');
      expect(t1['artist'], 'Master Musician');
      expect(t1['hasCover'], true);
      expect(t1['artUrl'], '/api/v1/art/track_12345');
      expect(t1['streamUrl'], '/api/v1/stream/track_12345');
      expect(t1['downloadUrl'], '/api/v1/download/track_12345');
      expect(t1['isLiked'], true);

      final t2 = tracks.firstWhere((t) => t['trackId'] == 'track_67890');
      expect(t2['hasCover'], false);
      expect(t2['artUrl'], isNull);
    });

    test('GET /api/v1/stream/<trackId> without Range serves full content (200 OK)', () async {
      final server = createTestServer();
      final request = Request('GET', Uri.parse('http://localhost/api/v1/stream/track_12345'));
      final response = await server.handler(request);

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'audio/flac');
      expect(response.headers['accept-ranges'], 'bytes');
      expect(response.headers['content-length'], audioData.length.toString());

      final bodyBytes = await response.read().expand((chunk) => chunk).toList();
      expect(bodyBytes, equals(audioData));
    });

    test('GET /api/v1/stream/<trackId> with Range serves 206 Partial Content (Seek)', () async {
      final server = createTestServer();
      const start = 1000;
      const end = 2999;
      const expectedLength = end - start + 1;

      final request = Request(
        'GET',
        Uri.parse('http://localhost/api/v1/stream/track_12345'),
        headers: {'range': 'bytes=$start-$end'},
      );
      final response = await server.handler(request);

      expect(response.statusCode, 206);
      expect(response.headers['content-range'], 'bytes $start-$end/${audioData.length}');
      expect(response.headers['content-length'], expectedLength.toString());
      expect(response.headers['accept-ranges'], 'bytes');
      expect(response.headers['content-type'], 'audio/flac');

      final bodyBytes = await response.read().expand((chunk) => chunk).toList();
      expect(bodyBytes.length, expectedLength);
      expect(bodyBytes, equals(audioData.sublist(start, end + 1)));
    });

    test('GET /api/v1/stream/<trackId> with open-ended Range bytes=50000-', () async {
      final server = createTestServer();
      const start = 50000;
      final expectedLength = audioData.length - start;

      final request = Request(
        'GET',
        Uri.parse('http://localhost/api/v1/stream/track_12345'),
        headers: {'range': 'bytes=$start-'},
      );
      final response = await server.handler(request);

      expect(response.statusCode, 206);
      expect(response.headers['content-range'], 'bytes $start-${audioData.length - 1}/${audioData.length}');
      expect(response.headers['content-length'], expectedLength.toString());

      final bodyBytes = await response.read().expand((chunk) => chunk).toList();
      expect(bodyBytes, equals(audioData.sublist(start)));
    });

    test('GET /api/v1/stream/<trackId> with out-of-bounds Range returns 416', () async {
      final server = createTestServer();
      final request = Request(
        'GET',
        Uri.parse('http://localhost/api/v1/stream/track_12345'),
        headers: {'range': 'bytes=999999-1000000'},
      );
      final response = await server.handler(request);

      expect(response.statusCode, 416);
      expect(response.headers['content-range'], 'bytes */${audioData.length}');
    });

    test('GET /api/v1/stream/<trackId> returns 404 for unknown track', () async {
      final server = createTestServer();
      final request = Request('GET', Uri.parse('http://localhost/api/v1/stream/non_existent'));
      final response = await server.handler(request);

      expect(response.statusCode, 404);
    });

    test('GET /api/v1/art/<trackId> returns 200 with image bytes', () async {
      final server = createTestServer();
      final request = Request('GET', Uri.parse('http://localhost/api/v1/art/track_12345'));
      final response = await server.handler(request);

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'image/jpeg');

      final bodyBytes = await response.read().expand((chunk) => chunk).toList();
      expect(bodyBytes, equals(artData));
    });

    test('GET /api/v1/art/<trackId> returns 404 when track has no artwork', () async {
      final server = createTestServer();
      final request = Request('GET', Uri.parse('http://localhost/api/v1/art/track_67890'));
      final response = await server.handler(request);

      expect(response.statusCode, 404);
    });

    test('GET /api/v1/download/<trackId> returns 200 with X-Orpheus-SHA256 header', () async {
      final server = createTestServer();
      final expectedSha = sha256.convert(audioData).toString();

      final request = Request('GET', Uri.parse('http://localhost/api/v1/download/track_12345'));
      final response = await server.handler(request);

      expect(response.statusCode, 200);
      expect(response.headers['x-orpheus-sha256'], expectedSha);
      expect(response.headers['content-disposition'], contains('test_song.flac'));

      final bodyBytes = await response.read().expand((chunk) => chunk).toList();
      expect(bodyBytes, equals(audioData));
    });
  });

  group('LocalSyncServer Live Socket Lifecycle', () {
    test('Starts on ephemeral port, responds via HTTP client, and stops cleanly', () async {
      final server = createTestServer();
      expect(server.isRunning, false);

      // Start on port 0 (ephemeral OS-allocated port)
      await server.start(port: 0);
      expect(server.isRunning, true);
      expect(server.port, isPositive);

      final pingUri = Uri.parse('http://127.0.0.1:${server.port}/api/v1/ping');
      final res = await http.get(pingUri);

      expect(res.statusCode, 200);
      final json = jsonDecode(res.body);
      expect(json['status'], 'ok');
      expect(json['deviceName'], 'Test-Orpheus-Machine');

      // Test real Range request over TCP socket
      final streamUri = Uri.parse('http://127.0.0.1:${server.port}/api/v1/stream/track_12345');
      final streamRes = await http.get(streamUri, headers: {'range': 'bytes=0-99'});
      expect(streamRes.statusCode, 206);
      expect(streamRes.bodyBytes.length, 100);
      expect(streamRes.headers['content-range'], 'bytes 0-99/${audioData.length}');

      // Stop server
      await server.stop();
      expect(server.isRunning, false);
    });
  });
}
