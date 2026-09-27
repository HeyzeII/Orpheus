import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Compact visual badge indicating that a track is a video media file.
class VideoBadge extends StatelessWidget {
  const VideoBadge({
    super.key,
    this.compact = false,
  });

  /// When true, renders a slightly more compact badge for tight mobile spaces.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6.0,
        vertical: 2.0,
      ),
      decoration: BoxDecoration(
        color: AppTheme.accent.withOpacity(0.18),
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(
          color: AppTheme.accent.withOpacity(0.45),
          width: 0.8,
        ),
      ),
      child: Text(
        'VIDEO',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: compact ? 10.0 : 10.5,
          fontWeight: FontWeight.w700,
          color: AppTheme.accent,
          letterSpacing: 0.6,
          height: 1.1,
        ),
      ),
    );
  }
}
