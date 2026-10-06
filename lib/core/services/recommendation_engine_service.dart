import 'dart:math' as math;
import 'package:isar/isar.dart';

import '../database/local_database.dart';
import '../models/track.dart';
import 'audio_player_service.dart';

/// Scored candidate container for ranking.
class _ScoredTrack {
  const _ScoredTrack({
    required this.track,
    required this.totalScore,
    required this.acousticSimilarity,
    required this.metadataAffinity,
    required this.behavioralScore,
  });

  final Track track;
  final double totalScore;
  final double acousticSimilarity;
  final double metadataAffinity;
  final double behavioralScore;
}

/// Offline, deterministic vectorized recommendation engine for Orpheus.
///
/// Combines 7D acoustic and behavioral vectors to generate infinite radio queues,
/// similar tracks, and mood playlists with smart 80/20 serendipity and anti-fatigue filtering.
class RecommendationEngineService {
  RecommendationEngineService._internal({
    LocalDatabase? db,
    AudioPlayerService? playerService,
  })  : _db = db ?? LocalDatabase.instance,
        _playerService = playerService ?? AudioPlayerService.instance;

  static final RecommendationEngineService instance =
      RecommendationEngineService._internal();

  factory RecommendationEngineService({
    LocalDatabase? db,
    AudioPlayerService? playerService,
  }) {
    if (db != null || playerService != null) {
      return RecommendationEngineService._internal(
        db: db,
        playerService: playerService,
      );
    }
    return instance;
  }

  final LocalDatabase _db;
  final AudioPlayerService _playerService;

  // ── Public Recommendation API ──────────────────────────────────────────────

  /// Generates a dynamic algorithmic radio queue seeded by [seedTrack].
  ///
  /// Balances 80% high-affinity tracks with 20% intelligent discovery while
  /// enforcing anti-monopoly artist rules and excluding recent playback history.
  Future<List<Track>> generateRadioQueue(
    Track seedTrack, {
    int limit = 20,
  }) async {
    final candidatePool = await _fetchCandidatePool(seedTrack);
    if (candidatePool.isEmpty) return [];

    final scored = _scoreCandidates(seedTrack, candidatePool);
    if (scored.isEmpty) return [];

    return _buildBalancedQueue(
      seedTrack: seedTrack,
      rankedCandidates: scored,
      limit: limit,
    );
  }

  /// Returns the top [count] most similar tracks to [targetTrack] for detail views.
  Future<List<Track>> getSimilarTracks(
    Track targetTrack, {
    int count = 10,
  }) async {
    final candidatePool = await _fetchCandidatePool(targetTrack);
    if (candidatePool.isEmpty) return [];

    final scored = _scoreCandidates(targetTrack, candidatePool);
    scored.sort((a, b) => b.totalScore.compareTo(a.totalScore));

    return scored.take(count).map((s) => s.track).toList();
  }

  /// Generates a curated playlist matching acoustic mood parameters.
  ///
  /// [targetRms]: Desired energy level [0.0 (quiet/ambient) to 1.0 (loud/intense)].
  /// [targetEnergy]: Desired rhythmic density [0.0 (smooth/slow) to 1.0 (fast/percussive)].
  /// [targetSpectral]: Optional brightness descriptor [0.0 (dark/warm) to 1.0 (bright/crisp)].
  Future<List<Track>> getMoodPlaylist({
    required double targetRms,
    required double targetEnergy,
    double? targetSpectral,
    int count = 20,
  }) async {
    final allTracks = await _db.getAllTracks();
    if (allTracks.isEmpty) return [];

    final spectral = targetSpectral ?? 0.5;
    final List<_ScoredTrack> scored = [];

    for (final track in allTracks) {
      final tRms = track.isScanned && track.rmsEnergy >= 0 ? track.rmsEnergy : 0.5;
      final tPeak = track.isScanned && track.peakDensity >= 0 ? track.peakDensity : 0.5;
      final tSpec = track.isScanned && track.spectralBalance >= 0 ? track.spectralBalance : 0.5;

      final dist = math.sqrt(
        0.45 * math.pow(targetRms - tRms, 2) +
            0.35 * math.pow(targetEnergy - tPeak, 2) +
            0.20 * math.pow(spectral - tSpec, 2),
      );

      final similarity = (1.0 - dist).clamp(0.0, 1.0);
      final behavioralBonus = (track.isLiked ? 0.20 : 0.0) +
          (track.playCount > 0 ? 0.10 : 0.0);

      final score = similarity * 0.75 + behavioralBonus * 0.25;
      scored.add(
        _ScoredTrack(
          track: track,
          totalScore: score,
          acousticSimilarity: similarity,
          metadataAffinity: 0.0,
          behavioralScore: behavioralBonus,
        ),
      );
    }

    scored.sort((a, b) => b.totalScore.compareTo(a.totalScore));
    return scored.take(count).map((s) => s.track).toList();
  }

