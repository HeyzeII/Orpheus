/// Result of processing a single file during a library scan.
///
/// The scanner returns a stream of [ScanResult] objects so the caller can
/// update a progress indicator in real time without waiting for the full scan
/// to finish.
library;

/// Outcome variants for a single file processed during scanning.
enum ScanOutcome {
  /// File was new and was written to the database for the first time.
  added,

  /// File already existed in the database and its metadata was refreshed.
  updated,

  /// File was skipped because the scanner could not read it (corrupt,
  /// permission denied, unsupported, etc.). See [ScanResult.error].
  skipped,

  /// The file's artist name is similar (but not identical) to an existing
  /// artist in the library, and the pair is not in the ignored list.
  /// The track was saved; the caller should surface a merge prompt in the UI.
  pendingArtistMerge,
}

/// Carries the outcome of processing one media file.
final class ScanResult {
  const ScanResult({
    required this.filePath,
    required this.outcome,
    this.error,
    this.existingArtist,
    this.candidateArtist,
  });

  /// Absolute path of the file that was processed.
  final String filePath;

  /// What the scanner did with this file.
  final ScanOutcome outcome;

  /// Set when [outcome] is [ScanOutcome.skipped].
  final Object? error;

  /// The artist name already in the database that is similar to this track's
  /// artist. Only set when [outcome] is [ScanOutcome.pendingArtistMerge].
  final String? existingArtist;

  /// This track's artist name (the candidate to be merged).
  /// Only set when [outcome] is [ScanOutcome.pendingArtistMerge].
  final String? candidateArtist;

  @override
  String toString() =>
      'ScanResult($outcome, ${filePath.split('/').last}'
      '${error != null ? ', error: $error' : ''}'
      '${existingArtist != null ? ', merge: $existingArtist ↔ $candidateArtist' : ''}'
      ')';
}
