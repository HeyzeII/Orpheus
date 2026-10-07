import 'package:flutter/material.dart';

import '../../core/services/audio_player_service.dart';
import '../theme/app_theme.dart';

/// A compact animated badge displayed in the [PlayerBar] and [MobileMiniPlayer]
/// when the active context is an algorithmic radio session.
///
/// Reads [AudioPlayerService.isRadioActiveNotifier] and renders itself only
/// when a Radio session is active.
class RadioIndicatorBadge extends StatelessWidget {
  const RadioIndicatorBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AudioPlayerService.isRadioActiveNotifier,
      builder: (context, isActive, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: anim,
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: isActive
              ? _RadioBadgeChip(key: const ValueKey('radio_active'))
              : const SizedBox.shrink(key: ValueKey('radio_inactive')),
        );
      },
    );
  }
}

class _RadioBadgeChip extends StatelessWidget {
  const _RadioBadgeChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.accent.withValues(alpha: 0.45),
          width: 1.0,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.radio_rounded,
            size: 11,
            color: AppTheme.accent,
          ),
          SizedBox(width: 4),
          Text(
            'RADIO',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: AppTheme.accent,
            ),
          ),
        ],
      ),
    );
  }
}
