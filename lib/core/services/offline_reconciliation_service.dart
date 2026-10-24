import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../database/local_database.dart';
import '../models/models.dart';
import '../network/orpheus_beacon_service.dart';
import '../services/audio_player_service.dart';
import '../services/sync_download_manager.dart';

/// Predefined storage quota choices for synced offline music files.
enum SyncStorageQuota {
  unlimited(0, 'Sin límite'),
  oneGb(1024 * 1024 * 1024, '1 GB'),
  twoGb(2 * 1024 * 1024 * 1024, '2 GB'),
  fiveGb(5 * 1024 * 1024 * 1024, '5 GB'),
  tenGb(10 * 1024 * 1024 * 1024, '10 GB');

  final int bytes;
  final String label;

  const SyncStorageQuota(this.bytes, this.label);

  static SyncStorageQuota fromBytes(int bytes) {
    for (final q in values) {
      if (q.bytes == bytes) return q;
    }
    return SyncStorageQuota.unlimited;
  }
}

/// Structured summary of an offline cleanup or pruning operation.
class PruneResult {
  final int prunedTrackCount;
  final int bytesFreed;
  final List<String> prunedTrackIds;

  const PruneResult({
    required this.prunedTrackCount,
    required this.bytesFreed,
    this.prunedTrackIds = const [],
  });

