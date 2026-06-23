import 'package:isar/isar.dart';

part 'playlist.g.dart';

/// Isar Collection representing a user playlist.
///
/// Playlists store only [trackIds] (the [Track.trackId] strings), never
/// duplicate the file data. Ordering is preserved by list position.
///
/// The [isDefault] flag marks system-managed playlists (e.g. "Liked Tracks")
/// that should not be deletable from the UI.
@collection
class Playlist {
  /// Isar auto-incremented primary key.
  Id id = Isar.autoIncrement;

  /// Stable unique identifier (UUID v4 generated at creation time).
  @Index(unique: true, replace: false)
  late String playlistId;

  /// Human-readable display name.
  late String name;

  /// Optional description shown in the playlist detail view.
  String? description;

  /// When `true`, this is a system-managed playlist (e.g. "Liked Tracks")
  /// and should not be editable or deletable from the user interface.
  bool isDefault = false;

  /// Absolute path to a custom cover image, or `null` to use auto-generated art.
  String? customCoverPath;

  /// Ordered list of [Track.trackId] references.
  ///
  /// - Preserves insertion order (the play order).
  /// - A trackId may appear at most once (enforced by [LocalDatabase]).
  List<String> trackIds = [];
}
