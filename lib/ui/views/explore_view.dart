import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

import '../../core/database/local_database.dart';
import '../../core/models/models.dart';
import '../../core/services/audio_handler.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/recommendation_engine_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mood_picker_widget.dart';
import '../widgets/radio_launch_sheet.dart';

/// Dynamic "Explorar" discovery view for Orpheus.
///
/// Features:
/// - Continuous smooth horizontal marquee of album covers with pause on hover/drag.
/// - Asymmetric Bento Grid:
///   * 🔮 "Para ti hoy": Hero recommendation based on recent acoustic affinity.
///   * 📦 "Joyas del Baúl": Forgotten tracks with low play counts.
///   * 🎲 "Descubrimientos": High-serendipity contrasting tracks.
/// - Integrated [MoodPickerWidget] with quick mood presets.
class ExploreView extends StatefulWidget {
  const ExploreView({super.key});

  @override
  State<ExploreView> createState() => _ExploreViewState();
}

class _ExploreViewState extends State<ExploreView> {
  final LocalDatabase _db = LocalDatabase.instance;
  final RecommendationEngineService _recEngine = RecommendationEngineService.instance;

  List<Track> _allTracks = [];
  Track? _heroSeedTrack;
  List<Track> _forYouTracks = [];
  List<Track> _vaultTracks = [];
  List<Track> _discoveryTracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExploreData();
  }

  Future<void> _loadExploreData() async {
    setState(() => _isLoading = true);
    try {
      final tracks = await _db.getAllTracks();
      if (!mounted) return;

      if (tracks.isEmpty) {
        setState(() {
          _allTracks = [];
          _isLoading = false;
        });
        return;
      }

      // 1. Pick Hero Seed Track (recent history or favorite track with highest plays)
      Track? seed;
      if (AudioPlayerService.instance.history.isNotEmpty) {
        seed = AudioPlayerService.instance.history.first;
      } else {
        final liked = tracks.where((t) => t.isLiked).toList();
        if (liked.isNotEmpty) {
          liked.sort((a, b) => b.stats.totalPlays.compareTo(a.stats.totalPlays));
          seed = liked.first;
        } else {
          final sorted = List<Track>.from(tracks)
            ..sort((a, b) => b.stats.totalPlays.compareTo(a.stats.totalPlays));
          seed = sorted.first;
        }
      }

      // 2. Query "Para ti hoy"
      final forYou = await _recEngine.getSimilarTracks(seed, count: 6);

      // 3. Query "Joyas del Baúl" (playCount <= 1 or not played recently)
      List<Track> vault = [];
      try {
        final isar = _db.db;
        vault = await isar.tracks
            .filter()
            .playCountLessThan(2)
            .limit(10)
            .findAll();
      } catch (_) {
        vault = tracks.where((t) => t.stats.totalPlays <= 1).take(10).toList();
      }
      vault.shuffle();

      // 4. Query "Descubrimientos" (random/contrasting selection)
      final discovery = List<Track>.from(tracks)..shuffle();
      final discoveryFiltered = discovery
          .where((t) => t.trackId != seed?.trackId && !forYou.any((f) => f.trackId == t.trackId))
          .take(6)
          .toList();

      if (mounted) {
        setState(() {
          _allTracks = tracks;
          _heroSeedTrack = seed;
          _forYouTracks = forYou;
          _vaultTracks = vault.take(4).toList();
          _discoveryTracks = discoveryFiltered;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _playTrack(Track track) {
    if (!OrpheusAudioHandler.hasInstance) return;
    OrpheusAudioHandler.instance.playTrack(
      track,
      contextQueue: _allTracks,
      contextName: 'Explorar',
    );
  }

  void _openRadioSheet(Track track) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => RadioLaunchSheet(seedTrack: track),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 700;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppTheme.accent,
        ),
      );
    }

    if (_allTracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.explore_off_rounded,
                  color: AppTheme.textHint.withAlpha(80), size: 80),
              const SizedBox(height: 24),
              Text(
                'Sin pistas para explorar',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Agrega archivos de audio a tu biblioteca para desbloquear descubrimientos y radios inteligentes.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadExploreData,
      color: AppTheme.accent,
      backgroundColor: AppTheme.bgSurface,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          isDesktop ? 32 : 16,
          isDesktop ? 32 : MediaQuery.of(context).padding.top + 16,
          isDesktop ? 32 : 16,
          isDesktop ? 120 : MediaQuery.of(context).padding.bottom + 140,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Editorial Header ───────────────────────────────────────────
            _ExploreHeader(onRefresh: _loadExploreData),
            const SizedBox(height: 24),

            // ── Infinite Album Cover Marquee ───────────────────────────────
            _ExploreCoverMarquee(
              tracks: _allTracks,
              onTapTrack: _openRadioSheet,
            ),
            const SizedBox(height: 36),

            // ── Asymmetric Bento Grid ──────────────────────────────────────
            if (isDesktop)
              _DesktopBentoGrid(
                heroSeedTrack: _heroSeedTrack,
                forYouTracks: _forYouTracks,
                vaultTracks: _vaultTracks,
                discoveryTracks: _discoveryTracks,
                onPlayTrack: _playTrack,
                onOpenRadio: _openRadioSheet,
              )
            else
              _MobileBentoStack(
                heroSeedTrack: _heroSeedTrack,
                forYouTracks: _forYouTracks,
                vaultTracks: _vaultTracks,
                discoveryTracks: _discoveryTracks,
                onPlayTrack: _playTrack,
                onOpenRadio: _openRadioSheet,
              ),

            const SizedBox(height: 36),

            // ── Integrated Mood Session Generator ──────────────────────────
            const MoodPickerWidget(),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 1. EDITORIAL HEADER
// ═════════════════════════════════════════════════════════════════════════════

class _ExploreHeader extends StatelessWidget {
  const _ExploreHeader({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EXPLORAR',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                  color: AppTheme.accent.withValues(alpha: 0.90),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Descubrimiento Sónico',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 26,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Radios generativas, afinidad acústica y tesoros de tu colección',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Actualizar sugerencias',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. INFINITE COVER MARQUEE
// ═════════════════════════════════════════════════════════════════════════════

class _ExploreCoverMarquee extends StatefulWidget {
  const _ExploreCoverMarquee({
    required this.tracks,
    required this.onTapTrack,
  });

  final List<Track> tracks;
  final void Function(Track) onTapTrack;

  @override
  State<_ExploreCoverMarquee> createState() => _ExploreCoverMarqueeState();
}

class _ExploreCoverMarqueeState extends State<_ExploreCoverMarquee> {
  late final ScrollController _scrollController;
  Timer? _ticker;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startMarquee());
  }

  void _startMarquee() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_scrollController.hasClients || _isHovered) return;
      final max = _scrollController.position.maxScrollExtent;
      final current = _scrollController.offset;
      if (current >= max) {
        _scrollController.jumpTo(0);
      } else {
        _scrollController.jumpTo(current + 0.75); // ~25px per second
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tracks.isEmpty) return const SizedBox.shrink();

    // Loop items 3 times for a seamless infinite feel
    final displayList = [
      ...widget.tracks,
      ...widget.tracks,
      ...widget.tracks,
    ];

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: SizedBox(
          height: 110,
          child: ListView.separated(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: displayList.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, idx) {
              final track = displayList[idx];
              final coverPath = track.customMetadata.customCoverPath;
              final file = coverPath != null && coverPath.isNotEmpty ? File(coverPath) : null;
              final hasCover = file != null && file.existsSync() && file.lengthSync() > 0;

              return Tooltip(
                message: 'Iniciar radio de "${track.displayTitle}"',
                child: GestureDetector(
                  onTap: () => widget.onTapTrack(track),
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(60),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (hasCover)
                            Image.file(
                              file,
                              fit: BoxFit.cover,
                              cacheWidth: 160,
                              cacheHeight: 160,
                              errorBuilder: (_, __, ___) => const _MarqueeFallbackCover(),
                            )
                          else
                            const _MarqueeFallbackCover(),
                          // Subtle bottom vignette with radio badge
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(160),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.sensors_rounded,
                                size: 12,
                                color: AppTheme.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MarqueeFallbackCover extends StatelessWidget {
  const _MarqueeFallbackCover();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1F1F1F),
      child: const Center(
        child: Icon(Icons.music_note_rounded, color: AppTheme.textHint, size: 30),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. DESKTOP BENTO GRID
// ═════════════════════════════════════════════════════════════════════════════

class _DesktopBentoGrid extends StatelessWidget {
  const _DesktopBentoGrid({
    required this.heroSeedTrack,
    required this.forYouTracks,
    required this.vaultTracks,
    required this.discoveryTracks,
    required this.onPlayTrack,
    required this.onOpenRadio,
  });

  final Track? heroSeedTrack;
  final List<Track> forYouTracks;
  final List<Track> vaultTracks;
  final List<Track> discoveryTracks;
  final void Function(Track) onPlayTrack;
  final void Function(Track) onOpenRadio;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Column: Hero 2x2 "Para ti hoy"
            Expanded(
              flex: 5,
              child: _HeroForYouCard(
                seedTrack: heroSeedTrack,
                recommendations: forYouTracks,
                onPlayTrack: onPlayTrack,
                onOpenRadio: onOpenRadio,
              ),
            ),
            const SizedBox(width: 20),

            // Right Column: Vault "Joyas del Baúl" + Discovery "Descubrimientos"
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  _VaultBoxCard(
                    tracks: vaultTracks,
                    onPlayTrack: onPlayTrack,
                  ),
                  const SizedBox(height: 20),
                  _DiscoveryCard(
                    tracks: discoveryTracks,
                    onPlayTrack: onPlayTrack,
                    onOpenRadio: onOpenRadio,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. MOBILE BENTO STACK
// ═════════════════════════════════════════════════════════════════════════════

class _MobileBentoStack extends StatelessWidget {
  const _MobileBentoStack({
    required this.heroSeedTrack,
    required this.forYouTracks,
    required this.vaultTracks,
    required this.discoveryTracks,
    required this.onPlayTrack,
    required this.onOpenRadio,
  });

  final Track? heroSeedTrack;
  final List<Track> forYouTracks;
  final List<Track> vaultTracks;
  final List<Track> discoveryTracks;
  final void Function(Track) onPlayTrack;
  final void Function(Track) onOpenRadio;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HeroForYouCard(
          seedTrack: heroSeedTrack,
          recommendations: forYouTracks,
          onPlayTrack: onPlayTrack,
          onOpenRadio: onOpenRadio,
        ),
        const SizedBox(height: 20),
        _VaultBoxCard(
          tracks: vaultTracks,
          onPlayTrack: onPlayTrack,
        ),
        const SizedBox(height: 20),
        _DiscoveryCard(
          tracks: discoveryTracks,
          onPlayTrack: onPlayTrack,
          onOpenRadio: onOpenRadio,
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 5. BENTO CARDS
// ═════════════════════════════════════════════════════════════════════════════

/// 🔮 Hero Card: "Para ti hoy"
class _HeroForYouCard extends StatelessWidget {
  const _HeroForYouCard({
    required this.seedTrack,
    required this.recommendations,
    required this.onPlayTrack,
    required this.onOpenRadio,
  });

  final Track? seedTrack;
  final List<Track> recommendations;
  final void Function(Track) onPlayTrack;
  final void Function(Track) onOpenRadio;

  @override
  Widget build(BuildContext context) {
    if (seedTrack == null) return const SizedBox.shrink();
    final track = seedTrack!;
    final coverPath = track.customMetadata.customCoverPath;
    final file = coverPath != null && coverPath.isNotEmpty ? File(coverPath) : null;
    final hasCover = file != null && file.existsSync() && file.lengthSync() > 0;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1E28), Color(0xFF14141A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x2AFFFFFF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.50),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: AppTheme.accent, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'PARA TI HOY',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (track.isScanned)
                Text(
                  'Afinidad Sonora ${(track.rmsEnergy * 100).round()}%',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.50),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Main Hero Showcase
          Row(
            children: [
              // Large Cover
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 110,
                  height: 110,
                  child: hasCover
                      ? Image.file(
                          file,
                          fit: BoxFit.cover,
                          cacheWidth: 220,
                          cacheHeight: 220,
                        )
                      : Container(
                          color: const Color(0xFF282828),
                          child: const Icon(Icons.music_note_rounded,
                              color: Colors.white24, size: 40),
                        ),
                ),
              ),
              const SizedBox(width: 18),

              // Track Info & Launch Action
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Inspirado en tu escucha',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.40),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: AppTheme.bgDeep,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => onOpenRadio(track),
                      icon: const Icon(Icons.sensors_rounded, size: 16),
                      label: const Text(
                        'Iniciar Radio',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (recommendations.isNotEmpty) ...[
            const SizedBox(height: 22),
            const Divider(color: Colors.white10),
            const SizedBox(height: 12),
            Text(
              'RECOMENDACIONES AFINES',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 10),
            for (final rec in recommendations.take(3))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: _MiniCover(path: rec.customMetadata.customCoverPath),
                  ),
                ),
                title: Text(
                  rec.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                subtitle: Text(
                  rec.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.play_arrow_rounded,
                      color: AppTheme.accent, size: 20),
                  onPressed: () => onPlayTrack(rec),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 📦 Card: "Joyas del Baúl"
class _VaultBoxCard extends StatelessWidget {
  const _VaultBoxCard({
    required this.tracks,
    required this.onPlayTrack,
  });

  final List<Track> tracks;
  final void Function(Track) onPlayTrack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF181820),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.inventory_2_rounded, color: Color(0xFFF39C12), size: 16),
              SizedBox(width: 8),
              Text(
                'JOYAS DEL BAÚL',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Color(0xFFF39C12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Canciones de tu biblioteca esperando a ser redescubiertas',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
          ),
          const SizedBox(height: 14),
          if (tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Has escuchado toda tu biblioteca activamente.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            )
          else
            for (final t in tracks.take(3))
              InkWell(
                onTap: () => onPlayTrack(t),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: _MiniCover(path: t.customMetadata.customCoverPath),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              t.displayArtist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.play_circle_outline_rounded,
                          color: Colors.white38, size: 20),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// 🎲 Card: "Descubrimientos"
class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({
    required this.tracks,
    required this.onPlayTrack,
    required this.onOpenRadio,
  });

  final List<Track> tracks;
  final void Function(Track) onPlayTrack;
  final void Function(Track) onOpenRadio;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF181820),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.casino_rounded, color: Color(0xFF9B59B6), size: 16),
              SizedBox(width: 8),
              Text(
                'DESCUBRIMIENTOS SÓNICOS',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Color(0xFF9B59B6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Serendipia y contrastes acústicos para variar tu flujo',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
          ),
          const SizedBox(height: 14),
          if (tracks.isEmpty)
            const SizedBox.shrink()
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in tracks.take(4))
                  ActionChip(
                    avatar: const Icon(Icons.radio_rounded, size: 14, color: Color(0xFF9B59B6)),
                    label: Text(
                      t.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    labelStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: Colors.white,
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    side: const BorderSide(color: Colors.white12),
                    onPressed: () => onOpenRadio(t),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MiniCover extends StatelessWidget {
  const _MiniCover({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final file = path != null && path!.isNotEmpty ? File(path!) : null;
    final hasCover = file != null && file.existsSync() && file.lengthSync() > 0;

    if (hasCover) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        cacheWidth: 72,
        cacheHeight: 72,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      color: const Color(0xFF262626),
      child: const Center(
        child: Icon(Icons.music_note_rounded, color: Colors.white24, size: 16),
      ),
    );
  }
}