  // ── Candidate Pruning & Isar Filtering ─────────────────────────────────────

  Future<List<Track>> _fetchCandidatePool(Track seedTrack) async {
    try {
      final isar = _db.db;
      final candidatesMap = <String, Track>{};

      // Pool 1: Same artist or collaborative artists (limit 30)
      final artistMatches = await isar.tracks
          .filter()
          .artistEqualTo(seedTrack.displayArtist, caseSensitive: false)
          .limit(30)
          .findAll();
      for (final t in artistMatches) {
        candidatesMap[t.trackId] = t;
      }

      // Pool 2: User Favorites (limit 50)
      final likedMatches = await isar.tracks
          .filter()
          .isLikedEqualTo(true)
          .limit(50)
          .findAll();
      for (final t in likedMatches) {
        candidatesMap[t.trackId] = t;
      }

      // Pool 3: Most played tracks (limit 50)
      final topPlayed = await isar.tracks
          .where()
          .sortByPlayCountDesc()
          .limit(50)
          .findAll();
      for (final t in topPlayed) {
        candidatesMap[t.trackId] = t;
      }

      // Pool 4: Acoustic window matching (RMS ± 0.25) if seed is scanned
      if (seedTrack.isScanned && seedTrack.rmsEnergy >= 0) {
        final minRms = (seedTrack.rmsEnergy - 0.25).clamp(0.0, 1.0);
        final maxRms = (seedTrack.rmsEnergy + 0.25).clamp(0.0, 1.0);
        final acousticMatches = await isar.tracks
            .filter()
            .isScannedEqualTo(true)
            .and()
            .rmsEnergyGreaterThan(minRms)
            .and()
            .rmsEnergyLessThan(maxRms)
            .limit(60)
            .findAll();
        for (final t in acousticMatches) {
          candidatesMap[t.trackId] = t;
        }
      } else {
        final generalScanned = await isar.tracks
            .filter()
            .isScannedEqualTo(true)
            .limit(50)
            .findAll();
        for (final t in generalScanned) {
          candidatesMap[t.trackId] = t;
        }
      }

      // Pool 5: Unexplored / Discovery candidates (playCount <= 1)
      final discoveryMatches = await isar.tracks
          .filter()
          .playCountLessThan(2)
          .limit(40)
          .findAll();
      for (final t in discoveryMatches) {
        candidatesMap[t.trackId] = t;
      }

      // Exclude seed track itself
      candidatesMap.remove(seedTrack.trackId);

      // Fallback: If library is small or query returned few, load all
      if (candidatesMap.length < 10) {
        final all = await _db.getAllTracks();
        for (final t in all) {
          if (t.trackId != seedTrack.trackId) {
            candidatesMap[t.trackId] = t;
          }
        }
      }

      return candidatesMap.values.toList();
    } catch (_) {
      // Safe fallback for in-memory or headless test environments
      final all = await _db.getAllTracks();
      return all.where((t) => t.trackId != seedTrack.trackId).toList();
    }
  }

