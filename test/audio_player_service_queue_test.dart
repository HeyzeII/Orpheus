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
      final thirdTrackId = player.currentTrack!.trackId;

      // Calling previous() must return to the exact second track played (pops _navigationStack)
      await player.previous();
      expect(player.currentTrack?.trackId, secondTrackId);

      // Calling previous() again must return to track1 (pops _navigationStack)
      await player.previous();
      expect(player.currentTrack?.trackId, 't1');

      // _navigationStack is now empty. With _contextIndex == 0 (track1 is first in shuffled list),
      // the context fallback cannot go further back → seek to zero (step 4).
      await player.previous();
      expect(player.currentTrack?.trackId, 't1');
      expect(player.position, Duration.zero);

      // Make thirdTrack accessible in assertion (avoid unused variable lint)
      expect(thirdTrackId, isNotEmpty);
    });

    test('previous() context fallback: steps back in album when _navigationStack is empty and _contextIndex > 0', () async {
      // Start at track3 (index 2) directly — simulates opening player mid-album
      await player.loadPlaylist([track1, track2, track3, track4], initialIndex: 2);
      expect(player.currentTrack?.trackId, 't3');
      // _navigationStack is empty (no prior next() calls)

      // previous() should fall back to context: _contextIndex-- → track2
      await player.previous();
      expect(player.currentTrack?.trackId, 't2');

      // previous() again → track1 (_contextIndex = 0)
      await player.previous();
      expect(player.currentTrack?.trackId, 't1');

      // previous() at _contextIndex == 0 → seek(Duration.zero), stays on track1
      await player.previous();
      expect(player.currentTrack?.trackId, 't1');
      expect(player.position, Duration.zero);
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

    // ── Pivot Model (Tidal-style pastContext) ──────────────────────────────────

    test('pastContext is empty at start and grows as _contextIndex advances', () async {
      await player.loadPlaylist([track1, track2, track3, track4], initialIndex: 0);

      // At track1 (index 0): no past context
      expect(player.pastContext, isEmpty);

      await player.next(); // track2
      expect(player.pastContext.map((t) => t.trackId), ['t1']);

      await player.next(); // track3
      expect(player.pastContext.map((t) => t.trackId), ['t1', 't2']);

      await player.next(); // track4
      expect(player.pastContext.map((t) => t.trackId), ['t1', 't2', 't3']);
    });

    test('playContextPastItem jumps backwards, preserves userQueue and accumulates history', () async {
      await player.loadPlaylist([track1, track2, track3, track4], initialIndex: 0);
      await player.next(); // track2, history=[t1]
      await player.next(); // track3, history=[t1, t2]

      player.addToQueue(track5); // userQueue=[t5]
      expect(player.currentTrack?.trackId, 't3');
      expect(player.pastContext.map((t) => t.trackId), ['t1', 't2']);
      expect(player.userQueue.map((t) => t.trackId), ['t5']);

      // Jump back to absoluteIndex=0 (track1 in pastContext)
      await player.playContextPastItem(0);

      expect(player.currentTrack?.trackId, 't1');
      // t3 was pushed to history (now [t1, t2, t3])
      expect(player.history.map((t) => t.trackId), ['t1', 't2', 't3']);
      // userQueue completely intact
      expect(player.userQueue.map((t) => t.trackId), ['t5']);
      // upcoming context from index 1 onward: [t2, t3, t4]
      expect(player.contextQueue.map((t) => t.trackId), ['t2', 't3', 't4']);
      // past context from index 0 (exclusive): now empty since we are at index 0
      expect(player.pastContext, isEmpty);
    });

    test('pastContext resets to empty when playFromExternalContext switches album', () async {
      await player.loadPlaylist([track1, track2, track3], initialIndex: 0);
      await player.next(); // track2, pastContext=[t1]
      expect(player.pastContext.map((t) => t.trackId), ['t1']);

      // Switch to a new album starting at index 0
      await player.playFromExternalContext(
        track4,
        [track4, track5],
        contextName: 'Album: New',
      );

      expect(player.currentTrack?.trackId, 't4');
      // pastContext must be empty: new context starts at index 0
      expect(player.pastContext, isEmpty);
      expect(player.contextQueue.map((t) => t.trackId), ['t5']);
    });

    test('canSkipPrevious evaluates to true when _contextIndex > 0 even with empty navigationStack and 0s position', () async {
      // Load context with track3 (index 2 in list)
      await player.playFromExternalContext(
        track3,
        [track1, track2, track3, track4],
        contextName: 'Album: Test',
      );

      player.setMockPosition(Duration.zero);

      // Stack is empty and position is 0s, but _contextIndex is 2 (>0)
      expect(player.canSkipPrevious, isTrue);
      expect(player.pastContext.map((t) => t.trackId), ['t1', 't2']);

      // At index 0, position 0s, fresh context with stack empty -> canSkipPrevious is false
      await player.playFromExternalContext(
        track1,
        [track1, track2, track3, track4],
        contextName: 'Album: Test',
      );
      player.setMockPosition(Duration.zero);
      expect(player.canSkipPrevious, isFalse);

      // But if position > 3s, canSkipPrevious becomes true
      player.setMockPosition(const Duration(seconds: 4));
      expect(player.canSkipPrevious, isTrue);
    });

    test('manual jump in context queue under sequential mode resets navigation stack so previous() goes to track N-1', () async {
      final tracks = List.generate(10, (i) => Track()..trackId = 't${i + 1}');

      // 1. Play track 5 (index 4) from 10-track playlist
      await player.playFromExternalContext(
        tracks[4],
        tracks,
        contextName: 'Album: Test 10',
      );
      expect(player.currentTrack?.trackId, 't5');
      expect(player.contextQueue.map((t) => t.trackId), ['t6', 't7', 't8', 't9', 't10']);

      // 2. User jumps directly to track 9 (relativeIndex = 3 in contextQueue)
      await player.playContextQueueItem(3);
      expect(player.currentTrack?.trackId, 't9');

      // 3. Press previous (< 3s)
      player.setMockPosition(Duration.zero);
      await player.previous();

      // 4. Must go to track 8 (index 7), NOT track 5
      expect(player.currentTrack?.trackId, 't8');

      // 5. Press previous again (< 3s) -> must go to track 7
      player.setMockPosition(Duration.zero);
      await player.previous();
      expect(player.currentTrack?.trackId, 't7');
    });

    test('manual jump in context queue under shuffle mode preserves navigation stack so previous() returns to previous played track', () async {
      final tracks = List.generate(10, (i) => Track()..trackId = 't${i + 1}');

      await player.playFromExternalContext(
        tracks[0],
        tracks,
        contextName: 'Album: Test 10',
      );
      player.toggleShuffle(); // shuffle enabled
      expect(player.shuffleEnabled, isTrue);

      final initialTrackId = player.currentTrack!.trackId;

      // Jump to an upcoming item in context queue
      await player.playContextQueueItem(0);
      final jumpedTrackId = player.currentTrack!.trackId;
      expect(jumpedTrackId, isNot(initialTrackId));

      // previous (< 3s) in shuffle unwinds to initialTrackId
      player.setMockPosition(Duration.zero);
      await player.previous();
      expect(player.currentTrack?.trackId, initialTrackId);
    });
  });
}
