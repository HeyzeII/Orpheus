import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/models/custom_metadata.dart';
import 'package:orpheus/core/models/playlist.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/network/orpheus_beacon_service.dart';
import 'package:orpheus/core/services/audio_player_service.dart';
import 'package:orpheus/core/services/offline_reconciliation_service.dart';

class FakeLocalDatabase extends LocalDatabase {
  FakeLocalDatabase() : super.internal();

  final Map<int, Track> _tracks = {};
  final Map<String, Playlist> _playlists = {};

  @override
  Future<List<Track>> getAllTracks() async => _tracks.values.toList();

  @override
  Future<void> saveTrack(Track track) async {
    _tracks[track.id] = track;
  }

  @override
  Future<void> deleteTrack(int id) async {
    _tracks.remove(id);
  }

  @override
  Future<List<Playlist>> getAllPlaylists() async => _playlists.values.toList();

  @override
  Future<void> savePlaylist(Playlist playlist) async {
    _playlists[playlist.playlistId] = playlist;
  }
}

class FakeBeaconService extends OrpheusBeaconService {
  final StreamController<List<DiscoveredNode>> _controller =
      StreamController<List<DiscoveredNode>>.broadcast();

  @override
  Stream<List<DiscoveredNode>> get onNodesChanged => _controller.stream;

  void emitNodes(List<DiscoveredNode> nodes) {
    _controller.add(nodes);
  }

  void close() {
    _controller.close();
  }
}

