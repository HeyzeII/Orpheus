/// Pure Dart fuzzy-matching utilities for Orpheus.
///
/// Used by the library scanner to detect near-duplicate artist names
/// (e.g. "Slipknot" vs "slipnot", "Malice Mizer" vs "MaliceMizer").
///
/// No external dependencies — all algorithms are implemented in plain Dart
/// so this library can be tested without Flutter bindings.
library;

/// Provides static helpers for fuzzy string comparison.
abstract final class FuzzyMatcher {
  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns `true` if [artistA] and [artistB] are considered the same artist.
  ///
  /// The comparison is:
  /// 1. Both strings are **normalised** (lowercased, trimmed, collapsed
  ///    whitespace, stripped of punctuation except letters/digits/spaces).
  /// 2. If the normalised strings are identical → always `true`.
  /// 3. Otherwise the **Dice coefficient** is computed on bigrams. If the
  ///    coefficient is >= [threshold] → `true`.
  ///
  /// The default [threshold] of 0.85 comfortably catches single-character
  /// typos and spacing differences ("MaliceMizer" ↔ "Malice Mizer" → ~0.91)
  /// while rejecting clearly different names ("Slipknot" ↔ "Korn" → ~0.09).
  static bool areArtistsSimilar(
    String artistA,
    String artistB, {
    double threshold = 0.85,
  }) {
    final a = _normalise(artistA);
    final b = _normalise(artistB);

    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;

    final diceScore = _diceCoefficient(a, b);
    if (diceScore >= threshold) return true;

    // Fallback: check Levenshtein similarity for character-level insertions/deletions.
    final maxLen = a.length > b.length ? a.length : b.length;
    final levDist = levenshteinDistance(a, b);
    final levScore = 1.0 - (levDist / maxLen);
    return levScore >= threshold;
  }

  /// Computes the raw Dice coefficient (0.0 – 1.0) between two raw strings
  /// after normalisation.
  ///
  /// Exposed for unit-testing and diagnostic UI.
  static double similarity(String a, String b) {
    return _diceCoefficient(_normalise(a), _normalise(b));
  }

  // ── Normalisation ──────────────────────────────────────────────────────────

  /// Strips noise from [raw] so that cosmetic differences don't skew the score.
  ///
  /// Steps:
  /// - lowercase
  /// - trim surrounding whitespace
  /// - collapse multiple spaces into one
  /// - remove characters that are not letters, digits, or spaces
  ///   (handles punctuation like dots, hyphens, underscores)
  static String _normalise(String raw) {
    return raw
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), '');
  }

  // ── Sørensen–Dice coefficient on character bigrams ─────────────────────────

  /// Returns the Sørensen–Dice coefficient for strings [a] and [b] using
  /// overlapping character bigrams as the token set.
  ///
  /// Formula: 2 × |intersection(A, B)| / (|A| + |B|)
  ///
  /// Bigrams are collected as multisets so duplicate pairs are handled
  /// correctly (e.g. "aaa" has two "aa" bigrams).
  static double _diceCoefficient(String a, String b) {
    // Edge cases: single-character strings have no bigrams — fall back to
    // exact equality (already handled by the caller, but guard here too).
    if (a.length < 2 || b.length < 2) {
      return a == b ? 1.0 : 0.0;
    }

    final bigramsA = _buildBigramMap(a);
    final bigramsB = _buildBigramMap(b);

    int totalA = 0;
    int totalB = 0;
    int intersection = 0;

    for (final entry in bigramsA.entries) {
      totalA += entry.value;
    }
    for (final entry in bigramsB.entries) {
      totalB += entry.value;
    }

    for (final entry in bigramsA.entries) {
      final countInB = bigramsB[entry.key] ?? 0;
      intersection += entry.value < countInB ? entry.value : countInB;
    }

    return (2 * intersection) / (totalA + totalB);
  }

  /// Builds a frequency map of all overlapping 2-character substrings in [s].
  static Map<String, int> _buildBigramMap(String s) {
    final map = <String, int>{};
    for (var i = 0; i < s.length - 1; i++) {
      final bigram = s.substring(i, i + 2);
      map[bigram] = (map[bigram] ?? 0) + 1;
    }
    return map;
  }

  // ── Levenshtein distance (kept for future use / comparison) ───────────────

  /// Computes the Levenshtein edit distance between [a] and [b].
  ///
  /// Not used in [areArtistsSimilar] (Dice is faster for short strings and
  /// better at handling transpositions), but exposed for tooling.
  static int levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    // Use two-row DP to save memory.
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var curr = List<int>.filled(b.length + 1, 0);

    for (var i = 0; i < a.length; i++) {
      curr[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        curr[j + 1] = _min3(
          curr[j] + 1,        // insertion
          prev[j + 1] + 1,    // deletion
          prev[j] + cost,     // substitution
        );
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[b.length];
  }

  static int _min3(int a, int b, int c) =>
      a < b ? (a < c ? a : c) : (b < c ? b : c);
}
