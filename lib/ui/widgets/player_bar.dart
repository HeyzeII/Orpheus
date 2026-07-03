import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/database/local_database.dart';
import '../../core/models/models.dart';
import '../../core/services/audio_player_service.dart';
import '../theme/app_theme.dart';
import '../views/expanded_player_view.dart';

/// Fixed bottom player bar — 90px tall, three-section layout.
///
/// Fully reactive via [StreamBuilder]s connected to [AudioPlayerService].
class PlayerBar extends StatelessWidget {
  const PlayerBar({
    super.key,
    this.lyricsActive = false,
    this.onToggleLyrics,
  });

  /// Whether the lyrics panel is currently visible.
  final bool lyricsActive;

  /// Callback to toggle the lyrics overlay. If null, the button is hidden.
  final VoidCallback? onToggleLyrics;

  static const double kHeight = 90.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kHeight,
      decoration: const BoxDecoration(
        color: AppTheme.bgSurface,
        border: Border(
          top: BorderSide(color: AppTheme.divider, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Left — Track info
          const Expanded(child: _TrackInfo()),
          // Center — Playback controls
          const _PlaybackControls(),
          // Right — Volume + Lyrics toggle
          Expanded(
            child: _VolumeControl(
              lyricsActive: lyricsActive,
              onToggleLyrics: onToggleLyrics,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Left: Track Info ──────────────────────────────────────────────────────────

class _TrackInfo extends StatelessWidget {
  const _TrackInfo();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Track?>(
      stream: AudioPlayerService.instance.currentTrackStream,
      initialData: AudioPlayerService.instance.currentTrack,
      builder: (context, snap) {
        final track = snap.data;

        return Row(
          children: [
            // Cover art
            _CoverArt(
              coverPath: track?.customMetadata.customCoverPath,
            ),
            const SizedBox(width: 12),
            // Title + Artist
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track?.displayTitle ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track?.displayArtist ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (track != null) _TrackActions(track: track),
          ],
        );
      },
    );
  }
}

class _CoverArt extends StatelessWidget {
  const _CoverArt({this.coverPath});

  final String? coverPath;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          showGeneralDialog(
            context: context,
            barrierDismissible: true,
            barrierLabel: 'Dismiss',
            barrierColor: Colors.black.withOpacity(0.5),
            transitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (context, animation, secondaryAnimation) {
              return const ExpandedPlayerView();
            },
            transitionBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: child,
              );
            },
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 55,
            height: 55,
            child: coverPath != null
                ? Image.file(
                    File(coverPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _placeholder(),
                  )
                : _placeholder(),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppTheme.bgHover,
        child: const Icon(
          Icons.music_note_rounded,
          color: AppTheme.textHint,
          size: 22,
        ),
      );
}

class _TrackActions extends StatefulWidget {
  const _TrackActions({required this.track});

  final Track track;

  @override
  State<_TrackActions> createState() => _TrackActionsState();
}

class _TrackActionsState extends State<_TrackActions> {
  List<Playlist> _playlists = [];
  late StreamSubscription _sub;

  @override
  void initState() {
    super.initState();
    _fetchPlaylists();
    _sub = LocalDatabase.instance.watchPlaylists().listen((_) => _fetchPlaylists());
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _fetchPlaylists() async {
    final list = await LocalDatabase.instance.getAllPlaylists();
    if (mounted) setState(() => _playlists = list);
  }

  @override
  Widget build(BuildContext context) {
    final customPlaylists = _playlists.where((p) => !p.isDefault).toList();
    final likedPlaylist = _playlists.firstWhere(
      (p) => p.playlistId == '__liked__',
      orElse: () => Playlist()..playlistId = '__liked__',
    );
    final isLiked = likedPlaylist.trackIds.contains(widget.track.trackId);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 18,
            color: isLiked ? Colors.redAccent : AppTheme.textSecondary,
          ),
          onPressed: () async {
            final db = LocalDatabase.instance;
            if (isLiked) {
              await db.removeTrackFromPlaylist(playlist: likedPlaylist, trackId: widget.track.trackId);
            } else {
              await db.addTrackToPlaylist(playlist: likedPlaylist, trackId: widget.track.trackId);
            }
          },
        ),
        PopupMenuButton<dynamic>(
              icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppTheme.textSecondary),
              color: AppTheme.bgSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppTheme.divider),
              ),
              onSelected: (value) {
                if (value == 'play_next') {
                  AudioPlayerService.instance.playNext(widget.track);
                } else if (value == 'add_to_queue') {
                  AudioPlayerService.instance.addToQueue(widget.track);
                } else if (value is Playlist) {
                  LocalDatabase.instance.addTrackToPlaylist(
                    playlist: value,
                    trackId: widget.track.trackId,
                  ).then((_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('"${widget.track.displayTitle}" añadido a "${value.name}"'),
                          backgroundColor: AppTheme.bgSurface,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  });
                }
              },
              itemBuilder: (context) {
                final items = <PopupMenuEntry<dynamic>>[];

                items.add(
                  const PopupMenuItem<dynamic>(
                    value: 'play_next',
                    child: Row(
                      children: [
                        Icon(Icons.playlist_play_rounded, size: 14, color: AppTheme.textPrimary),
                        SizedBox(width: 8),
                        Text('Reproducir siguiente', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                      ],
                    ),
                  ),
                );
                items.add(
                  const PopupMenuItem<dynamic>(
                    value: 'add_to_queue',
                    child: Row(
                      children: [
                        Icon(Icons.queue_music_rounded, size: 14, color: AppTheme.textPrimary),
                        SizedBox(width: 8),
                        Text('Añadir a cola', style: TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                      ],
                    ),
                  ),
                );
                items.add(const PopupMenuDivider(height: 1));

                items.add(
                  const PopupMenuItem<dynamic>(
                    enabled: false,
                    child: Text(
                      'AGREGAR A PLAYLIST',
                      style: TextStyle(
                          color: AppTheme.textHint,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0),
                    ),
                  ),
                );

                if (customPlaylists.isEmpty) {
                  items.add(
                    const PopupMenuItem<dynamic>(
                      enabled: false,
                      child: Text('No hay playlists', style: TextStyle(color: AppTheme.textHint, fontSize: 12)),
                    ),
                  );
                } else {
                  for (final p in customPlaylists) {
                    items.add(
                      PopupMenuItem<dynamic>(
                        value: p,
                        child: Row(
                          children: [
                            const Icon(Icons.playlist_add_rounded, size: 14, color: AppTheme.textSecondary),
                            const SizedBox(width: 8),
                            Text(p.name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  }
                }
                return items;
              },
            ),
          ],
        );
  }
}

// ── Center: Playback Controls ─────────────────────────────────────────────────

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls();

  @override
  Widget build(BuildContext context) {
    final player = AudioPlayerService.instance;

    return SizedBox(
      width: 420,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Shuffle
              StreamBuilder<bool>(
                stream: player.shuffleStream,
                builder: (_, snap) {
                  final on = snap.data ?? player.shuffleEnabled;
                  return _IconBtn(
                    icon: Icons.shuffle_rounded,
                    active: on,
                    onTap: player.toggleShuffle,
                    tooltip: 'Aleatoria',
                  );
                },
              ),
              const SizedBox(width: 12),
              // Previous
              _IconBtn(
                icon: Icons.skip_previous_rounded,
                size: 22,
                onTap: player.previous,
                tooltip: 'Anterior',
              ),
              const SizedBox(width: 10),
              // Play / Pause (premium circle button)
              StreamBuilder<bool>(
                stream: player.isPlayingStream,
                builder: (_, snap) {
                  final playing = snap.data ?? player.isPlaying;
                  return _PlayButton(
                    isPlaying: playing,
                    onTap: playing ? player.pause : player.play,
                  );
                },
              ),
              const SizedBox(width: 10),
              // Next
              _IconBtn(
                icon: Icons.skip_next_rounded,
                size: 22,
                onTap: player.next,
                tooltip: 'Siguiente',
              ),
              const SizedBox(width: 12),
              // Repeat
              StreamBuilder<bool>(
                stream: player.repeatStream,
                builder: (_, snap) {
                  final on = snap.data ?? player.repeatEnabled;
                  return _IconBtn(
                    icon: Icons.repeat_rounded,
                    active: on,
                    onTap: player.toggleRepeat,
                    tooltip: 'Repetir',
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Progress slider
          _ProgressBar(),
        ],
      ),
    );
  }
}

/// Animated play/pause circular button.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.isPlaying, required this.onTap});

  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: AppTheme.textPrimary,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: AppTheme.bgDeep,
          size: 22,
        ),
      ),
    );
  }
}

