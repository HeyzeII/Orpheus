import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../core/models/models.dart';
import '../../core/services/audio_player_service.dart';
import '../theme/app_theme.dart';

/// Dynamic Home View — Displays user greeting, quick picks, recently played tracks,
/// and a library teaser query from [LocalDatabase].
///
/// Layout adapts to screen width:
/// - Desktop (≥ 600 px): 6-column grid, 32 px side padding, unchanged behaviour.
/// - Mobile  (< 600 px): 2-column quick-access grid + horizontal carousels,
///   with extra bottom padding so the [MobileMiniPlayer] never covers content.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  List<Track> _recentlyPlayed = [];
  List<Track> _mostPlayed = [];
  List<String> _genres = [];
  List<Track> _allTracks = [];
  bool _isLoading = true;

  StreamSubscription<void>? _tracksSubscription;

  @override
  void initState() {
    super.initState();
    _loadHomeData(showSpinner: true);
    _tracksSubscription = LocalDatabase.instance.watchTracks().listen((_) {
      _loadHomeData(showSpinner: false);
    });
  }

  @override
  void dispose() {
    _tracksSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadHomeData({bool showSpinner = false}) async {
    if (showSpinner) setState(() => _isLoading = true);
    final db = LocalDatabase.instance;
    final recentlyPlayed = await db.getRecentlyPlayedTracks(limit: 6);
    final mostPlayed = await db.getMostPlayedTracks(limit: 6);
    final genres = await db.getUniqueGenres();
    final allTracks = await db.getAllTracks();

    // Score-sort the full library for the "TU BIBLIOTECA" teaser:
    // cover art (+50) > liked (+30) > plays (×10) > insertion order.
    final likedIds = LocalDatabase.instance.likedTrackIdsNotifier.value;
    int scoreOf(Track t) {
      int s = t.stats.totalPlays * 10;
      if (t.customMetadata.customCoverPath != null &&
          t.customMetadata.customCoverPath!.isNotEmpty) s += 50;
      if (likedIds.contains(t.trackId)) s += 30;
      return s;
    }

    final sortedAll = List<Track>.from(allTracks)
      ..sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));

    if (!mounted) return;
    setState(() {
      _recentlyPlayed = recentlyPlayed;
      _mostPlayed = mostPlayed;
      _genres = genres;
      _allTracks = sortedAll;
      _isLoading = false;
    });
  }

  Future<void> _playTrack(Track track) async =>
      AudioPlayerService.instance.loadPlaylist([track]);

  Future<void> _playGenre(String genre) async {
    final genreTracks = _allTracks.where((t) => t.genre == genre).toList();
    if (genreTracks.isNotEmpty) {
      await AudioPlayerService.instance.loadPlaylist(genreTracks);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    }

    if (_allTracks.isEmpty) return _EmptyLibraryState();

    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return isMobile ? _buildMobileLayout() : _buildDesktopLayout();
  }

  // ── Desktop layout (original 6-column grid, unchanged) ───────────────────

  Widget _buildDesktopLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 36, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting
          Text(_greeting(),
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 4),
          Text('Bienvenido de regreso a tu reproductor Orpheus.',
              style: Theme.of(context).textTheme.titleSmall),

          const SizedBox(height: 40),

          // Genres
          if (_genres.isNotEmpty) ...[
            _SectionLabel('GÉNEROS EN TU BIBLIOTECA'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final genre in _genres.take(8))
                  _GenreChip(label: genre, onTap: () => _playGenre(genre)),
              ],
            ),
            const SizedBox(height: 40),
          ],

          // Recently played
          _SectionLabel(_recentlyPlayed.any((t) => t.stats.totalPlays > 0)
              ? 'REPRODUCIDO RECIENTEMENTE'
              : 'AGREGADO RECIENTEMENTE'),
          const SizedBox(height: 16),
          _DesktopGrid(
              tracks: _recentlyPlayed,
              onTap: _playTrack),

          const SizedBox(height: 40),

          // Most played
          if (_mostPlayed.any((t) => t.stats.totalPlays > 0)) ...[
            _SectionLabel('MÁS ESCUCHADAS'),
            const SizedBox(height: 16),
            _DesktopGrid(tracks: _mostPlayed, onTap: _playTrack),
            const SizedBox(height: 40),
          ],

          // Library teaser
          _SectionLabel('TU BIBLIOTECA'),
          const SizedBox(height: 16),
          _DesktopGrid(tracks: _allTracks.take(12).toList(), onTap: _playTrack),
        ],
      ),
    );
  }

  // ── Mobile layout (Tidal-style 2-col top grid + horizontal carousels) ────

  Widget _buildMobileLayout() {
    // Extra bottom padding: mini-player (66) + bottom-nav (56) + gap (16)
    const double bottomPad = kBottomNavigationBarHeight + 66 + 24;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 24, 16, bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Greeting ────────────────────────────────────────────────────
          Text(
            _greeting(),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Bienvenido de regreso',
            style: Theme.of(context).textTheme.bodySmall,
          ),

          const SizedBox(height: 24),

          // ── Quick-access top grid (2 columns, compact horizontal tiles) ─
          _SectionLabel('ACCESO RÁPIDO'),
          const SizedBox(height: 12),
          _MobileTopGrid(
            tracks: _allTracks.take(6).toList(),
            onTap: _playTrack,
          ),

          const SizedBox(height: 28),

          // ── Recently / Added carousel ────────────────────────────────────
          _SectionLabel(
            _recentlyPlayed.any((t) => t.stats.totalPlays > 0)
                ? 'REPRODUCIDO RECIENTEMENTE'
                : 'AGREGADO RECIENTEMENTE',
          ),
          const SizedBox(height: 12),
          _HorizontalCarousel(tracks: _recentlyPlayed, onTap: _playTrack),

          const SizedBox(height: 28),

          // ── Most played carousel (only when data exists) ─────────────────
          if (_mostPlayed.any((t) => t.stats.totalPlays > 0)) ...[
            _SectionLabel('MÁS ESCUCHADAS'),
            const SizedBox(height: 12),
            _HorizontalCarousel(tracks: _mostPlayed, onTap: _playTrack),
            const SizedBox(height: 28),
          ],

          // ── Genres row ───────────────────────────────────────────────────
          if (_genres.isNotEmpty) ...[
            _SectionLabel('GÉNEROS'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final genre in _genres.take(12))
                  _GenreChip(label: genre, onTap: () => _playGenre(genre)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días';
    if (hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyLibraryState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_rounded,
                color: AppTheme.textHint.withAlpha(80), size: 80),
            const SizedBox(height: 24),
            Text(
              'Tu biblioteca está vacía',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Para comenzar, ve a la sección de Ajustes, añade una carpeta de música y realiza un escaneo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 2.5),
      );
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          border: Border.all(color: AppTheme.divider),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            )),
      ),
    );
  }
}

