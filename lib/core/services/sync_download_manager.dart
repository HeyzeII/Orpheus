import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/local_database.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../network/local_sync_client.dart';
import '../utils/debug_logger.dart';
import '../utils/string_sanitizer.dart';

/// Status of an offline synchronization download task.
enum SyncDownloadStatus {
  queued,
  downloading,
  verifying,
  completed,
  failed,
  cancelled,
}

/// Represents an individual track download task managed by [SyncDownloadManager].
class SyncDownloadTask {
  final String trackId;
  final Track track;
  final LocalSyncClient client;

  SyncDownloadStatus status;
  int bytesDownloaded;
  int totalBytes;
  double progress;
  double bytesPerSecond;
  String? error;
  String? localFilePath;

  final DateTime queuedAt;
  DateTime? startedAt;
  DateTime? completedAt;

  SyncDownloadTask({
    required this.trackId,
    required this.track,
    required this.client,
    this.status = SyncDownloadStatus.queued,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.progress = 0.0,
    this.bytesPerSecond = 0.0,
    this.error,
    this.localFilePath,
    DateTime? queuedAt,
    this.startedAt,
    this.completedAt,
  }) : queuedAt = queuedAt ?? DateTime.now();

  /// Whether the task is actively downloading or verifying.
  bool get isRunning =>
      status == SyncDownloadStatus.downloading ||
      status == SyncDownloadStatus.verifying;

  /// Whether the task has reached a terminal state.
  bool get isFinished =>
      status == SyncDownloadStatus.completed ||
      status == SyncDownloadStatus.failed ||
      status == SyncDownloadStatus.cancelled;

  /// Current percentage (0 to 100).
  int get percentage => (progress * 100).clamp(0, 100).round();

  /// Formatted human-readable download speed.
  String get formattedSpeed {
    if (bytesPerSecond <= 0) return '0 B/s';
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    }
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }
}

/// Aggregate summary of all sync download tasks.
class SyncProgressSummary {
  final int totalTasks;
  final int queuedTasks;
  final int activeTasks;
  final int completedTasks;
  final int failedTasks;
  final int cancelledTasks;
  final int totalBytesDownloaded;
  final int totalExpectedBytes;
  final double overallProgress;
  final double overallSpeedBytesPerSec;

  const SyncProgressSummary({
    required this.totalTasks,
    required this.queuedTasks,
    required this.activeTasks,
    required this.completedTasks,
    required this.failedTasks,
    required this.cancelledTasks,
    required this.totalBytesDownloaded,
    required this.totalExpectedBytes,
    required this.overallProgress,
    required this.overallSpeedBytesPerSec,
  });

  factory SyncProgressSummary.empty() => const SyncProgressSummary(
        totalTasks: 0,
        queuedTasks: 0,
        activeTasks: 0,
        completedTasks: 0,
        failedTasks: 0,
        cancelledTasks: 0,
        totalBytesDownloaded: 0,
        totalExpectedBytes: 0,
        overallProgress: 0.0,
        overallSpeedBytesPerSec: 0.0,
      );

  /// Whether no tasks are currently queued or running.
  bool get isIdle => activeTasks == 0 && queuedTasks == 0;
}

/// Orchestrates batch and selective track downloads from remote Orpheus desktop
/// nodes to local storage, validating SHA-256 checksums and automatically updating
/// the local Isar database.
class SyncDownloadManager {
  // ── Singleton Boilerplate ──────────────────────────────────────────────────

  SyncDownloadManager._internal({
    LocalDatabase? db,
    this.customDownloadDirectory,
    this.maxConcurrentDownloads = 2,
    this.chunkTimeout = const Duration(seconds: 12),
  }) : _db = db ?? LocalDatabase.instance;

  static final SyncDownloadManager instance = SyncDownloadManager._internal();

  factory SyncDownloadManager({
    LocalDatabase? db,
    Directory? customDownloadDirectory,
    int maxConcurrentDownloads = 2,
    Duration chunkTimeout = const Duration(seconds: 12),
  }) {
    if (db != null ||
        customDownloadDirectory != null ||
        chunkTimeout != const Duration(seconds: 12)) {
      return SyncDownloadManager._internal(
        db: db,
        customDownloadDirectory: customDownloadDirectory,
        maxConcurrentDownloads: maxConcurrentDownloads,
        chunkTimeout: chunkTimeout,
      );
    }
    return instance;
  }

