import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/services/audio_player_service.dart';

void main() {
  group('AudioPlayerService Queue Management', () {
    late AudioPlayerService player;
    late Track track1;
    late Track track2;
    late Track track3;

    setUp(() async {
      player = AudioPlayerService.instance;
      // We clear the queue before each test
      await player.loadPlaylist([]);

      track1 = Track()..trackId = 't1';
      track2 = Track()..trackId = 't2';
      track3 = Track()..trackId = 't3';
    });

    test('addToQueue on empty queue starts playing track1', () async {
      player.addToQueue(track1);

      expect(player.queue.length, 1);
      expect(player.queue[0].trackId, 't1');
      expect(player.currentIndex, 0);
    });

    test('addToQueue adds to the end of the queue', () async {
      await player.loadPlaylist([track1], initialIndex: 0);
      expect(player.queue.length, 1);

      player.addToQueue(track2);
      expect(player.queue.length, 2);
      expect(player.queue[1].trackId, 't2');
      expect(player.currentIndex, 0); // Still playing t1
    });

    test('playNext inserts immediately after current track', () async {
      await player.loadPlaylist([track1, track3], initialIndex: 0); // Currently playing t1
      expect(player.queue.length, 2);
      expect(player.currentIndex, 0);

      player.playNext(track2);
      
      expect(player.queue.length, 3);
      expect(player.queue[1].trackId, 't2');
      expect(player.queue[2].trackId, 't3');
      expect(player.currentIndex, 0); // Still playing t1
    });

    test('playNext removes existing instance from later in queue to prevent duplicates mid-queue', () async {
      await player.loadPlaylist([track1, track2, track3], initialIndex: 0);
      expect(player.queue.length, 3);
      
      // We are at track1, queue is t1, t2, t3.
      // playNext(track3) should move t3 to index 1.
      player.playNext(track3);

      expect(player.queue.length, 3);
      expect(player.queue[1].trackId, 't3');
      expect(player.queue[2].trackId, 't2');
    });

    test('playNext on empty queue starts playing track immediately', () async {
      player.playNext(track1);

      expect(player.queue.length, 1);
      expect(player.queue[0].trackId, 't1');
      expect(player.currentIndex, 0);
    });

    test('clearQueue removes all tracks except the current one', () async {
      await player.loadPlaylist([track1, track2, track3], initialIndex: 1);
      expect(player.queue.length, 3);
      expect(player.currentIndex, 1); // Playing t2

      player.clearQueue();

      expect(player.queue.length, 1);
      expect(player.queue[0].trackId, 't2'); // Only current track remains
      expect(player.currentIndex, 0);
    });

    test('clearQueue on empty queue does nothing', () async {
      // queue is already empty from setUp
      expect(player.queue.length, 0);
      player.clearQueue(); // Should not throw
      expect(player.queue.length, 0);
    });
  });
}
