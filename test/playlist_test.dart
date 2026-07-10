import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/models/playlist.dart';

class PlaylistFakeLocalDatabase extends LocalDatabase {
  PlaylistFakeLocalDatabase() : super.internal();

  final Map<String, Playlist> _playlists = {};

  @override
  Future<void> savePlaylist(Playlist playlist) async {
    _playlists[playlist.playlistId] = playlist;
  }

  @override
  Future<List<Playlist>> getAllPlaylists() async {
    return _playlists.values.toList();
  }

  @override
  Future<Playlist?> getPlaylistById(String playlistId) async {
    if (playlistId == '__liked__') {
      return _playlists[playlistId] ?? (Playlist()
        ..playlistId = '__liked__'
        ..name = 'Liked Tracks'
        ..description = 'Tracks you have marked as liked.'
        ..isDefault = true);
    }
    return _playlists[playlistId];
  }

  @override
  Future<void> deletePlaylist(int id) async {
    final toDelete = _playlists.values.firstWhere((p) => p.id == id, orElse: () => throw StateError('Not found'));
    if (toDelete.isDefault) {
      throw ArgumentError('Cannot delete system playlist "${toDelete.name}".');
    }
    _playlists.remove(toDelete.playlistId);
  }
}

void main() {
  group('LocalDatabase - Playlist tests', () {
    late PlaylistFakeLocalDatabase db;
    late Playlist customPlaylist;
    late Playlist likedPlaylist;

    setUp(() {
      db = PlaylistFakeLocalDatabase();
      
      customPlaylist = Playlist()
        ..id = 101
        ..playlistId = 'custom_123'
        ..name = 'My Custom Playlist'
        ..description = 'Testing description'
        ..isDefault = false
        ..trackIds = [];

      likedPlaylist = Playlist()
        ..id = 1
        ..playlistId = '__liked__'
        ..name = 'Liked Tracks'
        ..isDefault = true
        ..trackIds = [];

      db.savePlaylist(customPlaylist);
      db.savePlaylist(likedPlaylist);
    });

    test('adds tracks to playlist and handles duplicates based on playlist type', () async {
      // Add first track to custom playlist
      await db.addTrackToPlaylist(playlist: customPlaylist, trackId: 'track_a');
      expect(customPlaylist.trackIds, contains('track_a'.hashCode));
      expect(customPlaylist.trackIds.length, 1);

      // Add duplicate track to custom playlist (should be allowed now)
      await db.addTrackToPlaylist(playlist: customPlaylist, trackId: 'track_a');
      expect(customPlaylist.trackIds.length, 2); // Allows duplicates

      // Add first track to liked playlist
      await db.addTrackToPlaylist(playlist: likedPlaylist, trackId: 'track_a');
      expect(likedPlaylist.trackIds, contains('track_a'.hashCode));
      expect(likedPlaylist.trackIds.length, 1);

      // Add duplicate track to liked playlist (should prevent duplicates)
      await db.addTrackToPlaylist(playlist: likedPlaylist, trackId: 'track_a');
      expect(likedPlaylist.trackIds.length, 1); // No change
    });

    test('removes tracks from playlist correctly', () async {
      await db.addTrackToPlaylist(playlist: customPlaylist, trackId: 'track_a');
      await db.addTrackToPlaylist(playlist: customPlaylist, trackId: 'track_b');
      
      await db.removeTrackFromPlaylist(playlist: customPlaylist, trackId: 'track_a');
      expect(customPlaylist.trackIds, isNot(contains('track_a'.hashCode)));
      expect(customPlaylist.trackIds, contains('track_b'.hashCode));
      expect(customPlaylist.trackIds.length, 1);
    });

    test('deletes custom playlist successfully', () async {
      final playlistsBefore = await db.getAllPlaylists();
      expect(playlistsBefore.length, 2);

      await db.deletePlaylist(customPlaylist.id);
      final playlistsAfter = await db.getAllPlaylists();
      expect(playlistsAfter.length, 1);
      expect(playlistsAfter.first.playlistId, '__liked__');
    });

    test('throws ArgumentError when deleting default/system playlist', () async {
      expect(
        () => db.deletePlaylist(likedPlaylist.id),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Cannot delete system playlist'),
        )),
      );
    });
  });
}