  /// Human-readable representation of freed disk space.
  String get formattedBytesFreed {
    if (bytesFreed <= 0) return '0 B';
    if (bytesFreed < 1024) return '$bytesFreed B';
    if (bytesFreed < 1024 * 1024) {
      return '${(bytesFreed / 1024).toStringAsFixed(1)} KB';
    }
    if (bytesFreed < 1024 * 1024 * 1024) {
      return '${(bytesFreed / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytesFreed / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  String toString() =>
      'PruneResult(pruned: $prunedTrackCount, freed: $formattedBytesFreed)';
}

/// Service managing offline storage policies, orphan file pruning, storage quotas (LRU),
/// and dynamic peer status reconciliation for local network synchronization.
class OfflineReconciliationService {
  OfflineReconciliationService({
    LocalDatabase? db,
    SyncDownloadManager? downloadManager,
    OrpheusBeaconService? beaconService,
    AudioPlayerService? playerService,
    this.customDownloadDirectory,
  })  : _db = db ?? LocalDatabase.instance,
        _downloadManager = downloadManager ?? SyncDownloadManager.instance,
        _beaconService = beaconService ?? OrpheusBeaconService.instance,
        _playerService = playerService ?? AudioPlayerService.instance;

  static final OfflineReconciliationService instance =
      OfflineReconciliationService();

  final LocalDatabase _db;
  final SyncDownloadManager _downloadManager;
  final OrpheusBeaconService _beaconService;
  final AudioPlayerService _playerService;
  final Directory? customDownloadDirectory;

  final ValueNotifier<SyncStorageQuota> quotaNotifier =
      ValueNotifier<SyncStorageQuota>(SyncStorageQuota.unlimited);

  StreamSubscription<List<DiscoveredNode>>? _beaconSub;
  List<DiscoveredNode> _lastKnownNodes = [];

  List<DiscoveredNode> get lastKnownNodes =>
      List.unmodifiable(_lastKnownNodes);

  /// Resolves the active download directory used for offline sync media.
  Future<Directory> resolveDownloadDirectory() async {
    final custom = customDownloadDirectory;
    if (custom != null) {
      return custom;
    }
    return _downloadManager.resolveDownloadDirectory();
  }

  /// Sets the storage quota for offline sync downloads.
  void setQuota(SyncStorageQuota quota) {
    quotaNotifier.value = quota;
  }

  // ── Protected Track Identification ──────────────────────────────────────────

  /// Collects all track IDs protected from deletion:
  /// 1. Tracks in the user's "Liked / Favorites" playlist (`likedTrackIdsNotifier`).
  /// 2. Tracks belonging to any playlist currently saved in [LocalDatabase].
  /// 3. Any explicitly passed [explicitProtectedTrackIds].
  Future<Set<String>> getProtectedTrackIds({
    Set<String>? explicitProtectedTrackIds,
  }) async {
    final protectedIds = <String>{};

    if (explicitProtectedTrackIds != null) {
      protectedIds.addAll(explicitProtectedTrackIds);
    }

    // 1. Favorites / Liked tracks
    protectedIds.addAll(_db.likedTrackIdsNotifier.value);

    // 2. Playlists tracks
    try {
      final playlists = await _db.getAllPlaylists();
      final allTrackIds = <int>{};
      for (final pl in playlists) {
        allTrackIds.addAll(pl.trackIds);
      }

      if (allTrackIds.isNotEmpty) {
        final allTracks = await _db.getAllTracks();
        for (final track in allTracks) {
          if (allTrackIds.contains(track.id)) {
            protectedIds.add(track.trackId);
          }
        }
      }
    } catch (_) {}

    return protectedIds;
  }

  /// Computes the total disk space consumed by files in the download directory.
  Future<int> calculateTotalDownloadedBytes() async {
    final downloadDir = await resolveDownloadDirectory();
    if (!downloadDir.existsSync()) return 0;

    int total = 0;
    try {
      final entities = downloadDir.listSync(recursive: true, followLinks: false);
      for (final entity in entities) {
        if (entity is File) {
          total += entity.lengthSync();
        }
      }
    } catch (_) {}

    return total;
  }

  // ── Orphan Pruning ──────────────────────────────────────────────────────────

  /// Scans local sync storage and removes tracks that do NOT belong to any protected
  /// playlist or favorite list.
  ///
  /// - Deletes physical audio and cover files from disk.
  /// - If [deleteFromDatabase] is true, deletes the track record from Isar entirely.
  /// - Otherwise, reverts `filePath` back to its remote HTTP streaming URL if `downloadSource`
  ///   is available, clearing the downloaded status.
  Future<PruneResult> pruneOrphanDownloads({
    Set<String>? explicitProtectedTrackIds,
    bool deleteFromDatabase = false,
  }) async {
    final protectedIds = await getProtectedTrackIds(
      explicitProtectedTrackIds: explicitProtectedTrackIds,
    );

    final downloadDir = await resolveDownloadDirectory();
    final allTracks = await _db.getAllTracks();

    int prunedCount = 0;
    int bytesFreed = 0;
    final prunedIds = <String>[];

    for (final track in allTracks) {
      final isDownloaded = (track.downloadSource != null &&
              track.downloadSource!.isNotEmpty) ||
          (downloadDir.existsSync() &&
              p.isWithin(downloadDir.path, track.filePath));

      if (!isDownloaded) continue;

      if (!protectedIds.contains(track.trackId)) {
        // Track is an orphan: delete file and revert or remove
        final file = File(track.filePath);
        if (file.existsSync()) {
          try {
            final size = file.lengthSync();
            file.deleteSync();
            bytesFreed += size;
          } catch (_) {}
        }

        // Check if cover art is inside download directory
        final coverPath = track.customMetadata.customCoverPath;
        if (coverPath != null &&
            downloadDir.existsSync() &&
            p.isWithin(downloadDir.path, coverPath)) {
          final coverFile = File(coverPath);
          if (coverFile.existsSync()) {
            try {
              bytesFreed += coverFile.lengthSync();
              coverFile.deleteSync();
            } catch (_) {}
          }
        }

        if (deleteFromDatabase) {
          try {
            await _db.deleteTrack(track.id);
          } catch (_) {}
        } else {
          // Revert back to remote streaming URI if available
          if (track.downloadSource != null &&
              track.downloadSource!.contains('/api/v1/download/')) {
            track.filePath = track.downloadSource!.replaceAll(
              '/api/v1/download/',
              '/api/v1/stream/',
            );
          }
          track.downloadSource = null;
          try {
            await _db.saveTrack(track);
          } catch (_) {}
        }

        prunedCount++;
        prunedIds.add(track.trackId);
      }
    }

    // Also scan download directory for orphaned files not matching any protected ID
    if (downloadDir.existsSync()) {
      try {
        final files = downloadDir.listSync(recursive: false);
        for (final entity in files) {
          if (entity is File) {
            final basename = p.basenameWithoutExtension(entity.path);

            final isProtected = protectedIds.any(
              (id) =>
                  basename == id ||
                  basename.startsWith('${id}_') ||
                  basename.startsWith('$id.'),
            );
            if (isProtected) continue;

            final isAlreadyPruned = prunedIds.any(
              (id) =>
                  basename == id ||
                  basename.startsWith('${id}_') ||
                  basename.startsWith('$id.'),
            );
            if (isAlreadyPruned) continue;

            final size = entity.lengthSync();
            entity.deleteSync();
            bytesFreed += size;
            prunedCount++;
            prunedIds.add(basename);
          }
        }
      } catch (_) {}
    }

    return PruneResult(
      prunedTrackCount: prunedCount,
      bytesFreed: bytesFreed,
      prunedTrackIds: prunedIds,
    );
  }

  // ── Storage Quota Enforcement (LRU) ─────────────────────────────────────────

  /// Enforces a maximum storage quota in bytes.
  ///
  /// If total downloaded sync bytes exceed [maxBytes] (or [quotaNotifier.value.bytes]),
  /// unprotected downloaded tracks are evicted based on LRU (least recently played,
  /// according to `lastPlayedAt` in Isar) until storage falls within the quota.
  Future<PruneResult> enforceStorageQuota({
    int? maxBytes,
    Set<String>? explicitProtectedTrackIds,
  }) async {
    final effectiveMax = maxBytes ?? quotaNotifier.value.bytes;
    if (effectiveMax <= 0) {
      // 0 represents unlimited quota
      return const PruneResult(prunedTrackCount: 0, bytesFreed: 0);
    }

    int currentBytes = await calculateTotalDownloadedBytes();
    if (currentBytes <= effectiveMax) {
      return const PruneResult(prunedTrackCount: 0, bytesFreed: 0);
    }

    final protectedIds = await getProtectedTrackIds(
      explicitProtectedTrackIds: explicitProtectedTrackIds,
    );

    final downloadDir = await resolveDownloadDirectory();
    final allTracks = await _db.getAllTracks();

    // Collect all unprotected downloaded tracks
    final candidateTracks = <Track>[];
    for (final track in allTracks) {
      final isDownloaded = (track.downloadSource != null &&
              track.downloadSource!.isNotEmpty) ||
          (downloadDir.existsSync() &&
              p.isWithin(downloadDir.path, track.filePath));

      if (isDownloaded && !protectedIds.contains(track.trackId)) {
        candidateTracks.add(track);
      }
    }

    // Sort LRU: tracks never played first (null), then oldest lastPlayedAt
    candidateTracks.sort((a, b) {
      final aPlayed = a.lastPlayedAt;
      final bPlayed = b.lastPlayedAt;
      if (aPlayed == null && bPlayed == null) return a.id.compareTo(b.id);
      if (aPlayed == null) return -1;
      if (bPlayed == null) return 1;
      return aPlayed.compareTo(bPlayed);
    });

    int prunedCount = 0;
    int bytesFreed = 0;
    final prunedIds = <String>[];

    for (final track in candidateTracks) {
      if (currentBytes <= effectiveMax) break;

      final file = File(track.filePath);
      if (file.existsSync()) {
        try {
          final size = file.lengthSync();
          file.deleteSync();
          bytesFreed += size;
          currentBytes -= size;
        } catch (_) {}
      }

      // Revert to remote streaming URI
      if (track.downloadSource != null &&
          track.downloadSource!.contains('/api/v1/download/')) {
        track.filePath = track.downloadSource!.replaceAll(
          '/api/v1/download/',
          '/api/v1/stream/',
        );
      }
      track.downloadSource = null;

      try {
        await _db.saveTrack(track);
      } catch (_) {}

      prunedCount++;
      prunedIds.add(track.trackId);
    }

    return PruneResult(
      prunedTrackCount: prunedCount,
      bytesFreed: bytesFreed,
      prunedTrackIds: prunedIds,
    );
  }

  // ── Peer Status & Playback Reconciler ────────────────────────────────────────

  /// Evaluates active peers and reconciles media URLs:
  ///
  /// - If a track has an HTTP remote URI, but a complete local downloaded copy
  ///   exists in the sync download directory, it is upgraded to local file playback
  ///   to avoid unnecessary network usage.
  /// - Returns the number of tracks reconciled.
  Future<int> reconcileOnPeerStatusChanged(
    List<DiscoveredNode> activeNodes,
  ) async {
    _lastKnownNodes = activeNodes;
    final downloadDir = await resolveDownloadDirectory();
    if (!downloadDir.existsSync()) return 0;

    final allTracks = await _db.getAllTracks();
    int reconciled = 0;

    for (final track in allTracks) {
      if (AudioPlayerService.isRemoteUri(track.filePath)) {
        // Check if an existing file on disk matches this track
        try {
          final entities = downloadDir.listSync(recursive: false);
          for (final entity in entities) {
            if (entity is File) {
              final name = p.basenameWithoutExtension(entity.path);
              if (name.startsWith(track.trackId)) {
                // Local copy found! Upgrade track to local file
                track.filePath = entity.path;
                await _db.saveTrack(track);

                // If currently loaded in audio player, update metadata
                if (_playerService.currentTrack?.trackId == track.trackId) {
                  _playerService.updateTrack(track);
                }

                reconciled++;
                break;
              }
            }
          }
        } catch (_) {}
      }
    }

    return reconciled;
  }

  /// Checks whether a given [track] is currently playable:
  ///
  /// - Returns `true` if it points to a local file that exists on disk.
  /// - For remote HTTP URIs, returns `true` only if at least one discovered
  ///   node matches the host/authority of the track's URI.
  bool isTrackReachable(
    Track track, {
    List<DiscoveredNode>? activeNodes,
  }) {
    if (!AudioPlayerService.isRemoteUri(track.filePath)) {
      final file = File(track.filePath);
      return file.existsSync();
    }

    final nodes = activeNodes ?? _lastKnownNodes;
    final uri = Uri.tryParse(track.filePath);
    if (uri == null) return false;

    for (final node in nodes) {
      if (uri.host == node.address.address ||
          uri.host == node.baseUrl ||
          track.filePath.contains(node.address.address)) {
        return true;
      }
    }

    return false;
  }

  /// Starts automatic background monitoring of LAN peers via [OrpheusBeaconService].
  void startPeerMonitoring() {
    _beaconSub?.cancel();
    _beaconSub = _beaconService.onNodesChanged.listen((nodes) {
      reconcileOnPeerStatusChanged(nodes);
    });
  }

  /// Stops background peer monitoring.
  void stopPeerMonitoring() {
    _beaconSub?.cancel();
    _beaconSub = null;
  }

  void dispose() {
    stopPeerMonitoring();
    quotaNotifier.dispose();
  }
}
