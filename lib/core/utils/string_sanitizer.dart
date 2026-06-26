/// Utility class for cleaning string fields (title, artist) and detecting download sources.
class StringSanitizer {
  StringSanitizer._();

  // Downloader patterns to match and remove
  static final _downloaderPatterns = {
    'y2mate.com': RegExp(r'y2mate\.com', caseSensitive: false),
    'snappea': RegExp(r'snappea', caseSensitive: false),
    'ssyoutube': RegExp(r'ssyoutube', caseSensitive: false),
    'savefrom': RegExp(r'savefrom', caseSensitive: false),
  };

  // Aesthetic noise/modisms to clean from title
  static final _noisePatterns = [
    RegExp(r'[\(\[]\s*official\s+(music|lyric|audio)?\s*(video|audio)?\s*[\)\]]', caseSensitive: false),
    RegExp(r'[\(\[]\s*(music|lyric)?\s*video\s*[\)\]]', caseSensitive: false),
    RegExp(r'[\(\[]\s*audio\s*[\)\]]', caseSensitive: false),
    RegExp(r'[\(\[]\s*lyrics?\s*[\)\]]', caseSensitive: false),
    RegExp(r'HD\s*4K|4K\s*HD', caseSensitive: false),
    RegExp(r'\b4K\b', caseSensitive: false),
    RegExp(r'\bHD\b', caseSensitive: false),
  ];

  /// Cleans the input string by removing downloader footprints and cosmetic modisms.
  /// Replaces multiple spaces and handles hanging punctuation cleanly.
  static String sanitize(String input) {
    var cleaned = input;

    // 1. Remove downloader domains/footprints
    for (final pattern in _downloaderPatterns.values) {
      cleaned = cleaned.replaceAll(pattern, '');
    }

    // 2. Remove modisms/noise
    for (final pattern in _noisePatterns) {
      cleaned = cleaned.replaceAll(pattern, '');
    }

    // 3. Collapse multiple spaces and trim
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    // 4. Remove empty brackets or parentheses remaining (e.g. "()" or "[]")
    cleaned = cleaned.replaceAll(RegExp(r'\(\s*\)'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\[\s*\]'), '');

    // 5. Clean up hanging hyphens or spaces at borders
    cleaned = cleaned.trim();
    cleaned = _trimHangingPunctuation(cleaned);

    return cleaned;
  }

  /// Detects if the string (or filepath) matches downloader patterns
  /// and returns the normalized download source name, or null.
  static String? detectDownloadSource(String pathOrText) {
    if (pathOrText.contains(_downloaderPatterns['y2mate.com']!)) {
      return 'YouTube (y2mate)';
    }
    if (pathOrText.contains(_downloaderPatterns['snappea']!)) {
      return 'YouTube (snappea)';
    }
    if (pathOrText.contains(_downloaderPatterns['ssyoutube']!)) {
      return 'YouTube (ssyoutube)';
    }
    if (pathOrText.contains(_downloaderPatterns['savefrom']!)) {
      return 'YouTube (savefrom)';
    }
    return null;
  }

  /// Helper to remove trailing/leading dashes, underscores, and extra spaces.
  static String _trimHangingPunctuation(String s) {
    var result = s.trim();

    bool changed = true;
    while (changed) {
      changed = false;
      // Trim leading hyphens, underscores, dots, or spaces
      if (result.startsWith('-') || result.startsWith('_') || result.startsWith('.')) {
        result = result.substring(1).trim();
        changed = true;
      }
      // Trim trailing hyphens, underscores, dots, or spaces
      if (result.endsWith('-') || result.endsWith('_') || result.endsWith('.')) {
        result = result.substring(0, result.length - 1).trim();
        changed = true;
      }
    }
    return result;
  }
}