  // ── 7D Scoring Engine ──────────────────────────────────────────────────────

  List<_ScoredTrack> _scoreCandidates(Track seedTrack, List<Track> candidates) {
    final historyTrackIds = _playerService.history
        .take(10)
        .map((t) => t.trackId)
        .toSet();

    final now = DateTime.now();
    final List<_ScoredTrack> scored = [];

    for (final candidate in candidates) {
      // 1. Fatigue check: Full exclusion if in recent 10-history
      if (historyTrackIds.contains(candidate.trackId)) {
        continue;
      }

      // 2. Acoustic Similarity
      double acousticSim = 0.50;
      final seedScanned = seedTrack.isScanned && seedTrack.rmsEnergy >= 0;
      final candidateScanned = candidate.isScanned && candidate.rmsEnergy >= 0;

      if (seedScanned && candidateScanned) {
        final dist = math.sqrt(
          0.40 * math.pow(seedTrack.rmsEnergy - candidate.rmsEnergy, 2) +
              0.35 * math.pow(seedTrack.peakDensity - candidate.peakDensity, 2) +
              0.25 * math.pow(seedTrack.spectralBalance - candidate.spectralBalance, 2),
        );
        acousticSim = (1.0 - dist).clamp(0.0, 1.0);
      }

      // 3. Metadata Affinity
      double metaScore = 0.0;
      final sameArtist = seedTrack.displayArtist.toLowerCase() ==
          candidate.displayArtist.toLowerCase();
      if (sameArtist) {
        metaScore += 0.40;
      } else {
        // Check collaborative artist intersection
        final seedArtists = seedTrack.individualArtists.map((a) => a.toLowerCase()).toSet();
        final candArtists = candidate.individualArtists.map((a) => a.toLowerCase()).toSet();
        if (seedArtists.intersection(candArtists).isNotEmpty) {
          metaScore += 0.20;
        }
      }

      if (seedTrack.displayAlbum.isNotEmpty &&
          seedTrack.displayAlbum != 'Unknown Album' &&
          seedTrack.displayAlbum != 'Vídeos' &&
          seedTrack.displayAlbum.toLowerCase() == candidate.displayAlbum.toLowerCase()) {
        metaScore += 0.15;
      }

      if (seedTrack.genre != null &&
          seedTrack.genre!.isNotEmpty &&
          candidate.genre != null &&
          seedTrack.genre!.toLowerCase() == candidate.genre!.toLowerCase()) {
        metaScore += 0.25;
      }
      metaScore = metaScore.clamp(0.0, 1.0);

      // 4. Behavioral Score
      final isLikedBonus = candidate.isLiked ? 0.40 : 0.0;
      final playCountNorm = (candidate.playCount / 20.0).clamp(0.0, 1.0);
      final totalInteractions = candidate.playCount + candidate.skipCount + 1.0;
      final skipRatio = (candidate.skipCount / totalInteractions).clamp(0.0, 1.0);

      double recencyScore = 0.0;
      if (candidate.lastPlayedAt != null) {
        final daysSincePlay = now.difference(candidate.lastPlayedAt!).inHours / 24.0;
        recencyScore = math.exp(-0.05 * math.max(0.0, daysSincePlay));
      }

      final behavioralScore = isLikedBonus +
          (0.30 * playCountNorm) +
          (0.30 * recencyScore) -
          (0.50 * skipRatio);

      // 5. Fatigue Penalty (Played in last 2 hours)
      double fatiguePenalty = 0.0;
      if (candidate.lastPlayedAt != null &&
          now.difference(candidate.lastPlayedAt!).inHours < 2) {
        fatiguePenalty = 0.40;
      }

      // 6. Weighted Combination (Adjusted weights if candidate is cold-start)
      double totalScore;
      if (candidateScanned) {
        totalScore = (0.45 * acousticSim) +
            (0.30 * metaScore) +
            (0.25 * behavioralScore) -
            fatiguePenalty;
      } else {
        totalScore = (0.15 * acousticSim) +
            (0.60 * metaScore) +
            (0.25 * behavioralScore) -
            fatiguePenalty;
      }

      scored.add(
        _ScoredTrack(
          track: candidate,
          totalScore: totalScore,
          acousticSimilarity: acousticSim,
          metadataAffinity: metaScore,
          behavioralScore: behavioralScore,
        ),
      );
    }

    return scored;
  }

