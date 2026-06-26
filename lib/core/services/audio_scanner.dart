import 'dart:io';

import 'package:metadata_god/metadata_god.dart';
import 'package:path_provider/path_provider.dart';

import '../database/local_database.dart';
import '../models/track.dart';
import '../utils/fuzzy_matcher.dart';
import '../utils/string_sanitizer.dart';
import 'scan_result.dart';

export 'scan_result.dart';

/// Supported media file extensions (lowercase, without the leading dot).
const _kSupportedExtensions = {'mp3', 'flac', 'mp4', 'm4a', 'wav'};

/// Batch size: how many tracks are committed in a single Isar transaction.
/// Keeps individual write transactions short to avoid blocking the main thread.
const _kBatchSize = 50;

/// Service that recursively scans a directory, extracts audio/video metadata
/// with [metadata_god], applies fuzzy-artist deduplication, and persists
/// tracks to [LocalDatabase] in efficient batches.
///
/// ### Threading model
/// [scanDirectory] is an `async*` generator that yields [ScanResult] objects
/// as each file is processed. Run it on a caller-controlled isolate if you
/// want to keep the UI completely jank-free for very large libraries; for
/// typical library sizes (<10 k files) the async I/O is sufficient on macOS.
///
/// ### Usage
/// ```dart
/// final scanner = AudioScannerService();
/// await for (final result in scanner.scanDirectory('/Users/me/Music')) {
///   setState(() => _results.add(result));
/// }
/// ```
class AudioScannerService {
  AudioScannerService({LocalDatabase? db})
      : _db = db ?? LocalDatabase.instance;

  final LocalDatabase _db;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Recursively scans [directoryPath] for supported media files and persists
  /// them to the database.
  ///
  /// Yields a [ScanResult] for every file encountered (including skipped ones)
  /// so the caller can drive a progress UI.
  ///
  /// Throws [ArgumentError] if [directoryPath] does not exist or is not a
  /// directory.
  Stream<ScanResult> scanDirectory(String directoryPath) async* {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      throw ArgumentError('Directory does not exist: $directoryPath');
    }

    // Load config once for the entire scan (artist ignore list + scan dirs).
    final config = await _db.getConfig();
    final ignoredPairs = config.conflictResolution.ignoredPairs;

    // Collect all known artist names for fuzzy comparison.
    final knownArtists = await _collectKnownArtists();

    // Cover-art cache directory inside the app support folder.
    final coverCacheDir = await _coverArtCacheDir();

    // Pending batch for bulk Isar writes.
    final batch = <Track>[];

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;

      final extension = _extensionOf(entity.path);
      if (!_kSupportedExtensions.contains(extension)) continue;

      // ── Extract metadata ─────────────────────────────────────────────────
      Metadata? meta;
      try {
        meta = await MetadataGod.readMetadata(file: entity.path);
      } catch (e) {
        // Corrupt file, permission denied, or unsupported codec — skip it.
        yield ScanResult(
          filePath: entity.path,
          outcome: ScanOutcome.skipped,
          error: e,
        );
        continue;
      }

      // ── Resolve cover art ────────────────────────────────────────────────
      String? coverPath;
      try {
        coverPath = await _saveCoverArt(
          picture: meta.picture,
          filePath: entity.path,
          cacheDir: coverCacheDir,
        );
      } catch (_) {
        // Cover art failure is non-fatal; proceed without it.
      }

      // ── Resolve duration ─────────────────────────────────────────────────
      final durationSec = meta.durationMs != null
          ? (meta.durationMs! / 1000).round()
          : 0;

      // ── Detect file type ─────────────────────────────────────────────────
      final fileType = _fileTypeFromExtension(extension);

      // ── Check for existing track (update vs insert) ───────────────────────
      final existingTrack = await _db.getTrackByFilePath(entity.path);

      final trackId = existingTrack?.trackId ?? _buildTrackId(entity.path);
      final isUpdate = existingTrack != null;

      // ── Fallback Parsing & Sanitization ──────────────────────────────────
      var rawTitle = meta.title?.trim();
      var rawArtist = meta.artist?.trim();

      // If both metadata title and artist are empty, fall back to file name parsing
      if ((rawTitle == null || rawTitle.isEmpty) && (rawArtist == null || rawArtist.isEmpty)) {
        final stem = _stemFromPath(entity.path);
        final hyphenIndex = stem.indexOf(' - ');
        if (hyphenIndex != -1) {
          rawArtist = stem.substring(0, hyphenIndex).trim();
          rawTitle = stem.substring(hyphenIndex + 3).trim();
        } else {
          rawTitle = stem;
        }
      }

      // Sanitize fields using StringSanitizer
      final cleanTitle = rawTitle != null && rawTitle.isNotEmpty
          ? StringSanitizer.sanitize(rawTitle)
          : null;
      final cleanArtist = rawArtist != null && rawArtist.isNotEmpty
          ? StringSanitizer.sanitize(rawArtist)
          : null;

      // Detect download source from path or raw metadata fields
      final downloadSource = StringSanitizer.detectDownloadSource(entity.path) ??
          (rawTitle != null ? StringSanitizer.detectDownloadSource(rawTitle) : null) ??
          (rawArtist != null ? StringSanitizer.detectDownloadSource(rawArtist) : null);

