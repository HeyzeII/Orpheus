import 'package:isar/isar.dart';

part 'custom_metadata.g.dart';

/// Embedded object that stores user-overridden aesthetic metadata for a [Track].
/// This allows full editorial control (title, artwork, etc.) without mutating
/// the original audio/video file on disk.
@embedded
class CustomMetadata {
  /// Override for the track's display title.
  String? title;

  /// Override for the track's display artist name.
  String? artist;

  /// Override for the track's display album name.
  String? album;

  /// Override for the track's genre label.
  String? genre;

  /// Absolute path to a custom cover image chosen by the user.
  String? customCoverPath;

  /// Whether this object contains any user-edited data.
  /// Drives UI indicators (e.g. a small "edited" badge on the track tile).
  bool isEdited = false;
}