// ── Desktop 6-column grid ─────────────────────────────────────────────────

class _DesktopGrid extends StatelessWidget {
  const _DesktopGrid({required this.tracks, required this.onTap});
  final List<Track> tracks;
  final Future<void> Function(Track) onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tracks.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, idx) => _TrackCard(
        track: tracks[idx],
        onTap: () => onTap(tracks[idx]),
      ),
    );
  }
}

// ── Mobile top-grid (2 columns, horizontal compact tiles) ─────────────────

class _MobileTopGrid extends StatelessWidget {
  const _MobileTopGrid({required this.tracks, required this.onTap});
  final List<Track> tracks;
  final Future<void> Function(Track) onTap;

  @override
  Widget build(BuildContext context) {
    // Rows of 2: a compact horizontal tile with small cover + title.
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tracks.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 3.0,
      ),
      itemBuilder: (context, idx) {
        final track = tracks[idx];
        final coverPath = track.customMetadata.customCoverPath;
        final hasArt =
            coverPath != null && coverPath.isNotEmpty && File(coverPath).existsSync();

        return GestureDetector(
          onTap: () => onTap(track),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                // Cover
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(8),
                  ),
                  child: SizedBox(
                    width: 48,
                    height: double.infinity,
                    child: hasArt
                        ? Image.file(File(coverPath!), fit: BoxFit.cover, cacheWidth: 96)
                        : const ColoredBox(
                            color: AppTheme.bgHover,
                            child: Icon(
                              Icons.music_note_rounded,
                              color: AppTheme.textHint,
                              size: 18,
                            ),
                          ),
                  ),
                ),
                // Title
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      track.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Horizontal carousel ───────────────────────────────────────────────────

class _HorizontalCarousel extends StatelessWidget {
  const _HorizontalCarousel({required this.tracks, required this.onTap});
  final List<Track> tracks;
  final Future<void> Function(Track) onTap;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 186,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 4),
        itemCount: tracks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, idx) {
          final track = tracks[idx];
          final coverPath = track.customMetadata.customCoverPath;
          final hasArt = coverPath != null &&
              coverPath.isNotEmpty &&
              File(coverPath).existsSync();

          return GestureDetector(
            onTap: () => onTap(track),
            child: SizedBox(
              width: 130,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Square cover art
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 130,
                      height: 130,
                      child: hasArt
                          ? Image.file(File(coverPath!),
                              fit: BoxFit.cover, cacheWidth: 260)
                          : const ColoredBox(
                              color: AppTheme.bgHover,
                              child: Center(
                                child: Icon(Icons.album_rounded,
                                    color: AppTheme.textHint, size: 42),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Title
                  Text(
                    track.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Artist
                  Text(
                    track.displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Desktop track card (original) ─────────────────────────────────────────

class _TrackCard extends StatefulWidget {
  const _TrackCard({required this.track, required this.onTap});
  final Track track;
  final VoidCallback onTap;

  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final coverPath = widget.track.customMetadata.customCoverPath;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: _hovered
              ? (Matrix4.identity()..translateByDouble(0.0, -2.0, 0.0, 1.0))
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.divider),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(100),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    )
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8)),
                  child: Container(
                    width: double.infinity,
                    color: AppTheme.bgHover,
                    child: coverPath != null
                        ? Image.file(File(coverPath), fit: BoxFit.cover)
                        : const Center(
                            child: Icon(Icons.album_rounded,
                                color: AppTheme.textHint, size: 40)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.track.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.track.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
