/// A single timestamped lyric line parsed from an `.lrc` file.
///
/// Both fields are immutable. Instances are comparable by [timestamp] so that
/// a list of [LyricLine]s can be sorted and binary-searched efficiently.
class LyricLine implements Comparable<LyricLine> {
  const LyricLine({required this.timestamp, required this.text});

  /// The position in the track at which this lyric should appear.
  final Duration timestamp;

  /// The human-readable lyric text (already trimmed).
  final String text;

  @override
  int compareTo(LyricLine other) => timestamp.compareTo(other.timestamp);

  @override
  String toString() => '[${_formatDuration(timestamp)}] $text';

  static String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0');
    return '$m:$s.$ms';
  }
}

/// Stateless parser for the LRC (Lyrics) file format.
///
/// Supports:
/// - Standard timestamps: `[mm:ss.xx]` and `[mm:ss.xxx]`
/// - Multiple timestamps on one line: `[00:12.34][00:14.56] shared lyric`
/// - Metadata tags (`[ti:]`, `[ar:]`, etc.) — silently ignored
/// - Instrument/blank lines — excluded from output
///
/// ### Usage
/// ```dart
/// final lines = LrcParser.parse(rawLrcString);
/// final active = LrcParser.activeLineIndex(lines, position);
/// ```
class LrcParser {
  LrcParser._(); // pure static utility

  // Matches one timestamp block: [mm:ss.xx] or [mm:ss.xxx]
  static final _timestampPattern = RegExp(
    r'\[(\d{1,2}):(\d{2})\.(\d{2,3})\]',
  );

  // Metadata lines like [ti:Title] or [ar:Artist]
  static final _metaPattern = RegExp(r'^\[\w+:.*\]$');

  /// Parses [lrcContent] and returns a **sorted** list of [LyricLine]s.
  ///
  /// Returns an empty list if [lrcContent] is null or blank.
  static List<LyricLine> parse(String? lrcContent) {
    if (lrcContent == null || lrcContent.trim().isEmpty) return const [];

    final result = <LyricLine>[];

    for (final rawLine in lrcContent.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Skip pure metadata lines (no lyric content)
      if (_metaPattern.hasMatch(line)) continue;

      // Extract all timestamp matches from this line
      final matches = _timestampPattern.allMatches(line).toList();
      if (matches.isEmpty) continue;

      // The lyric text follows the last timestamp block
      final lastMatch = matches.last;
      final text = line.substring(lastMatch.end).trim();

      // Skip purely instrumental/blank lyric lines
      if (text.isEmpty) continue;

      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final centisStr = match.group(3)!;

        // Normalise 2-digit centiseconds or 3-digit milliseconds to ms
        final milliseconds = centisStr.length == 3
            ? int.parse(centisStr)
            : int.parse(centisStr) * 10;

        final timestamp = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        result.add(LyricLine(timestamp: timestamp, text: text));
      }
    }

    result.sort();
    return List.unmodifiable(result);
  }

  /// Returns the index of the lyric line that is active at [position].
  ///
  /// Uses a linear scan from the end so that if [position] is past the last
  /// line the last valid line index is returned. Returns `-1` if [lines] is
  /// empty or [position] is before the first line.
  static int activeLineIndex(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) return -1;

    int active = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].timestamp <= position) {
        active = i;
      } else {
        break; // list is sorted — no need to continue
      }
    }
    return active;
  }
}
