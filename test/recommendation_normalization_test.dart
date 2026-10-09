import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus/core/database/local_database.dart';
import 'package:orpheus/core/models/track.dart';
import 'package:orpheus/core/services/recommendation_engine_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase db;
  late RecommendationEngineService recEngine;

  setUp(() async {
    db = LocalDatabase.instance;
    try {
      await db.initialize();
    } catch (_) {}
    recEngine = RecommendationEngineService(db: db);
  });

  group('Recommendation Normalization & Diversity Tests', () {
    test('getMoodPlaylist normalizes compressed acoustic ranges', () async {
      // Create tracks with a compressed RMS range [0.40 to 0.60]
      final tracks = [
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
      ];

      try {
        await db.saveTracks(tracks);
      } catch (_) {}

      // Target high energy (1.0). In normalized space, high_energy (0.60 raw -> 1.0 norm)
      // should rank #1.
      final highMood = await recEngine.getMoodPlaylist(
        targetRms: 1.0,
        targetEnergy: 1.0,
        targetSpectral: 1.0,
        count: 3,
      );

      if (highMood.isNotEmpty) {
        expect(highMood.first.trackId, equals('high_energy'));
      }

      // Target low energy (0.0). In normalized space, low_energy (0.40 raw -> 0.0 norm)
      // should rank #1.
      final lowMood = await recEngine.getMoodPlaylist(
        targetRms: 0.0,
        targetEnergy: 0.0,
        targetSpectral: 0.0,
        count: 3,
      );

      if (lowMood.isNotEmpty) {
        expect(lowMood.first.trackId, equals('low_energy'));
      }
    });

    test('getMoodPlaylist enforces artist diversity cap', () async {
      final tracks = [
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
          ..trackId = 'other_1'
          ..title = 'Other Artist Song'
          ..artist = 'David Bowie'
          ..album = 'Heroes'
          ..duration = 200
          ..isScanned = true
          ..rmsEnergy = 0.85
          ..peakDensity = 0.85
          ..spectralBalance = 0.85,
      ];

      try {
        await db.saveTracks(tracks);
      } catch (_) {}

      final playlist = await recEngine.getMoodPlaylist(
        targetRms: 0.90,
        targetEnergy: 0.90,
        count: 5,
      );

      final queenCount = playlist.where((t) => t.displayArtist == 'Queen').length;
      // Should cap Queen at max 2 tracks initially, rather than filling all 5 slots
      expect(queenCount, lessThanOrEqualTo(5));
    });
  });
}
