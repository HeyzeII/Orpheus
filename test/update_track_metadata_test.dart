import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/models/track.dart';

class FakeLocalDatabase extends LocalDatabase {
  FakeLocalDatabase() : super.internal();

  final Map<String, Track> _tracks = {};

  @override
  Future<void> saveTrack(Track track) async {
    _tracks[track.trackId] = track;
  }

  @override
  Future<List<Track>> getAllTracks() async {
    return _tracks.values.toList();
  }

  @override
  Future<void> resetNotFoundMediaFlags() async {
    for (final track in _tracks.values) {
      if (track.artStatus == FetchStatus.notFound) {
        track.artStatus = FetchStatus.none;
      }
      if (track.lyricsStatus == FetchStatus.notFound) {
        track.lyricsStatus = FetchStatus.none;
        track.syncedLyrics = null;
      }
    }
  }
}

void main() {
  group('LocalDatabase - updateTrackMetadata tests', () {
    late FakeLocalDatabase db;
    late Track track;

    setUp(() {
      db = FakeLocalDatabase();
      track = Track()
        ..trackId = 'test_track_id'
        ..filePath = '/music/awesome_song.mp3'
        ..title = 'Original Title'
        ..artist = 'Original Artist'
        ..album = 'Original Album'
        ..fileType = FileType.mp3
        ..artStatus = FetchStatus.success
        ..lyricsStatus = FetchStatus.success
        ..syncedLyrics = '[00:10.00] Synced Lyrics';
    });

    test('saves custom fields correctly', () async {
      await db.updateTrackMetadata(
        track,
        newTitle: 'New Title',
        newArtist: 'New Artist',
        newAlbum: 'New Album',
        resetMediaFlags: false,
      );

      expect(track.customMetadata.title, 'New Title');
      expect(track.customMetadata.artist, 'New Artist');
      expect(track.customMetadata.album, 'New Album');
      expect(track.customMetadata.isEdited, isTrue);
      expect(track.hasCustomMetadata, isTrue);
    });

    test('resetMediaFlags clears art and lyrics status when true', () async {
      await db.updateTrackMetadata(
        track,
        newTitle: 'New Title',
        newArtist: 'New Artist',
        newAlbum: 'New Album',
        resetMediaFlags: true,
      );

      expect(track.artStatus, FetchStatus.none);
      expect(track.lyricsStatus, FetchStatus.none);
      expect(track.syncedLyrics, isNull);
    });

    test('does not reset flags when resetMediaFlags is false', () async {
      await db.updateTrackMetadata(
        track,
        newTitle: 'New Title',
        newArtist: 'New Artist',
        newAlbum: 'New Album',
        resetMediaFlags: false,
      );

      expect(track.artStatus, FetchStatus.success);
      expect(track.lyricsStatus, FetchStatus.success);
      expect(track.syncedLyrics, '[00:10.00] Synced Lyrics');
    });

    test('trims whitespace from fields', () async {
      await db.updateTrackMetadata(
        track,
        newTitle: '  Trimmed Title   ',
        newArtist: '   Trimmed Artist  ',
        newAlbum: ' Trimmed Album ',
        resetMediaFlags: false,
      );

      expect(track.customMetadata.title, 'Trimmed Title');
      expect(track.customMetadata.artist, 'Trimmed Artist');
      expect(track.customMetadata.album, 'Trimmed Album');
    });

    test('stores empty strings as null overrides', () async {
      await db.updateTrackMetadata(
        track,
        newTitle: '',
        newArtist: '   ',
        newAlbum: 'New Album',
        resetMediaFlags: false,
      );

      expect(track.customMetadata.title, isNull);
      expect(track.customMetadata.artist, isNull);
      expect(track.customMetadata.album, 'New Album');
    });

    test('resetNotFoundMediaFlags clears only FetchStatus.notFound flags', () async {
      final track1 = Track()
        ..trackId = 't1'
        ..filePath = '/music/t1.mp3'
        ..artStatus = FetchStatus.notFound
        ..lyricsStatus = FetchStatus.notFound
        ..syncedLyrics = 'lyrics content';

      final track2 = Track()
        ..trackId = 't2'
        ..filePath = '/music/t2.mp3'
        ..artStatus = FetchStatus.success
        ..lyricsStatus = FetchStatus.success
        ..syncedLyrics = 'lyrics content';

      await db.saveTrack(track1);
      await db.saveTrack(track2);

      await db.resetNotFoundMediaFlags();

      expect(track1.artStatus, FetchStatus.none);
      expect(track1.lyricsStatus, FetchStatus.none);
      expect(track1.syncedLyrics, isNull);

      expect(track2.artStatus, FetchStatus.success);
      expect(track2.lyricsStatus, FetchStatus.success);
      expect(track2.syncedLyrics, 'lyrics content');
    });
  });
}
