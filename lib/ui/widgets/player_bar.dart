import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/track.dart';
import '../../core/services/audio_player_service.dart';
import '../theme/app_theme.dart';

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
    return ClipRRect(
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