  // ── Dependencies & State ───────────────────────────────────────────────────

  final LocalDatabase _db;

  /// Custom destination directory override (useful for testing or user config).
  Directory? customDownloadDirectory;

  /// Maximum number of simultaneous downloads.
  int maxConcurrentDownloads;

  /// Inactivity timeout between streaming data chunks (defaults to 12 seconds).
  Duration chunkTimeout;

  final Map<String, SyncDownloadTask> _tasks = {};
  final List<String> _queue = [];
  final Set<String> _activeTrackIds = {};
  final Map<String, bool> _cancellationFlags = {};
  final Map<String, IOSink> _activeSinks = {};

  bool _isDisposed = false;

  // ── Streams and Notifiers ──────────────────────────────────────────────────

  final _taskUpdateController = StreamController<SyncDownloadTask>.broadcast();
  Stream<SyncDownloadTask> get onTaskUpdated => _taskUpdateController.stream;

  final _summaryUpdateController =
      StreamController<SyncProgressSummary>.broadcast();
  Stream<SyncProgressSummary> get onSummaryUpdated =>
      _summaryUpdateController.stream;

  final summaryNotifier =
      ValueNotifier<SyncProgressSummary>(SyncProgressSummary.empty());

  // ── Directory Resolution ───────────────────────────────────────────────────

  /// Resolves the absolute directory on disk where synchronized files will be stored.
  Future<Directory> resolveDownloadDirectory() async {
    if (customDownloadDirectory != null) {
      return customDownloadDirectory!;
    }

    try {
      final docDir = await getApplicationDocumentsDirectory();
      return Directory(p.join(docDir.path, 'Orpheus', 'Downloads'));
    } catch (_) {
      try {
        final supportDir = await getApplicationSupportDirectory();
        return Directory(p.join(supportDir.path, 'downloads'));
      } catch (_) {
        return Directory.systemTemp.createTempSync('orpheus_downloads_');
      }
    }
  }

  // ── Task Queries ───────────────────────────────────────────────────────────

  SyncDownloadTask? getTask(String trackId) => _tasks[trackId];

  List<SyncDownloadTask> get allTasks => _tasks.values.toList();

  List<SyncDownloadTask> get activeTasks =>
      _tasks.values.where((t) => t.isRunning).toList();

  List<SyncDownloadTask> get queuedTasks => _tasks.values
      .where((t) => t.status == SyncDownloadStatus.queued)
      .toList();

  List<SyncDownloadTask> get completedTasks => _tasks.values
      .where((t) => t.status == SyncDownloadStatus.completed)
      .toList();

  List<SyncDownloadTask> get failedTasks => _tasks.values
      .where((t) => t.status == SyncDownloadStatus.failed)
      .toList();

  SyncProgressSummary get currentSummary => _calculateSummary();

  /// For testing: registers a task directly in memory and emits updates.
  void registerTaskForTesting(SyncDownloadTask task) {
    _tasks[task.trackId] = task;
    _emitTaskUpdate(task);
  }

  /// For testing: clears all tasks and resets state.
  void clearTasksForTesting() {
    _tasks.clear();
    _queue.clear();
    _activeTrackIds.clear();
    summaryNotifier.value = SyncProgressSummary.empty();
  }

  // ── Enqueue Operations ─────────────────────────────────────────────────────

  LocalSyncClient _resolveClient(Track track, LocalSyncClient? client) {
    if (client != null) return client;
    final uri = Uri.tryParse(track.filePath);
    if (uri != null && uri.hasAuthority && uri.host.isNotEmpty) {
      final port = uri.hasPort ? uri.port : 50505;
      return LocalSyncClient(
        baseUrl: 'http://${uri.host}:$port',
      );
    }
    return LocalSyncClient();
  }