  // ── 80/20 Serendipity & Anti-Monopoly Balancing ────────────────────────────

  List<Track> _buildBalancedQueue({
    required Track seedTrack,
    required List<_ScoredTrack> rankedCandidates,
    required int limit,
  }) {
    if (rankedCandidates.isEmpty) return [];

    // Sort by overall score descending
    final sorted = List<_ScoredTrack>.from(rankedCandidates)
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    // Split into Core Pool vs Discovery Pool (unexplored / high acoustic diversity)
    final List<_ScoredTrack> discoveryPool = [];
    final List<_ScoredTrack> corePool = [];

    for (final st in sorted) {
      final isDifferentArtist = st.track.displayArtist.toLowerCase() !=
          seedTrack.displayArtist.toLowerCase();
      final isUnexplored = st.track.playCount <= 1;
      final isAcousticallySimilar = st.acousticSimilarity >= 0.70;

      if (isDifferentArtist && (isUnexplored || isAcousticallySimilar)) {
        discoveryPool.add(st);
      } else {
        corePool.add(st);
      }
    }

    final targetDiscoveryCount = (limit * 0.20).round();
    final maxPerArtist = math.max(2, (limit * 0.25).ceil());

    final List<Track> resultQueue = [];
    final artistCountMap = <String, int>{};
    String? lastArtist;
    int consecutiveArtistCount = 0;

    bool canAddTrack(Track track) {
      final artist = track.displayArtist.toLowerCase();
      final currentCount = artistCountMap[artist] ?? 0;
      if (currentCount >= maxPerArtist) return false;

      if (artist == lastArtist && consecutiveArtistCount >= 2) {
        return false;
      }
      return true;
    }

    void addTrack(Track track) {
      final artist = track.displayArtist.toLowerCase();
      resultQueue.add(track);
      artistCountMap[artist] = (artistCountMap[artist] ?? 0) + 1;

      if (artist == lastArtist) {
        consecutiveArtistCount++;
      } else {
        lastArtist = artist;
        consecutiveArtistCount = 1;
      }
    }

    // Positions where discovery tracks should be interspersed (e.g., 4th, 9th, 14th, 19th)
    final discoveryPositions = <int>{};
    for (int i = 1; i <= targetDiscoveryCount; i++) {
      discoveryPositions.add(math.min(limit - 1, i * 5 - 1));
    }

    int coreIdx = 0;
    int discIdx = 0;

    for (int pos = 0; pos < limit; pos++) {
      Track? selectedTrack;

      if (discoveryPositions.contains(pos) && discIdx < discoveryPool.length) {
        // Try picking from discovery pool
        while (discIdx < discoveryPool.length) {
          final cand = discoveryPool[discIdx++].track;
          if (canAddTrack(cand)) {
            selectedTrack = cand;
            break;
          }
        }
      }

      // If no discovery track chosen, take next valid core track
      if (selectedTrack == null) {
        while (coreIdx < corePool.length) {
          final cand = corePool[coreIdx++].track;
          if (canAddTrack(cand)) {
            selectedTrack = cand;
            break;
          }
        }
      }

      // Fallback: If strict anti-monopoly constraints exhausted pool, pick best remaining
      if (selectedTrack == null) {
        if (coreIdx < corePool.length) {
          selectedTrack = corePool[coreIdx++].track;
        } else if (discIdx < discoveryPool.length) {
          selectedTrack = discoveryPool[discIdx++].track;
        }
      }

      if (selectedTrack != null) {
        addTrack(selectedTrack);
      } else {
        break;
      }
    }

    return resultQueue;
  }
}
