import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../database/local_database.dart';
import '../models/track.dart';
import '../utils/string_sanitizer.dart';

/// Singleton service responsible for lazy background fetching of missing album art.
///
/// ## Concurrency & Rate Limiting
/// - Limits concurrent downloads to at most 2.
/// - Stores a status flag (`artStatus = FetchStatus.notFound`) on search failures (404 / no results)
///   to ensure network resources are not wasted on subsequent scans.
class AlbumArtFetcherService {
  AlbumArtFetcherService.internal({LocalDatabase? db, http.Client? client})
      : _db = db ?? LocalDatabase.instance,
        _client = client ?? http.Client();

  static final AlbumArtFetcherService instance = AlbumArtFetcherService.internal();

  factory AlbumArtFetcherService() => instance;

  final LocalDatabase _db;
  final http.Client _client;

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

  /// Single-track lookup worker using iTunes Search API.
  Future<void> _fetchArtForTrack(Track track) async {
    // 1. Sanitize values using prepareSearchQuery
    final artist = StringSanitizer.prepareSearchQuery(id3Tag: track.artist, filePath: track.filePath);
    final album = StringSanitizer.prepareSearchQuery(id3Tag: track.album, filePath: track.filePath);
    final title = StringSanitizer.prepareSearchQuery(id3Tag: track.title, filePath: track.filePath);

    if (artist.isEmpty && album.isEmpty && title.isEmpty) {
      track.artStatus = FetchStatus.notFound;
      await _db.saveTrack(track);
      return;
    }

    final displayArtist = track.displayArtist;
    final displayTitle = track.displayTitle;

    // Prefer Album + Artist search term, fallback to Artist + Title, fallback to Title
    String searchTerm = '';
    if (artist.isNotEmpty && album.isNotEmpty) {
      searchTerm = '$artist $album';
    } else if (artist.isNotEmpty && title.isNotEmpty) {
      searchTerm = '$artist $title';
    } else {
      searchTerm = title.isNotEmpty ? title : album;
    }

    print('[Art Fetcher] Buscando portada para: $displayArtist - $displayTitle (Búsqueda: "$searchTerm")');

    final url = Uri.parse('https://itunes.apple.com/search')
        .replace(queryParameters: {
          'term': searchTerm,
          'limit': '1',
          'entity': 'song',
        });

    try {
      final response = await _client.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 404) {
        print('[Art Fetcher] ❌ Portada no encontrada (404) para: $displayArtist - $displayTitle');
        track.artStatus = FetchStatus.notFound;
        await _db.saveTrack(track);
        return;
      }

      if (response.statusCode != 200) {
        print('[Art Fetcher] ⚠️ Error de red temporal (${response.statusCode}) para: $displayArtist - $displayTitle');
        return;
      }

      final Map<String, dynamic> json = jsonDecode(response.body) as Map<String, dynamic>;
      final results = json['results'] as List<dynamic>?;

      if (results == null || results.isEmpty) {
        print('[Art Fetcher] ❌ Portada no encontrada en iTunes para: $displayArtist - $displayTitle');
        track.artStatus = FetchStatus.notFound;
        await _db.saveTrack(track);
        return;
      }

      final item = results.first as Map<String, dynamic>;
      var artUrlStr = item['artworkUrl100'] as String?;
      if (artUrlStr == null || artUrlStr.isEmpty) {
        print('[Art Fetcher] ❌ URL de carátula vacía en iTunes para: $displayArtist - $displayTitle');
        track.artStatus = FetchStatus.notFound;
        await _db.saveTrack(track);
        return;
      }

      // Upgrade resolution from 100x100 to 500x500
      artUrlStr = artUrlStr.replaceAll('100x100bb', '500x500bb');

      // Download actual image bytes
      final imgResponse = await _client.get(Uri.parse(artUrlStr)).timeout(const Duration(seconds: 15));
      if (imgResponse.statusCode != 200 || imgResponse.bodyBytes.isEmpty) {
        print('[Art Fetcher] ⚠️ Error descargando imagen (${imgResponse.statusCode}) de $artUrlStr');
        return;
      }

      final supportDir = await getApplicationSupportDirectory();
      final coverDir = Directory('${supportDir.path}/cover_art');
      if (!coverDir.existsSync()) {
        coverDir.createSync(recursive: true);
      }

      final ext = artUrlStr.toLowerCase().contains('.png') ? '.png' : '.jpg';
      final file = File('${coverDir.path}/${track.trackId}$ext');

      await file.writeAsBytes(imgResponse.bodyBytes);

      track.customMetadata.customCoverPath = file.path;
      track.artStatus = FetchStatus.success;
      await _db.saveTrack(track);
      print('[Art Fetcher] 🎉 Portada descargada y asociada con éxito para: $displayArtist - $displayTitle');
    } catch (e) {
      print('[Art Fetcher] ⚠️ Excepción buscando portada para: $displayArtist - $displayTitle: $e');
    }
  }
}
