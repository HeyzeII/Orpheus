import 'package:isar/isar.dart';

part 'playback_state.g.dart';

/// Isar collection that persists the last known playback state of Orpheus.
///
/// Design:
/// - There is always **at most one** document (id == 1).
/// - [trackId] references [Track.trackId] (not the Isar auto-id) so the
///   link survives database re-scans that regenerate Isar ids.
/// - [positionMs] is in milliseconds to match [Duration.inMilliseconds].
/// - [queueTrackIds] is the ordered list of [Track.trackId] strings for the
///   full queue at the time the state was captured, allowing Orpheus to
///   restore the exact queue on next launch.
@collection
class PlaybackState {
  /// Fixed primary key — only one playback state document exists at any time.
  Id id = 1;

  /// [Track.trackId] of the track that was playing (or last played).
  /// `null` when no track has been played yet.
  String? trackId;

  /// Playback position in milliseconds when the state was last captured.
  int positionMs = 0;

  /// Ordered list of [Track.trackId] strings that formed the queue.
  List<String> queueTrackIds = [];
}
