import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/services/audio_handler.dart';
import '../../theme/app_theme.dart';

/// Interactive vertical volume slider styled as a futuristic energy battery stack.
///
/// Supported interactions:
/// - Vertical drag: slide up to increase, slide down to decrease.
/// - Tap to seek: tap directly on any segment of the stack to jump to that volume.
/// - Mouse wheel scroll: scroll up/down while hovering to adjust volume with micro precision.
class VolumeEnergyStack extends StatelessWidget {
  const VolumeEnergyStack({
    super.key,
    this.width = 24.0,
    this.height = 105.0,
    this.segments = 6,
  });

  final double width;
  final double height;
  final int segments;

  @override
  Widget build(BuildContext context) {
    final handler = OrpheusAudioHandler.hasInstance ? OrpheusAudioHandler.instance : null;

    return StreamBuilder<double>(
      stream: handler?.volumeStream,
      initialData: 1.0,
      builder: (context, snapshot) {
        final volume = (snapshot.data ?? 1.0).clamp(0.0, 1.0);
        final volumePercent = (volume * 100).round();

        return Tooltip(
          message: 'Volumen: $volumePercent%',
          waitDuration: const Duration(milliseconds: 300),
          child: Listener(
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent && handler != null) {
                // Scroll up (negative dy) increases volume; scroll down decreases volume
                final delta = -pointerSignal.scrollDelta.dy / 600.0;
                final newVol = (volume + delta).clamp(0.0, 1.0);
                handler.setVolume(newVol);
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                if (handler == null) return;
                // Upward movement has negative delta -> increases volume
                final delta = -details.primaryDelta! / height;
                final newVol = (volume + delta).clamp(0.0, 1.0);
                handler.setVolume(newVol);
              },
              onTapDown: (details) {
                if (handler == null) return;
                final localY = details.localPosition.dy;
                // Invert Y coordinate so bottom is 0.0 and top is 1.0
                final targetVol = (1.0 - (localY / height)).clamp(0.0, 1.0);
                handler.setVolume(targetVol);
              },
              child: Container(
                width: width,
                height: height,
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xB312141A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.12),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.40),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Battery cathode positive terminal tip
                    Container(
                      width: 6,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: volume > 0.05
                            ? AppTheme.accent.withOpacity(0.7)
                            : Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),

                    // Segmented Energy Cells (Top is 100%, Bottom is ~15%)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(segments, (index) {
                            // index 0 is top (highest threshold), index 5 is bottom (lowest threshold)
                            final segmentThreshold = (segments - index) / segments;
                            final isActive = volume >= (segmentThreshold - (0.5 / segments));

                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: width - 8,
                              height: 4.5,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                color: isActive
                                    ? AppTheme.accent
                                    : Colors.white.withOpacity(0.07),
                                boxShadow: isActive
                                    ? [
                                        BoxShadow(
                                          color: AppTheme.accent.withOpacity(0.6),
                                          blurRadius: 4,
                                          spreadRadius: 0.5,
                                        ),
                                      ]
                                    : null,
                              ),
                            );
                          }),
                        ),
                      ),
                    ),

                    // Bottom volume status icon
                    Icon(
                      volume == 0
                          ? Icons.volume_off_rounded
                          : volume < 0.5
                              ? Icons.volume_down_rounded
                              : Icons.volume_up_rounded,
                      size: 11,
                      color: volume > 0 ? AppTheme.accent : AppTheme.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
