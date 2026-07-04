import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../../core/models/models.dart';

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
    // PlayerBar is 90px tall. We float above it on desktop.
    final bottomMargin = isDesktop ? 90.0 + 24.0 : 24.0;

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
            child: Material(
              color: const Color(0xFF1E1E1E), // Graphite
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.white10),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: AppTheme.accent, size: 20),
                      const SizedBox(width: 12),
                    ],
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
  }
}