void main() {
  late Directory tempDir;
  late Directory downloadDir;
  late FakeLocalDatabase fakeDb;
  late FakeBeaconService fakeBeacon;
  late OfflineReconciliationService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('orpheus_recon_test_');
    downloadDir = Directory('${tempDir.path}/downloads');
    await downloadDir.create(recursive: true);

    fakeDb = FakeLocalDatabase();
    fakeBeacon = FakeBeaconService();

    service = OfflineReconciliationService(
      db: fakeDb,
      beaconService: fakeBeacon,
      customDownloadDirectory: downloadDir,
    );
  });

  tearDown(() async {
    fakeBeacon.close();
    service.dispose();
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Track createTrackFixture({
    required int id,
    required String trackId,
    required String title,
    String? filePath,
    String? downloadSource,
    DateTime? lastPlayedAt,
    String? customCoverPath,
  }) {
    final track = Track()
      ..id = id
      ..trackId = trackId
      ..title = title
      ..artist = 'Artist $id'
      ..album = 'Album $id'
      ..duration = 200
      ..filePath = filePath ?? '${downloadDir.path}/${trackId}_audio.flac'
      ..downloadSource = downloadSource
      ..lastPlayedAt = lastPlayedAt;

    if (customCoverPath != null) {
      track.hasCustomMetadata = true;
      track.customMetadata = CustomMetadata()..customCoverPath = customCoverPath;
    }
    return track;
  }

  File createDummyFile(String path, int sizeInBytes) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List<int>.filled(sizeInBytes, 42));
    return file;
  }

  group('SyncStorageQuota and PruneResult', () {
    test('SyncStorageQuota fromBytes and values', () {
      expect(SyncStorageQuota.fromBytes(0), SyncStorageQuota.unlimited);
      expect(SyncStorageQuota.fromBytes(1024 * 1024 * 1024), SyncStorageQuota.oneGb);
      expect(SyncStorageQuota.fromBytes(2 * 1024 * 1024 * 1024), SyncStorageQuota.twoGb);
      expect(SyncStorageQuota.fromBytes(5 * 1024 * 1024 * 1024), SyncStorageQuota.fiveGb);
      expect(SyncStorageQuota.fromBytes(10 * 1024 * 1024 * 1024), SyncStorageQuota.tenGb);
      expect(SyncStorageQuota.fromBytes(9999), SyncStorageQuota.unlimited);
    });

    test('PruneResult formattedBytesFreed output', () {
      expect(const PruneResult(prunedTrackCount: 0, bytesFreed: 0).formattedBytesFreed, '0 B');
      expect(const PruneResult(prunedTrackCount: 1, bytesFreed: 500).formattedBytesFreed, '500 B');
      expect(const PruneResult(prunedTrackCount: 1, bytesFreed: 2048).formattedBytesFreed, '2.0 KB');
      expect(
        const PruneResult(prunedTrackCount: 1, bytesFreed: 10 * 1024 * 1024).formattedBytesFreed,
        '10.00 MB',
      );
      expect(
        const PruneResult(prunedTrackCount: 1, bytesFreed: 2 * 1024 * 1024 * 1024).formattedBytesFreed,
        '2.00 GB',
      );
    });

    test('setQuota updates quotaNotifier value', () {
      expect(service.quotaNotifier.value, SyncStorageQuota.unlimited);
      service.setQuota(SyncStorageQuota.fiveGb);
      expect(service.quotaNotifier.value, SyncStorageQuota.fiveGb);
    });
  });

  group('Protected Track Identification', () {
    test('aggregates explicit IDs, liked tracks, and playlist tracks', () async {
      fakeDb.likedTrackIdsNotifier.value = {'liked_1', 'liked_2'};

      final t1 = createTrackFixture(id: 101, trackId: 'pl_track_1', title: 'Track 1');
      final t2 = createTrackFixture(id: 102, trackId: 'pl_track_2', title: 'Track 2');
      final t3 = createTrackFixture(id: 103, trackId: 'unprotected_1', title: 'Track 3');
      await fakeDb.saveTrack(t1);
      await fakeDb.saveTrack(t2);
      await fakeDb.saveTrack(t3);

      final playlist = Playlist()
        ..playlistId = 'pl_user_1'
        ..name = 'My Roadtrip'
        ..trackIds = [101, 102];
      await fakeDb.savePlaylist(playlist);

      final protected = await service.getProtectedTrackIds(
        explicitProtectedTrackIds: {'explicit_1'},
      );

      expect(protected, containsAll(['explicit_1', 'liked_1', 'liked_2', 'pl_track_1', 'pl_track_2']));
      expect(protected.contains('unprotected_1'), isFalse);
    });
  });

  group('calculateTotalDownloadedBytes', () {
    test('calculates correct byte sum in download directory', () async {
      expect(await service.calculateTotalDownloadedBytes(), 0);

      createDummyFile('${downloadDir.path}/track1.flac', 1000);
      createDummyFile('${downloadDir.path}/track2.flac', 2500);

      expect(await service.calculateTotalDownloadedBytes(), 3500);
    });
  });

  group('pruneOrphanDownloads', () {
    test('removes orphan tracks and keeps protected tracks intact', () async {
      final f1 = createDummyFile('${downloadDir.path}/prot_1_audio.flac', 2000);
      final f2 = createDummyFile('${downloadDir.path}/orphan_1_audio.flac', 4000);
      final c2 = createDummyFile('${downloadDir.path}/orphan_1_cover.jpg', 500);

      final protectedTrack = createTrackFixture(
        id: 1,
        trackId: 'prot_1',
        title: 'Protected Song',
        filePath: f1.path,
        downloadSource: 'http://192.168.1.50:50505/api/v1/download/prot_1',
      );

      final orphanTrack = createTrackFixture(
        id: 2,
        trackId: 'orphan_1',
        title: 'Orphan Song',
        filePath: f2.path,
        downloadSource: 'http://192.168.1.50:50505/api/v1/download/orphan_1',
        customCoverPath: c2.path,
      );

      await fakeDb.saveTrack(protectedTrack);
      await fakeDb.saveTrack(orphanTrack);

      fakeDb.likedTrackIdsNotifier.value = {'prot_1'};

      final result = await service.pruneOrphanDownloads(deleteFromDatabase: false);

      expect(result.prunedTrackCount, 1);
      expect(result.bytesFreed, 4500);
      expect(result.prunedTrackIds, contains('orphan_1'));

      expect(f1.existsSync(), isTrue);
      expect(f2.existsSync(), isFalse);
      expect(c2.existsSync(), isFalse);

      final allTracks = await fakeDb.getAllTracks();
      expect(allTracks.length, 2);

      final updatedOrphan = allTracks.firstWhere((t) => t.trackId == 'orphan_1');
      expect(updatedOrphan.filePath, 'http://192.168.1.50:50505/api/v1/stream/orphan_1');
      expect(updatedOrphan.downloadSource, isNull);
    });

    test('deletes orphan track record from database when deleteFromDatabase is true', () async {
      final f1 = createDummyFile('${downloadDir.path}/orphan_db.flac', 3000);
      final orphanTrack = createTrackFixture(
        id: 99,
        trackId: 'orphan_db',
        title: 'To Be Fully Deleted',
        filePath: f1.path,
        downloadSource: 'http://192.168.1.50:50505/api/v1/download/orphan_db',
      );
      await fakeDb.saveTrack(orphanTrack);

      final result = await service.pruneOrphanDownloads(deleteFromDatabase: true);

      expect(result.prunedTrackCount, 1);
      expect(result.bytesFreed, 3000);
      expect(f1.existsSync(), isFalse);

      final allTracks = await fakeDb.getAllTracks();
      expect(allTracks.isEmpty, isTrue);
    });

    test('deletes untracked orphan files residing in download directory', () async {
      final untrackedFile = createDummyFile('${downloadDir.path}/unknown_123_audio.flac', 1200);

      final result = await service.pruneOrphanDownloads();

      expect(result.prunedTrackCount, 1);
      expect(result.bytesFreed, 1200);
      expect(untrackedFile.existsSync(), isFalse);
    });
  });

  group('enforceStorageQuota (LRU Policy)', () {
    test('does nothing when quota is unlimited (0) or storage is within limit', () async {
      createDummyFile('${downloadDir.path}/track1.flac', 2000);
      final track = createTrackFixture(
        id: 1,
        trackId: 'track1',
        title: 'Song 1',
        filePath: '${downloadDir.path}/track1.flac',
        downloadSource: 'http://192.168.1.50:50505/api/v1/download/track1',
      );
      await fakeDb.saveTrack(track);

      final r1 = await service.enforceStorageQuota(maxBytes: 0);
      expect(r1.prunedTrackCount, 0);

      final r2 = await service.enforceStorageQuota(maxBytes: 5000);
      expect(r2.prunedTrackCount, 0);
    });

    test('evicts unprotected tracks by LRU: never-played first, then oldest lastPlayedAt', () async {
      final now = DateTime.now();

      final fNever = createDummyFile('${downloadDir.path}/t_never_audio.flac', 1000);
      final fOld = createDummyFile('${downloadDir.path}/t_old_audio.flac', 1000);
      final fRecent = createDummyFile('${downloadDir.path}/t_recent_audio.flac', 1000);

      final tNever = createTrackFixture(
        id: 1,
        trackId: 't_never',
        title: 'Never Played',
        filePath: fNever.path,
        downloadSource: 'http://192.168.1.50:50505/api/v1/download/t_never',
        lastPlayedAt: null,
      );

      final tOld = createTrackFixture(
        id: 2,
        trackId: 't_old',
        title: 'Played Long Ago',
        filePath: fOld.path,
        downloadSource: 'http://192.168.1.50:50505/api/v1/download/t_old',
        lastPlayedAt: now.subtract(const Duration(days: 30)),
      );

      final tRecent = createTrackFixture(
        id: 3,
        trackId: 't_recent',
        title: 'Played Recently',
        filePath: fRecent.path,
        downloadSource: 'http://192.168.1.50:50505/api/v1/download/t_recent',
        lastPlayedAt: now.subtract(const Duration(minutes: 5)),
      );

      await fakeDb.saveTrack(tNever);
      await fakeDb.saveTrack(tOld);
      await fakeDb.saveTrack(tRecent);

      expect(await service.calculateTotalDownloadedBytes(), 3000);

      // Quota is 2500 bytes -> need to evict 1 track (1000 bytes).
      // t_never should be evicted first.
      final result1 = await service.enforceStorageQuota(maxBytes: 2500);
      expect(result1.prunedTrackCount, 1);
      expect(result1.prunedTrackIds, ['t_never']);
      expect(fNever.existsSync(), isFalse);
      expect(fOld.existsSync(), isTrue);
      expect(fRecent.existsSync(), isTrue);

      // Next, reduce quota to 500 bytes -> t_old should be evicted, leaving t_recent
      final result2 = await service.enforceStorageQuota(maxBytes: 500);
      expect(result2.prunedTrackCount, 2); // t_old + t_recent evicted to fit 500 bytes
      expect(fOld.existsSync(), isFalse);
    });

    test('never evicts protected tracks even if quota is strictly exceeded', () async {
      final fProt = createDummyFile('${downloadDir.path}/t_prot_audio.flac', 2000);
      final fUnprot = createDummyFile('${downloadDir.path}/t_unprot_audio.flac', 2000);

      final tProt = createTrackFixture(
        id: 1,
        trackId: 't_prot',
        title: 'Protected Favorite',
        filePath: fProt.path,
        downloadSource: 'http://192.168.1.50:50505/api/v1/download/t_prot',
      );
      final tUnprot = createTrackFixture(
        id: 2,
        trackId: 't_unprot',
        title: 'Unprotected Casual Track',
        filePath: fUnprot.path,
        downloadSource: 'http://192.168.1.50:50505/api/v1/download/t_unprot',
      );

      await fakeDb.saveTrack(tProt);
      await fakeDb.saveTrack(tUnprot);

      fakeDb.likedTrackIdsNotifier.value = {'t_prot'};

      // Quota is 500 bytes -> unprot is evicted, but prot is strictly preserved
      final result = await service.enforceStorageQuota(maxBytes: 500);
      expect(result.prunedTrackCount, 1);
      expect(result.prunedTrackIds, ['t_unprot']);
      expect(fProt.existsSync(), isTrue);
      expect(fUnprot.existsSync(), isFalse);
    });
  });

  group('reconcileOnPeerStatusChanged and Playback Priority', () {
    test('upgrades remote HTTP track to local file if downloaded copy exists', () async {
      final localFile = createDummyFile('${downloadDir.path}/track_reconcile_01_hq.flac', 4096);

      final remoteTrack = createTrackFixture(
        id: 50,
        trackId: 'track_reconcile_01',
        title: 'Online Song',
        filePath: 'http://192.168.1.50:50505/api/v1/stream/track_reconcile_01',
      );
      await fakeDb.saveTrack(remoteTrack);

      final nodes = [
        DiscoveredNode(
          deviceId: 'node-remote',
          deviceName: 'Studio PC',
          platform: 'linux',
          port: 50505,
          address: InternetAddress('192.168.1.50'),
          version: '1.0.0',
          lastSeen: DateTime.now(),
        ),
      ];

      final count = await service.reconcileOnPeerStatusChanged(nodes);
      expect(count, 1);

      final allTracks = await fakeDb.getAllTracks();
      final updated = allTracks.firstWhere((t) => t.trackId == 'track_reconcile_01');
      expect(updated.filePath, localFile.path);
      expect(AudioPlayerService.isRemoteUri(updated.filePath), isFalse);
    });
  });

  group('isTrackReachable', () {
    test('local file returns true if file exists, false otherwise', () {
      final existing = createDummyFile('${downloadDir.path}/exists.flac', 100);
      final t1 = createTrackFixture(id: 1, trackId: 'ex', title: 'Ex', filePath: existing.path);
      final t2 = createTrackFixture(
        id: 2,
        trackId: 'non_ex',
        title: 'NonEx',
        filePath: '${downloadDir.path}/missing.flac',
      );

      expect(service.isTrackReachable(t1), isTrue);
      expect(service.isTrackReachable(t2), isFalse);
    });

    test('remote URI returns true only if matching peer is discovered', () {
      final remoteTrack = createTrackFixture(
        id: 10,
        trackId: 'remote_stream',
        title: 'Remote Song',
        filePath: 'http://192.168.1.88:50505/api/v1/stream/remote_stream',
      );

      final activeNodes = [
        DiscoveredNode(
          deviceId: 'node-88',
          deviceName: 'Server',
          platform: 'linux',
          port: 50505,
          address: InternetAddress('192.168.1.88'),
          version: '1.0.0',
          lastSeen: DateTime.now(),
        ),
      ];

      // With node active
      expect(service.isTrackReachable(remoteTrack, activeNodes: activeNodes), isTrue);

      // With no nodes active
      expect(service.isTrackReachable(remoteTrack, activeNodes: []), isFalse);
    });
  });

  group('startPeerMonitoring and stopPeerMonitoring', () {
    test('reacts to beacon service stream and updates lastKnownNodes', () async {
      service.startPeerMonitoring();

      final node = DiscoveredNode(
        deviceId: 'node-dyn',
        deviceName: 'Dynamic Node',
        platform: 'macos',
        port: 50505,
        address: InternetAddress('192.168.1.99'),
        version: '1.0.0',
        lastSeen: DateTime.now(),
      );

      fakeBeacon.emitNodes([node]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.lastKnownNodes.length, 1);
      expect(service.lastKnownNodes.first.deviceId, 'node-dyn');

      service.stopPeerMonitoring();
    });
  });
}
