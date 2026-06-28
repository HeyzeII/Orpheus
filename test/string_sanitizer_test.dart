import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/utils/string_sanitizer.dart';

void main() {
  group('StringSanitizer - sanitize', () {
    test('Cleans downloader noise', () {
      expect(
        StringSanitizer.sanitize('y2mate.com - Song Title'),
        equals('Song Title'),
      );
      expect(
        StringSanitizer.sanitize('Song Title snappea'),
        equals('Song Title'),
      );
      expect(
        StringSanitizer.sanitize('ssyoutube - Song Title'),
        equals('Song Title'),
      );
      expect(
        StringSanitizer.sanitize('Song Title savefrom'),
        equals('Song Title'),
      );
    });

    test('Removes video/audio modisms', () {
      expect(
        StringSanitizer.sanitize('Song Title [Official Video]'),
        equals('Song Title'),
      );
      expect(
        StringSanitizer.sanitize('Song Title (Audio)'),
        equals('Song Title'),
      );
      expect(
        StringSanitizer.sanitize('Song Title (Lyrics)'),
        equals('Song Title'),
      );
      expect(
        StringSanitizer.sanitize('Song Title HD 4K'),
        equals('Song Title'),
      );
      expect(
        StringSanitizer.sanitize('Song Title (Official Lyric Video)'),
        equals('Song Title'),
      );
    });

    test('Combines downloader and modism cleaning', () {
      expect(
        StringSanitizer.sanitize('y2mate.com - Linkin Park - Numb (Official Video) [Lyrics]'),
        equals('Linkin Park - Numb'),
      );
    });

    test('Trims extra punctuation and spaces correctly', () {
      expect(
        StringSanitizer.sanitize('--- Song Title ---'),
        equals('Song Title'),
      );
      expect(
        StringSanitizer.sanitize('...Song Title...'),
        equals('Song Title'),
      );
      expect(
        StringSanitizer.sanitize('_Song Title_'),
        equals('Song Title'),
      );
      expect(
        StringSanitizer.sanitize('   Song   Title   '),
        equals('Song Title'),
      );
    });
  });

  group('StringSanitizer - detectDownloadSource', () {
    test('Detects source from text/path containing indicators', () {
      expect(
        StringSanitizer.detectDownloadSource('path/to/y2mate.com - track.mp3'),
        equals('YouTube (y2mate)'),
      );
      expect(
        StringSanitizer.detectDownloadSource('snappea_track_name'),
        equals('YouTube (snappea)'),
      );
      expect(
        StringSanitizer.detectDownloadSource('ssyoutube_audio'),
        equals('YouTube (ssyoutube)'),
      );
      expect(
        StringSanitizer.detectDownloadSource('track_savefrom_source'),
        equals('YouTube (savefrom)'),
      );
    });

    test('Returns null when no source is matched', () {
      expect(
        StringSanitizer.detectDownloadSource('/Users/BETTY/Music/Song.mp3'),
        isNull,
      );
    });
  });

  group('StringSanitizer - prepareSearchQuery', () {
    test('Uses non-empty ID3 tag and sanitizes it', () {
      expect(
        StringSanitizer.prepareSearchQuery(
          id3Tag: 'y2mate.com - Linkin Park [Official Video]',
          filePath: '/path/to/numb.mp3',
        ),
        equals('Linkin Park'),
      );
    });

    test('Falls back to filename and cleans common modifiers when ID3 tag is empty', () {
      expect(
        StringSanitizer.prepareSearchQuery(
          id3Tag: null,
          filePath: '/path/to/My Song [Official Audio] (Sub Esp).mp3',
        ),
        equals('My Song'),
      );
      expect(
        StringSanitizer.prepareSearchQuery(
          id3Tag: '',
          filePath: '/path/to/Another Track sub esp official audio.mp3',
        ),
        equals('Another Track'),
      );
    });
  });
}
