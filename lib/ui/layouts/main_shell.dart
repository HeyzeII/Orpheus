import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../views/home_view.dart';
import '../views/library_view.dart';
import '../views/settings_view.dart';
import '../widgets/player_bar.dart';
import '../widgets/sidebar.dart';


/// Root layout shell for Orpheus desktop.
///
/// Composes three fixed regions:
/// - [Sidebar] on the left (fixed 240px, drives navigation state).
/// - Dynamic main content area in the center.
/// - [PlayerBar] at the bottom (fixed 90px, full width).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  NavDestination _selected = NavDestination.home;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      body: Column(
        children: [
          // ── Top row: Sidebar + Main content ──────────────────────────────
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sidebar
                Sidebar(
                  selected: _selected,
                  onSelect: (dest) => setState(() => _selected = dest),
                ),
                // Thin divider between sidebar and content
                Container(width: 1, color: AppTheme.divider),
                // Main content
                Expanded(
                  child: _ContentArea(destination: _selected),
                ),
              ],
            ),
          ),
          // ── Bottom: Player bar ────────────────────────────────────────────
          const PlayerBar(),
        ],
      ),
    );
  }
}

/// Switches the center pane based on active [NavDestination].
///
/// Uses an [IndexedStack] so each view retains its scroll position when
/// the user navigates away and back.
class _ContentArea extends StatelessWidget {
  const _ContentArea({required this.destination});

  final NavDestination destination;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: destination.index,
      children: const [
        HomeView(),
        _PlaceholderView(label: 'Explorar'),
        LibraryView(),
        SettingsView(),
      ],
    );
  }
}

/// Fallback view shown for destinations that are not yet implemented.
class _PlaceholderView extends StatelessWidget {
  const _PlaceholderView({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.construction_rounded,
            color: AppTheme.textHint,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.textSecondary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Esta sección estará disponible próximamente.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
