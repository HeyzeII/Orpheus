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

  late _FakeLocalDb db;
  late RecommendationEngineService recEngine;

  setUp(() {
    db = _FakeLocalDb();
    recEngine = RecommendationEngineService(
      db: db,
      playerService: _FakeAudioPlayerService(),
    );
  });

  group('Recommendation Normalization & Diversity Tests', () {
    test('getMoodPlaylist normalizes compressed acoustic ranges', () async {
      // Create tracks with a compressed RMS range [0.40 to 0.60]
      db.tracks.addAll([
        Track()
          ..trackId = 'low_energy'
          ..title = 'Ambient Song'
          ..artist = 'Artist 1'
          ..album = 'Album 1'
          ..duration = 200
          ..isScanned = true
          ..rmsEnergy = 0.40
          ..peakDensity = 0.40
          ..spectralBalance = 0.40,
        Track()
          ..trackId = 'mid_energy'
          ..title = 'Pop Song'
          ..artist = 'Artist 2'
          ..album = 'Album 2'
          ..duration = 200
          ..isScanned = true
          ..rmsEnergy = 0.50
          ..peakDensity = 0.50
          ..spectralBalance = 0.50,
        Track()
          ..trackId = 'high_energy'
          ..title = 'Rock Song'
          ..artist = 'Artist 3'
          ..album = 'Album 3'
          ..duration = 200
          ..isScanned = true
          ..rmsEnergy = 0.60
          ..peakDensity = 0.60
          ..spectralBalance = 0.60,
      ]);

      // Target high energy (1.0). In normalized space, high_energy (0.60 raw -> 1.0 norm)
      // should rank #1.
      final highMood = await recEngine.getMoodPlaylist(
        targetRms: 1.0,
        targetEnergy: 1.0,
        targetSpectral: 1.0,
        count: 3,
      );

      expect(highMood.isNotEmpty, isTrue);
      expect(highMood.first.trackId, equals('high_energy'));

      // Target low energy (0.0). In normalized space, low_energy (0.40 raw -> 0.0 norm)
      // should rank #1.
      final lowMood = await recEngine.getMoodPlaylist(
        targetRms: 0.0,
        targetEnergy: 0.0,
        targetSpectral: 0.0,
        count: 3,
      );

      expect(lowMood.isNotEmpty, isTrue);
      expect(lowMood.first.trackId, equals('low_energy'));
    });

    test('getMoodPlaylist enforces artist diversity cap', () async {
      db.tracks.addAll([
        for (int i = 1; i <= 5; i++)
          Track()
            ..trackId = 'queen_$i'
            ..title = 'Queen Song $i'
            ..artist = 'Queen'
            ..album = 'Album $i'
            ..duration = 200
            ..isScanned = true
            ..rmsEnergy = 0.90
            ..peakDensity = 0.90
            ..spectralBalance = 0.90,
        Track()
          ..trackId = 'bowie_1'
          ..title = 'Heroes'
          ..artist = 'David Bowie'
          ..album = 'Heroes Album'
          ..duration = 200
          ..isScanned = true
          ..rmsEnergy = 0.89
          ..peakDensity = 0.89
          ..spectralBalance = 0.89,
        Track()
          ..trackId = 'elton_1'
          ..title = 'Rocket Man'
          ..artist = 'Elton John'
          ..album = 'Honky Chateau'
          ..duration = 200
          ..isScanned = true
          ..rmsEnergy = 0.88
          ..peakDensity = 0.88
          ..spectralBalance = 0.88,
        Track()
          ..trackId = 'beatles_1'
          ..title = 'Come Together'
          ..artist = 'The Beatles'
          ..album = 'Abbey Road'
          ..duration = 200
          ..isScanned = true
          ..rmsEnergy = 0.87
          ..peakDensity = 0.87
          ..spectralBalance = 0.87,
      ]);

      final playlist = await recEngine.getMoodPlaylist(
        targetRms: 0.90,
        targetEnergy: 0.90,
        count: 5,
      );

      final queenCount = playlist.where((t) => t.displayArtist == 'Queen').length;
      // Should cap Queen at max 2 tracks
      expect(queenCount, equals(2));
      expect(playlist.length, equals(5));
    });
  });
}
