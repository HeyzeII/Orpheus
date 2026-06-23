import 'package:isar/isar.dart';

part 'track_stats.g.dart';

/// Embedded object that stores playback analytics for a [Track].
///
/// Monthly history is stored as two parallel lists — [playMonths] for the
/// "YYYY-MM" keys and [playCountsPerMonth] for the corresponding counts —
/// because Isar embedded objects do not support `Map<String, int>` natively.
/// The helper methods below keep them in sync.
@embedded
class TrackStats {
  /// Total number of times this track has been played (all time).
  int totalPlays = 0;

  /// Parallel list of "YYYY-MM" formatted month keys (e.g. "2026-06").
  List<String> playMonths = [];

  /// Parallel list of play counts for each month in [playMonths].
  List<int> playCountsPerMonth = [];

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Reconstructs the month → count map from the parallel lists.
  /// Annotated with [@ignore] so the Isar generator skips it
  /// (`Map&lt;String,int&gt;` is not a supported Isar field type).
  @ignore
  Map<String, int> get monthlyPlays {
    final Map<String, int> result = {};
    for (var i = 0; i < playMonths.length; i++) {
      result[playMonths[i]] = playCountsPerMonth[i];
    }
    return result;
  }

  /// Records a single play event. Call this each time the track finishes.
  ///
  /// Pass a pre-formatted [monthKey] ("YYYY-MM") so the caller controls
  /// the timezone — Orpheus always uses local time.
  void recordPlay(String monthKey) {
    totalPlays++;
    final index = playMonths.indexOf(monthKey);
    if (index == -1) {
      playMonths.add(monthKey);
      playCountsPerMonth.add(1);
    } else {
      playCountsPerMonth[index]++;
    }
  }
}
