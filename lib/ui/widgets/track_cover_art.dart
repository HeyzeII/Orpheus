import 'dart:io';
import 'package:flutter/material.dart';

import '../../core/services/audio_player_service.dart';
import '../theme/app_theme.dart';

/// Resilient widget for rendering track or album artwork from either a local
/// file path or a remote network URL (e.g. streaming over LAN).
///
/// Automatically handles:
/// - Remote HTTP/HTTPS URLs via [Image.network] with graceful error fallback
/// - Local file paths via [Image.file] after validating disk presence
/// - Missing or corrupted covers with a styled modern placeholder
class TrackCoverArt extends StatelessWidget {
  const TrackCoverArt({
    super.key,
    required this.coverPath,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.fallback,
    this.fallbackIcon = Icons.music_note_rounded,
    this.fallbackIconSize = 22,
  });

  /// The raw file path or remote HTTP/HTTPS URL.
  final String? coverPath;

  /// Width constraint for the artwork container.
  final double? width;

  /// Height constraint for the artwork container.
  final double? height;

  /// Border radius applied to the image.
  final BorderRadiusGeometry borderRadius;

  /// Image fit mode.
  final BoxFit fit;

  /// Target decoded cache width for memory efficiency.
  final int? cacheWidth;

  /// Custom fallback widget when artwork is absent or fails to load.
  final Widget? fallback;

  /// Icon used in the default stylized placeholder.
  final IconData fallbackIcon;

  /// Icon size used in the default stylized placeholder.
  final double fallbackIconSize;

  Widget _buildFallback() {
    if (fallback != null) return fallback!;
    return Container(
      width: width,
      height: height,
      color: AppTheme.bgHover,
      alignment: Alignment.center,
      child: Icon(
        fallbackIcon,
        color: AppTheme.textHint.withValues(alpha: 0.6),
        size: fallbackIconSize,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = coverPath?.trim();
    if (path == null || path.isEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: SizedBox(
          width: width,
          height: height,
          child: _buildFallback(),
        ),
      );
    }

    final isRemote = AudioPlayerService.isRemoteUri(path);
    Widget imageContent;

    if (isRemote) {
      imageContent = Image.network(
        path,
        fit: fit,
        cacheWidth: cacheWidth,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );
    } else {
      bool exists = false;
      try {
        final file = File(path);
        exists = file.existsSync();
      } catch (_) {
        exists = false;
      }

      if (exists) {
        imageContent = Image.file(
          File(path),
          fit: fit,
          cacheWidth: cacheWidth,
          errorBuilder: (context, error, stackTrace) => _buildFallback(),
        );
      } else {
        imageContent = _buildFallback();
      }
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: imageContent,
      ),
    );
  }
}
