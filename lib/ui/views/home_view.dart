import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../core/models/models.dart';
import '../../core/services/audio_player_service.dart';
import '../theme/app_theme.dart';

/// Dynamic Home View — Displays user greeting, quick picks, recently played tracks,
/// and a library teaser query from [LocalDatabase].
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
    if (showSpinner) {
      setState(() => _isLoading = true);
    }
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

  Future<void> _playTrack(Track track) async {
    await AudioPlayerService.instance.loadPlaylist([track]);
  }

  Future<void> _playGenre(String genre) async {
    final genreTracks = _allTracks.where((t) => t.genre == genre).toList();
    if (genreTracks.isNotEmpty) {
      await AudioPlayerService.instance.loadPlaylist(genreTracks);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accent),
      );
    }

    if (_allTracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_note_rounded,
                color: AppTheme.textHint.withAlpha(80),
                size: 80,
              ),
              const SizedBox(height: 24),
              Text(
                'Tu biblioteca está vacía',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Para comenzar, ve a la sección de Ajustes, añade una carpeta de música y realiza un escaneo.',
                textAlign: Alignment.center.x == 0 ? TextAlign.center : TextAlign.start,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Usa el menú de "Ajustes" en el panel lateral izquierdo.',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 36, 32, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Greeting ───────────────────────────────────────────────────────
          Text(
            _greeting(),
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Bienvenido de regreso a tu reproductor Orpheus.',
            style: Theme.of(context).textTheme.titleSmall,
          ),

          const SizedBox(height: 40),

          // ── Quick Picks ────────────────────────────────────────────────────
          if (_genres.isNotEmpty) ...[
            Text(
              'GÉNEROS EN TU BIBLIOTECA',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 2.5,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final genre in _genres.take(8))
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _playGenre(genre),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.bgSurface,
                          border: Border.all(color: AppTheme.divider),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          genre,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 40),
          ],

          // ── Recently Played (or fallback) ──────────────────────────────────
          Text(
            _recentlyPlayed.any((t) => t.stats.totalPlays > 0)
                ? 'REPRODUCIDO RECIENTEMENTE'
                : 'AGREGADO RECIENTEMENTE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 2.5,
                ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recentlyPlayed.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.82,
            ),
            itemBuilder: (context, idx) {
              final track = _recentlyPlayed[idx];
              return _TrackCard(
                track: track,
                onTap: () => _playTrack(track),
              );
            },
          ),

          const SizedBox(height: 40),

          // ── Most Played ────────────────────────────────────────────────────
          if (_mostPlayed.any((t) => t.stats.totalPlays > 0)) ...[
            Text(
              'MÁS ESCUCHADAS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 2.5,
                  ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _mostPlayed.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              itemBuilder: (context, idx) {
                final track = _mostPlayed[idx];
                return _TrackCard(
                  track: track,
                  onTap: () => _playTrack(track),
                );
              },
            ),
            const SizedBox(height: 40),
          ],

          // ── Library Teaser ─────────────────────────────────────────────────
          Text(
            'TU BIBLIOTECA',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 2.5,
                ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _allTracks.take(12).length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.82,
            ),
            itemBuilder: (context, idx) {
              final track = _allTracks[idx];
              return _TrackCard(
                track: track,
                onTap: () => _playTrack(track),
              );
            },
          ),
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

class _TrackCard extends StatefulWidget {
  const _TrackCard({
    required this.track,
    required this.onTap,
  });

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
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover art area
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                  child: Container(
                    width: double.infinity,
                    color: AppTheme.bgHover,
                    child: coverPath != null
                        ? Image.file(
                            File(coverPath),
                            fit: BoxFit.cover,
                          )
                        : const Center(
                            child: Icon(
                              Icons.album_rounded,
                              color: AppTheme.textHint,
                              size: 40,
                            ),
                          ),
                  ),
                ),
              ),
              // Metadata
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
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.track.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
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
