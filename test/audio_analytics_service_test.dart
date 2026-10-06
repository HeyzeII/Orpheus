import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/services/audio_analytics_service.dart';

class AnalyticsMockDatabase extends LocalDatabase {
  AnalyticsMockDatabase() : super.internal();

  final Map<String, Track> tracksMap = {};

  @override
  Future<Track?> getTrackByTrackId(String trackId) async {
    return tracksMap[trackId];
  }

  @override
  Future<void> saveTrack(Track track) async {
    tracksMap[track.trackId] = track;
  }

  @override
  Future<void> saveTracks(List<Track> tracks) async {
    for (final t in tracks) {
      tracksMap[t.trackId] = t;
    }
  }
}

void main() {
  group('AudioAnalyticsService Unit Tests', () {
    late AnalyticsMockDatabase mockDb;
    late AudioAnalyticsService service;
    late Track testTrack;

    setUp(() {
      mockDb = AnalyticsMockDatabase();
      testTrack = Track()
        ..trackId = 'track_xyz'
        ..filePath = '/music/test.mp3'
        ..title = 'Analytics Test Track'
        ..artist = 'Test Artist'
        ..duration = 180
        ..fileType = FileType.mp3
        ..playCount = 0
        ..skipCount = 0
        ..isLiked = false;

      mockDb.tracksMap['track_xyz'] = testTrack;
      service = AudioAnalyticsService(db: mockDb);
    });

    test('recordCompletion buffers completion and persists on flush', () async {
      service.recordCompletion('track_xyz');
      expect(testTrack.playCount, 0); // Not flushed yet

      await service.flush();

      expect(testTrack.playCount, 1);
      expect(testTrack.lastPlayedAt, isNotNull);
      expect(testTrack.stats.totalPlays, 1);
    });

    test('recordSkip increments skipCount', () async {
      service.recordSkip('track_xyz');
      service.recordSkip('track_xyz');
      await service.flush();

      expect(testTrack.skipCount, 2);
    });

    test('recordLike updates isLiked flag', () async {
      service.recordLike('track_xyz', true);
      await service.flush();

      expect(testTrack.isLiked, isTrue);

      service.recordLike('track_xyz', false);
      await service.flush();

      expect(testTrack.isLiked, isFalse);
    });
  });
}
