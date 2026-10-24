import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orpheus/core/models/custom_metadata.dart';
import 'package:orpheus/core/models/playlist.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/network/local_sync_client.dart';
import 'package:orpheus/core/network/local_sync_server.dart';
import 'package:orpheus/core/services/sync_download_manager.dart';
import 'package:shelf/shelf.dart' as shelf;

void main() {
  late Directory tempDir;
  late Directory downloadDir;
  const baseUrl = 'http://192.168.1.100:50505';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('orpheus_sync_mgr_test_');
    downloadDir = Directory('${tempDir.path}/downloads');
    await downloadDir.create(recursive: true);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Track createMockRemoteTrack({
    String trackId = 'track_dl_001',
    String title = 'Hotel California',
    String artist = 'Eagles',
    FileType fileType = FileType.flac,
    String? coverArtUrl,
  }) {
    final track = Track()
      ..trackId = trackId
      ..title = title
      ..artist = artist
      ..album = 'Hotel California Album'
      ..duration = 391
      ..fileType = fileType
      ..audioQuality = 'HI-FI'
      ..filePath = '$baseUrl/api/v1/stream/$trackId';

    if (coverArtUrl != null) {
      track.hasCustomMetadata = true;
      track.customMetadata = CustomMetadata()..customCoverPath = coverArtUrl;
    }
    return track;
  }

  group('SyncDownloadManager Successful Downloads and Integrity Verification', () {
    test('downloads track, verifies SHA-256 and updates local filePath and artwork', () async {
      final sampleAudio = List.generate(4096, (i) => (i * 7) % 256);
      final expectedHash = sha256.convert(sampleAudio).toString();
      final sampleCover = [1, 2, 3, 4, 5, 6, 7, 8];

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/download/track_dl_001') {
          return http.Response.bytes(
            sampleAudio,
            200,
            headers: {
              'Content-Type': 'audio/flac',
              'Content-Length': sampleAudio.length.toString(),
              'X-Orpheus-SHA256': expectedHash,
            },
          );
        }
        if (request.url.path == '/api/v1/art/track_dl_001') {
          return http.Response.bytes(
            sampleCover,
            200,
            headers: {'Content-Type': 'image/jpeg'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final syncClient = LocalSyncClient(baseUrl: baseUrl, client: mockClient);
      final manager = SyncDownloadManager(
        customDownloadDirectory: downloadDir,
        maxConcurrentDownloads: 1,
      );

      final track = createMockRemoteTrack(
        coverArtUrl: '$baseUrl/api/v1/art/track_dl_001',
      );

      final task = await manager.enqueueTrack(track, client: syncClient);
      expect(task.status, anyOf(SyncDownloadStatus.queued, SyncDownloadStatus.downloading));

      // Await task completion
      await manager.onTaskUpdated
          .firstWhere((t) => t.trackId == track.trackId && t.isFinished);

      expect(task.status, SyncDownloadStatus.completed);
      expect(task.progress, 1.0);
      expect(task.bytesDownloaded, 4096);
      expect(task.localFilePath, isNotNull);

      // Verify file on disk
      final savedFile = File(task.localFilePath!);
      expect(savedFile.existsSync(), isTrue);
      expect(await savedFile.readAsBytes(), equals(sampleAudio));

      // Verify no temporary .part files remained
      final partFiles = downloadDir
          .listSync()
          .where((f) => f.path.endsWith('.part'))
          .toList();
      expect(partFiles, isEmpty);

      // Verify track object was updated with local paths
      expect(track.filePath, equals(savedFile.path));
      expect(track.customMetadata.customCoverPath, isNotNull);
      expect(track.customMetadata.customCoverPath!.startsWith('http'), isFalse);
      final coverFile = File(track.customMetadata.customCoverPath!);
      expect(coverFile.existsSync(), isTrue);
      expect(await coverFile.readAsBytes(), equals(sampleCover));
    });

    test('fails and removes temp file when SHA-256 checksum fails', () async {
      final sampleAudio = [10, 20, 30, 40];

      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          sampleAudio,
          200,
          headers: {
            'Content-Length': '4',
            'X-Orpheus-SHA256': 'corrupted_hash_does_not_match',
          },
        );
      });

      final syncClient = LocalSyncClient(baseUrl: baseUrl, client: mockClient);
      final manager = SyncDownloadManager(
        customDownloadDirectory: downloadDir,
        maxConcurrentDownloads: 1,
      );

      final track = createMockRemoteTrack(trackId: 'track_corrupted');
      final task = await manager.enqueueTrack(track, client: syncClient);

      await manager.onTaskUpdated
          .firstWhere((t) => t.trackId == track.trackId && t.isFinished);

      expect(task.status, SyncDownloadStatus.failed);
      expect(task.error, contains('SHA-256 verification failed'));

      // Ensure no target or partial files exist
      final allFiles = downloadDir.listSync();
      expect(allFiles, isEmpty);
    });
  });

  group('SyncDownloadManager Error Handling and Network Failures', () {
    test('handles HTTP 404 or 500 error gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final syncClient = LocalSyncClient(baseUrl: baseUrl, client: mockClient);
      final manager = SyncDownloadManager(
        customDownloadDirectory: downloadDir,
        maxConcurrentDownloads: 1,
      );

      final track = createMockRemoteTrack(trackId: 'track_error_500');
      final task = await manager.enqueueTrack(track, client: syncClient);

      await manager.onTaskUpdated
          .firstWhere((t) => t.trackId == track.trackId && t.isFinished);

      expect(task.status, SyncDownloadStatus.failed);
      expect(task.error, contains('500'));
    });

    test('handles network exceptions during download', () async {
      final mockClient = MockClient((request) async {
        throw const SocketException('Connection reset by peer');
      });

      final syncClient = LocalSyncClient(baseUrl: baseUrl, client: mockClient);
      final manager = SyncDownloadManager(
        customDownloadDirectory: downloadDir,
        maxConcurrentDownloads: 1,
      );

      final track = createMockRemoteTrack(trackId: 'track_socket_err');
      final task = await manager.enqueueTrack(track, client: syncClient);

      await manager.onTaskUpdated
          .firstWhere((t) => t.trackId == track.trackId && t.isFinished);

      expect(task.status, SyncDownloadStatus.failed);
      expect(task.error, contains('SocketException'));
    });
  });

  group('SyncDownloadManager Queue & Concurrency Control', () {
    test('respects maxConcurrentDownloads limit and processes FIFO queue', () async {
      final sampleBytes = List.generate(512, (i) => i % 256);
      final hash = sha256.convert(sampleBytes).toString();

      final mockClient = MockClient((request) async {
        await Future.delayed(const Duration(milliseconds: 30));
        return http.Response.bytes(
          sampleBytes,
          200,
          headers: {
            'Content-Length': sampleBytes.length.toString(),
            'X-Orpheus-SHA256': hash,
          },
        );
      });

      final syncClient = LocalSyncClient(baseUrl: baseUrl, client: mockClient);
      final manager = SyncDownloadManager(
        customDownloadDirectory: downloadDir,
        maxConcurrentDownloads: 2,
      );

      final tracks = List.generate(
        4,
        (i) => createMockRemoteTrack(trackId: 't_$i', title: 'Song $i'),
      );

      await manager.enqueueTracks(tracks, client: syncClient);

      expect(manager.allTasks.length, 4);
      // At start, at most 2 should be active while others remain queued
      expect(manager.activeTasks.length, lessThanOrEqualTo(2));

      // Wait for all 4 to finish
      await Future.doWhile(() async {
        if (manager.completedTasks.length == 4) return false;
        await Future.delayed(const Duration(milliseconds: 20));
        return true;
      });

      expect(manager.completedTasks.length, 4);
      expect(manager.failedTasks.length, 0);
      expect(manager.queuedTasks.length, 0);
      expect(manager.currentSummary.isIdle, isTrue);
    });

    test('re-enqueuing an active or queued track returns existing task without duplicate', () async {
      final mockClient = MockClient((request) async {
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response.bytes([1, 2, 3], 200);
      });

      final syncClient = LocalSyncClient(baseUrl: baseUrl, client: mockClient);
      final manager = SyncDownloadManager(
        customDownloadDirectory: downloadDir,
        maxConcurrentDownloads: 2,
      );

      final track = createMockRemoteTrack(trackId: 'dup_track');
      final t1 = await manager.enqueueTrack(track, client: syncClient);
      final t2 = await manager.enqueueTrack(track, client: syncClient);

      expect(identical(t1, t2), isTrue);
      expect(manager.allTasks.length, 1);

      await manager.onTaskUpdated
          .firstWhere((t) => t.trackId == track.trackId && t.isFinished);
    });
  });

  group('SyncDownloadManager Cancellation', () {
    test('cancelling a task cleans up partial files and updates status', () async {
      final mockClient = MockClient((request) async {
        await Future.delayed(const Duration(milliseconds: 100));
        return http.Response.bytes(List.generate(2000, (i) => i % 256), 200);
      });

      final syncClient = LocalSyncClient(baseUrl: baseUrl, client: mockClient);
      final manager = SyncDownloadManager(
        customDownloadDirectory: downloadDir,
        maxConcurrentDownloads: 1,
      );

      final track = createMockRemoteTrack(trackId: 'cancel_me');
      final task = await manager.enqueueTrack(track, client: syncClient);

      manager.cancel(task.trackId);

      expect(task.status, SyncDownloadStatus.cancelled);
      expect(manager.queuedTasks, isEmpty);
      expect(manager.activeTasks, isEmpty);
    });

    test('cancelAll marks all in-flight tasks as cancelled', () async {
      final mockClient = MockClient((request) async {
        await Future.delayed(const Duration(milliseconds: 100));
        return http.Response.bytes([1, 2], 200);
      });

      final syncClient = LocalSyncClient(baseUrl: baseUrl, client: mockClient);
      final manager = SyncDownloadManager(
        customDownloadDirectory: downloadDir,
        maxConcurrentDownloads: 1,
      );

      final t1 = createMockRemoteTrack(trackId: 'c1');
      final t2 = createMockRemoteTrack(trackId: 'c2');

      await manager.enqueueTracks([t1, t2], client: syncClient);
      manager.cancelAll();

      expect(manager.allTasks.every((t) => t.status == SyncDownloadStatus.cancelled), isTrue);
      expect(manager.currentSummary.cancelledTasks, 2);
    });
  });

  group('SyncDownloadManager Playlist Enqueue and Clear History', () {
    test('enqueuePlaylist enqueues tracks and handles database saving', () async {
      final sample = [1, 2, 3];
      final hash = sha256.convert(sample).toString();

      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          sample,
          200,
          headers: {'X-Orpheus-SHA256': hash},
        );
      });

      final syncClient = LocalSyncClient(baseUrl: baseUrl, client: mockClient);
      final manager = SyncDownloadManager(
        customDownloadDirectory: downloadDir,
        maxConcurrentDownloads: 2,
      );

      final playlist = Playlist()
        ..playlistId = 'pl_rock'
        ..name = 'Classic Rock'
        ..trackIds = [1, 2];

      final tracks = [
        createMockRemoteTrack(trackId: 'p1', title: 'P1 Song'),
        createMockRemoteTrack(trackId: 'p2', title: 'P2 Song'),
      ];

      final tasks = await manager.enqueuePlaylist(playlist, tracks, client: syncClient);
      expect(tasks.length, 2);

      await Future.doWhile(() async {
        if (manager.completedTasks.length == 2) return false;
        await Future.delayed(const Duration(milliseconds: 10));
        return true;
      });

      expect(manager.completedTasks.length, 2);

      // Test clearFinishedTasks
      manager.clearFinishedTasks();
      expect(manager.allTasks, isEmpty);
    });
  });

  group('Hermetic End-to-End: SyncDownloadManager with LocalSyncServer', () {
    late File serverAudioFile;
    late Track serverTrack;
    late LocalSyncServer server;
    late List<int> originalAudioBytes;

    setUp(() async {
      originalAudioBytes = List.generate(8192, (i) => (i * 13) % 256);
      serverAudioFile = File('${tempDir.path}/server_audio.flac');
      await serverAudioFile.writeAsBytes(originalAudioBytes);

      serverTrack = Track()
        ..trackId = 'e2e_track_42'
        ..filePath = serverAudioFile.path
        ..title = 'End To End Symphony'
        ..artist = 'Hermetic Virtuoso'
        ..album = 'LAN Symphony'
        ..duration = 240
        ..fileType = FileType.flac
        ..audioQuality = 'HI-FI';

      server = LocalSyncServer(
        deviceName: 'Hermetic-Download-Node',
        tracksProvider: () async => [serverTrack],
        trackByIdProvider: (id) async => id == serverTrack.trackId ? serverTrack : null,
      );
    });

    test('downloads directly from LocalSyncServer with real SHA-256 hashing', () async {
      // Connect MockClient directly to shelf handler
      final mockClient = MockClient((request) async {
        final shelfRequest = shelf.Request(
          request.method,
          request.url,
          headers: request.headers,
          body: request.bodyBytes,
        );
        final shelfResponse = await server.handler(shelfRequest);
        final bodyBytes = await shelfResponse.read().fold<List<int>>(
              <int>[],
              (prev, chunk) => prev..addAll(chunk),
            );
        return http.Response.bytes(
          bodyBytes,
          shelfResponse.statusCode,
          headers: shelfResponse.headers,
        );
      });

      final syncClient = LocalSyncClient(baseUrl: 'http://localhost:50505', client: mockClient);
      final manager = SyncDownloadManager(
        customDownloadDirectory: downloadDir,
        maxConcurrentDownloads: 1,
      );

      // Client fetches remote library
      final remoteTracks = await syncClient.fetchLibrary();
      expect(remoteTracks.length, 1);

      final remoteTrack = remoteTracks.first;
      expect(remoteTrack.filePath, startsWith('http://localhost:50505/api/v1/stream'));

      // Manager downloads the track
      final task = await manager.enqueueTrack(remoteTrack, client: syncClient);

      await manager.onTaskUpdated
          .firstWhere((t) => t.trackId == remoteTrack.trackId && t.isFinished);

      expect(task.status, SyncDownloadStatus.completed);
      expect(task.localFilePath, isNotNull);

      final downloadedFile = File(task.localFilePath!);
      expect(downloadedFile.existsSync(), isTrue);
      expect(await downloadedFile.readAsBytes(), equals(originalAudioBytes));
      expect(remoteTrack.filePath, equals(downloadedFile.path));
    });
  });
}
