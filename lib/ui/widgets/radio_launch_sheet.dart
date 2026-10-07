import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/models/track.dart';
import '../../core/services/audio_player_service.dart';
import '../../core/services/recommendation_engine_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';

/// Glassmorphism bottom sheet that previews the first 3 tracks of the
/// algorithmically generated radio queue and lets the user confirm playback.
///
/// Usage:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   backgroundColor: Colors.transparent,
///   isScrollControlled: true,
///   builder: (_) => RadioLaunchSheet(seedTrack: track),
/// );
/// ```
class RadioLaunchSheet extends StatefulWidget {
  const RadioLaunchSheet({super.key, required this.seedTrack});

  final Track seedTrack;

  /// Convenience static method to open the sheet.
  static Future<void> show(BuildContext context, Track seedTrack) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => RadioLaunchSheet(seedTrack: seedTrack),
    );
  }

  @override
  State<RadioLaunchSheet> createState() => _RadioLaunchSheetState();
}

class _RadioLaunchSheetState extends State<RadioLaunchSheet> {
  late final Future<List<Track>> _radioFuture;

  @override
  void initState() {
    super.initState();
    _radioFuture = RecommendationEngineService.instance.generateRadioQueue(
      widget.seedTrack,
      limit: 20,
    );
  }

  Future<void> _startRadio(List<Track> queue) async {
    if (queue.isEmpty) {
      if (mounted) {
        AppToast.showText(
          context,
          'No se encontraron pistas similares para la radio.',
          icon: Icons.radio_rounded,
        );
      }
      return;
    }
    Navigator.of(context).pop();
    await AudioPlayerService.instance.loadPlaylist(
      queue,
      contextName: 'Radio: ${widget.seedTrack.displayTitle}',
    );
    AudioPlayerService.isRadioActiveNotifier.value = true;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomPad),
          decoration: BoxDecoration(
            color: const Color(0xFF141414).withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: const Border(
              top: BorderSide(color: Color(0x1FFFFFFF), width: 0.8),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.radio_rounded,
                      color: AppTheme.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Iniciar Radio',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Basada en "${widget.seedTrack.displayTitle}"',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Preview section
              FutureBuilder<List<Track>>(
                future: _radioFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return _ShimmerPreview();
                  }
                  if (snap.hasError || !snap.hasData || snap.data!.isEmpty) {
                    return _EmptyPreview();
                  }

                  final queue = snap.data!;
                  final preview = queue.take(3).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PRÓXIMAS EN LA RADIO',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: Colors.white.withValues(alpha: 0.40),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...preview.asMap().entries.map((entry) {
                        final i = entry.key;
                        final t = entry.value;
                        return _PreviewTrackTile(track: t, index: i + 1);
                      }),
                      if (queue.length > 3)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '+ ${queue.length - 3} pistas más',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),

                      // Confirm button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: AppTheme.bgDeep,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () => _startRadio(queue),
                          icon: const Icon(Icons.radio_rounded, size: 20),
                          label: const Text('Iniciar Radio'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Preview track tile ────────────────────────────────────────────────────────

class _PreviewTrackTile extends StatelessWidget {
  const _PreviewTrackTile({required this.track, required this.index});

  final Track track;
  final int index;

  @override
  Widget build(BuildContext context) {
    final coverPath = track.customMetadata.customCoverPath;
    final hasArt =
        coverPath != null && coverPath.isNotEmpty && File(coverPath).existsSync();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // Index
          SizedBox(
            width: 20,
            child: Text(
              '$index',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.35),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 10),
          // Cover
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 40,
              height: 40,
              child: hasArt
                  ? Image.file(File(coverPath), fit: BoxFit.cover, cacheWidth: 80)
                  : const ColoredBox(
                      color: AppTheme.bgHover,
                      child: Icon(Icons.music_note_rounded,
                          size: 18, color: AppTheme.textHint),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  track.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.50),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shimmer loading state ─────────────────────────────────────────────────────

class _ShimmerPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                _ShimmerBox(width: 20, height: 14, radius: 4),
                const SizedBox(width: 10),
                _ShimmerBox(width: 40, height: 40, radius: 6),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ShimmerBox(width: double.infinity, height: 12, radius: 4),
                      const SizedBox(height: 6),
                      _ShimmerBox(width: 100, height: 10, radius: 4),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _ShimmerBox(width: double.infinity, height: 50, radius: 14),
      ],
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width == double.infinity ? null : width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.library_music_rounded,
                size: 36, color: Colors.white.withValues(alpha: 0.25)),
            const SizedBox(height: 12),
            Text(
              'No hay suficientes pistas para generar una radio.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