  /// Enqueues a single [remoteTrack] for offline download using [client].
  Future<SyncDownloadTask> enqueueTrack(
    Track remoteTrack, {
    LocalSyncClient? client,
    bool startImmediately = true,
  }) async {
    final trackId = remoteTrack.trackId;
    final effectiveClient = _resolveClient(remoteTrack, client);

    // If already active or queued, return existing task
    final existing = _tasks[trackId];
    if (existing != null && (existing.isRunning || existing.status == SyncDownloadStatus.queued)) {
      return existing;
    }

    final task = SyncDownloadTask(
      trackId: trackId,
      track: remoteTrack,
      client: effectiveClient,
      status: SyncDownloadStatus.queued,
    );

    _tasks[trackId] = task;
    _cancellationFlags.remove(trackId);
    _queue.add(trackId);

    _emitTaskUpdate(task);

    if (startImmediately) {
      _processQueue();
    }

    return task;
  }

  /// Enqueues a collection of [remoteTracks] for batch download.
  Future<List<SyncDownloadTask>> enqueueTracks(
    List<Track> remoteTracks, {
    LocalSyncClient? client,
  }) async {
    final List<SyncDownloadTask> enqueued = [];
    for (final track in remoteTracks) {
      final task = await enqueueTrack(
        track,
        client: client,
        startImmediately: false,
      );
      enqueued.add(task);
    }

    _processQueue();
    return enqueued;
  }

  /// Enqueues all tracks in a [playlist] and associates them upon download.
  Future<List<SyncDownloadTask>> enqueuePlaylist(
    Playlist playlist,
    List<Track> playlistTracks, {
    LocalSyncClient? client,
  }) async {
    final tasks = await enqueueTracks(playlistTracks, client: client);

    try {
      await _db.savePlaylist(playlist);
    } catch (_) {}

    return tasks;
  }

  // ── Cancellation and Queue Management ──────────────────────────────────────

  /// Cancels an active or queued download task for [trackId].
  void cancel(String trackId) {
    _cancellationFlags[trackId] = true;
    _queue.remove(trackId);

    final task = _tasks[trackId];
    if (task != null) {
      task.status = SyncDownloadStatus.cancelled;
      _emitTaskUpdate(task);
    }

    final sink = _activeSinks.remove(trackId);
    if (sink != null) {
      try {
        sink.close();
      } catch (_) {}
    }

    _activeTrackIds.remove(trackId);
    _processQueue();
  }

  /// Cancels all queued and active download tasks.
  void cancelAll() {
    for (final trackId in _tasks.keys.toList()) {
      _cancellationFlags[trackId] = true;
      final task = _tasks[trackId];
      if (task != null && !task.isFinished) {
        task.status = SyncDownloadStatus.cancelled;
        _emitTaskUpdate(task);
      }
    }

    _queue.clear();

    for (final sink in _activeSinks.values) {
      try {
        sink.close();
      } catch (_) {}
    }
    _activeSinks.clear();
    _activeTrackIds.clear();

    _emitSummary();
  }

  /// Removes finished (completed, failed, or cancelled) tasks from tracking.
  void clearFinishedTasks() {
    _tasks.removeWhere((_, task) => task.isFinished);
    _emitSummary();
  }

  // ── Queue Processing Engine ────────────────────────────────────────────────

  void _processQueue() {
    if (_isDisposed) return;

    while (_activeTrackIds.length < maxConcurrentDownloads && _queue.isNotEmpty) {
      final nextTrackId = _queue.removeAt(0);
      final task = _tasks[nextTrackId];

      if (task == null || task.status == SyncDownloadStatus.cancelled) {
        continue;
      }

      _activeTrackIds.add(nextTrackId);
      _executeDownload(task);
    }

    _emitSummary();
  }

