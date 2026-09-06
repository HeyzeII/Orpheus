import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
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

  // ── Base Cache Directory Resolution ────────────────────────────────────────

  /// Returns the base `.orpheus_cache/` directory.
  ///
  /// Resolution order:
  /// 1. `_customBaseDir` if explicitly set (e.g. in tests).
  /// 2. `musicDirectoryPath` if provided and exists.
  /// 3. First directory from `config.scanDirectories` in [LocalDatabase] if it exists.
  /// 4. Fallback: `<applicationSupportDirectory>/.orpheus_cache`.
  Future<Directory> getBaseCacheDirectory([String? musicDirectoryPath]) async {
    if (_customBaseDir != null) {
      if (!_customBaseDir!.existsSync()) {
        _customBaseDir!.createSync(recursive: true);
      }
      return _customBaseDir!;
    }

    // 1. Explicit directory provided
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

    // 2. User configured music directories in database
    try {
      final config = await _db.getConfig();
      if (config.scanDirectories.isNotEmpty) {
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
      // If database is not ready, continue to fallback.
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
    final updatedEntry = Map<String, dynamic>.from(metadata);
    updatedEntry['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    index[hash] = updatedEntry;

    final jsonString = const JsonEncoder.withIndent('  ').convert(index);
    await indexFile.writeAsString(jsonString);
  }
}
