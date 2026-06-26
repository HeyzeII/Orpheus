import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Navigation destinations exposed by the [Sidebar].
enum NavDestination {
  home,
  explore,
  library,
  settings,
}

/// Maps each destination to its display label.
extension NavDestinationLabel on NavDestination {
  String get label => switch (this) {
        NavDestination.home => 'Inicio',
        NavDestination.explore => 'Explorar',
        NavDestination.library => 'Tu Biblioteca',
        NavDestination.settings => 'Ajustes',
      };

  IconData get icon => switch (this) {
        NavDestination.home => Icons.home_rounded,
        NavDestination.explore => Icons.explore_rounded,
        NavDestination.library => Icons.library_music_rounded,
        NavDestination.settings => Icons.settings_rounded,
      };
}

/// Left navigation sidebar — fixed width, premium dark aesthetic.
///
/// Accepts the current [selected] destination and an [onSelect] callback.
/// Designed to be stateless; the parent owns the navigation state.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final NavDestination selected;
  final ValueChanged<NavDestination> onSelect;

  static const double kWidth = 240.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kWidth,
      color: AppTheme.bgSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Logo(),
          const SizedBox(height: 16),
          // Navigation menu
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final dest in NavDestination.values)
                  _NavItem(
                    destination: dest,
                    isSelected: dest == selected,
                    onTap: () => onSelect(dest),
                  ),
              ],
            ),
          ),
          // Bottom decorative gradient
          Container(
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.bgSidebar.withAlpha(0),
                  AppTheme.bgSidebar,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Logotype in the sidebar header.
class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.music_note_rounded,
              color: AppTheme.bgDeep,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'ORPHEUS',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              letterSpacing: 3.0,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single navigation item with an active indicator bar on the left.
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 44,
          decoration: BoxDecoration(
            color: _hovered && !isSelected
                ? AppTheme.bgHover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Row(
            children: [
              // Active indicator bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 3,
                height: isSelected ? 20 : 0,
                margin: const EdgeInsets.only(left: 4, right: 12),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // When not selected, add missing left margin
              if (!isSelected) const SizedBox(width: 3 + 12),
              Icon(
                widget.destination.icon,
                size: 18,
                color: isSelected
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