  Future<void> _executeDownload(SyncDownloadTask task) async {
    final trackId = task.trackId;
    File? tempFile;

    try {
      task.status = SyncDownloadStatus.downloading;
      task.startedAt = DateTime.now();
      task.bytesDownloaded = 0;
      task.progress = 0.0;
      task.bytesPerSecond = 0.0;
      _emitTaskUpdate(task);

      final downloadDir = await resolveDownloadDirectory();
      await downloadDir.create(recursive: true);

      final ext = task.track.fileType != FileType.unknown
          ? task.track.fileType.name
          : 'mp3';
      final cleanTitle = StringSanitizer.sanitize(task.track.displayTitle)
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\-\. ]'), '_')
          .replaceAll(' ', '_');
      final fileName = '${task.trackId}_$cleanTitle.$ext';
      final targetFile = File(p.join(downloadDir.path, fileName));
      tempFile = File(p.join(downloadDir.path, '$fileName.part'));

      if (_cancellationFlags[trackId] == true) {
        task.status = SyncDownloadStatus.cancelled;
        _emitTaskUpdate(task);
        return;
      }

      // Stream the media binary
      final streamedResponse =
          await task.client.openDownloadStream(task.trackId);

      if (streamedResponse.statusCode != 200) {
        throw LocalSyncClientException(
          'Download failed with HTTP ${streamedResponse.statusCode}',
          statusCode: streamedResponse.statusCode,
        );
      }

      task.totalBytes = streamedResponse.contentLength ?? 0;
      final expectedSha = streamedResponse.headers['x-orpheus-sha256'] ??
          streamedResponse.headers['X-Orpheus-SHA256'];

      if (tempFile.existsSync()) {
        await tempFile.delete();
      }

      final sink = tempFile.openWrite();
      _activeSinks[trackId] = sink;

      final stopwatch = Stopwatch()..start();
      DateTime lastEmitTime = DateTime.now();

      final timedStream = streamedResponse.stream.timeout(
        chunkTimeout,
        onTimeout: (EventSink<List<int>> eventSink) {
          eventSink.addError(
            TimeoutException('Descarga interrumpida: sin datos por más de ${chunkTimeout.inSeconds}s'),
          );
        },
      );

      await for (final chunk in timedStream) {
        if (_cancellationFlags[trackId] == true) {
          await sink.close();
          _activeSinks.remove(trackId);
          if (tempFile.existsSync()) {
            await tempFile.delete();
          }
          task.status = SyncDownloadStatus.cancelled;
          _emitTaskUpdate(task);
          return;
        }

        sink.add(chunk);
        task.bytesDownloaded += chunk.length;

        if (task.totalBytes > 0) {
          task.progress = (task.bytesDownloaded / task.totalBytes).clamp(0.0, 1.0);
        }

        final elapsedMs = stopwatch.elapsedMilliseconds;
        if (elapsedMs > 0) {
          task.bytesPerSecond = (task.bytesDownloaded / elapsedMs) * 1000.0;
        }

        final now = DateTime.now();
        if (now.difference(lastEmitTime).inMilliseconds >= 120) {
          lastEmitTime = now;
          _emitTaskUpdate(task);
        }
      }

      await sink.flush();
      await sink.close();
      _activeSinks.remove(trackId);

      // Verify SHA-256 integrity
      task.status = SyncDownloadStatus.verifying;
      _emitTaskUpdate(task);

      final fileBytes = await tempFile.readAsBytes();
      final actualSha = sha256.convert(fileBytes).toString().toLowerCase();

      if (expectedSha != null && expectedSha.trim().isNotEmpty) {
        final cleanExpected = expectedSha.trim().toLowerCase();
        if (actualSha != cleanExpected) {
          if (tempFile.existsSync()) {
            await tempFile.delete();
          }
          throw LocalSyncClientException(
            'SHA-256 verification failed for track $trackId. Expected $cleanExpected but got $actualSha',
          );
        }
      }

      // Finalize destination file
      if (targetFile.existsSync()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);
      task.localFilePath = targetFile.path;

      // Optional: Fetch cover artwork and persist locally
      final remoteArtUrl = task.track.customMetadata.customCoverPath;
      if (remoteArtUrl != null &&
          (remoteArtUrl.startsWith('http://') || remoteArtUrl.startsWith('https://'))) {
        try {
          final artResponse = await task.client.httpClient.get(Uri.parse(remoteArtUrl));
          if (artResponse.statusCode == 200) {
            final coversDir = Directory(p.join(downloadDir.path, 'covers'));
            await coversDir.create(recursive: true);
            final artFile = File(p.join(coversDir.path, '$trackId.jpg'));
            await artFile.writeAsBytes(artResponse.bodyBytes);
            task.track.customMetadata.customCoverPath = artFile.path;
            task.track.hasCustomMetadata = true;
          }
        } catch (_) {}
      }

      // Update track file path and persist in Isar database
      task.track.filePath = targetFile.path;
      task.track.downloadSource = task.client.getDownloadUrl(task.trackId);

      try {
        final existing = await _db.getTrackByTrackId(task.trackId);
        if (existing != null) {
          existing.filePath = targetFile.path;
          existing.customMetadata = task.track.customMetadata;
          existing.hasCustomMetadata = task.track.hasCustomMetadata;
          existing.downloadSource = task.track.downloadSource;
          if (task.track.title != null) existing.title = task.track.title;
          if (task.track.artist != null) existing.artist = task.track.artist;
          if (task.track.album != null) existing.album = task.track.album;
          if (task.track.duration > 0) existing.duration = task.track.duration;
          existing.fileType = task.track.fileType;
          await _db.saveTrack(existing);
        } else {
          await _db.saveTrack(task.track);
        }
      } catch (e) {
        DebugLogger.log('SyncDownloadManager: Error saving track to DB: $e');
      }

      task.status = SyncDownloadStatus.completed;
      task.completedAt = DateTime.now();
      task.progress = 1.0;
      _emitTaskUpdate(task);
      DebugLogger.log(
        'SyncDownloadManager: Successfully downloaded track $trackId -> ${targetFile.path}',
      );
    } catch (e) {
      final sink = _activeSinks.remove(trackId);
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      if (tempFile != null && tempFile.existsSync()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      if (_cancellationFlags[trackId] != true && task.status != SyncDownloadStatus.cancelled) {
        task.status = SyncDownloadStatus.failed;
        if (e is TimeoutException) {
          task.error = e.message ?? 'Descarga interrumpida: tiempo de espera agotado';
        } else if (e is LocalSyncClientException) {
          task.error = e.message;
        } else {
          task.error = e.toString();
        }
        _emitTaskUpdate(task);
      }
      DebugLogger.log('SyncDownloadManager: Download error for $trackId: $e');
    } finally {
      _activeTrackIds.remove(trackId);
      _cancellationFlags.remove(trackId);
      _processQueue();
    }
  }

