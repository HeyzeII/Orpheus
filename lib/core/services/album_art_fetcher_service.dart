import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../database/local_database.dart';
import '../models/track.dart';
import '../utils/fuzzy_matcher.dart';
import '../utils/string_sanitizer.dart';
import 'media_cache_service.dart';
import 'network_guard_service.dart';

/// Singleton service responsible for lazy background fetching of missing album art.
///
/// ## Concurrency & Rate Limiting
/// - Limits concurrent downloads to at most 2.
/// - Stores a status flag (`artStatus = FetchStatus.notFound`) on search failures (404 / no results)
///   to ensure network resources are not wasted on subsequent scans.
class AlbumArtFetcherService {
  AlbumArtFetcherService.internal({
    LocalDatabase? db,
    http.Client? client,
    NetworkGuardService? networkGuard,
  })  : _db = db ?? LocalDatabase.instance,
        _client = client ?? http.Client(),
        _networkGuard = networkGuard ?? NetworkGuardService.instance;

  static final AlbumArtFetcherService instance = AlbumArtFetcherService.internal();

  factory AlbumArtFetcherService({
    LocalDatabase? db,
    http.Client? client,
    NetworkGuardService? networkGuard,
  }) {
    if (db != null || client != null || networkGuard != null) {
      return AlbumArtFetcherService.internal(
        db: db,
        client: client,
        networkGuard: networkGuard,
      );
    }
    return instance;
  }

  final LocalDatabase _db;
  final http.Client _client;
  final NetworkGuardService _networkGuard;

  bool _isProcessing = false;

  /// Returns true if the background queue is currently processing.
  bool get isProcessing => _isProcessing;

  /// Scans the entire library and lazy-downloads artwork for tracks that have none.
  ///
  /// Processes with a maximum concurrency of 2.
  Future<void> processLibrary() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final tracks = await _db.getAllTracks();
      
      // Select tracks that lack cover art and haven't failed lookup previously
      final pending = tracks.where((track) {
        final path = track.customMetadata.customCoverPath;
        final hasNoArt = path == null || path.isEmpty;
        return hasNoArt && track.artStatus == FetchStatus.none;
      }).toList();

      if (pending.isEmpty) {
        _isProcessing = false;
        return;
      }

      final completer = Completer<void>();
      int activeDownloads = 0;
      int nextIndex = 0;

      void launchNext() {
        if (nextIndex >= pending.length) {
          if (activeDownloads == 0 && !completer.isCompleted) {
            completer.complete();
          }
          return;
        }

        final track = pending[nextIndex++];
        activeDownloads++;

        _fetchArtForTrack(track).then((_) {
          activeDownloads--;
          launchNext();
        }).catchError((_) {
          activeDownloads--;
          launchNext();
        });
      }

      // Launch at most 2 workers in parallel
      launchNext();
      launchNext();

