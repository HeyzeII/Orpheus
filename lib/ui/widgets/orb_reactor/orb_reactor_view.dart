import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/models/track.dart';
import '../../../core/services/audio_handler.dart';
import '../../../core/services/desktop_window_service.dart';
import '../../theme/app_theme.dart';
import 'central_orb_disc.dart';
import 'orb_transport_controls.dart';
import 'reactor_waves_painter.dart';
import 'volume_energy_stack.dart';

/// Floating glassmorphic desktop widget: "Orpheus Orb Reactor" for macOS and Linux.
///
/// Features:
/// - Compact 320 × 320 px footprint.
/// - Full-window [DragToMoveArea] enabling seamless window repositioning.
/// - Concentric harmonic audio waves rendered via [ReactorWavesPainter] on GPU layer.
/// - Central vinyl/core rotating artwork disc with glowing corona.
/// - Interactive vertical battery stack volume slider with wheel and drag support.
/// - Real-time metadata, like button, and transport playback controls.
class OrbReactorView extends StatefulWidget {
  const OrbReactorView({super.key});

  @override
  State<OrbReactorView> createState() => _OrbReactorViewState();
}

class _OrbReactorViewState extends State<OrbReactorView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handler = OrpheusAudioHandler.hasInstance ? OrpheusAudioHandler.instance : null;
    final trackStream = handler?.currentTrackStream;
    final playingStream = handler?.isPlayingStream;
    final volumeStream = handler?.volumeStream;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          DesktopWindowService.instance.exitMiniPlayer();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xEE0B0C12), // Deep glassy obsidian
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: Colors.white.withOpacity(0.12),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.70),
              blurRadius: 32,
              spreadRadius: 4,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: AppTheme.accent.withOpacity(0.12),
              blurRadius: 20,
              spreadRadius: -2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(31),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: StreamBuilder<Track?>(
              stream: trackStream,
              initialData: handler?.currentTrack,
              builder: (context, trackSnap) {
                final track = trackSnap.data;

                return StreamBuilder<bool>(
                  stream: playingStream,
                  initialData: handler?.isPlaying ?? false,
                  builder: (context, playingSnap) {
                    final isPlaying = playingSnap.data ?? false;

                    return StreamBuilder<double>(
                      stream: volumeStream,
                      initialData: handler?.volume ?? 1.0,
                      builder: (context, volumeSnap) {
                        final volume = volumeSnap.data ?? 1.0;

                        return Stack(
                          children: [
                            // Background drag area covering the entire widget
                            const Positioned.fill(
                              child: DragToMoveArea(
                                child: SizedBox.expand(),
                              ),
                            ),

                            // Main Content Layer with generous margins (top: 36px, left: 24px) placing metadata cleanly below macOS buttons
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24.0, 36.0, 24.0, 18.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // 1. Top Header: Title, Artist, Like, and Restore buttons
                                  OrbHeaderRow(track: track),

                                  // 2. Center: Panoramic Harmonic Wave Reactor & Orb Core Disc with Volume Column
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          // Panoramic Audio Waves Layer expanding horizontally across the entire width
                                          // with lateral ShaderMask fade preventing collisions with text & volume stack
                                          Positioned.fill(
                                            child: ShaderMask(
                                              shaderCallback: (Rect bounds) {
                                                return const LinearGradient(
                                                  begin: Alignment.centerLeft,
                                                  end: Alignment.centerRight,
                                                  colors: [
                                                    Colors.transparent,
                                                    Colors.white,
                                                    Colors.white,
                                                    Colors.transparent,
                                                  ],
                                                  stops: [0.0, 0.16, 0.84, 1.0],
                                                ).createShader(bounds);
                                              },
                                              blendMode: BlendMode.dstIn,
                                              child: RepaintBoundary(
                                                child: AnimatedBuilder(
                                                  animation: _waveController,
                                                  builder: (context, _) {
                                                    return CustomPaint(
                                                      size: Size.infinite,
                                                      painter: ReactorWavesPainter(
                                                        animationValue: _waveController.value,
                                                        isPlaying: isPlaying,
                                                        volume: volume,
                                                        accentColor: AppTheme.accent,
                                                        secondaryColor: const Color(0xFF8B5CF6),
                                                        magentaColor: const Color(0xFFD946EF),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),

                                      // Foreground Row: Symmetrical spacer, Central Vinyl Disc, Volume Column
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          // Symmetrical left spacer balancing the right volume stack
                                          const SizedBox(width: 32),

                                          // Central Rotating Album Orb Disc
                                          Expanded(
                                            child: Center(
                                              child: CentralOrbDisc(
                                                coverPath: track?.customMetadata.customCoverPath,
                                                isPlaying: isPlaying,
                                                size: 122,
                                                accentColor: AppTheme.accent,
                                              ),
                                            ),
                                          ),

                                          // Right: Dedicated column for Volume Energy Stack
                                          const SizedBox(
                                            width: 32,
                                            child: Center(
                                              child: VolumeEnergyStack(
                                                width: 22.0,
                                                height: 105.0,
                                                segments: 6,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // 3. Bottom: Progress bar with timestamps and transport controls
                              OrbBottomTransport(
                                track: track,
                                isPlaying: isPlaying,
                                handler: handler,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    ),
  ),
),
      ),
    );
  }
}
