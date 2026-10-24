import 'package:flutter/material.dart';

import '../../core/models/track.dart';
import '../../core/services/audio_handler.dart';
import '../../core/services/audio_player_service.dart';
import '../views/nearby_devices_view.dart';

/// A compact, animated indicator badge displayed in the player bar and
/// expanded player views whenever the actively playing track is being
/// streamed from an Orpheus peer on the local network.
class NetworkIndicatorBadge extends StatelessWidget {
  const NetworkIndicatorBadge({super.key, this.track});

  final Track? track;

  @override
  Widget build(BuildContext context) {
    if (track != null) {
      final isRemote = AudioPlayerService.isRemoteUri(track!.filePath);
      return isRemote
          ? _NetworkBadgeChip(
              key: const ValueKey('network_active'),
              track: track!,
            )
          : const SizedBox.shrink(key: ValueKey('network_inactive'));
    }

    if (!OrpheusAudioHandler.hasInstance) return const SizedBox.shrink();
    final handler = OrpheusAudioHandler.instance;

    return StreamBuilder<Track?>(
      stream: handler.currentTrackStream,
      initialData: handler.currentTrack,
      builder: (context, snapshot) {
        final track = snapshot.data;
        final isRemote =
            track != null && AudioPlayerService.isRemoteUri(track.filePath);

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: anim,
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: isRemote
              ? _NetworkBadgeChip(
                  key: const ValueKey('network_active'),
                  track: track,
                )
              : const SizedBox.shrink(key: ValueKey('network_inactive')),
        );
      },
    );
  }
}

class _NetworkBadgeChip extends StatelessWidget {
  const _NetworkBadgeChip({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    const streamColor = Color(0xFF00E5FF); // Vibrant Cyan/Neon Blue

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (ctx) => const NearbyDevicesView(),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: streamColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: streamColor.withValues(alpha: 0.4),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lan_rounded,
                size: 11,
                color: streamColor,
              ),
              const SizedBox(width: 4),
              const Text(
                'RED LOCAL',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: streamColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
