import 'package:isar/isar.dart';

part 'app_config.g.dart';

/// Embedded object representing a single artist-pair that the user has
/// decided to permanently ignore during the fuzzy-similarity scanner.
///
/// When the similarity algorithm proposes merging "slipnot" → "Slipknot",
/// the user can dismiss it permanently. That decision is stored here so the
/// algorithm never surfaces that pair again.
@embedded
class IgnoredArtistPair {
  /// The "wrong" or variant artist name found in the library.
  String artistA = '';

  /// The canonical artist name the scanner suggested merging into.
  String artistB = '';
}

/// Embedded object that holds the conflict-resolution state for the
/// fuzzy-matching artist-name deduplication feature.
@embedded
class ConflictResolution {
  /// All artist pairs permanently dismissed by the user.
  List<IgnoredArtistPair> ignoredPairs = [];
}

/// Isar Collection for global application configuration.
///
/// There is always exactly one [AppConfig] document (id == 1).
/// Retrieve it with [LocalDatabase.getConfig] and write it back
/// with [LocalDatabase.saveConfig].
@collection
class AppConfig {
  /// Fixed primary key — there is only one config document.
  Id id = 1;

  /// Current UI theme identifier (e.g. "dark_tidal", "amoled", "light").
  String theme = 'dark_tidal';

  /// Absolute paths of directories that the library scanner should index.
  List<String> scanDirectories = [];

  /// Artist-pair conflict resolution state (fuzzy-matching deduplication).
  ConflictResolution conflictResolution = ConflictResolution();
}
