import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../core/models/models.dart';
import '../../core/services/audio_handler.dart';

class AppToast {
  /// Shows a premium toast notification for adding a track to a playlist.
  static void showAddedToPlaylist(
    BuildContext context, {
    required Track track,
    required Playlist playlist,
  }) {
    showCustom(
      context,
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
          ),
          children: [
            TextSpan(
              text: track.displayTitle,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: ' agregado a ',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontWeight: FontWeight.w400,
              ),
            ),
            TextSpan(
              text: playlist.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      icon: Icons.playlist_add_check_rounded,
    );
  }

  /// Shows a toast notification for adding multiple tracks to a playlist.
  static void showTracksAddedToPlaylist(
    BuildContext context, {
    required int count,
    required Playlist playlist,
    String? collectionTitle,
  }) {
    showCustom(
      context,
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
          ),
          children: [
            TextSpan(
              text: collectionTitle != null ? '$collectionTitle ($count)' : '$count canciones',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: ' agregadas a ',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontWeight: FontWeight.w400,
              ),
            ),
            TextSpan(
              text: playlist.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      icon: Icons.playlist_add_check_rounded,
    );
  }

  /// Shows a premium generic toast notification.
  static void showText(
    BuildContext context,
    String message, {
    IconData? icon,
  }) {
    showCustom(
      context,
      child: Text(
        message,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      icon: icon,
    );
  }

  /// Base method to show a premium custom toast.
  static void showCustom(
    BuildContext context, {
    required Widget child,
    IconData? icon,
  }) {
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final double bottomMargin;
    if (isDesktop) {
      // PlayerBar is 90px tall. We float above it on desktop.
      bottomMargin = 90.0 + 24.0;
    } else {
      final hasTrack = OrpheusAudioHandler.hasInstance &&
          OrpheusAudioHandler.instance.currentTrack != null &&
          OrpheusAudioHandler.instance.currentTrack!.trackId.isNotEmpty;
      final sysPad = MediaQuery.maybePaddingOf(context)?.bottom ?? 0.0;
      // Unified bottom panel: mini-player (64) + nav bar (60) + bottom margin (12) + gap (16)
      bottomMargin = (hasTrack ? 124.0 : 60.0) + 12.0 + sysPad + 16.0;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          margin: EdgeInsets.only(
            bottom: bottomMargin,
            left: 24,
            right: 24,
          ),
          padding: EdgeInsets.zero,
          duration: const Duration(milliseconds: 2500),
          content: Center(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181B).withOpacity(0.85),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.12),
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: AppTheme.accent, size: 20),
                          const SizedBox(width: 12),
                        ],
                        Flexible(child: child),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
  }
}