      // ── Fuzzy artist deduplication ────────────────────────────────────────
      ScanOutcome outcome = isUpdate ? ScanOutcome.updated : ScanOutcome.added;
      String? mergeExistingArtist;
      String? mergeCandidateArtist;

      if (cleanArtist != null && cleanArtist.isNotEmpty) {
        final match = _findSimilarArtist(cleanArtist, knownArtists);
        if (match != null && match != cleanArtist) {
          // Check if the user has explicitly ignored this pair.
          final isIgnored = ignoredPairs.any(
            (p) =>
                (p.artistA == cleanArtist && p.artistB == match) ||
                (p.artistA == match && p.artistB == cleanArtist),
          );

          if (!isIgnored) {
            // Surface to the UI for the user to decide.
            outcome = ScanOutcome.pendingArtistMerge;
            mergeExistingArtist = match;
            mergeCandidateArtist = cleanArtist;
          }
        }

        // Register new artist so subsequent files in this scan can match it.
        if (!knownArtists.contains(cleanArtist)) {
          knownArtists.add(cleanArtist);
        }
      }

      // ── Build Track object ────────────────────────────────────────────────
      final track = existingTrack ?? Track();
      track
        ..trackId = trackId
        ..filePath = entity.path
        ..fileType = fileType
        ..duration = durationSec
        ..title = cleanTitle
        ..artist = cleanArtist
        ..album = meta.album?.trim()
        ..genre = meta.genre?.trim()
        ..downloadSource = downloadSource;

      // Persist cover art path only if not already overridden by user.
      if (coverPath != null && !track.hasCustomMetadata) {
        track.customMetadata.customCoverPath = coverPath;
      }

      batch.add(track);

      // Flush batch when it reaches the configured size.
      if (batch.length >= _kBatchSize) {
        await _db.saveTracks(batch);
        batch.clear();
      }

      yield ScanResult(
        filePath: entity.path,
        outcome: outcome,
        existingArtist: mergeExistingArtist,
        candidateArtist: mergeCandidateArtist,
      );
    }

    // Flush the remaining batch.
    if (batch.isNotEmpty) {
      await _db.saveTracks(batch);
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Collects all unique artist names already in the database.
  /// Used as the corpus for fuzzy matching during the scan.
  Future<Set<String>> _collectKnownArtists() async {
    final tracks = await _db.getAllTracks();
    return {
      for (final t in tracks)
        if (t.artist != null && t.artist!.isNotEmpty) t.artist!,
    };
  }

  /// Searches [knownArtists] for a name that is fuzzy-similar to [artist].
  /// Returns the matching known name, or `null` if none are similar enough.
  String? _findSimilarArtist(String artist, Set<String> knownArtists) {
    for (final known in knownArtists) {
      if (FuzzyMatcher.areArtistsSimilar(artist, known)) {
        return known;
      }
    }
    return null;
  }

  /// Returns the cover-art cache directory, creating it if necessary.
  Future<Directory> _coverArtCacheDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/cover_art');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Writes embedded cover art to disk and returns the saved file's path.
  ///
  /// Returns `null` if [picture] is null or its data is empty.
  /// The file name is derived from the source [filePath] so it is stable
  /// across re-scans (same file → same cover path, no duplicates on disk).
  Future<String?> _saveCoverArt({
    required Picture? picture,
    required String filePath,
    required Directory cacheDir,
  }) async {
    final data = picture?.data;
    if (data == null || data.isEmpty) return null;

    // Stable filename: sanitised version of the source path.
    final sanitised = filePath
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final ext = _mimeToExtension(picture?.mimeType);
    final coverFile = File('${cacheDir.path}/$sanitised$ext');

    // Skip writing if the exact same file already exists (re-scan optimisation).
    if (!coverFile.existsSync()) {
      await coverFile.writeAsBytes(data);
    }

    return coverFile.path;
  }

  /// Returns a stable track identifier for [filePath].
  ///
  /// We use a deterministic string derived from the absolute path.
  /// SHA-256 would be ideal but requires dart:crypto — using a fast
  /// xxh3-style fingerprint is deferred to when we add the crypto package.
  /// For now we encode the path as a URL-safe base64 trimmed to 64 chars.
  String _buildTrackId(String filePath) {
    // Simple but stable: join char codes and format as hex.
    // Replace with a proper hash (crypto package) in a future sprint.
    final codeUnits = filePath.codeUnits;
    var hash = 0xcbf29ce484222325; // FNV-1a offset basis (64-bit).
    for (final unit in codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// Returns the lowercase extension without the dot, or an empty string.
  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  /// Maps a file extension to the [FileType] enum used by [Track].
  static FileType _fileTypeFromExtension(String ext) {
    return switch (ext) {
      'mp3' => FileType.mp3,
      'flac' => FileType.flac,
      'mp4' => FileType.mp4,
      'm4a' => FileType.m4a,
      'wav' => FileType.wav,
      _ => FileType.unknown,
    };
  }

  /// Maps a MIME type string to a file extension for cover art files.
  static String _mimeToExtension(String? mime) {
    return switch (mime) {
      'image/jpeg' || 'image/jpg' => '.jpg',
      'image/png' => '.png',
      'image/webp' => '.webp',
      _ => '.jpg', // safest fallback for embedded ID3 art.
    };
  }

  /// Strips directory and extension from a file path to derive a fallback title.
  static String _stemFromPath(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot == -1 ? name : name.substring(0, dot);
  }
}