/// Compact icon button for transport controls.
class _IconBtn extends StatefulWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.size = 18.0,
    this.active = false,
    this.tooltip = '',
  });

  final IconData icon;
  final double size;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _hovered ? AppTheme.bgHover : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              widget.icon,
              size: widget.size,
              color: widget.active
                  ? AppTheme.accent
                  : _hovered
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Seek bar combining position and duration streams.
class _ProgressBar extends StatelessWidget {
  _ProgressBar();

  final player = AudioPlayerService.instance;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, posSnap) {
        return StreamBuilder<Duration>(
          stream: player.durationStream,
          builder: (context, durSnap) {
            final pos = posSnap.data ?? player.position;
            final dur = durSnap.data ?? player.duration;
            final maxVal = dur.inMilliseconds.toDouble();
            final curVal = (pos.inMilliseconds.toDouble()).clamp(
              0.0,
              maxVal > 0 ? maxVal : 1.0,
            );

            return Row(
              children: [
                // Elapsed time
                SizedBox(
                  width: 36,
                  child: Text(
                    _fmt(pos),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      color: AppTheme.textSecondary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context),
                    child: Slider(
                      value: curVal,
                      min: 0,
                      max: maxVal > 0 ? maxVal : 1.0,
                      onChanged: maxVal > 0
                          ? (val) => player.seek(
                                Duration(milliseconds: val.toInt()),
                              )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Total time
                SizedBox(
                  width: 36,
                  child: Text(
                    _fmt(dur),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      color: AppTheme.textSecondary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ── Right: Volume Control ────────────────────────────────────────────────

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({
    this.lyricsActive = false,
    this.onToggleLyrics,
  });

  final bool lyricsActive;
  final VoidCallback? onToggleLyrics;

  @override
  Widget build(BuildContext context) {
    final player = AudioPlayerService.instance;

    return StreamBuilder<double>(
      stream: player.volumeStream,
      builder: (_, snap) {
        final vol = snap.data ?? player.volume;

        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // Lyrics toggle button
            if (onToggleLyrics != null)
              Tooltip(
                message: lyricsActive ? 'Ocultar letras' : 'Ver letras',
                child: _IconBtn(
                  icon: Icons.lyrics_rounded,
                  active: lyricsActive,
                  onTap: onToggleLyrics!,
                  tooltip: '',
                ),
              ),
            const SizedBox(width: 8),
            Icon(
              vol == 0
                  ? Icons.volume_off_rounded
                  : vol < 0.5
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
              size: 18,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 100,
              child: SliderTheme(
                data: SliderTheme.of(context),
                child: Slider(
                  value: vol.clamp(0.0, 1.0),
                  min: 0,
                  max: 1,
                  onChanged: (v) => player.setVolume(v),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
