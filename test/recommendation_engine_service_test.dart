import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/services/audio_player_service.dart';
import 'package:orpheus/core/services/recommendation_engine_service.dart';

class FakeLocalDbForRecommendation extends LocalDatabase {
  FakeLocalDbForRecommendation() : super.internal();

  final List<Track> allTracks = [];

  @override
  Future<List<Track>> getAllTracks() async {
    return allTracks;
  }
}

class FakeAudioPlayerServiceForRecommendation implements AudioPlayerService {
  final List<Track> mockHistory = [];

  @override
  List<Track> get history => List.unmodifiable(mockHistory);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('RecommendationEngineService Unit Tests', () {
    late FakeLocalDbForRecommendation fakeDb;
    late FakeAudioPlayerServiceForRecommendation fakePlayer;
    late RecommendationEngineService service;

    late Track seedTrack;
    late Track similarTrack1;
    late Track similarTrack2;
    late Track differentTrack;
    late Track coldStartTrack;

    setUp(() {
      fakeDb = FakeLocalDbForRecommendation();
      fakePlayer = FakeAudioPlayerServiceForRecommendation();
      service = RecommendationEngineService(
        db: fakeDb,
        playerService: fakePlayer,
      );

      seedTrack = Track()
        ..trackId = 'seed_1'
        ..title = 'Seed Song'
        ..artist = 'Artist A'
        ..album = 'Album 1'
        ..genre = 'Rock'
        ..rmsEnergy = 0.8
        ..peakDensity = 0.7
        ..spectralBalance = 0.6
        ..isScanned = true
        ..playCount = 10
        ..isLiked = true;

      similarTrack1 = Track()
        ..trackId = 'sim_1'
        ..title = 'Similar Rock Song'
        ..artist = 'Artist A'
        ..album = 'Album 1'
        ..genre = 'Rock'
        ..rmsEnergy = 0.78
        ..peakDensity = 0.72
        ..spectralBalance = 0.58
        ..isScanned = true
        ..playCount = 8
        ..isLiked = true;

      similarTrack2 = Track()
        ..trackId = 'sim_2'
        ..title = 'Similar Band Song'
        ..artist = 'Artist B'
        ..album = 'Album 2'
        ..genre = 'Rock'
        ..rmsEnergy = 0.82
        ..peakDensity = 0.68
        ..spectralBalance = 0.62
        ..isScanned = true
        ..playCount = 5
        ..isLiked = false;

      differentTrack = Track()
        ..trackId = 'diff_1'
        ..title = 'Quiet Acoustic Ambient'
        ..artist = 'Artist C'
        ..album = 'Ambient Album'
        ..genre = 'Ambient'
        ..rmsEnergy = 0.1
        ..peakDensity = 0.05
        ..spectralBalance = 0.1
        ..isScanned = true
        ..playCount = 1
        ..isLiked = false;

      coldStartTrack = Track()
        ..trackId = 'cold_1'
        ..title = 'New Unscanned Rock Song'
        ..artist = 'Artist A'
        ..album = 'Album 1'
        ..genre = 'Rock'
        ..rmsEnergy = -1.0
        ..peakDensity = -1.0
        ..spectralBalance = -1.0
        ..isScanned = false
        ..playCount = 0
        ..isLiked = false;

      fakeDb.allTracks.addAll([
        seedTrack,
        similarTrack1,
        similarTrack2,
        differentTrack,
        coldStartTrack,
      ]);
    });

    test('generateRadioQueue excludes seedTrack and ranks similar tracks higher', () async {
      final radio = await service.generateRadioQueue(seedTrack, limit: 10);

      expect(radio, isNotEmpty);
      expect(radio.any((t) => t.trackId == seedTrack.trackId), isFalse);

      final trackIds = radio.map((t) => t.trackId).toList();
      // similarTrack1 should rank higher than differentTrack
      expect(trackIds.indexOf('sim_1'), lessThan(trackIds.indexOf('diff_1')));
    });

    test('getSimilarTracks returns top ranked tracks', () async {
      final similar = await service.getSimilarTracks(seedTrack, count: 2);

      expect(similar.length, 2);
      expect(similar.first.trackId, anyOf('sim_1', 'sim_2', 'cold_1'));
      expect(similar.any((t) => t.trackId == 'diff_1'), isFalse);
    });

    test('getMoodPlaylist matches target acoustic parameters', () async {
      // Search for calm ambient music
      final ambientPlaylist = await service.getMoodPlaylist(
        targetRms: 0.1,
        targetEnergy: 0.05,
        targetSpectral: 0.1,
        count: 1,
      );

      expect(ambientPlaylist, isNotEmpty);
      expect(ambientPlaylist.first.trackId, 'diff_1');

      // Search for high energy rock
      final highEnergyPlaylist = await service.getMoodPlaylist(
        targetRms: 0.8,
        targetEnergy: 0.7,
        targetSpectral: 0.6,
        count: 1,
      );

      expect(highEnergyPlaylist, isNotEmpty);
      expect(highEnergyPlaylist.first.trackId, anyOf('sim_1', 'sim_2', 'seed_1'));
    });

    test('Anti-Fatigue excludes tracks present in recent history', () async {
      fakePlayer.mockHistory.add(similarTrack1);

      final radio = await service.generateRadioQueue(seedTrack, limit: 10);

      // similarTrack1 should be excluded due to fatigue filter
      expect(radio.any((t) => t.trackId == 'sim_1'), isFalse);
    });

    test('Anti-Monopoly rule prevents more than 2 consecutive tracks by same artist', () async {
      // Add 5 tracks by Artist A
      for (int i = 3; i <= 7; i++) {
        fakeDb.allTracks.add(
          Track()
            ..trackId = 'artist_a_$i'
            ..title = 'Track $i'
            ..artist = 'Artist A'
            ..rmsEnergy = 0.8
            ..peakDensity = 0.7
            ..spectralBalance = 0.6
            ..isScanned = true,
        );
      }
      // Add tracks by other artists
      for (int i = 1; i <= 5; i++) {
        fakeDb.allTracks.add(
          Track()
            ..trackId = 'other_$i'
            ..title = 'Other Track $i'
            ..artist = 'Other Artist $i'
            ..rmsEnergy = 0.79
            ..peakDensity = 0.71
            ..spectralBalance = 0.59
            ..isScanned = true,
        );
      }

      final radio = await service.generateRadioQueue(seedTrack, limit: 10);

      String? prevArtist;
      int consecutiveCount = 0;
      for (final t in radio) {
        if (t.displayArtist == prevArtist) {
          consecutiveCount++;
        } else {
          prevArtist = t.displayArtist;
          consecutiveCount = 1;
        }
        expect(consecutiveCount, lessThanOrEqualTo(2));
      }
    });

    test('Cold start tracks are scored gracefully based on metadata', () async {
      final similar = await service.getSimilarTracks(seedTrack, count: 4);

      // coldStartTrack shares artist, album, and genre with seedTrack
      expect(similar.any((t) => t.trackId == 'cold_1'), isTrue);
    });
  });
}
