import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/services/audio_player_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AudioPlayerService player;

  final track1 = Track()..trackId = 't1'..title = 'Track 1'..artist = 'Artist'..duration = 180;
  final track2 = Track()..trackId = 't2'..title = 'Track 2'..artist = 'Artist'..duration = 200;
  final track3 = Track()..trackId = 't3'..title = 'Track 3'..artist = 'Artist'..duration = 220;
  final track4 = Track()..trackId = 't4'..title = 'Track 4'..artist = 'Artist'..duration = 240;

  final userTrack1 = Track()..trackId = 'u1'..title = 'User Track 1'..artist = 'Guest'..duration = 150;
  final userTrack2 = Track()..trackId = 'u2'..title = 'User Track 2'..artist = 'Guest'..duration = 160;

  setUp(() async {
    player = AudioPlayerService.instance;
    await player.stopAndReset(clearHistory: true);
  });

  tearDown(() async {
    await player.stopAndReset(clearHistory: true);
  });

  group('Parent Context Locking & Transient Playback Tests', () {
    test('playNext locks parent contextIndex and projects transient track in playbackDisplayTracks', () async {
      await player.loadPlaylist([track1, track2, track3, track4], initialIndex: 0);
      expect(player.currentTrack?.trackId, 't1');
      expect(player.currentContextIndex, 0);
      expect(player.isTransientPlayback, isFalse);
      expect(player.currentDisplayIndex, 0);
      expect(player.playbackDisplayTracks.map((t) => t.trackId), ['t1', 't2', 't3', 't4']);

      // User adds userTrack1 via playNext
      player.playNext(userTrack1);
      expect(player.userQueue.map((t) => t.trackId), ['u1']);

      // Advancing with next() enters transient playback
      await player.next();
      expect(player.currentTrack?.trackId, 'u1');
      expect(player.isTransientPlayback, isTrue);
      // Parent context pointer is locked at 0
      expect(player.currentContextIndex, 0);
      // Display index points to u1 (index 1 in projected list)
      expect(player.currentDisplayIndex, 1);
      expect(player.playbackDisplayTracks.map((t) => t.trackId), ['t1', 'u1', 't2', 't3', 't4']);
    });

    test('next() from transient returns cleanly to parent context, and previous() unwinds back to transient', () async {
      await player.loadPlaylist([track1, track2, track3, track4], initialIndex: 0);

      player.playNext(userTrack1);
      await player.next();
      expect(player.currentTrack?.trackId, 'u1');
      expect(player.isTransientPlayback, isTrue);

      // next() when userQueue is exhausted resumes parent context at t2
      await player.next();
      expect(player.currentTrack?.trackId, 't2');
      expect(player.isTransientPlayback, isFalse);
      expect(player.currentContextIndex, 1);
      expect(player.currentDisplayIndex, 1);
      expect(player.playbackDisplayTracks.map((t) => t.trackId), ['t1', 't2', 't3', 't4']);

      // previous() within 3 seconds unwinds to u1 instead of skipping it
      player.setMockPosition(Duration.zero);
      await player.previous();
      expect(player.currentTrack?.trackId, 'u1');
      expect(player.isTransientPlayback, isTrue);
      expect(player.currentContextIndex, 0);
      expect(player.currentDisplayIndex, 1);

      // previous() again unwinds to t1
      player.setMockPosition(Duration.zero);
      await player.previous();
      expect(player.currentTrack?.trackId, 't1');
      expect(player.isTransientPlayback, isFalse);
      expect(player.currentContextIndex, 0);
      expect(player.currentDisplayIndex, 0);
    });

    test('playUserQueueItem does NOT mutate parent _contextIndex even if track is in parent playlist', () async {
      await player.loadPlaylist([track1, track2, track3, track4], initialIndex: 0);
      expect(player.currentContextIndex, 0);

      // Add track3 (which is index 2 in playlist) to userQueue and play it
      player.addToQueue(track3);
      await player.playUserQueueItem(0);

      expect(player.currentTrack?.trackId, 't3');
      expect(player.isTransientPlayback, isTrue);
      // _contextIndex must NOT jump to 2; it stays locked at 0
      expect(player.currentContextIndex, 0);
      expect(player.currentDisplayIndex, 1);
      expect(player.playbackDisplayTracks.map((t) => t.trackId), ['t1', 't3', 't2', 't3', 't4']);

      // Calling next() advances to t2 (the next track from locked parent pointer 0)
      await player.next();
      expect(player.currentTrack?.trackId, 't2');
      expect(player.isTransientPlayback, isFalse);
      expect(player.currentContextIndex, 1);
    });

    test('multiple user queue items are correctly projected in playbackDisplayTracks', () async {
      await player.loadPlaylist([track1, track2, track3], initialIndex: 1); // at t2
      expect(player.currentContextIndex, 1);

      player.addToQueue(userTrack1);
      player.addToQueue(userTrack2);

      await player.next(); // plays u1
      expect(player.currentTrack?.trackId, 'u1');
      expect(player.isTransientPlayback, isTrue);
      expect(player.currentContextIndex, 1);

      // Projection: [t1, t2, u1 (current), u2 (queued), t3 (upcoming)]
      expect(player.playbackDisplayTracks.map((t) => t.trackId), ['t1', 't2', 'u1', 'u2', 't3']);
      expect(player.currentDisplayIndex, 2);

      await player.next(); // plays u2
      expect(player.currentTrack?.trackId, 'u2');
      expect(player.isTransientPlayback, isTrue);
      expect(player.currentContextIndex, 1);
      expect(player.playbackDisplayTracks.map((t) => t.trackId), ['t1', 't2', 'u2', 't3']);
      expect(player.currentDisplayIndex, 2);

      await player.next(); // resumes context at t3
      expect(player.currentTrack?.trackId, 't3');
      expect(player.isTransientPlayback, isFalse);
      expect(player.currentContextIndex, 2);
      expect(player.playbackDisplayTracks.map((t) => t.trackId), ['t1', 't2', 't3']);
      expect(player.currentDisplayIndex, 2);
    });
  });
}
