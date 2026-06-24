import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/utils/fuzzy_matcher.dart';

void main() {
  group('FuzzyMatcher - areArtistsSimilar', () {
    test('Exact match (different casing and spacing)', () {
      expect(
        FuzzyMatcher.areArtistsSimilar('Slipknot', 'slipknot'),
        isTrue,
      );
      expect(
        FuzzyMatcher.areArtistsSimilar('  Slipknot  ', 'Slipknot'),
        isTrue,
      );
      expect(
        FuzzyMatcher.areArtistsSimilar('Malice Mizer', 'MaliceMizer'),
        isTrue,
      );
    });

    test('Match with special characters', () {
      expect(
        FuzzyMatcher.areArtistsSimilar('Linkin Park', 'Linkin_Park'),
        isTrue,
      );
      expect(
        FuzzyMatcher.areArtistsSimilar('AC/DC', 'ACDC'),
        isTrue,
      );
      expect(
        FuzzyMatcher.areArtistsSimilar('Guns N\' Roses', 'Guns N Roses'),
        isTrue,
      );
    });

    test('Match with slight typos (Dice coefficient)', () {
      expect(
        FuzzyMatcher.areArtistsSimilar('Slipknot', 'slipnot'),
        isTrue, // Dice coefficient should be high enough
      );
      expect(
        FuzzyMatcher.areArtistsSimilar('Metallica', 'Metalica'),
        isTrue,
      );
    });

    test('Do not match clearly different artists', () {
      expect(
        FuzzyMatcher.areArtistsSimilar('Slipknot', 'Korn'),
        isFalse,
      );
      expect(
        FuzzyMatcher.areArtistsSimilar('Nirvana', 'Radiohead'),
        isFalse,
      );
    });

    test('Empty inputs', () {
      expect(FuzzyMatcher.areArtistsSimilar('', 'Slipknot'), isFalse);
      expect(FuzzyMatcher.areArtistsSimilar('Slipknot', ''), isFalse);
      expect(FuzzyMatcher.areArtistsSimilar('', ''), isFalse);
    });

    test('Custom threshold', () {
      // "Metallica" vs "Metal"
      // Normalised: "metallica" vs "metal"
      // Bigrams metallica: me, et, ta, al, ll, li, ic, ca
      // Bigrams metal: me, et, ta, al
      // Intersection: me, et, ta, al (4)
      // (2 * 4) / (8 + 4) = 8 / 12 = 0.666...
      expect(
        FuzzyMatcher.areArtistsSimilar('Metallica', 'Metal', threshold: 0.6),
        isTrue,
      );
      expect(
        FuzzyMatcher.areArtistsSimilar('Metallica', 'Metal', threshold: 0.7),
        isFalse,
      );
    });
  });

  group('FuzzyMatcher - similarity (Dice coefficient)', () {
    test('Calculates similarity correctly', () {
      expect(FuzzyMatcher.similarity('abc', 'abc'), 1.0);
      expect(FuzzyMatcher.similarity('abc', 'def'), 0.0);
      expect(FuzzyMatcher.similarity('a', 'b'), 0.0);
      expect(FuzzyMatcher.similarity('a', 'a'), 1.0);
    });
  });

  group('FuzzyMatcher - levenshteinDistance', () {
    test('Calculates edit distance correctly', () {
      expect(FuzzyMatcher.levenshteinDistance('kitten', 'sitting'), 3);
      expect(FuzzyMatcher.levenshteinDistance('book', 'back'), 2);
      expect(FuzzyMatcher.levenshteinDistance('', 'abc'), 3);
      expect(FuzzyMatcher.levenshteinDistance('abc', ''), 3);
      expect(FuzzyMatcher.levenshteinDistance('abc', 'abc'), 0);
    });
  });
}
