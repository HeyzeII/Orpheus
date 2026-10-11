import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/services/audio_player_service.dart';
import 'package:orpheus/core/services/recommendation_engine_service.dart';

class _FakeLocalDb extends LocalDatabase {
  _FakeLocalDb() : super.internal();

  final List<Track> tracks = [];

  @override
  Future<List<Track>> getAllTracks() async => tracks;
}

class _FakeAudioPlayerService implements AudioPlayerService {
  @override
  List<Track> get history => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLocalDb fakeDb;
  late RecommendationEngineService recEngine;

  setUp(() {
    fakeDb = _FakeLocalDb();
    recEngine = RecommendationEngineService(
      db: fakeDb,
      playerService: _FakeAudioPlayerService(),
    );
  });

  group('Gaussian Pure Acoustic Mood Engine Tests (Phase 5.1)', () {
    test('Extreme mood parameters deliver completely different top tracks', () async {
      fakeDb.tracks.addAll([
        Track()
          ..trackId = 'workout_track'
          ..title = 'Hardstyle Beat'
          ..artist = 'DJ Pulse'
          ..album = 'Energy Lab'
          ..duration = 180
          ..isScanned = true
          ..rmsEnergy = 0.95
          ..peakDensity = 0.90
          ..spectralBalance = 0.85,
        Track()
          ..trackId = 'chill_track'
          ..title = 'Ambient Rain'
          ..artist = 'Lofi Dream'
          ..album = 'Midnight Sleep'
          ..duration = 240
          ..isScanned = true
          ..rmsEnergy = 0.15
          ..peakDensity = 0.20
          ..spectralBalance = 0.25,
        Track()
          ..trackId = 'mid_track'
          ..title = 'Acoustic Morning'
          ..artist = 'Folk Band'
          ..album = 'Coffee Time'
          ..duration = 210
          ..isScanned = true
          ..rmsEnergy = 0.50
          ..peakDensity = 0.50
          ..spectralBalance = 0.50,
      ]);

      // 1. Workout Query
      final workoutPlaylist = await recEngine.getMoodPlaylist(
        targetRms: 0.95,
        targetEnergy: 0.90,
        targetSpectral: 0.85,
        count: 1,
      );
      expect(workoutPlaylist.isNotEmpty, isTrue);
      expect(workoutPlaylist.first.trackId, equals('workout_track'));

      // 2. Chill Query
      final chillPlaylist = await recEngine.getMoodPlaylist(
        targetRms: 0.15,
        targetEnergy: 0.20,
        targetSpectral: 0.25,
        count: 1,
      );
      expect(chillPlaylist.isNotEmpty, isTrue);
      expect(chillPlaylist.first.trackId, equals('chill_track'));
    });

    test('Pure acoustic matching prioritizes sound over isLiked favorite status', () async {
      fakeDb.tracks.addAll([
        // Distant acoustic track marked as favorite with high plays
        Track()
          ..trackId = 'liked_wrong_mood'
          ..title = 'Quiet Ballad'
          ..artist = 'Soft Singer'
          ..album = 'Whispers'
          ..duration = 200
          ..isLiked = true
          ..playCount = 100
          ..isScanned = true
          ..rmsEnergy = 0.20
          ..peakDensity = 0.20
          ..spectralBalance = 0.20,
        // Perfect acoustic match, not liked, 0 plays
        Track()
          ..trackId = 'unliked_perfect_mood'
          ..title = 'Heavy Metal Thunder'
          ..artist = 'Metal Gods'
          ..album = 'Iron Core'
          ..duration = 200
          ..isLiked = false
          ..playCount = 0
          ..isScanned = true
          ..rmsEnergy = 0.95
          ..peakDensity = 0.95
          ..spectralBalance = 0.90,
      ]);

      final result = await recEngine.getMoodPlaylist(
        targetRms: 0.95,
        targetEnergy: 0.95,
        targetSpectral: 0.90,
        count: 2,
      );

      // Unliked perfect acoustic match MUST rank #1 ahead of the liked quiet ballad
      expect(result.first.trackId, equals('unliked_perfect_mood'));
    });

    test('Enforces strict diversity cap (max 2 per artist, 1 per album)', () async {
      fakeDb.tracks.addAll([
        for (int i = 1; i <= 4; i++)
          Track()
            ..trackId = 'metallica_same_album_$i'
            ..title = 'Master of Puppets Track $i'
            ..artist = 'Metallica'
            ..album = 'Master of Puppets'
            ..duration = 300
            ..isScanned = true
            ..rmsEnergy = 0.90
            ..peakDensity = 0.85
            ..spectralBalance = 0.80,
        for (int i = 1; i <= 2; i++)
          Track()
            ..trackId = 'metallica_diff_album_$i'
            ..title = 'Ride the Lightning Track $i'
            ..artist = 'Metallica'
            ..album = 'Ride the Lightning'
            ..duration = 300
            ..isScanned = true
            ..rmsEnergy = 0.90
            ..peakDensity = 0.85
            ..spectralBalance = 0.80,
        Track()
          ..trackId = 'megadeth_1'
          ..title = 'Holy Wars'
          ..artist = 'Megadeth'
          ..album = 'Rust in Peace'
          ..duration = 300
          ..isScanned = true
          ..rmsEnergy = 0.89
          ..peakDensity = 0.84
          ..spectralBalance = 0.79,
        Track()
          ..trackId = 'slayer_1'
          ..title = 'Raining Blood'
          ..artist = 'Slayer'
          ..album = 'Reign in Blood'
          ..duration = 300
          ..isScanned = true
          ..rmsEnergy = 0.88
          ..peakDensity = 0.83
          ..spectralBalance = 0.78,
      ]);

      final playlist = await recEngine.getMoodPlaylist(
        targetRms: 0.90,
        targetEnergy: 0.85,
        targetSpectral: 0.80,
        count: 4,
      );

      final metallicaTracks =
          playlist.where((t) => t.displayArtist == 'Metallica').toList();
      expect(metallicaTracks.length, lessThanOrEqualTo(2));

      // Max 1 per album for Master of Puppets
      final mopTracks =
          playlist.where((t) => t.displayAlbum == 'Master of Puppets').length;
      expect(mopTracks, lessThanOrEqualTo(1));
    });
  });
}
