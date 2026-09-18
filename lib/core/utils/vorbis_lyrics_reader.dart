import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Pure Dart, strictly read-only utility to extract embedded lyrics from FLAC Vorbis Comments.
class VorbisLyricsReader {
  VorbisLyricsReader._();

  static const _flacMagic = [0x66, 0x4C, 0x61, 0x43]; // 'fLaC'

  /// Supported Vorbis comment tag keys for embedded lyrics.
  static const _lyricsTagKeys = {
    'LYRICS',
    'UNSYNCEDLYRICS',
    'SYNCEDLYRICS',
    'UNSYNCED LYRICS',
    'LYRICS_TEXT',
    'SUBTITLE',
  };

  /// Reads a FLAC file at [filePath] in read-only mode and extracts any embedded Vorbis lyrics.
  /// Returns `null` if the file is not a valid FLAC, has no Vorbis comments, or contains no lyrics tags.
  static Future<String?> extractLyricsFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final magic = await raf.read(4);
      if (magic.length < 4 ||
          magic[0] != _flacMagic[0] ||
          magic[1] != _flacMagic[1] ||
          magic[2] != _flacMagic[2] ||
          magic[3] != _flacMagic[3]) {
        return null;
      }

      bool isLastBlock = false;
      while (!isLastBlock) {
        final header = await raf.read(4);
        if (header.length < 4) break;

        isLastBlock = (header[0] & 0x80) != 0;
        final blockType = header[0] & 0x7F;
        final blockLength = (header[1] << 16) | (header[2] << 8) | header[3];

        if (blockType == 4) {
          // VORBIS_COMMENT block
          final blockData = await raf.read(blockLength);
          if (blockData.length < blockLength) return null;
          return parseVorbisCommentBlock(Uint8List.fromList(blockData));
        } else {
          // Skip other metadata blocks (e.g. STREAMINFO, PICTURE, PADDING)
          final currentPos = await raf.position();
          await raf.setPosition(currentPos + blockLength);
        }
      }
    } catch (_) {
      return null;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }

    return null;
  }

  /// Parses a raw Vorbis comment block byte buffer and extracts embedded lyrics text.
  static String? parseVorbisCommentBlock(Uint8List bytes) {
    if (bytes.length < 8) return null;

    final byteData = ByteData.sublistView(bytes);
    var offset = 0;

    // 1. Vendor string length (32-bit LE)
    if (offset + 4 > bytes.length) return null;
    final vendorLength = byteData.getUint32(offset, Endian.little);
    offset += 4 + vendorLength;

    // 2. User comment list count (32-bit LE)
    if (offset + 4 > bytes.length) return null;
    final userCommentCount = byteData.getUint32(offset, Endian.little);
    offset += 4;

    // 3. Iterate user comments
    for (var i = 0; i < userCommentCount; i++) {
      if (offset + 4 > bytes.length) break;
      final commentLength = byteData.getUint32(offset, Endian.little);
      offset += 4;

      if (offset + commentLength > bytes.length) break;
      final commentBytes = bytes.sublist(offset, offset + commentLength);
      offset += commentLength;

      final commentStr = utf8.decode(commentBytes, allowMalformed: true);
      final eqIdx = commentStr.indexOf('=');
      if (eqIdx != -1) {
        final key = commentStr.substring(0, eqIdx).trim().toUpperCase();
        final value = commentStr.substring(eqIdx + 1).trim();
        if (_lyricsTagKeys.contains(key) && value.isNotEmpty) {
          return value;
        }
      }
    }

    return null;
  }
}