      await completer.future;
    } finally {
      _isProcessing = false;
    }
  }

  /// Fetches and caches cover art for a single [track] immediately.
  ///
  /// Use this when the user has just corrected a track's metadata and wants
  /// the system to re-identify the artwork right away, without waiting for the
  /// full [processLibrary] sweep.
  Future<void> processTrack(Track track) async {
    await _fetchArtForTrack(track);
  }

  /// Single-track lookup worker using iTunes Search API.

  Future<void> _fetchArtForTrack(Track track) async {
    if (track.artStatus == FetchStatus.custom ||
        track.customMetadata.isEdited ||
        (track.customMetadata.customCoverPath != null &&
            track.customMetadata.customCoverPath!.isNotEmpty)) {
      return;
    }

    // 1. Sanitize values using prepareSearchQuery (preferring custom metadata overrides if present)
    final rawArtist = track.hasCustomMetadata && track.customMetadata.artist != null
        ? track.customMetadata.artist
        : track.artist;
    final rawAlbum = track.hasCustomMetadata && track.customMetadata.album != null
        ? track.customMetadata.album
        : track.album;
    final rawTitle = track.hasCustomMetadata && track.customMetadata.title != null
        ? track.customMetadata.title
        : track.title;

    final artist = StringSanitizer.prepareSearchQuery(id3Tag: rawArtist, filePath: track.filePath, fallbackToFilename: false);
    final album = StringSanitizer.prepareSearchQuery(id3Tag: rawAlbum, filePath: track.filePath, fallbackToFilename: false);
    final title = StringSanitizer.prepareSearchQuery(id3Tag: rawTitle, filePath: track.filePath, fallbackToFilename: true);

    if (artist.isEmpty && album.isEmpty && title.isEmpty) {
      track.artStatus = FetchStatus.notFound;
      await _db.saveTrack(track);
      return;
    }

    final displayArtist = track.displayArtist;
    final displayTitle = track.displayTitle;
    final musicDir = track.filePath.isNotEmpty ? File(track.filePath).parent.path : null;

    // 1. Check persistent hash cache in .orpheus_cache/
    final cachedCover = await MediaCacheService.instance.getCachedCover(displayArtist, displayTitle, musicDir);
    if (cachedCover != null) {
      track.customMetadata.customCoverPath = cachedCover.path;
      track.artStatus = FetchStatus.success;
      await _db.saveTrack(track);
      debugPrint('[Art Fetcher] ⚡ Portada obtenida de caché persistente para: $displayArtist - $displayTitle');
      return;
    }

    // 2. Check local cover image in the same directory as the audio file
    if (track.filePath.isNotEmpty) {
      final localCover = await MediaCacheService.instance.findLocalCoverFile(track.filePath);
      if (localCover != null) {
        try {
          final bytes = await localCover.readAsBytes();
          if (bytes.isNotEmpty) {
            final cachedPath = await MediaCacheService.instance.saveCover(
              displayArtist,
              displayTitle,
              bytes,
              musicDir,
            );
            track.customMetadata.customCoverPath = cachedPath;
          } else {
            track.customMetadata.customCoverPath = localCover.path;
          }
        } catch (_) {
          track.customMetadata.customCoverPath = localCover.path;
        }
        track.artStatus = FetchStatus.success;
        await _db.saveTrack(track);
        debugPrint('[Art Fetcher] 📁 Portada local encontrada en carpeta para: $displayArtist - $displayTitle');
        return;
      }
    }

    // Prefer Album + Artist search term, fallback to Artist + Title, fallback to Title.
    // Deduplicate to avoid repeating identical or containing sub-strings.
    String searchTerm = '';
    final lowerArtist = artist.toLowerCase();
    final lowerAlbum = album.toLowerCase();
    final lowerTitle = title.toLowerCase();

    if (artist.isNotEmpty && album.isNotEmpty) {
      if (lowerAlbum.contains(lowerArtist)) {
        searchTerm = album;
      } else if (lowerArtist.contains(lowerAlbum)) {
        searchTerm = artist;
      } else {
        searchTerm = '$artist $album';
      }
    } else if (artist.isNotEmpty && title.isNotEmpty) {
      if (lowerTitle.contains(lowerArtist)) {
        searchTerm = title;
      } else if (lowerArtist.contains(lowerTitle)) {
        searchTerm = artist;
      } else {
        searchTerm = '$artist $title';
      }
    } else {
      searchTerm = title.isNotEmpty ? title : (album.isNotEmpty ? album : artist);
    }

    // 3. Check network permissions (Strict Offline Mode & cover download policy)
    final networkAccess = await _networkGuard.checkCoverDownloadAccess();
    if (networkAccess != NetworkAccessResult.allowed) {
      debugPrint('[Art Fetcher] ⏸️ Descarga remota omitida (${networkAccess.name}) para: $displayArtist - $displayTitle');
      return;
    }

    debugPrint('[Art Fetcher] Buscando portada para: $displayArtist - $displayTitle (Búsqueda: "$searchTerm")');

    final url = Uri.parse('https://itunes.apple.com/search')
        .replace(queryParameters: {
          'term': searchTerm,
          'limit': '5',
          'entity': 'song',
        });

    try {
      final response = await _client.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 404) {
        debugPrint('[Art Fetcher] ❌ Portada no encontrada (404) para: $displayArtist - $displayTitle');
        track.artStatus = FetchStatus.notFound;
        await _db.saveTrack(track);
        return;
      }

      if (response.statusCode != 200) {
        debugPrint('[Art Fetcher] ⚠️ Error de red temporal (${response.statusCode}) para: $displayArtist - $displayTitle');
        return;
      }

      final Map<String, dynamic> json = jsonDecode(response.body) as Map<String, dynamic>;
      final results = json['results'] as List<dynamic>?;

      if (results == null || results.isEmpty) {
        debugPrint('[Art Fetcher] ❌ Portada no encontrada en iTunes para: $displayArtist - $displayTitle');
        track.artStatus = FetchStatus.notFound;
        await _db.saveTrack(track);
        return;
      }

      // Evaluate candidates with fuzzy similarity validation (threshold: >= 0.75)
      Map<String, dynamic>? bestCandidate;
      double bestScore = 0.0;

      for (final rawItem in results) {
        if (rawItem is! Map<String, dynamic>) continue;
        final score = evaluateCandidateMatch(track, rawItem);
        if (score > bestScore) {
          bestScore = score;
          bestCandidate = rawItem;
        }
      }

      const minMatchThreshold = 0.75;
      if (bestCandidate == null || bestScore < minMatchThreshold) {
        debugPrint(
            '[Art Fetcher] ❌ Ningún candidato superó el umbral de similitud ($bestScore < $minMatchThreshold) para: $displayArtist - $displayTitle');
        track.artStatus = FetchStatus.notFound;
        await _db.saveTrack(track);
        return;
      }

      var artUrlStr = bestCandidate['artworkUrl100'] as String?;
      if (artUrlStr == null || artUrlStr.isEmpty) {
        debugPrint('[Art Fetcher] ❌ URL de carátula vacía en candidato iTunes para: $displayArtist - $displayTitle');
        track.artStatus = FetchStatus.notFound;
        await _db.saveTrack(track);
        return;
      }

      // Upgrade resolution from 100x100 to 500x500
      artUrlStr = artUrlStr.replaceAll('100x100bb', '500x500bb');

      // Download actual image bytes
      final imgResponse = await _client.get(Uri.parse(artUrlStr)).timeout(const Duration(seconds: 15));
      if (imgResponse.statusCode != 200 || imgResponse.bodyBytes.isEmpty) {
        debugPrint('[Art Fetcher] ⚠️ Error descargando imagen (${imgResponse.statusCode}) de $artUrlStr');
        return;
      }

      // Persist to hash-based covers cache directory
      final savedPath = await MediaCacheService.instance.saveCover(
        displayArtist,
        displayTitle,
        imgResponse.bodyBytes,
      );

      track.customMetadata.customCoverPath = savedPath;
      track.artStatus = FetchStatus.success;
      await _db.saveTrack(track);
      debugPrint('[Art Fetcher] 🎉 Portada descargada y asociada en caché persistente para: $displayArtist - $displayTitle (score: ${bestScore.toStringAsFixed(2)})');
    } catch (e) {
      debugPrint('[Art Fetcher] ⚠️ Excepción buscando portada para: $displayArtist - $displayTitle: $e');
    }
  }

  // ── Fuzzy Matching & Normalization Helpers ─────────────────────────────────

  /// Normalizes a string for fuzzy metadata comparison by:
  /// - Lowercasing and trimming
  /// - Removing accents/diacritics
  /// - Removing cosmetic suffixes like "(Remastered)", "[Live]", "(feat. X)", etc.
  /// - Removing punctuation and collapsing multiple spaces
  static String normalizeForMatching(String input) {
    var s = input.toLowerCase().trim();

    // 1. Remove diacritics / accents
    const withDia = 'àáâãäåòóôõöøèéêëðçìíîïùúûüñšÿýž';
    const withoutDia = 'aaaaaaooooooeeeeeciiiiuuuunsyyz';
    for (int i = 0; i < withDia.length; i++) {
      s = s.replaceAll(withDia[i], withoutDia[i]);
    }

    // 2. Remove cosmetic modifier patterns / suffixes
    final suffixPattern = RegExp(
      r'[\(\[]\s*(remaster(ed)?|deluxe(\s+edition)?|live(\s+at\s+[^\)\]]+)?|bonus(\s+track)?|anniversary(\s+edition)?|expanded|special\s+edition|version|feat\.?|ft\.?|official(\s+(music|lyric|audio)?\s*(video|audio)?)?|sub\s+esp)[^\)\]]*[\)\]]',
      caseSensitive: false,
    );
    s = s.replaceAll(suffixPattern, ' ');

    // 3. Remove punctuation and non-alphanumeric characters (keeping spaces)
    s = s.replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), ' ');

    // 4. Collapse spaces and trim
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

    return s;
  }

  /// Computes a similarity score between 0.0 and 1.0 between [target] and [candidate].
  static double computeSimilarity(String target, String candidate) {
    final t = normalizeForMatching(target);
    final c = normalizeForMatching(candidate);

    if (t.isEmpty || c.isEmpty) return 0.0;
    if (t == c) return 1.0;

    // Substring containment check: if one contains the other and covers majority
    if (t.contains(c) || c.contains(t)) {
      final minLen = t.length < c.length ? t.length : c.length;
      final maxLen = t.length > c.length ? t.length : c.length;
      if (maxLen > 0 && (minLen / maxLen) >= 0.6) {
        final ratio = (minLen / maxLen) * 0.95;
        final dice = FuzzyMatcher.similarity(t, c);
        return dice > ratio ? dice : ratio;
      }
    }

    final dice = FuzzyMatcher.similarity(t, c);
    final maxLen = t.length > c.length ? t.length : c.length;
    final lev = maxLen > 0 ? (1.0 - FuzzyMatcher.levenshteinDistance(t, c) / maxLen) : 0.0;

    return dice > lev ? dice : lev;
  }

  /// Evaluates an iTunes candidate item against the given [track], returning a confidence
  /// score between 0.0 and 1.0.
  static double evaluateCandidateMatch(Track track, Map<String, dynamic> item) {
    final targetArtist = track.displayArtist;
    final targetTitle = track.displayTitle;
    final targetAlbum = track.displayAlbum != 'Unknown Album' && track.displayAlbum != 'Artista Desconocido'
        ? track.displayAlbum
        : '';

    final candidateArtist = (item['artistName'] as String?) ?? '';
    final candidateTitle = (item['trackName'] as String?) ?? '';
    final candidateAlbum = (item['collectionName'] as String?) ?? '';

    // 1. Artist similarity
    final artistSim = computeSimilarity(targetArtist, candidateArtist);

    // 2. Title similarity
    final titleSim = computeSimilarity(targetTitle, candidateTitle);

    // 3. Album similarity
    final albumSim = targetAlbum.isNotEmpty ? computeSimilarity(targetAlbum, candidateAlbum) : 0.0;

    // Best content similarity (Title or Album)
    final contentSim = albumSim > titleSim ? albumSim : titleSim;

    // Disqualify if artist is completely mismatched (< 0.5)
    if (artistSim < 0.5) {
      return 0.0;
    }

    // Disqualify if content (title/album) is completely mismatched (< 0.5)
    if (contentSim < 0.5) {
      return 0.0;
    }

    // Weighted score: 50% artist + 50% content (album/title)
    return (artistSim * 0.5) + (contentSim * 0.5);
  }
}
