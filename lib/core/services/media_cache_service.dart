import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/local_database.dart';

/// Singleton service responsible for managing persistent media cache (covers, lyrics,
/// and metadata index) stored in a hidden `.orpheus_cache/` directory inside the user's
/// music directory (or falling back to the application support directory).
///
/// Directory structure:
/// - `<musicDirectory>/.orpheus_cache/covers/{hash}.jpg`
/// - `<musicDirectory>/.orpheus_cache/lyrics/{hash}.lrc`
/// - `<musicDirectory>/.orpheus_cache/metadata_index.json`
///
/// Hash formula:
/// - `SHA256("${artist.trim().toLowerCase()}_${title.trim().toLowerCase()}")`
class MediaCacheService {
  MediaCacheService._internal({LocalDatabase? db})
      : _db = db ?? LocalDatabase.instance;

  static final MediaCacheService instance = MediaCacheService._internal();

  factory MediaCacheService() => instance;

  final LocalDatabase _db;
  Directory? _customBaseDir;

  /// Allows setting a custom base directory (useful for testing or overrides).
  @visibleForTesting
  Directory? get customBaseDir => _customBaseDir;

  @visibleForTesting
  set customBaseDir(Directory? dir) => _customBaseDir = dir;

  /// Generates a deterministic SHA-256 hash based on normalized artist and title.
  String computeMediaHash(String artist, String title) {
    final normalized = '${artist.trim().toLowerCase()}_${title.trim().toLowerCase()}';
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  /// Returns the base `.orpheus_cache/` directory.
  ///
  /// Resolution order:
  /// 1. `_customBaseDir` if explicitly set (e.g. in tests).
  /// 2. Configured scan directories in [LocalDatabase]: if `musicDirectoryPath`
  ///    matches or is inside a scan directory, the root scan directory is used.
  /// 3. First existing scan directory from `config.scanDirectories`.
  /// 4. Explicit `musicDirectoryPath` if valid directory.
  /// 5. Fallback: `<applicationSupportDirectory>/.orpheus_cache`.
  Future<Directory> getBaseCacheDirectory([String? musicDirectoryPath]) async {
    if (_customBaseDir != null) {
      if (!_customBaseDir!.existsSync()) {
        _customBaseDir!.createSync(recursive: true);
      }
      return _customBaseDir!;
    }

    // 1. Force resolving to configured root scan directories in database first
    try {
      final config = await _db.getConfig();
      if (config.scanDirectories.isNotEmpty) {
        // If musicDirectoryPath is provided, match against the root scan directories
        if (musicDirectoryPath != null && musicDirectoryPath.trim().isNotEmpty) {
          final cleanPath = musicDirectoryPath.trim();
          for (final scanPath in config.scanDirectories) {
            if (cleanPath == scanPath || cleanPath.startsWith('$scanPath/')) {
              final rootDir = Directory(scanPath);
              if (rootDir.existsSync()) {
                final cacheDir = Directory('${rootDir.path}/.orpheus_cache');
                if (!cacheDir.existsSync()) {
                  cacheDir.createSync(recursive: true);
                }
                return cacheDir;
              }
            }
          }
        }

        // Otherwise use the first existing scan directory root
        for (final scanPath in config.scanDirectories) {
          final scanDir = Directory(scanPath);
          if (scanDir.existsSync()) {
            final cacheDir = Directory('${scanDir.path}/.orpheus_cache');
            if (!cacheDir.existsSync()) {
              cacheDir.createSync(recursive: true);
            }
            return cacheDir;
          }
        }
      }
    } catch (_) {
      // If database is not ready, continue
    }

    // 2. Explicit directory fallback (e.g. if DB not initialized or outside scanDirs)
    if (musicDirectoryPath != null && musicDirectoryPath.trim().isNotEmpty) {
      final target = Directory(musicDirectoryPath.trim());
      if (target.existsSync()) {
        final cacheDir = Directory('${target.path}/.orpheus_cache');
        if (!cacheDir.existsSync()) {
          cacheDir.createSync(recursive: true);
        }
        return cacheDir;
      }
    }

    // 3. Fallback to application support directory
    final supportDir = await getApplicationSupportDirectory();
    final fallbackCache = Directory('${supportDir.path}/.orpheus_cache');
    if (!fallbackCache.existsSync()) {
      fallbackCache.createSync(recursive: true);
    }
    return fallbackCache;
  }

  // ── Cover Art Cache ────────────────────────────────────────────────────────

  /// Returns the covers directory (`.orpheus_cache/covers`), creating it if needed.
  Future<Directory> getCoversDirectory([String? musicDirectoryPath]) async {
    final baseDir = await getBaseCacheDirectory(musicDirectoryPath);
    final coversDir = Directory('${baseDir.path}/covers');
    if (!coversDir.existsSync()) {
      coversDir.createSync(recursive: true);
    }
    return coversDir;
  }

  /// Returns the cached cover [File] if it exists and has content, otherwise `null`.
  Future<File?> getCachedCover(String artist, String title, [String? musicDirectoryPath]) async {
    if (artist.trim().isEmpty && title.trim().isEmpty) return null;
    final hash = computeMediaHash(artist, title);
    
    // Check primary cache directory
    final coversDir = await getCoversDirectory(musicDirectoryPath);
    final file = File('${coversDir.path}/$hash.jpg');
    if (await file.exists() && (await file.length()) > 0) {
      return file;
    }

    // Secondary check: application support directory legacy location
    try {
      final supportDir = await getApplicationSupportDirectory();
      final legacyFile = File('${supportDir.path}/covers/$hash.jpg');
      if (await legacyFile.exists() && (await legacyFile.length()) > 0) {
        return legacyFile;
      }
    } catch (_) {}

    return null;
  }

  /// Checks if a cached cover exists on disk for the given artist and title.
  Future<bool> hasCachedCover(String artist, String title, [String? musicDirectoryPath]) async {
    final file = await getCachedCover(artist, title, musicDirectoryPath);
    return file != null;
  }

  /// Persists cover image bytes to `.orpheus_cache/covers/{hash}.jpg`
  /// and returns the absolute file path.
  Future<String> saveCover(
    String artist,
    String title,
    List<int> bytes, [
    String? musicDirectoryPath,
  ]) async {
    if (bytes.isEmpty) {
      throw ArgumentError('Cannot save empty cover bytes');
    }
    final hash = computeMediaHash(artist, title);
    final coversDir = await getCoversDirectory(musicDirectoryPath);
    final file = File('${coversDir.path}/$hash.jpg');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // ── Lyrics Cache ───────────────────────────────────────────────────────────

  /// Returns the lyrics directory (`.orpheus_cache/lyrics`), creating it if needed.
  Future<Directory> getLyricsDirectory([String? musicDirectoryPath]) async {
    final baseDir = await getBaseCacheDirectory(musicDirectoryPath);
    final lyricsDir = Directory('${baseDir.path}/lyrics');
    if (!lyricsDir.existsSync()) {
      lyricsDir.createSync(recursive: true);
    }
    return lyricsDir;
  }

  /// Returns the cached LRC string if `lyrics/{hash}.lrc` exists and is not empty,
  /// otherwise `null`.
  Future<String?> getCachedLyrics(String artist, String title, [String? musicDirectoryPath]) async {
    if (artist.trim().isEmpty && title.trim().isEmpty) return null;
    final hash = computeMediaHash(artist, title);

    // Check primary lyrics directory
    final lyricsDir = await getLyricsDirectory(musicDirectoryPath);
    final file = File('${lyricsDir.path}/$hash.lrc');
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.trim().isNotEmpty) {
        return content;
      }
    }

    // Secondary check: application support directory legacy location
    try {
      final supportDir = await getApplicationSupportDirectory();
      final legacyFile = File('${supportDir.path}/lyrics/$hash.lrc');
      if (await legacyFile.exists()) {
        final content = await legacyFile.readAsString();
        if (content.trim().isNotEmpty) {
          return content;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Checks if cached lyrics exist on disk for the given artist and title.
  Future<bool> hasCachedLyrics(String artist, String title, [String? musicDirectoryPath]) async {
    final lyrics = await getCachedLyrics(artist, title, musicDirectoryPath);
    return lyrics != null && lyrics.isNotEmpty;
  }

  /// Persists raw LRC lyrics content to `.orpheus_cache/lyrics/{hash}.lrc`
  /// and returns the absolute file path.
  Future<String> saveLyrics(
    String artist,
    String title,
    String lrcContent, [
    String? musicDirectoryPath,
  ]) async {
    final hash = computeMediaHash(artist, title);
    final lyricsDir = await getLyricsDirectory(musicDirectoryPath);
    final file = File('${lyricsDir.path}/$hash.lrc');
    await file.writeAsString(lrcContent);
    return file.path;
  }

  // ── Metadata Index Persistence ─────────────────────────────────────────────

  /// Reads and returns the complete metadata index map from `.orpheus_cache/metadata_index.json`.
  Future<Map<String, dynamic>> readMetadataIndex([String? musicDirectoryPath]) async {
    try {
      final baseDir = await getBaseCacheDirectory(musicDirectoryPath);
      final indexFile = File('${baseDir.path}/metadata_index.json');
      if (await indexFile.exists()) {
        final content = await indexFile.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        }
      }
    } catch (e) {
      debugPrint('[MediaCacheService] Error reading metadata index: $e');
    }
    return <String, dynamic>{};
  }

  /// Retrieves a specific metadata entry from `.orpheus_cache/metadata_index.json`
  /// matching the given artist and title hash.
  Future<Map<String, dynamic>?> getMetadataEntry(
    String artist,
    String title, [
    String? musicDirectoryPath,
  ]) async {
    if (artist.trim().isEmpty && title.trim().isEmpty) return null;
    final hash = computeMediaHash(artist, title);
    final index = await readMetadataIndex(musicDirectoryPath);
    final entry = index[hash];
    if (entry is Map<String, dynamic>) {
      return entry;
    }
    return null;
  }

  /// Saves or updates a metadata entry in `.orpheus_cache/metadata_index.json`.
  /// If an existing entry already has `isEdited: true`, it is preserved unless
  /// the incoming [metadata] also explicitly has `isEdited: true`.
  Future<void> saveMetadataEntry(
    String artist,
    String title,
    Map<String, dynamic> metadata, [
    String? musicDirectoryPath,
  ]) async {
    if (artist.trim().isEmpty && title.trim().isEmpty) return;
    final hash = computeMediaHash(artist, title);
    final baseDir = await getBaseCacheDirectory(musicDirectoryPath);
    final indexFile = File('${baseDir.path}/metadata_index.json');

    final index = await readMetadataIndex(musicDirectoryPath);
    final existingEntry = index[hash];

    // Protect user-edited entries from being overwritten by automatic re-scans
    if (existingEntry is Map<String, dynamic> && existingEntry['isEdited'] == true) {
      if (metadata['isEdited'] != true) {
        return;
      }
    }

    final updatedEntry = Map<String, dynamic>.from(metadata);
    updatedEntry['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    index[hash] = updatedEntry;

    final jsonString = const JsonEncoder.withIndent('  ').convert(index);
    await indexFile.writeAsString(jsonString);
  }

  // ── Multi-Key Metadata Index ───────────────────────────────────────────────

  /// Persists a metadata entry indexed under multiple independent keys so that
  /// a fresh scanner can always find it regardless of which information it has:
  ///
  /// Keys written to `metadata_index.json`:
  /// - `file:<filePath>` – absolute file path (most stable on same device)
  /// - `rel:<relativeFilePath>` – path relative to the scan root
  /// - `rel:<fileName>` – just the file name (e.g. `Song.mp3`)
  /// - `stem:<stem>` – bare filename without extension (e.g. `Song`)
  /// - `hash:<editedHash>` – SHA-256 of edited artist+title
  /// - `hash:<originalHash>` – SHA-256 of original/raw ID3 artist+title
  ///
  /// All keys point to the same complete payload map.
  Future<void> saveTrackMetadataEntry({
    required String filePath,
    required String scanRootPath,
    required String originalArtist,
    required String originalTitle,
    required String editedArtist,
    required String editedTitle,
    required Map<String, dynamic> payload,
  }) async {
    if (filePath.isEmpty) return;

    final baseDir = await getBaseCacheDirectory(scanRootPath);
    final indexFile = File('${baseDir.path}/metadata_index.json');

    final index = await readMetadataIndex(scanRootPath);

    // Build keys
    final fileName = p.basename(filePath);
    final stem = p.basenameWithoutExtension(filePath);
    final relPath = filePath.startsWith('$scanRootPath/')
        ? filePath.substring(scanRootPath.length + 1)
        : fileName;

    final editedHash = computeMediaHash(editedArtist, editedTitle);
    final originalHash = computeMediaHash(originalArtist, originalTitle);

    // Enrich payload with identity fields
    final enrichedPayload = Map<String, dynamic>.from(payload);
    enrichedPayload['filePath'] = filePath;
    enrichedPayload['relativeFilePath'] = relPath;
    enrichedPayload['fileStem'] = stem;
    enrichedPayload['originalArtist'] = originalArtist;
    enrichedPayload['originalTitle'] = originalTitle;
    enrichedPayload['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

    // Write all keys pointing to the same enriched payload
    final keys = <String>[
      'file:$filePath',
      'rel:$relPath',
      'rel:$fileName',
      'stem:$stem',
      'hash:$editedHash',
      editedHash, // backwards compatibility with existing legacy key
      if (originalHash != editedHash) ...['hash:$originalHash', originalHash],
    ];

    for (final key in keys) {
      // Only skip writing an un-edited payload over an already-edited one
      final existing = index[key];
      if (existing is Map<String, dynamic> && existing['isEdited'] == true) {
        if (enrichedPayload['isEdited'] != true) continue;
      }
      index[key] = enrichedPayload;
    }

    final jsonString = const JsonEncoder.withIndent('  ').convert(index);
    await indexFile.writeAsString(jsonString);
  }

  /// Looks up a metadata entry from `metadata_index.json` using a multi-step
  /// fallback ladder keyed by physical file identity and raw ID3 hashes.
  ///
  /// Lookup order (first match wins):
  /// 1. `file:<filePath>` – exact device path
  /// 2. `rel:<relativeFilePath>` – path relative to scan root
  /// 3. `rel:<fileName>` – bare filename
  /// 4. `stem:<stem>` – filename without extension
  /// 5. `hash:<rawHash>` – SHA-256(rawArtist_rawTitle)
  /// 6. `hash:<stemHash>` – SHA-256(rawArtist_stem)  (fallback for title-less files)
  /// 7. Deep scan: iterate all values and match `filePath`, `relativeFilePath`, or `fileStem`
  Future<Map<String, dynamic>?> findMetadataEntry({
    required String filePath,
    required String scanRootPath,
    required String rawArtist,
    required String rawTitle,
  }) async {
    if (filePath.isEmpty) return null;

    final index = await readMetadataIndex(scanRootPath);
    if (index.isEmpty) return null;

    final fileName = p.basename(filePath);
    final stem = p.basenameWithoutExtension(filePath);
    final relPath = filePath.startsWith('$scanRootPath/')
        ? filePath.substring(scanRootPath.length + 1)
        : fileName;

    final rawHash = computeMediaHash(rawArtist, rawTitle);
    final stemHash = computeMediaHash(rawArtist, stem);

    // Ordered lookup keys
    final lookupKeys = [
      'file:$filePath',
      'rel:$relPath',
      'rel:$fileName',
      'stem:$stem',
      'hash:$rawHash',
      rawHash, // legacy key
      'hash:$stemHash',
      stemHash,
    ];

    for (final key in lookupKeys) {
      final entry = index[key];
      if (entry is Map<String, dynamic>) return entry;
    }

    // 7. Deep scan: iterate all values matching by identity fields
    for (final value in index.values) {
      if (value is! Map<String, dynamic>) continue;
      if (value['filePath'] == filePath) return value;
      if (value['relativeFilePath'] == relPath) return value;
      if (value['fileStem'] == stem) return value;
    }

    return null;
  }

  // ── Local File Discovery Helpers (Same folder as audio file) ───────────────

  /// Finds a matching `.lrc` file in the same physical directory as [audioFilePath].
  /// Matches `{stem}.lrc` (case-insensitive extension).
  Future<File?> findLocalLrcFile(String audioFilePath) async {
    if (audioFilePath.isEmpty) return null;
    try {
      final audioFile = File(audioFilePath);
      final parentDir = audioFile.parent;
      if (!await parentDir.exists()) return null;

      final fileName = audioFilePath.split('/').last;
      final dotIndex = fileName.lastIndexOf('.');
      final stem = dotIndex == -1 ? fileName : fileName.substring(0, dotIndex);

      final candidates = [
        '${parentDir.path}/$stem.lrc',
        '${parentDir.path}/$stem.LRC',
      ];

      for (final path in candidates) {
        final f = File(path);
        if (await f.exists() && (await f.length()) > 0) {
          return f;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Finds a local cover image in the same physical directory as [audioFilePath].
  /// Checks candidates in priority order:
  /// 1. `{stem}.jpg`, `{stem}.png`, `{stem}.jpeg`, `{stem}.webp`
  /// 2. `cover.jpg`, `cover.png`, `cover.jpeg`, `cover.webp`
  /// 3. `folder.jpg`, `folder.png`, `folder.jpeg`, `folder.webp`
  /// 4. `album.jpg`, `album.png`, `front.jpg`
  Future<File?> findLocalCoverFile(String audioFilePath) async {
    if (audioFilePath.isEmpty) return null;
    try {
      final audioFile = File(audioFilePath);
      final parentDir = audioFile.parent;
      if (!await parentDir.exists()) return null;

      final fileName = audioFilePath.split('/').last;
      final dotIndex = fileName.lastIndexOf('.');
      final stem = dotIndex == -1 ? fileName : fileName.substring(0, dotIndex);

      final candidates = [
        '${parentDir.path}/$stem.jpg',
        '${parentDir.path}/$stem.png',
        '${parentDir.path}/$stem.jpeg',
        '${parentDir.path}/$stem.webp',
        '${parentDir.path}/cover.jpg',
        '${parentDir.path}/cover.png',
        '${parentDir.path}/cover.jpeg',
        '${parentDir.path}/cover.webp',
        '${parentDir.path}/folder.jpg',
        '${parentDir.path}/folder.png',
        '${parentDir.path}/folder.jpeg',
        '${parentDir.path}/folder.webp',
        '${parentDir.path}/album.jpg',
        '${parentDir.path}/album.png',
        '${parentDir.path}/front.jpg',
        '${parentDir.path}/front.png',
      ];

      for (final path in candidates) {
        final f = File(path);
        if (await f.exists() && (await f.length()) > 0) {
          return f;
        }
      }
    } catch (_) {}
    return null;
  }
}
