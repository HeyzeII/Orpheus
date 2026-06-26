import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../database/local_database.dart';
import '../models/track.dart';

/// Singleton service responsible for fetching and caching synced lyrics.
///
/// ## Strategy
/// 1. **Offline-first**: If `track.syncedLyrics` is already stored in Isar
///    (non-null), it is returned immediately without any network call.
/// 2. **API lookup**: Otherwise a GET request is made to the public LRCLIB
///    API. On success the raw LRC string is persisted in Isar and returned.
/// 3. **Not-found caching**: If the API returns 404 or an empty body, an
///    empty string is stored in Isar so no further requests are made.
/// 4. **Error resilience**: Network timeouts (10 s), HTTP errors, and JSON
///    parse failures all return `null` without crashing the caller. A second
///    call will retry the network request (we don't cache failures).
///
/// ### Usage
/// ```dart
/// final lrc = await LyricsService.instance.fetchLyrics(track);
/// final lines = LrcParser.parse(lrc);
/// ```
class LyricsService {
  // ── Singleton boilerplate ──────────────────────────────────────────────────

  LyricsService._internal({LocalDatabase? db, http.Client? client})
      : _db = db ?? LocalDatabase.instance,
        _client = client ?? http.Client();

  static final LyricsService instance = LyricsService._internal();

  factory LyricsService() => instance;

  // ── Dependencies ───────────────────────────────────────────────────────────

  final LocalDatabase _db;
  final http.Client _client;

  static const _baseUrl = 'https://lrclib.net/api/get';
  static const _timeout = Duration(seconds: 10);

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the raw LRC string for [track], or `null` on network failure.
  ///
  /// - Returns a **non-empty string** when synced lyrics are available.
  /// - Returns an **empty string** when the track has been looked up before
  ///   but LRCLIB had no lyrics (avoids redundant network round-trips).
  /// - Returns **`null`** only on transient network/parse failures so the UI
  ///   can display a retry option.
  Future<String?> fetchLyrics(Track track) async {
    // ── 1. Offline cache hit ───────────────────────────────────────────────
    if (track.syncedLyrics != null) {
      return track.syncedLyrics;
    }

    // ── 2. Skip if we have no useful search terms ─────────────────────────
    final artist = track.displayArtist;
    final title = track.displayTitle;

    if (artist == 'Unknown Artist' || title.isEmpty) {
      // Cache the "not found" result so we don't retry every time.
      await _persistLyrics(track, '');
      return '';
    }

    // ── 3. Build request URL ──────────────────────────────────────────────
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'artist_name': artist,
      'track_name': title,
    });

    // ── 4. Network call with timeout ──────────────────────────────────────
    try {
      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': 'Orpheus/1.0 (local music player; contact@orpheus.app)',
        },
      ).timeout(_timeout);

      if (response.statusCode == 404) {
        // LRCLIB definitively has no entry for this track.
        await _persistLyrics(track, '');
        return '';
      }

      if (response.statusCode != 200) {
        // Transient server error — do NOT cache, allow retry.
        return null;
      }

      // ── 5. Parse JSON body ─────────────────────────────────────────────
      final Map<String, dynamic> json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      final syncedLyrics = json['syncedLyrics'] as String?;
      final plainLyrics = json['plainLyrics'] as String?;

      // Prefer synced (timestamped) lyrics; fall back to plain text.
      final lrcContent = (syncedLyrics?.trim().isNotEmpty == true)
          ? syncedLyrics!
          : (plainLyrics?.trim().isNotEmpty == true)
              ? plainLyrics!
              : '';

      await _persistLyrics(track, lrcContent);
      return lrcContent;
    } on TimeoutException {
      // Let the UI show a "retry" state without caching.
      return null;
    } on SocketException {
      return null;
    } on http.ClientException {
      return null;
    } on HttpException {
      return null;
    } on FormatException {
      // Malformed JSON — don't cache, treat as transient.
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Clears cached lyrics for [track], forcing a fresh API call next time.
  Future<void> clearCache(Track track) async {
    await _db.updateTrackLyrics(track, '');
    // Reset to null so the next fetchLyrics call hits the network.
    track.syncedLyrics = null;
    await _db.saveTrack(track);
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _persistLyrics(Track track, String content) async {
    try {
      await _db.updateTrackLyrics(track, content);
    } catch (_) {
      // Non-fatal: the in-memory value is still fresh for this session.
    }
  }
}
