import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/models/track.dart';
import '../../../core/services/audio_handler.dart';
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

    return Scaffold(
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

                    return Stack(
                      children: [
                        // Background drag area covering the entire widget
                        const Positioned.fill(
                          child: DragToMoveArea(
                            child: SizedBox.expand(),
                          ),
                        ),

                        // Main Content Layer
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // 1. Top Header: Title, Artist, Like, and Restore buttons
                              OrbHeaderRow(track: track),

                              // 2. Center: Orb Disc with Harmonic Wave Reactor & Volume Stack
                              Expanded(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Animated Audio Waves (RepaintBoundary for isolated GPU rasterization)
                                    Positioned.fill(
                                      child: RepaintBoundary(
                                        child: AnimatedBuilder(
                                          animation: _waveController,
                                          builder: (context, _) {
                                            return CustomPaint(
                                              painter: ReactorWavesPainter(
                                                animationValue: _waveController.value,
                                                isPlaying: isPlaying,
                                                accentColor: AppTheme.accent,
                                                secondaryColor: const Color(0xFF8B5CF6),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),

                                    // Central Rotating Album Orb Disc
                                    CentralOrbDisc(
                                      coverPath: track?.customMetadata.customCoverPath,
                                      isPlaying: isPlaying,
                                      size: 118,
                                      accentColor: AppTheme.accent,
                                    ),

                                    // Right Vertical Battery Volume Stack
                                    const Positioned(
                                      right: 2,
                                      child: VolumeEnergyStack(
                                        width: 20.0,
                                        height: 95.0,
                                        segments: 6,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // 3. Bottom: Progress bar and transport controls
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
            ),
          ),
        ),
      ),
    );
  }
}