  // ── Summary & Emitters ─────────────────────────────────────────────────────

  void _emitTaskUpdate(SyncDownloadTask task) {
    if (_isDisposed) return;
    _taskUpdateController.add(task);
    _emitSummary();
  }

  void _emitSummary() {
    if (_isDisposed) return;
    final summary = _calculateSummary();
    summaryNotifier.value = summary;
    _summaryUpdateController.add(summary);
  }

  SyncProgressSummary _calculateSummary() {
    int queued = 0;
    int active = 0;
    int completed = 0;
    int failed = 0;
    int cancelled = 0;
    int downloadedBytes = 0;
    int expectedBytes = 0;
    double speedSum = 0.0;

    for (final task in _tasks.values) {
      switch (task.status) {
        case SyncDownloadStatus.queued:
          queued++;
          break;
        case SyncDownloadStatus.downloading:
        case SyncDownloadStatus.verifying:
          active++;
          downloadedBytes += task.bytesDownloaded;
          expectedBytes += task.totalBytes;
          speedSum += task.bytesPerSecond;
          break;
        case SyncDownloadStatus.completed:
          completed++;
          downloadedBytes += task.totalBytes > 0 ? task.totalBytes : task.bytesDownloaded;
          expectedBytes += task.totalBytes > 0 ? task.totalBytes : task.bytesDownloaded;
          break;
        case SyncDownloadStatus.failed:
          failed++;
          break;
        case SyncDownloadStatus.cancelled:
          cancelled++;
          break;
      }
    }

    final total = _tasks.length;
    double progress = 0.0;
    if (total > 0) {
      if (expectedBytes > 0) {
        progress = (downloadedBytes / expectedBytes).clamp(0.0, 1.0);
      } else {
        progress = completed / total;
      }
    }

    return SyncProgressSummary(
      totalTasks: total,
      queuedTasks: queued,
      activeTasks: active,
      completedTasks: completed,
      failedTasks: failed,
      cancelledTasks: cancelled,
      totalBytesDownloaded: downloadedBytes,
      totalExpectedBytes: expectedBytes,
      overallProgress: progress,
      overallSpeedBytesPerSec: speedSum,
    );
  }

  /// Disposes active sinks and stream controllers.
  void dispose() {
    _isDisposed = true;
    cancelAll();
    _taskUpdateController.close();
    _summaryUpdateController.close();
    summaryNotifier.dispose();
  }
}
