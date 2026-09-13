import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/services/audio_player_service.dart';

void main() {
  group('AudioPlayerService Decoupled Queue Architecture (Tidal Style)', () {
    late AudioPlayerService player;
    late Track track1;
    late Track track2;
    late Track track3;
    late Track track4;
    late Track track5;

    setUp(() async {
      player = AudioPlayerService.instance;
      await player.stopAndReset(clearHistory: true);

      track1 = Track()..trackId = 't1';
      track2 = Track()..trackId = 't2';
      track3 = Track()..trackId = 't3';
      track4 = Track()..trackId = 't4';
      track5 = Track()..trackId = 't5';
    });

    test('addToQueue on empty queue starts playing track1', () async {
      player.addToQueue(track1);

      expect(player.queue.length, 1);
      expect(player.queue[0].trackId, 't1');
      expect(player.currentIndex, 0);
      expect(player.currentTrack?.trackId, 't1');
    });

    test('addToQueue adds to the end of userQueue', () async {
      await player.loadPlaylist([track1], initialIndex: 0);
      expect(player.queue.length, 1);

      player.addToQueue(track2);
      expect(player.userQueue.length, 1);
      expect(player.userQueue[0].trackId, 't2');
      expect(player.queue.length, 2);
      expect(player.queue[1].trackId, 't2');
      expect(player.currentIndex, 0); // Still playing t1
    });

    test('playNext inserts at front of userQueue without mutating context', () async {
      await player.loadPlaylist([track1, track3], initialIndex: 0); // Currently playing t1, contextQueue = [t3]
      expect(player.queue.length, 2);
      expect(player.currentIndex, 0);

      player.playNext(track2);

      expect(player.userQueue.length, 1);
      expect(player.userQueue[0].trackId, 't2');
      expect(player.contextQueue.map((t) => t.trackId), ['t3']);
      expect(player.queue.map((t) => t.trackId), ['t1', 't2', 't3']);
      expect(player.currentIndex, 0); // Still playing t1
    });

    test('playNext on empty queue starts playing track immediately', () async {
      player.playNext(track1);

      expect(player.queue.length, 1);
      expect(player.queue[0].trackId, 't1');
      expect(player.currentIndex, 0);
      expect(player.currentTrack?.trackId, 't1');
    });

    test('clearQueue removes userQueue and upcoming context except the current one, preserving history', () async {
      await player.loadPlaylist([track1, track2, track3], initialIndex: 0);
      player.addToQueue(track4);
      await player.next(); // plays userQueue track4, pushes track1 to history

      expect(player.history.map((t) => t.trackId), ['t1']);
      expect(player.currentTrack?.trackId, 't4');
      expect(player.contextQueue.map((t) => t.trackId), ['t2', 't3']);

      player.clearQueue();

      // Invariant: history is preserved as an immutable audit log
      expect(player.history.map((t) => t.trackId), ['t1']);
      expect(player.userQueue, isEmpty);
      expect(player.contextQueue, isEmpty);
      expect(player.queue.length, 2); // [t1 (history), t4 (current)]
      expect(player.queue.map((t) => t.trackId), ['t1', 't4']);
      expect(player.currentIndex, 1);
    });

    test('clearQueue on empty queue does nothing', () async {
      expect(player.queue.length, 0);
      player.clearQueue();
      expect(player.queue.length, 0);
    });

    test('dual queue: userQueue and contextQueue separation and clearUserQueue', () async {
      await player.loadPlaylist([track1, track2], initialIndex: 0, contextName: 'Album: Test');
      expect(player.contextName, 'Album: Test');
      expect(player.userQueue, isEmpty);
      expect(player.contextQueue.map((t) => t.trackId), ['t2']);

      // Add track3 via playNext
      player.playNext(track3);
      expect(player.userQueue.map((t) => t.trackId), ['t3']);
      expect(player.contextQueue.map((t) => t.trackId), ['t2']);
      expect(player.queue.map((t) => t.trackId), ['t1', 't3', 't2']);

      // clearUserQueue removes only user items
      player.clearUserQueue();
      expect(player.userQueue, isEmpty);
      expect(player.contextQueue.map((t) => t.trackId), ['t2']);
      expect(player.queue.map((t) => t.trackId), ['t1', 't2']);
    });

    test('dual queue: reordering within userQueue', () async {
      await player.loadPlaylist([track1, track2], initialIndex: 0);

      player.addToQueue(track3);
      player.addToQueue(track4);
      expect(player.userQueue.map((t) => t.trackId), ['t3', 't4']);

      // Reorder track3 and track4 in userQueue
      player.reorderUserQueue(0, 2);
      expect(player.userQueue.map((t) => t.trackId), ['t4', 't3']);
    });

    test('dual queue: reordering within contextQueue', () async {
      await player.loadPlaylist([track1, track2, track3, track4], initialIndex: 0);
      expect(player.contextQueue.map((t) => t.trackId), ['t2', 't3', 't4']);

      player.reorderContextQueue(0, 3);
      expect(player.contextQueue.map((t) => t.trackId), ['t3', 't4', 't2']);
    });

    test('dual queue: toggleShuffle preserves userQueue before shuffled contextQueue', () async {
      await player.loadPlaylist([track1, track2, track4, track5], initialIndex: 0);

      player.playNext(track3); // userQueue = [track3]
      expect(player.userQueue.map((t) => t.trackId), ['t3']);

      // Shuffle enabled
      player.toggleShuffle();
      expect(player.shuffleEnabled, isTrue);
      // userQueue must still be track3 and immediately after current track (t1) in consolidated queue
      expect(player.userQueue.map((t) => t.trackId), ['t3']);
      expect(player.queue[1].trackId, 't3');

      // Unshuffle restores
      player.toggleShuffle();
      expect(player.shuffleEnabled, isFalse);
    });

    test('playUserQueueItem consumes previous user items and preserves context', () async {
      await player.loadPlaylist([track1, track2], initialIndex: 0);

      player.addToQueue(track3);
      player.addToQueue(track4);
      player.addToQueue(track5);
      // userQueue: [t3, t4, t5]
      // contextQueue: [t2]
      expect(player.userQueue.map((t) => t.trackId), ['t3', 't4', 't5']);
      expect(player.contextQueue.map((t) => t.trackId), ['t2']);

      // Tap index 1 of userQueue (t4).
      // t3 should be consumed/skipped, t4 becomes currentTrack, t5 stays in userQueue, t2 in contextQueue
      await player.playUserQueueItem(1);

      expect(player.currentTrack?.trackId, 't4');
      expect(player.userQueue.map((t) => t.trackId), ['t5']);
      expect(player.contextQueue.map((t) => t.trackId), ['t2']);
      expect(player.history.map((t) => t.trackId), ['t1']); // t1 pushed to history
    });

    test('playContextQueueItem preserves 100% of userQueue and pushes ONLY currentTrack to history', () async {
      await player.loadPlaylist([track1, track2, track4, track5], initialIndex: 0);

      player.addToQueue(track3);
      // current: t1
      // userQueue: [t3]
      // contextQueue: [t2, t4, t5]
      expect(player.userQueue.map((t) => t.trackId), ['t3']);
      expect(player.contextQueue.map((t) => t.trackId), ['t2', 't4', 't5']);

      // Tap index 1 of contextQueue (t4). (Skipping t2)
      // Only t1 is pushed to history, skipped intermediate t2 is NOT in history!
      await player.playContextQueueItem(1);

      expect(player.currentTrack?.trackId, 't4');
      expect(player.history.map((t) => t.trackId), ['t1']); // Only t1, t2 NOT injected
      expect(player.userQueue.map((t) => t.trackId), ['t3']); // userQueue 100% intact
      expect(player.contextQueue.map((t) => t.trackId), ['t5']); // remaining context
    });

    test('playFromExternalContext preserves userQueue and pushes previous track to history', () async {
      final track6 = Track()..trackId = 't6';

      await player.loadPlaylist([track1, track2], initialIndex: 0);
      player.addToQueue(track3);
      expect(player.userQueue.map((t) => t.trackId), ['t3']);

      // User selects track5 from a new Album [t4, t5, t6]
      await player.playFromExternalContext(
        track5,
        [track4, track5, track6],
        contextName: 'Album: New',
      );

      expect(player.currentTrack?.trackId, 't5');
      expect(player.contextName, 'Album: New');
      // userQueue [t3] is preserved
      expect(player.userQueue.map((t) => t.trackId), ['t3']);
      expect(player.contextQueue.map((t) => t.trackId), ['t6']);
      expect(player.history.map((t) => t.trackId), ['t1']);
    });

    test('history stack: records played tracks as playback advances', () async {
      await player.loadPlaylist([track1, track2, track3, track4], initialIndex: 0);

      expect(player.currentTrack?.trackId, 't1');
      expect(player.history, isEmpty);
      expect(player.contextQueue.map((t) => t.trackId), ['t2', 't3', 't4']);

      await player.next(); // advances to t2
      expect(player.currentTrack?.trackId, 't2');
      expect(player.history.map((t) => t.trackId), ['t1']);
      expect(player.contextQueue.map((t) => t.trackId), ['t3', 't4']);

      await player.next(); // advances to t3
      expect(player.currentTrack?.trackId, 't3');
      expect(player.history.map((t) => t.trackId), ['t1', 't2']);
      expect(player.contextQueue.map((t) => t.trackId), ['t4']);
    });

    test('playHistoryItem jumps to history track, logs active track to history, and keeps entire history intact', () async {
      await player.loadPlaylist([track1, track2, track3, track4], initialIndex: 0);
      await player.next(); // t2, history = [t1]
      await player.next(); // t3, history = [t1, t2]

      player.addToQueue(track5); // userQueue = [t5]
      expect(player.history.map((t) => t.trackId), ['t1', 't2']);
      expect(player.currentTrack?.trackId, 't3');
      expect(player.userQueue.map((t) => t.trackId), ['t5']);
      expect(player.contextQueue.map((t) => t.trackId), ['t4']);

      // Jump to history index 0 (t1).
      // Invariant: t3 is pushed to history log. History is NOT truncated (immutable log = [t1, t2, t3]).
      // t1 becomes current. userQueue = [t5] is 100% intact.
      // upcoming context is synced to [t2, t3, t4].
      await player.playHistoryItem(0);

      expect(player.currentTrack?.trackId, 't1');
      expect(player.history.map((t) => t.trackId), ['t1', 't2', 't3']);
      expect(player.userQueue.map((t) => t.trackId), ['t5']);
      expect(player.contextQueue.map((t) => t.trackId), ['t2', 't3', 't4']);
    });

    test('consecutive deduplication: pushing the same track consecutively does NOT create duplicates in _history', () async {
      await player.loadPlaylist([track1, track2], initialIndex: 0);
      await player.next(); // current = t2, history = [t1]

      expect(player.currentTrack?.trackId, 't2');
      expect(player.history.map((t) => t.trackId), ['t1']);

      // Jump to history index 0 (t1) -> current = t1, pushes t2 to history -> history = [t1, t2]
      await player.playHistoryItem(0);
      expect(player.currentTrack?.trackId, 't1');
      expect(player.history.map((t) => t.trackId), ['t1', 't2']);

      // Tapping t1 in history again (it is currently playing) should seek to zero and NOT duplicate in history
      await player.playHistoryItem(0);
      expect(player.currentTrack?.trackId, 't1');
      expect(player.history.map((t) => t.trackId), ['t1', 't2']); // Still 2 items, no duplicate!

      // Jump to history index 1 (t2) -> current = t2, pushes t1 to history -> history = [t1, t2, t1]
      await player.playHistoryItem(1);
      expect(player.currentTrack?.trackId, 't2');
      expect(player.history.map((t) => t.trackId), ['t1', 't2', 't1']);
    });

    test('previous() with position > 3s restarts current track and does not change track', () async {
      await player.loadPlaylist([track1, track2], initialIndex: 0);
      await player.next(); // current = track2
      expect(player.currentTrack?.trackId, 't2');

      // Set position to 10 seconds (> 3s)
      player.setMockPosition(const Duration(seconds: 10));
      expect(player.position, const Duration(seconds: 10));

      await player.previous();

      // Track should still be track2, position reset to 0
      expect(player.currentTrack?.trackId, 't2');
      expect(player.position, Duration.zero);
    });

    test('navigation loop prevention: previous() pops navigation stack and stops at first track without ping-pong', () async {
      await player.loadPlaylist([track1, track2], initialIndex: 0); // starts at track1, navigationStack = []
      await player.next(); // current = track2, navigationStack = [t1]
      expect(player.currentTrack?.trackId, 't2');

      // First previous() (< 3s): pops t1 from navigationStack, current becomes t1, navigationStack is now []
      await player.previous();
      expect(player.currentTrack?.trackId, 't1');

      // Second previous() (< 3s): navigationStack is empty -> stays on t1, seeks to zero, NO ping-pong to t2!
      await player.previous();
      expect(player.currentTrack?.trackId, 't1');
      expect(player.position, Duration.zero);
    });

    test('previous() in Shuffle mode strictly unwinds playback navigation stack', () async {
      await player.loadPlaylist([track1, track2, track3, track4], initialIndex: 0);
      player.toggleShuffle(); // shuffle enabled

      // Advance two tracks in shuffle
      await player.next();
      final secondTrackId = player.currentTrack!.trackId;
      await player.next();

      // Calling previous() must return to the exact second track played
      await player.previous();
      expect(player.currentTrack?.trackId, secondTrackId);

      // Calling previous() again must return to track1
      await player.previous();
      expect(player.currentTrack?.trackId, 't1');

      // Calling previous() on empty stack stays on track1
      await player.previous();
      expect(player.currentTrack?.trackId, 't1');
    });

    test('consolidated queue getter reflects [History + Current + UserQueue + UpcomingContext]', () async {
      await player.loadPlaylist([track1, track2, track3, track4], initialIndex: 0);
      player.addToQueue(track5);
      
      // Initially: current=t1, history=[], userQueue=[t5], context=[t2, t3, t4]
      expect(player.queue.map((t) => t.trackId), ['t1', 't5', 't2', 't3', 't4']);
      expect(player.currentIndex, 0);

      // Advance -> consumes userQueue t5, t1 pushed to history
      await player.next();
      // Now: history=[t1], current=t5, userQueue=[], context=[t2, t3, t4]
      expect(player.queue.map((t) => t.trackId), ['t1', 't5', 't2', 't3', 't4']);
      expect(player.currentIndex, 1); // Points to t5 in consolidated queue
      expect(player.queue[player.currentIndex].trackId, 't5');
    });

    test('skipToIndex correctly routes to history, userQueue, and contextQueue', () async {
      await player.loadPlaylist([track1, track2, track3, track4], initialIndex: 0);
      await player.next(); // t2, history=[t1]
      player.addToQueue(track5); // userQueue=[t5]
      // Consolidated queue: [t1 (hist 0), t2 (curr 1), t5 (user 2), t3 (ctx 3), t4 (ctx 4)]
      expect(player.queue.map((t) => t.trackId), ['t1', 't2', 't5', 't3', 't4']);

      // Skip to index 4 (t4 in upcoming context)
      await player.skipToIndex(4);
      expect(player.currentTrack?.trackId, 't4');
      expect(player.userQueue.map((t) => t.trackId), ['t5']); // userQueue preserved
    });
  });
}
