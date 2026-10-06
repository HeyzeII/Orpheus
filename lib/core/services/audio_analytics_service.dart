import 'dart:async';
import 'package:flutter/foundation.dart';

import '../database/local_database.dart';
import '../models/track.dart';

/// Representation of pending behavioral mutations for a specific track.
class _TrackAnalyticsDelta {
  _TrackAnalyticsDelta(this.trackId);

  final String trackId;
  int playDelta = 0;
  int skipDelta = 0;
  DateTime? lastPlayedAt;
  bool? isLiked;
  bool recordMonthlyStats = false;
  String? monthKey;

  bool get hasChanges =>
      playDelta != 0 ||
      skipDelta != 0 ||
      lastPlayedAt != null ||
      isLiked != null ||
      recordMonthlyStats;
}

/// High-performance, non-blocking background analytics engine for Orpheus.
///
/// Buffers behavioral playback events (completions, skips, likes) and persists
/// them to [LocalDatabase] in micro-batches with debounce to guarantee 0ms UI lag
/// and zero interference with audio decoding.
class AudioAnalyticsService {
  AudioAnalyticsService._internal({LocalDatabase? db})
      : _db = db ?? LocalDatabase.instance;

  static final AudioAnalyticsService instance =
      AudioAnalyticsService._internal();

  factory AudioAnalyticsService({LocalDatabase? db}) {
    if (db != null) {
      return AudioAnalyticsService._internal(db: db);
    }
    return instance;
  }

  final LocalDatabase _db;

  /// In-memory coalesced delta map keyed by [trackId].
  final Map<String, _TrackAnalyticsDelta> _pendingDeltas = {};

  /// Timer for coalescing debounced writes.
  Timer? _debounceTimer;

  /// Lock chain to serialize database write transactions safely.
  Future<void>? _flushChain;

  /// Coalescing window in milliseconds before flushing to disk.
  static const int _kDebounceMs = 300;

  /// Max pending tracks before an immediate flush is triggered.
  static const int _kMaxBatchSize = 5;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Records that [trackId] reached completion threshold (e.g. >= 80% played).
  void recordCompletion(String trackId) {
    if (trackId.isEmpty) return;
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final delta = _pendingDeltas.putIfAbsent(
      trackId,
      () => _TrackAnalyticsDelta(trackId),
    );

    delta.playDelta += 1;
    delta.lastPlayedAt = now;
    delta.recordMonthlyStats = true;
    delta.monthKey = monthKey;

    _scheduleFlush();
  }

  /// Records a premature skip for [trackId] (< 15 seconds into playback).
  void recordSkip(String trackId) {
    if (trackId.isEmpty) return;

    final delta = _pendingDeltas.putIfAbsent(
      trackId,
      () => _TrackAnalyticsDelta(trackId),
    );

    delta.skipDelta += 1;

    _scheduleFlush();
  }

  /// Records an explicit like / favorite toggle for [trackId].
  void recordLike(String trackId, bool isLiked) {
    if (trackId.isEmpty) return;

    final delta = _pendingDeltas.putIfAbsent(
      trackId,
      () => _TrackAnalyticsDelta(trackId),
    );

    delta.isLiked = isLiked;

    _scheduleFlush();
  }

  /// Immediately flushes all buffered analytics events to disk.
  Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _executeFlush();
  }

  // ── Internal Batching & Persistence ────────────────────────────────────────

  void _scheduleFlush() {
    if (_pendingDeltas.length >= _kMaxBatchSize) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      unawaited(_executeFlush());
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: _kDebounceMs), () {
      unawaited(_executeFlush());
    });
  }

  Future<void> _executeFlush() async {
    if (_pendingDeltas.isEmpty) return;

    // Drain pending deltas atomically to avoid race conditions with new incoming events
    final deltasToProcess = List<_TrackAnalyticsDelta>.from(_pendingDeltas.values);
    _pendingDeltas.clear();

    final prev = _flushChain ?? Future.value();
    final completer = Completer<void>();
    _flushChain = completer.future;

    try {
      await prev;
      await _persistBatch(deltasToProcess);
    } catch (e, stack) {
      debugPrint('AudioAnalyticsService: Error flushing analytics batch: $e\n$stack');
    } finally {
      completer.complete();
    }
  }

  Future<void> _persistBatch(List<_TrackAnalyticsDelta> deltas) async {
    if (deltas.isEmpty) return;

    try {
      final List<Track> modifiedTracks = [];

      for (final delta in deltas) {
        if (!delta.hasChanges) continue;

        final track = await _db.getTrackByTrackId(delta.trackId);
        if (track == null) continue;

        if (delta.playDelta != 0) {
          track.playCount += delta.playDelta;
        }

        if (delta.skipDelta != 0) {
          track.skipCount += delta.skipDelta;
        }

        if (delta.lastPlayedAt != null) {
          track.lastPlayedAt = delta.lastPlayedAt;
        }

        if (delta.isLiked != null) {
          track.isLiked = delta.isLiked!;
        }

        if (delta.recordMonthlyStats && delta.monthKey != null) {
          track.stats.recordPlay(delta.monthKey!);
        }

        modifiedTracks.add(track);
      }

      if (modifiedTracks.isNotEmpty) {
        await _db.saveTracks(modifiedTracks);
      }
    } catch (e) {
      debugPrint('AudioAnalyticsService: Error persisting tracks batch: $e');
    }
  }
}
