import 'package:isar/isar.dart';

import 'custom_metadata.dart';
import 'track_stats.dart';

part 'track.g.dart';

/// Supported media file types that Orpheus can play.
enum FileType { mp3, flac, mp4, m4a, wav, unknown }

/// Fetch status of external metadata.
enum FetchStatus { none, success, notFound }

/// Isar Collection representing a single audio or video file on disk.
///
/// Design principles:
/// - [filePath] is the source of truth — always points to the real file.
/// - [trackId] is a stable, unique identifier (SHA-256 of [filePath]) so that
///   the same file is never imported twice regardless of library re-scans.
/// - Aesthetic overrides live in the embedded [customMetadata] object, keeping
///   the original file untouched.
/// - Playback analytics live in the embedded [stats] object.
@collection
class Track {
  /// Isar auto-incremented primary key.
  Id id = Isar.autoIncrement;

  /// Stable unique identifier: SHA-256 hex digest of [filePath].
  /// Indexed for fast duplicate detection during library scanning.
  @Index(unique: true, replace: false)
  late String trackId;

  /// Absolute path to the media file on disk.
  /// Indexed for fast duplicate detection during library scanning.
  @Index(unique: true, replace: false)
  late String filePath;

  /// Media container/codec type (mp3, flac, mp4, …).
  @enumerated
  late FileType fileType;

  /// Track duration in whole seconds (extracted from file metadata).
  int duration = 0;

  // ── Raw file metadata (read from tags on import) ─────────────────────────

  /// Title extracted from the file's embedded tags (ID3, Vorbis comment, etc.).
  String? title;

  /// Artist extracted from file tags.
  String? artist;

  /// Album extracted from file tags.
  String? album;

  /// Genre extracted from file tags.
  String? genre;

  /// Where this track was downloaded from (e.g. YouTube, etc.).
  String? downloadSource;

  /// Cached synced lyrics in LRC format fetched from LRCLIB.
  ///
  /// Stored raw (e.g. `[00:23.45] Some lyric line`) so that [LrcParser]
  /// can convert it to timed [LyricLine] objects at display time.
  /// `null` means lyrics have not been fetched yet; an empty string
  /// means a lookup was attempted but no lyrics were found.
  String? syncedLyrics;

  /// Fetch status of the track's album art.
  @enumerated
  FetchStatus artStatus = FetchStatus.none;

  /// Fetch status of the track's lyrics.
  @enumerated
  FetchStatus lyricsStatus = FetchStatus.none;

  /// Whether the user has applied custom metadata overrides via [customMetadata].
  bool hasCustomMetadata = false;

  // ── Embedded objects ───────────────────────────────────────────────────────

  /// User-editable aesthetic overrides (title, artist, cover art, etc.).
  /// Only active when [hasCustomMetadata] is `true`.
  CustomMetadata customMetadata = CustomMetadata();

  /// Playback analytics (total plays, monthly breakdown).
  TrackStats stats = TrackStats();

  // ── Computed display helpers ───────────────────────────────────────────────

  /// Returns the display title: custom override → raw tag → filename stem.
  String get displayTitle {
    if (hasCustomMetadata && customMetadata.title != null) {
      return customMetadata.title!;
    }
    return title ?? _stemFromPath(filePath);
  }

  /// Returns the display artist: custom override → raw tag → "Unknown Artist".
  String get displayArtist {
    if (hasCustomMetadata && customMetadata.artist != null) {
      return customMetadata.artist!;
    }
    return artist ?? 'Unknown Artist';
  }

  /// Returns the display album: custom override → raw tag → "Unknown Album".
  String get displayAlbum {
    if (hasCustomMetadata && customMetadata.album != null) {
      return customMetadata.album!;
    }
    return album ?? 'Unknown Album';
  }

  /// Strips directory and extension from a file path to derive a fallback title.
  static String _stemFromPath(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot == -1 ? name : name.substring(0, dot);
  }
}
