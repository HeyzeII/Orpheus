import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/utils/vorbis_lyrics_reader.dart';

Uint8List createMockFlacWithVorbisComments(Map<String, String> comments) {
  final commentBytesList = <List<int>>[];
  for (final entry in comments.entries) {
    final commentStr = '${entry.key}=${entry.value}';
    final commentUtf8 = utf8.encode(commentStr);
    final lenBytes = ByteData(4)..setUint32(0, commentUtf8.length, Endian.little);
    commentBytesList.add(lenBytes.buffer.asUint8List());
    commentBytesList.add(commentUtf8);
  }

  final vendorUtf8 = utf8.encode('reference libFLAC 1.4.0');
  final vendorLenBytes = ByteData(4)..setUint32(0, vendorUtf8.length, Endian.little);

  final userCountBytes = ByteData(4)..setUint32(0, comments.length, Endian.little);

  final vorbisPayload = <int>[
    ...vendorLenBytes.buffer.asUint8List(),
    ...vendorUtf8,
    ...userCountBytes.buffer.asUint8List(),
    for (final cb in commentBytesList) ...cb,
  ];

  final vorbisLen = vorbisPayload.length;
  final vorbisHeader = [
    0x84, // isLast = true (0x80) | blockType = 4 (VORBIS_COMMENT)
    (vorbisLen >> 16) & 0xFF,
    (vorbisLen >> 8) & 0xFF,
    vorbisLen & 0xFF,
  ];

  final streamInfoPayload = List<int>.filled(34, 0);
  final streamInfoHeader = [
    0x00, // isLast = false | blockType = 0 (STREAMINFO)
    0x00,
    0x00,
    34,
  ];

  return Uint8List.fromList([
    0x66, 0x4C, 0x61, 0x43, // 'fLaC' magic
    ...streamInfoHeader,
    ...streamInfoPayload,
    ...vorbisHeader,
    ...vorbisPayload,
  ]);
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vorbis_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('VorbisLyricsReader Tests', () {
    test('extracts LYRICS tag from valid FLAC file', () async {
      const expectedLyrics = '[00:12.50] Is this the real life?\n[00:15.00] Is this just fantasy?';
      final flacBytes = createMockFlacWithVorbisComments({
        'ARTIST': 'Queen',
        'TITLE': 'Bohemian Rhapsody',
        'LYRICS': expectedLyrics,
      });

      final flacFile = File('${tempDir.path}/song.flac');
      await flacFile.writeAsBytes(flacBytes);

      final extracted = await VorbisLyricsReader.extractLyricsFromFile(flacFile.path);
      expect(extracted, equals(expectedLyrics));
    });

    test('extracts UNSYNCEDLYRICS and SYNCEDLYRICS tags', () async {
      const unsyncedLyrics = 'Plain text lyrics without timestamps.';
      final flacBytes = createMockFlacWithVorbisComments({
        'TITLE': 'Sample Track',
        'UNSYNCEDLYRICS': unsyncedLyrics,
      });

      final flacFile = File('${tempDir.path}/unsynced.flac');
      await flacFile.writeAsBytes(flacBytes);

      final extracted = await VorbisLyricsReader.extractLyricsFromFile(flacFile.path);
      expect(extracted, equals(unsyncedLyrics));
    });

    test('returns null if FLAC has Vorbis comments but no lyrics tag', () async {
      final flacBytes = createMockFlacWithVorbisComments({
        'ARTIST': 'Daft Punk',
        'TITLE': 'One More Time',
        'ALBUM': 'Discovery',
      });

      final flacFile = File('${tempDir.path}/no_lyrics.flac');
      await flacFile.writeAsBytes(flacBytes);

      final extracted = await VorbisLyricsReader.extractLyricsFromFile(flacFile.path);
      expect(extracted, isNull);
    });

    test('returns null for non-FLAC files or corrupt binaries', () async {
      final mp3File = File('${tempDir.path}/not_a_flac.flac');
      await mp3File.writeAsString('ID3\x03\x00\x00\x00some-mp3-data');

      final extracted = await VorbisLyricsReader.extractLyricsFromFile(mp3File.path);
      expect(extracted, isNull);
    });

    test('parseVorbisCommentBlock parses raw Uint8List buffer directly', () {
      const expectedLyrics = '[00:01.00] Test line';
      final flacBytes = createMockFlacWithVorbisComments({
        'LYRICS': expectedLyrics,
      });

      // Vorbis block starts after 4 bytes magic + 4 bytes header + 34 bytes STREAMINFO + 4 bytes Vorbis header = 46 bytes
      final vorbisBlockPayload = flacBytes.sublist(46);
      final extracted = VorbisLyricsReader.parseVorbisCommentBlock(vorbisBlockPayload);
      expect(extracted, equals(expectedLyrics));
    });
  });
}
